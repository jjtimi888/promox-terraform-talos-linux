# Copyright (c) Timi

# -----------------------------------------------------------------------------
# Talos Outputs
# -----------------------------------------------------------------------------

output "talos_config" {
  description = "Talos client configuration file"
  value       = module.talos.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes kubeconfig file"
  value       = module.talos.kubeconfig
  sensitive   = true
}

output "control_plane_ips" {
  description = "List of control plane node IPs"
  value       = module.talos.control_plane_ips
}

output "worker_ips" {
  description = "List of worker node IPs"
  value       = module.talos.worker_ips
}

output "all_node_ips" {
  description = "List of all node IPs (control + workers)"
  value       = module.talos.all_node_ips
}

# -----------------------------------------------------------------------------
# GitOps Outputs
# -----------------------------------------------------------------------------

output "gitops_repo_url" {
  description = "The HTTP URL to access the GitOps fleet repository on GitHub"
  value       = "https://github.com/${var.github_owner}/${var.github_repository}"
}