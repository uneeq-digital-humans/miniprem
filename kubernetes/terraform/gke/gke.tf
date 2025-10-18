resource "google_container_cluster" "primary" {
  name     = local.cluster_name
  location = var.gcp_region

  release_channel {
    channel = "REGULAR"
  }

  min_master_version = var.kubernetes_version

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.id
  subnetwork      = google_compute_subnetwork.gke_subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  resource_labels = local.common_labels

  lifecycle {
    ignore_changes = [
      node_pool,
      initial_node_count,
    ]
  }
}
