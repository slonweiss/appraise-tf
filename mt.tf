resource "google_cloud_run_service" "mt" {
  name     = "${var.deployment_name}-mt"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email

      containers {
        env {
          name = "DB_USER"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_user.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_password.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "DB_NAME"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_name.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "DB_HOST"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_host.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "DB_PORT"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_port.secret_id
              key  = "latest"
            }
          }
        }

        image = local.api_image

        ports {
          container_port = 3000
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "8"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.serverless_connector.id
      }

      labels = {
        "run.googleapis.com/startupProbeType" = "Default"
      }
    }
  }

  metadata {
    labels = var.labels
  }

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
    ]
  }
}
