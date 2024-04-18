# Create secrets in Google Secret Manager
resource "google_secret_manager_secret" "db_user" {
  secret_id = "db_user"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_user_version" {
  secret      = google_secret_manager_secret.db_user.id
  secret_data = "postgres"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "db_password"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = "ZGC5uft4pgm@eqt0bqm"
}

resource "google_secret_manager_secret" "db_name" {
  secret_id = "db_name"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_name_version" {
  secret      = google_secret_manager_secret.db_name.id
  secret_data = "appraisedb"
}

# Grant access to the secrets to the Cloud Run service account
resource "google_secret_manager_secret_iam_member" "db_user_access" {
  secret_id = google_secret_manager_secret.db_user.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_secret_manager_secret_iam_member" "db_name_access" {
  secret_id = google_secret_manager_secret.db_name.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runsa.email}"
}

