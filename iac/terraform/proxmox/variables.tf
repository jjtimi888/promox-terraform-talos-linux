# Copyright (c) Timi

# -----------------------------------------------------------------------------
# Proxmox Provider
# -----------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Talos Cluster
# -----------------------------------------------------------------------------

variable "talos_cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-cluster"
}

variable "talos_version" {
  description = "Version of Talos to use"
  type        = string
}

# -----------------------------------------------------------------------------
# Control Plane VMs
# -----------------------------------------------------------------------------

variable "proxmox_control_vm_cores" {
  description = "Number of CPU cores for the control plane VMs"
  type        = number
  default     = 2
}

variable "proxmox_control_vm_memory" {
  description = "Memory in MB for the control plane VMs"
  type        = number
  default     = 4096
}

variable "proxmox_control_vm_disk_size" {
  description = "Disk size in GB for the control plane VMs"
  type        = number
  default     = 20
}

# -----------------------------------------------------------------------------
# Worker VMs
# -----------------------------------------------------------------------------

variable "proxmox_worker_vm_cores" {
  description = "Number of CPU cores for the worker VMs"
  type        = number
  default     = 2
}

variable "proxmox_worker_vm_memory" {
  description = "Memory in MB for the worker VMs"
  type        = number
  default     = 2048
}

variable "proxmox_worker_vm_disk_size" {
  description = "Disk size in GB for the worker VMs"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# Node Definitions
# -----------------------------------------------------------------------------

variable "control_nodes" {
  description = "Map of Talos control node names to Proxmox node names"
  type        = map(string)
  default = {
    "talos-control" = "pve"
  }
}

variable "worker_nodes" {
  description = "Map of Talos worker node names to Proxmox node names"
  type        = map(string)
  default = {
    "talos-worker-01" = "pve"
    "talos-worker-02" = "pve"
    "talos-worker-03" = "pve"
  }
}

# -----------------------------------------------------------------------------
# MAC Addresses (for static DHCP assignment)
# -----------------------------------------------------------------------------

variable "control_plane_mac_addresses" {
  description = "Map of control plane node names to MAC addresses"
  type        = map(string)
  default     = {}
}

variable "worker_mac_addresses" {
  description = "Map of worker node names to MAC addresses"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Machine Config Patches
# -----------------------------------------------------------------------------

variable "control_machine_config_patches" {
  description = "List of YAML patches to apply to the control machine configuration"
  type        = list(string)
  default = [
    <<-EOT
    machine:
      install:
        disk: "/dev/vda"
      kubelet:
        extraArgs:
          rotate-server-certificates: true
    cluster:
      network:
        cni:
          name: none
      proxy:
        disabled: true
    EOT
  ]
}

variable "worker_machine_config_patches" {
  description = "List of YAML patches to apply to the worker machine configuration"
  type        = list(string)
  default = [
    <<-EOT
    machine:
      install:
        disk: "/dev/vda"
      kubelet:
        extraArgs:
          rotate-server-certificates: true
    cluster:
      network:
        cni:
          name: none
      proxy:
        disabled: true
    EOT
  ]
}

# -----------------------------------------------------------------------------
# Cilium
# -----------------------------------------------------------------------------

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.5"
}

variable "lb_pool_start" {
  description = "Start IP for the Cilium LoadBalancer IP pool"
  type        = string
  default     = "192.168.100.200"
}

variable "lb_pool_stop" {
  description = "Stop IP for the Cilium LoadBalancer IP pool"
  type        = string
  default     = "192.168.100.240"
}

# -----------------------------------------------------------------------------
# GitHub Configuration
# -----------------------------------------------------------------------------

variable "github_owner" {
  description = "GitHub owner (username or organization)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name for GitOps fleet"
  type        = string
  default     = "promox-terraform-talos-linux"
}

variable "primary_worker_node" {
  description = "The worker node name to pin platform services (like L2 announcement) on"
  type        = string
  default     = "talos-worker-01"
}
