resource "google_dns_managed_zone" "public_zone" {
  name        = "appraise-public-zone"
  dns_name    = "appraise.estate."
  description = "Public DNS zone for appraise.estate"
  visibility  = "public"

  dnssec_config {
    state = "on"
    non_existence = "nsec3"
    default_key_specs {
      algorithm = "rsasha256"
      key_length = 2048
      key_type = "keySigning"
      kind = "dnsKeySpec"
    }
    default_key_specs {
      algorithm = "rsasha256"
      key_length = 1024
      key_type = "zoneSigning"
      kind = "dnsKeySpec"
    }
  }
}

resource "google_dns_managed_zone" "appraise_gs_zone" {
  name        = "appraise-gs-zone"
  dns_name    = "gs.appraise.estate."
  description = "Private DNS zone for GS Appraise estate"
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.main.self_link
    }
  }
}

resource "google_dns_record_set" "geoserver_record" {
  name         = "gs.appraise.estate."
  managed_zone = google_dns_managed_zone.appraise_gs_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.geoserver_docker_instance.network_interface[0].network_ip]
}


resource "google_dns_managed_zone" "appraise_db_zone" {
  name        = "appraise-db-zone"
  dns_name    = "db.appraise.estate."
  description = "Private DNS zone for appraise estate db"
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.main.self_link
    }
  }
}

resource "google_dns_record_set" "db_record" {
  name         = "db.appraise.estate."
  managed_zone = google_dns_managed_zone.appraise_db_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.postgres_instance.network_interface[0].network_ip]
}
