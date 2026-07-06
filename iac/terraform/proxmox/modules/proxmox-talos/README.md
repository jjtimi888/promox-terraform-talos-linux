# proxmox-talos

Terraform module to provision Talos Linux Kubernetes clusters on Proxmox VE.

## Features

- Downloads Talos images from [Talos Factory](https://factory.talos.dev/) with custom schematic support
- Creates control plane and worker VMs on Proxmox with configurable CPU, memory, and disk
- Supports multi-node Proxmox clusters (VMs can be placed on different Proxmox nodes)
- Generates Talos machine secrets, applies machine configs, and bootstraps the cluster
- Waits for cluster health before exposing kubeconfig
- Optional VLAN, MAC address pinning (for DHCP reservations), and extra worker disks
- Custom machine config patches for both control plane and worker nodes

## Requirements

| Provider | Version |
|----------|---------|
| [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) | `~> 0.111.1` |
| [siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos/latest) | `~> 0.11.0` |

## Usage

```hcl
module "talos_cluster" {
  source = "./modules/proxmox-talos"

  talos_cluster_name = "my-cluster"
  talos_version      = "1.10.2"

  control_nodes = {
    "cp-0" = "pve-node-1"
  }

  worker_nodes = {
    "worker-0" = "pve-node-1"
    "worker-1" = "pve-node-2"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `talos_cluster_name` | Name of the Talos cluster | `string` | — | yes |
| `talos_version` | Talos OS version | `string` | — | yes |
| `control_nodes` | Map of control node names → Proxmox node names | `map(string)` | — | yes |
| `worker_nodes` | Map of worker node names → Proxmox node names | `map(string)` | — | yes |
| `talos_schematic_id` | Talos Factory schematic ID (must include `qemu-guest-agent`) | `string` | `"ce4c98..."` | no |
| `talos_arch` | CPU architecture (`amd64` / `arm64`) | `string` | `"amd64"` | no |
| `cluster_endpoint` | VIP or LB address for the K8s API. Falls back to first control node IP | `string` | `null` | no |
| `primary_control_node_name` | Control node used for bootstrap. Required when >1 control node | `string` | `null` | no |
| `proxmox_control_vm_cores` | CPU cores for control plane VMs | `number` | `4` | no |
| `proxmox_worker_vm_cores` | CPU cores for worker VMs | `number` | `4` | no |
| `proxmox_control_vm_memory` | Memory (MB) for control plane VMs | `number` | `4096` | no |
| `proxmox_worker_vm_memory` | Memory (MB) for worker VMs | `number` | `4096` | no |
| `proxmox_control_vm_disk_size` | Disk size (GB) for control plane VMs | `number` | `32` | no |
| `proxmox_worker_vm_disk_size` | Disk size (GB) for worker VMs | `number` | `100` | no |
| `proxmox_iso_datastore` | Datastore for the Talos qcow2 image | `string` | `"local"` | no |
| `proxmox_image_datastore` | Datastore for VM disks | `string` | `"local-lvm"` | no |
| `proxmox_vm_type` | Emulated CPU type | `string` | `"x86-64-v2-AES"` | no |
| `proxmox_network_bridge` | Network bridge | `string` | `"vmbr0"` | no |
| `proxmox_network_vlan_id` | VLAN ID (optional) | `number` | `null` | no |
| `proxmox_control_pool_id` | Proxmox pool for control VMs | `string` | `null` | no |
| `proxmox_worker_pool_id` | Proxmox pool for worker VMs | `string` | `null` | no |
| `network_interface_index` | Guest agent network interface index for IP discovery | `number` | `7` | no |
| `control_plane_mac_addresses` | Map of control node names → MAC addresses | `map(string)` | `{}` | no |
| `worker_mac_addresses` | Map of worker node names → MAC addresses | `map(string)` | `{}` | no |
| `control_machine_config_patches` | YAML patches for control plane machine config | `list(string)` | install disk `/dev/vda` | no |
| `worker_machine_config_patches` | YAML patches for worker machine config | `list(string)` | install disk `/dev/vda` | no |
| `worker_extra_disks` | Extra disks per worker node | `map(list(object))` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `talos_config` | Talos client configuration (sensitive) |
| `kubeconfig` | Cluster kubeconfig (sensitive) |
| `control_plane_ips` | List of control plane node IPs |
| `worker_ips` | List of worker node IPs |
| `all_node_ips` | All node IPs (control + workers) |

## Notes

- This module does **not** install a CNI. Deploy one (e.g., Cilium) after the cluster is up.
- `skip_kubernetes_checks = true` is set on health checks because nodes stay `NotReady` until a CNI is installed.
- The default `talos_schematic_id` includes the `qemu-guest-agent` extension. Generate your own at [factory.talos.dev](https://factory.talos.dev/) — make sure to include this extension.

## License

MIT
