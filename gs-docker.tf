resource "google_compute_instance" "geoserver_docker_instance" {
  name         = "geoserver-docker-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
    }
  }

  network_interface {
    subnetwork = "projects/linear-equator-414922/regions/us-central1/subnetworks/appraise-private-network"
    network_ip = "10.128.0.41" 
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash

    # Install Docker
    apt-get update
    apt-get install -y docker.io openssl openjdk-17-jdk

    # Start Docker service
    systemctl start docker
    systemctl enable docker
    
    gcloud auth configure-docker gcr.io
    
    # Mount the persistent disk
    sudo mkdir -p /opt/geoserver_data

    # Check if the disk already has an ext4 filesystem
    FS_TYPE=$(sudo blkid -o value -s TYPE /dev/disk/by-id/google-${google_compute_disk.geoserver_data.name})

    if [ "$FS_TYPE" != "ext4" ]; then
      echo "Formatting disk as it does not have an ext4 filesystem"
      # Format the disk only if it does not have an ext4 filesystem
      sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${google_compute_disk.geoserver_data.name}
    else
      echo "Disk already formatted with ext4, skipping format step"
    fi  
    sudo mount -o discard,defaults /dev/disk/by-id/google-${google_compute_disk.geoserver_data.name} /opt/geoserver_data
  
    # Make the directory for the cert and private key
    mkdir -p /opt/geoserver_data/etc/tls/

    # Define variables
    CERT_PATH="/opt/geoserver_data/etc/tls/certificate.pem"
    KEY_PATH="/opt/geoserver_data/etc/tls/privatekey.pem"
    KEYSTORE_PASSWORD=$(gcloud secrets versions access latest --secret="geoserver-keystore-password")
    ALIAS="geoserver_cert" # Change alias as needed
    JKS_KEYSTORE_PATH="/opt/geoserver_data/etc/tls/keystore.jks"

    # Check if the JKS keystore already exists
    if [ ! -f "$JKS_KEYSTORE_PATH" ]; then
        # Retrieve certificate from Secret Manager
        gcloud secrets versions access latest --secret="geoserver-certificate" > $CERT_PATH
        # Retrieve private key from Secret Manager
        gcloud secrets versions access latest --secret="geoserver-private-key" > $KEY_PATH

        cd /opt/geoserver_data/etc/tls/
        # Step 1: Convert to PKCS12 format
        echo "Converting to PKCS12..."
        openssl pkcs12 -export -in "$CERT_PATH" -inkey "$KEY_PATH" -name "$ALIAS" -out keystore.p12 -password pass:$KEYSTORE_PASSWORD

        # Check for successful PKCS12 conversion
        if [ $? -ne 0 ]; then
            echo "Failed to convert to PKCS12 format."
            exit 1
        fi

        # Step 2: Import PKCS12 into JKS keystore
        echo "Importing into JKS keystore..."
        keytool -importkeystore -deststorepass $KEYSTORE_PASSWORD -destkeypass $KEYSTORE_PASSWORD -destkeystore "$JKS_KEYSTORE_PATH" -srckeystore keystore.p12 -srcstoretype PKCS12 -alias "$ALIAS" -srcstorepass $KEYSTORE_PASSWORD

        # Check for successful JKS import
        if [ $? -ne 0 ]; then
            echo "Failed to import into JKS keystore."
            exit 1
        fi

        echo "Certificate and key have been successfully imported into JKS keystore."
    else
        echo "JKS keystore already exists. No action taken."
    fi
    
    # Check if the desired Geoserver image is already pulled
    IMAGE_NAME="gcr.io/linear-equator-414922/geoserver:latest"
    CONTAINER_NAME="geoserver"
    GEOSERVER_DATA_PATH="/opt/geoserver_data/"

    if ! docker images "$IMAGE_NAME" | awk '{ print $2 }' | grep -q '2.24.1'; then
      echo "Pulling Geoserver image..."
      docker pull "$IMAGE_NAME"
    else
      echo "Geoserver image already pulled."
    fi

    # Check if the Geoserver container is already created
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
      # Start the container if it exists but stopped
      if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Starting existing Geoserver container..."
        docker start "$CONTAINER_NAME"
      else
        echo "Geoserver container is already running."
      fi
    else
      # Run the Geoserver container if it does not exist
      echo "Running new Geoserver container..."
      docker run -d -p 8080:8080 \
        --name "$CONTAINER_NAME" \
        --mount type=bind,src="$GEOSERVER_DATA_PATH",target=/opt/geoserver_data/ \
        "$IMAGE_NAME"
    fi
      EOF

  #scheduling {
  #  preemptible      = true
  #  automatic_restart = false
  #}
  tags = ["geoserver-iap", "geoserver-cloudrun"]

  service_account {
    scopes = ["cloud-platform"]
  }
  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
  attached_disk {
    source      = google_compute_disk.geoserver_data.self_link
    device_name = google_compute_disk.geoserver_data.name
  }
}

resource "google_compute_firewall" "geoserver" {
  name        = "geoserver-firewall"
  network     = google_compute_network.main.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]  # IAP's IP range
  target_tags   = ["geoserver-iap"]
}

resource "google_compute_firewall" "geoserver-cloudrun" {
  name        = "geoserver-firewall-cloudrun"
  network     = google_compute_network.main.self_link
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["geoserver-cloudrun"]
}


resource "google_secret_manager_secret" "private_key_secret" {
  secret_id = "geoserver-private-key"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "pk_secret_version" {
  secret = google_secret_manager_secret.private_key_secret.id
  secret_data = acme_certificate.certificate.private_key_pem
}

resource "google_secret_manager_secret" "keystore_password_secret" {
  secret_id = "geoserver-keystore-password"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "keystore_password_secret_version" {
  secret = google_secret_manager_secret.keystore_password_secret.id
  secret_data = "changeit"  # Replace with your desired keystore password
}

resource "google_secret_manager_secret" "certificate_secret" {
  secret_id = "geoserver-certificate"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "certificate_secret_version" {
  secret = google_secret_manager_secret.certificate_secret.id
  secret_data = acme_certificate.certificate.certificate_pem
}

resource "google_secret_manager_secret_iam_member" "keystore_password_secret_access" {
  secret_id = google_secret_manager_secret.keystore_password_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_compute_instance.geoserver_docker_instance.service_account[0].email}"
}

resource "google_secret_manager_secret_iam_member" "certificate_secret_access" {
  secret_id = google_secret_manager_secret.certificate_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_compute_instance.geoserver_docker_instance.service_account[0].email}"
}

# Create a persistent disk
resource "google_compute_disk" "geoserver_data" {
  name = "geoserver-data-disk"
  type = "pd-standard"
  size = 10
  zone = "us-central1-a"
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = "jonathan.weiss@chinnu.com"
}

resource "acme_certificate" "certificate" {
  account_key_pem = acme_registration.reg.account_key_pem
  common_name     = "gs.appraise.estate"

  dns_challenge {
    provider = "gcloud"
    config = {
      GCE_PROJECT = var.project_id
    }
  }
}


