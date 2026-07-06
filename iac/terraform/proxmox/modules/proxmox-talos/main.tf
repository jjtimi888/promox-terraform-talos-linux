# Copyright (c) Timi

locals {
  all_proxmox_nodes         = distinct(concat(values(var.control_nodes), values(var.worker_nodes)))
  primary_control_node_name = var.primary_control_node_name != null ? var.primary_control_node_name : one(keys(var.control_nodes))
  primary_control_node_ip   = [for ip in flatten(proxmox_virtual_environment_vm.talos_control_vm[local.primary_control_node_name].ipv4_addresses) : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0]
  control_node_ips          = [for vm in keys(var.control_nodes) : [for ip in flatten(proxmox_virtual_environment_vm.talos_control_vm[vm].ipv4_addresses) : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0]]
  worker_node_ips           = [for vm in keys(var.worker_nodes) : [for ip in flatten(proxmox_virtual_environment_vm.talos_worker_vm[vm].ipv4_addresses) : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0]]
  cluster_endpoint          = coalesce(var.cluster_endpoint, local.primary_control_node_ip)
  node_ips = concat(
    local.control_node_ips,
    local.worker_node_ips
  )
}

resource "proxmox_download_file" "talos_image" {
  for_each            = toset(local.all_proxmox_nodes)
  content_type        = "iso"
  datastore_id        = var.proxmox_iso_datastore
  node_name           = each.value
  url                 = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/metal-${var.talos_arch}.qcow2"
  file_name           = "${var.talos_cluster_name}-talos_linux-${var.talos_schematic_id}-${var.talos_version}-${var.talos_arch}.img"
  overwrite           = true
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "talos_control_vm" {
  for_each  = var.control_nodes
  name      = each.key
  node_name = each.value
  pool_id   = var.proxmox_control_pool_id
  on_boot   = true
  started   = true
  agent {
    enabled = true
    wait_for_ip {
      ipv4 = true
    }
  }
  cpu {
    cores = var.proxmox_control_vm_cores
    type  = var.proxmox_vm_type
  }
  memory {
    dedicated = var.proxmox_control_vm_memory
    floating  = var.proxmox_control_vm_memory
  }
  disk {
    datastore_id = var.proxmox_image_datastore
    file_id      = proxmox_download_file.talos_image[each.value].id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.proxmox_control_vm_disk_size
  }
  network_device {
    vlan_id     = var.proxmox_network_vlan_id
    bridge      = var.proxmox_network_bridge
    mac_address = lookup(var.control_plane_mac_addresses, each.key, null)
  }
  operating_system {
    type = "l26"
  }
  lifecycle {
    ignore_changes = [disk]
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker_vm" {
  for_each  = var.worker_nodes
  name      = each.key
  node_name = each.value
  pool_id   = var.proxmox_worker_pool_id
  on_boot   = true
  started   = true
  agent {
    enabled = true
    wait_for_ip {
      ipv4 = true
    }
  }
  cpu {
    cores = var.proxmox_worker_vm_cores
    type  = var.proxmox_vm_type
  }
  memory {
    dedicated = var.proxmox_worker_vm_memory
    floating  = var.proxmox_worker_vm_memory
  }
  disk {
    datastore_id = var.proxmox_image_datastore
    file_id      = proxmox_download_file.talos_image[each.value].id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.proxmox_worker_vm_disk_size
  }
  network_device {
    vlan_id     = var.proxmox_network_vlan_id
    bridge      = var.proxmox_network_bridge
    mac_address = lookup(var.worker_mac_addresses, each.key, null)
  }
  dynamic "disk" {
    for_each = lookup(var.worker_extra_disks, each.key, [])
    content {
      datastore_id = disk.value.datastore_id
      file_format  = disk.value.file_format
      file_id      = disk.value.file_id
      interface    = "virtio${disk.key + 1}"
      iothread     = true
      discard      = "on"
      size         = disk.value.size
    }
  }
  operating_system {
    type = "l26"
  }
  lifecycle {
    ignore_changes = [disk]
  }
}

resource "talos_machine_secrets" "talos_secrets" {
  lifecycle {
    # For production, it is recommended to set this to true.
    prevent_destroy = false
  }
}

data "talos_machine_configuration" "control_mc" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.talos_secrets.machine_secrets
}

data "talos_machine_configuration" "worker_mc" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.talos_secrets.machine_secrets
}

data "talos_client_configuration" "talos_client_config" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.talos_secrets.client_configuration
  endpoints            = local.control_node_ips
  nodes                = local.node_ips
}

resource "talos_machine_configuration_apply" "talos_control_mc_apply" {
  for_each                    = var.control_nodes
  client_configuration        = talos_machine_secrets.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_mc.machine_configuration
  node                        = [for ip in flatten(proxmox_virtual_environment_vm.talos_control_vm[each.key].ipv4_addresses) : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0]
  config_patches = concat(var.control_machine_config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    })
  ])
}

resource "talos_machine_configuration_apply" "talos_worker_mc_apply" {
  for_each                    = var.worker_nodes
  client_configuration        = talos_machine_secrets.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_mc.machine_configuration
  node                        = [for ip in flatten(proxmox_virtual_environment_vm.talos_worker_vm[each.key].ipv4_addresses) : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0]
  config_patches = concat(var.worker_machine_config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    })
  ])
}

# You only need to bootstrap 1 control node, so use the configured primary.
resource "talos_machine_bootstrap" "talos_bootstrap" {
  depends_on           = [talos_machine_configuration_apply.talos_control_mc_apply]
  node                 = local.primary_control_node_ip
  client_configuration = talos_machine_secrets.talos_secrets.client_configuration
}

# Wait for the cluster to be healthy before exposing kubeconfig.
# skip_kubernetes_checks = true because nodes won't be Ready until CNI (Cilium) is installed.
# This still validates etcd health and Talos API responsiveness.
data "talos_cluster_health" "health" {
  depends_on = [
    talos_machine_configuration_apply.talos_control_mc_apply,
    talos_machine_configuration_apply.talos_worker_mc_apply,
    talos_machine_bootstrap.talos_bootstrap,
  ]
  client_configuration   = talos_machine_secrets.talos_secrets.client_configuration
  control_plane_nodes    = local.control_node_ips
  worker_nodes           = local.worker_node_ips
  endpoints              = local.control_node_ips
  skip_kubernetes_checks = true

  timeouts = {
    read = "5m"
  }
}

resource "talos_cluster_kubeconfig" "talos_kubeconfig" {
  depends_on = [
    talos_machine_bootstrap.talos_bootstrap,
    data.talos_cluster_health.health,
  ]
  client_configuration = talos_machine_secrets.talos_secrets.client_configuration
  node                 = local.primary_control_node_ip
}