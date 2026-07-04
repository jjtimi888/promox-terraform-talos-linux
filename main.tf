terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "~> 0.111.1"
    }
    talos = {
      source = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.100.252:8006/"
  insecure = true
}

module "talos" {
    source  = "bbtechsys/talos/proxmox"
    version = "0.1.6"
    talos_cluster_name = "talos-cluster"
    talos_version = "1.13.5"

    proxmox_control_vm_cores = 2
    proxmox_control_vm_memory = 6144
    proxmox_control_vm_disk_size = 20

    proxmox_worker_vm_cores = 1
    proxmox_worker_vm_memory = 2048
    proxmox_worker_vm_disk_size = 10
    
    control_nodes = {
        "talos-control" = "pve"
    }
    worker_nodes = {
        "talos-worker-01" = "pve"
        "talos-worker-02" = "pve"
        "talos-worker-03" = "pve"
    }

    control_plane_mac_addresses = {
        "talos-control" = "BC:24:11:AA:BB:01"
    }
    worker_mac_addresses = {
        "talos-worker-01" = "BC:24:11:AA:BB:02"
        "talos-worker-02" = "BC:24:11:AA:BB:03"
        "talos-worker-03" = "BC:24:11:AA:BB:04"
    }

    control_machine_config_patches = [
      <<-EOT
      machine:
        install:
          disk: "/dev/vda"
      cluster:
        network:
          cni:
            name: none
        proxy:
          disabled: true
      EOT
    ]

    worker_machine_config_patches = [
      <<-EOT
      machine:
        install:
          disk: "/dev/vda"
      cluster:
        network:
          cni:
            name: none
        proxy:
          disabled: true
      EOT
    ]
}


output "talos_config" {
    description = "Talos configuration file"
    value       = module.talos.talos_config
    sensitive   = true
}

output "kubeconfig" {
    description = "Kubeconfig file"
    value       = module.talos.kubeconfig
    sensitive   = true
}