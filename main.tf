# Copyright (c) Timi

module "talos" {
  source             = "./modules/proxmox-talos"
  talos_cluster_name = var.talos_cluster_name
  talos_version      = var.talos_version

  proxmox_control_vm_cores     = var.proxmox_control_vm_cores
  proxmox_control_vm_memory    = var.proxmox_control_vm_memory
  proxmox_control_vm_disk_size = var.proxmox_control_vm_disk_size

  proxmox_worker_vm_cores     = var.proxmox_worker_vm_cores
  proxmox_worker_vm_memory    = var.proxmox_worker_vm_memory
  proxmox_worker_vm_disk_size = var.proxmox_worker_vm_disk_size

  control_nodes = var.control_nodes
  worker_nodes  = var.worker_nodes

  control_plane_mac_addresses = var.control_plane_mac_addresses
  worker_mac_addresses        = var.worker_mac_addresses

  control_machine_config_patches = var.control_machine_config_patches
  worker_machine_config_patches  = var.worker_machine_config_patches
}