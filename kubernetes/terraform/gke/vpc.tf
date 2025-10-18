resource "google_compute_network" "vpc" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "${local.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

resource "google_compute_router" "router" {
  name    = "${local.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name   = "${local.cluster_name}-nat"
  router = google_compute_router.router.name
  region = var.gcp_region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr
  ]
}

resource "google_compute_firewall" "allow_webrtc" {
  name    = "${local.cluster_name}-allow-webrtc"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "3478"]
  }

  allow {
    protocol = "udp"
    ports    = ["3478", "49152-65535"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["renny-node"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${local.cluster_name}-allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
}
