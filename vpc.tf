resource "google_compute_network" "main" {
  provider                = google-beta
  name                    = "${var.deployment_name}-private-network"
  auto_create_subnetworks = true
  project                 = var.project_id
}

resource "google_compute_global_address" "main" {
  name          = "${var.deployment_name}-vpc-address"
  provider      = google-beta
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.name
  project       = var.project_id
}


resource "google_service_networking_connection" "main" {
  network                 = google_compute_network.main.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.main.name]
}


# Cloud Router
resource "google_compute_router" "geoserver_router" {
  name    = "geoserver-router"
  region  = "us-central1"
  network = google_compute_network.main.id
}

resource "google_compute_address" "geoserver_nat_ip" {
  name   = "geoserver-nat-ip"
  region = "us-central1"
}

# Cloud NAT with a specified static IP for NAT
resource "google_compute_router_nat" "geoserver_nat" {
  name                     = "geoserver-nat"
  router                   = google_compute_router.geoserver_router.name
  region                   = "us-central1"
  nat_ip_allocate_option   = "MANUAL_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  nat_ips                  = [google_compute_address.geoserver_nat_ip.id]
}

resource "google_vpc_access_connector" "serverless_connector" {
  provider      = google-beta
  name          = "${var.deployment_name}-vpc-cx"
  region        = var.region  # Ensure this matches the region of your serverless services
  network       = google_compute_network.main.name
  ip_cidr_range = "10.8.0.0/28"  # Choose a range not used within your VPC
  project       = var.project_id
}

