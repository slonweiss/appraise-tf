# Create a GKE cluster
resource "google_container_cluster" "primary" {
  name     = "${var.deployment_name}-cluster"
  location = var.zone
  project  = var.project_id
  remove_default_node_pool = true
  initial_node_count = 1
  network = google_compute_network.main.name

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

# Create a Kubernetes Deployment
resource "kubernetes_deployment" "geoserver" {
  metadata {
    name = "${var.deployment_name}-geoserver"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        App = "${var.deployment_name}-geoserver"
      }
    }

    template {
      metadata {
        labels = {
          App = "${var.deployment_name}-geoserver"
        }
      }

      spec {
        container {
          image = local.geoserver_image
          name  = "geoserver"

          volume_mount {
            mount_path = "/opt/geoserver_data/"
            name       = "geoserver-disk"
          }
        }

        volume {
          name = "geoserver-disk"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.geoserver_disk.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume" "geoserver" {
  metadata {
    name = "examplevolumename"
  }
  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      gce_persistent_disk {
        pd_name = "test-123"
      }
    }
  }
}

# Create a Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "geoserver_disk" {
  metadata {
    name = "${var.deployment_name}-geoserver-disk"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}
