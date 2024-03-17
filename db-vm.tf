resource "google_compute_instance" "postgres_instance" {
  name         = "postgres-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-2204-lts"
      size  = 10
    }
  }

  network_interface {
    network = "projects/linear-equator-414922/regions/us-central1/subnetworks/appraise-private-network"
  }

metadata = {
    "gce-container-declaration" = module.gce-container.metadata_value
}

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
