resource "google_compute_instance" "postgres_instance" {
  name         = "postgres-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      #image = "cos-cloud/cos-stable"
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
    }
  }

  network_interface {
    network = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/${google_compute_network.main.name}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash

    # Install Docker
    apt-get update
    apt-get install -y docker.io

    # Start Docker service
    systemctl start docker
    systemctl enable docker

    # Run the Postgres container using the gce-container module
    docker run -d -p 5432:5432 \
      --name postgres \
      -e POSTGRES_DB=${module.gce-container.container.env[0].value} \
      -e POSTGRES_USER=${module.gce-container.container.env[1].value} \
      -e POSTGRES_PASSWORD=${module.gce-container.container.env[2].value} \
      -e PGDATA=${module.gce-container.container.env[3].value} \
      -v ${module.gce-container.volumes[0].gcePersistentDisk.pdName}:${module.gce-container.container.volumeMounts[0].mountPath} \
      ${module.gce-container.container.image}
  EOF

  scheduling {
    preemptible      = true
    automatic_restart = false
  }
  tags = ["allow-postgres", "allow-ssh", "allow-gcr-access"]

  service_account {
    scopes = ["cloud-platform"]
  }
  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
  attached_disk {
    source      = google_compute_disk.postgres_data.self_link
    device_name = google_compute_disk.postgres_data.name
  }
}

resource "google_compute_firewall" "postgres_firewall" {
  name    = "allow-postgres-access"
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

resource "google_compute_firewall" "allow_gcr_access" {
  name    = "allow-gcr-access"
  network = google_compute_network.main.self_link

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  direction          = "EGRESS"
  destination_ranges = ["199.36.153.8/30", "199.36.153.4/30"]
  target_tags        = ["allow-gcr-access"]
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
        value = "/var/lib/postgresql/data/postgres"
      }
    ]

    volumeMounts = [
      {
        mountPath = "/var/lib/postgresql/data"
        name      = "data"
        readOnly  = false
        subPath   = "postgres"
      }
    ]
  }

  volumes = [
    {
      name = "data"

      gcePersistentDisk = {
        pdName = google_compute_disk.postgres_data.name
        fsType = "ext4"
      }
    }
  ]

  restart_policy = "Always"
}
