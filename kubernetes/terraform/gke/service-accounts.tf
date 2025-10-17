resource "google_service_account" "gke_nodes" {
  account_id   = "${local.cluster_name}-nodes"
  display_name = "Service Account for ${local.cluster_name} GKE nodes"
}

resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_artifact_registry" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "kubernetes_service_account" "renny" {
  metadata {
    name      = "renny-sa"
    namespace = "uneeq-renderer"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.renny_workload.email
    }
  }

  depends_on = [google_container_cluster.primary]
}

resource "google_service_account" "renny_workload" {
  account_id   = "${local.cluster_name}-renny"
  display_name = "Workload Identity for Renny pods"
}

resource "google_service_account_iam_binding" "renny_workload_identity" {
  service_account_id = google_service_account.renny_workload.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[uneeq-renderer/renny-sa]"
  ]
}

resource "google_service_account" "cluster_autoscaler" {
  account_id   = "${local.cluster_name}-autoscaler"
  display_name = "Service Account for Cluster Autoscaler"
}

resource "google_project_iam_custom_role" "cluster_autoscaler" {
  role_id = replace("${local.cluster_name}_autoscaler", "-", "_")
  title   = "Cluster Autoscaler Role for ${local.cluster_name}"

  permissions = [
    "compute.instanceGroupManagers.get",
    "compute.instanceGroupManagers.list",
    "compute.instanceGroupManagers.update",
    "compute.instanceGroups.get",
    "compute.instanceGroups.list",
    "compute.instances.list",
    "compute.zones.list",
  ]
}

resource "google_project_iam_member" "cluster_autoscaler" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.cluster_autoscaler.id
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.cluster_autoscaler.email
    }
  }

  depends_on = [google_container_cluster.primary]
}

resource "google_service_account_iam_binding" "cluster_autoscaler_workload_identity" {
  service_account_id = google_service_account.cluster_autoscaler.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/cluster-autoscaler]"
  ]
}
