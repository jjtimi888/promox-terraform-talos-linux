# Copyright (c) Timi

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
  }
}