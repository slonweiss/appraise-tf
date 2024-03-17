resource "google_compute_address" "geoserver" {
  name = "geoserver-ip"
}

resource "google_compute_firewall" "geoserver" {
  name        = "geoserver-firewall"
  network     = google_compute_network.main.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]  # IAP's IP range
  target_tags   = ["geoserver"]
}

# Create a persistent disk
resource "google_compute_disk" "geoserver_data" {
  name = "geoserver-data-disk"
  type = "pd-standard"
  size = 10
  zone = "us-central1-a"
}

# Create a spot instance VM
resource "google_compute_instance" "geoserver" {
  name         = "geoserver-spot-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 10
    }
  }
  network_interface {
    subnetwork = "projects/linear-equator-414922/regions/us-central1/subnetworks/appraise-private-network"
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash

  # Update packages
  sudo apt-get update

  # Install Java
  sudo apt-get install -y openjdk-11-jdk unzip

  # Download and install GeoServer
  if [ ! -d "/opt/geoserver-2.24.1" ]; then
    # Download and install GeoServer
    cd /opt
    wget -O /opt/geoserver-2.24.1-bin.zip "https://sourceforge.net/projects/geoserver/files/GeoServer/2.24.1/geoserver-2.24.1-bin.zip/download"
    unzip -d /opt/geoserver-2.24.1 geoserver-2.24.1-bin.zip
    rm geoserver-2.24.1-bin.zip
  fi

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
  
  sudo chown -R ubuntu:ubuntu /opt/geoserver-2.24.1
  sudo chown -R ubuntu:ubuntu /opt/geoserver_data
  sudo chmod -R 755 /opt/geoserver_data

  # Configure GeoServer data directory
  export GEOSERVER_DATA_DIR="/opt/geoserver_data"

  # Create a systemd service file for GeoServer
  sudo tee /etc/systemd/system/geoserver.service > /dev/null <<EOT
  [Unit]
  Description=GeoServer
  After=network.target

  [Service]
  Type=simple
  User=ubuntu
  Environment=GEOSERVER_DATA_DIR=/opt/geoserver_data
  Environment=GEOSERVER_HOME=/opt/geoserver-2.24.1
  ExecStart=/opt/geoserver-2.24.1/bin/startup.sh
  ExecStop=/opt/geoserver-2.24.1/bin/shutdown.sh
  Restart=always

  [Install]
  WantedBy=multi-user.target
  EOT

  # Reload systemd and start the GeoServer service
  sudo systemctl daemon-reload
  sudo systemctl enable geoserver.service
  sudo systemctl start geoserver.service

  EOF
  scheduling {
    preemptible      = true
    automatic_restart = false
  }
  service_account {
    scopes = ["storage-ro"]
  }
  tags = ["geoserver"]
  # Attach the persistent disk to the VM
  attached_disk {
    source      = google_compute_disk.geoserver_data.self_link
    device_name = google_compute_disk.geoserver_data.name
  }
}

# Output the public IP address of the spot instance
#output "geoserver_public_ip" {
#  value = google_compute_instance.geoserver.network_interface[0].access_config[0].nat_ip
#}

# Assuming 'google_compute_network.main' is defined elsewhere in your Terraform config

# Cloud Router
resource "google_compute_router" "geoserver_router" {
  name    = "geoserver-router"
  region  = "us-central1"
  network = google_compute_network.main.id
}

# Cloud NAT
resource "google_compute_router_nat" "geoserver_nat" {
  name                               = "geoserver-nat"
  router                             = google_compute_router.geoserver_router.name
  region                             = "us-central1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
