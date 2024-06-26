
resource "google_cloud_run_service" "fe" {
  name     = "${var.deployment_name}-fe"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.fe_image
        ports {
          container_port = 3000
        }
      }
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "8"
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
