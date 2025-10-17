output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

output "region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.gke_subnet.id
}

output "node_service_account_email" {
  description = "Node service account email"
  value       = google_service_account.gke_nodes.email
}

output "renny_service_account_email" {
  description = "Renny workload service account email"
  value       = google_service_account.renny_workload.email
}

output "autoscaler_service_account_email" {
  description = "Cluster autoscaler service account email"
  value       = google_service_account.cluster_autoscaler.email
}
