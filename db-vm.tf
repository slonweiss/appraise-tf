resource "google_compute_instance" "postgres_instance" {
  name         = "postgres-instance"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      #image = "cos-cloud/cos-stable"
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
    }
  }

  attached_disk {
    source      = google_compute_disk.postgres_data.self_link
    device_name = google_compute_disk.postgres_data.name
    mode        = "READ_WRITE"
  }
  
  network_interface {
    network = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/${google_compute_network.main.name}"
    network_ip = "10.128.0.43" 
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash
  # Install Docker
  apt-get update
  apt-get install -y docker.io

  # Start Docker service
  systemctl start docker
  systemctl enable docker

  # Create the mount directory
  mkdir -p /mnt/disks/postgres-data

  # Check if the disk already has an ext4 filesystem
  FS_TYPE=$(sudo blkid -o value -s TYPE /dev/disk/by-id/google-${google_compute_disk.postgres_data.name})

  if [ "$FS_TYPE" != "ext4" ]; then
    echo "Formatting disk as it does not have an ext4 filesystem"
    # Format the disk only if it does not have an ext4 filesystem
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${google_compute_disk.postgres_data.name}
  else
    echo "Disk already formatted with ext4, skipping format step"
  fi  
  # Mount the persistent disk
  mount -o discard,defaults /dev/disk/by-id/google-${google_compute_disk.postgres_data.name} /mnt/disks/postgres-data
  # Create the postgres container mount point directory
  mkdir -p /mnt/disks/postgres-data/pgdata

  # Check if the Postgres container is already running
  if docker ps -a --format '{{.Names}}' | grep -q '^postgres$'; then
    # Start the existing container if it's not running
    docker start postgres
  else
    # Run the Postgres container using the gce-container module
    docker run -d -p 5432:5432 \
      --name postgres \
      -e POSTGRES_DB=${module.gce-container.container.env[0].value} \
      -e POSTGRES_USER=${module.gce-container.container.env[1].value} \
      -e POSTGRES_PASSWORD=${module.gce-container.container.env[2].value} \
      -e PGDATA=${module.gce-container.container.env[3].value} \
      -v /mnt/disks/postgres-data/pgdata:${module.gce-container.container.volumeMounts[0].mountPath} \
      ${module.gce-container.container.image}
  fi

  echo "Docker complete"
  EOF

  tags = ["allow-postgres", "allow-ssh", "allow-gcr-access"]

  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
}

resource "google_compute_firewall" "postgres_firewall" {
  name    = "allow-postgres"
  network = google_compute_network.main.self_link

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  target_tags = ["allow-postgres"]

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]  # IAP's IP range
  target_tags   = ["allow-ssh"]
}


resource "google_compute_disk" "postgres_data" {
  name  = "postgres-data"
  type  = "pd-ssd"
  zone  = "us-central1-a"
  size  = 10 // Size in GB
}

module "gce-container" {
  source  = "terraform-google-modules/container-vm/google"
  version = "~> 3.1"

  container = {
    image = "postgis/postgis:15-master"
    env = [
      {
        name  = "POSTGRES_DB"
        value = "postgisdb"
      },
      {
        name  = "POSTGRES_USER"
        value = "postgres"
      },
      {
        name  = "POSTGRES_PASSWORD"
        value = "ZGC5uft4pgm@eqt0bqm"
      },
      {
        name  = "PGDATA"
        value = "/var/lib/postgresql/data"
      }
    ]

    volumeMounts = [
      {
        mountPath = "/var/lib/postgresql/data"
        name      = "data"
        readOnly  = false
      }
    ]
  }

  volumes = [
    {
      name = "data"
      hostPath = {
        path = "/mnt/disks/postgres-data"
      }
    }
  ]

  restart_policy = "Always"
}
