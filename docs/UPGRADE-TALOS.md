# Upgrading Talos OS

Talos OS is upgraded **in-place** using `talosctl upgrade` — not by changing `talos_version` in Terraform.

> The VM resources have `lifecycle { ignore_changes = [disk] }` to prevent Terraform from recreating VMs when the version changes.

## Prerequisites

```bash
# Check current version
talosctl version --nodes <node-ip>

# Verify cluster health
talosctl health --nodes <control-plane-ip>

# Backup etcd (recommended)
talosctl etcd snapshot db.snapshot --nodes <control-plane-ip>
```

Only upgrade **one minor version** at a time (e.g. `1.13.x` → `1.14.x`).
See the [Support Matrix](https://docs.siderolabs.com/talos/v1.13/getting-started/support-matrix) for compatible Kubernetes versions.

## Upgrade Procedure

Upgrade **one node at a time**. Control plane first, then workers.

```bash
talosctl upgrade \
  --nodes <node-ip> \
  --image factory.talos.dev/installer/<schematic-id>:v<new-version>
```

Example (`1.13.5` → `1.14.0`):

```bash
# Control plane
talosctl upgrade --nodes 192.168.100.21 \
  --image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.0

# Wait for healthy, then upgrade each worker
talosctl health --nodes 192.168.100.21

talosctl upgrade --nodes 192.168.100.22 \
  --image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.0

talosctl upgrade --nodes 192.168.100.23 \
  --image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.0

talosctl upgrade --nodes 192.168.100.24 \
  --image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.0
```

## Verify

```bash
talosctl version --nodes 192.168.100.21,192.168.100.22,192.168.100.23,192.168.100.24
talosctl health --nodes 192.168.100.21
kubectl get nodes -o wide
```

## Update Terraform (optional)

After a successful upgrade, update `talos_version` in `terraform.tfvars` to keep state in sync:

```hcl
talos_version = "1.14.0"
```

## Rollback

```bash
talosctl rollback --nodes <node-ip>
```

## Upgrading Kubernetes

After upgrading Talos OS, you can also upgrade Kubernetes:

```bash
talosctl upgrade-k8s --nodes <control-plane-ip> --to <kubernetes-version>
```
