# Talos Kubernetes Cluster on Proxmox VE with Cilium CNI

This repository contains the Terraform configurations to deploy and bootstrap a high-performance, secure **Talos Linux Kubernetes Cluster** on **Proxmox Virtual Environment (VE)**. It integrates **Cilium CNI** in kube-proxy-free mode, including L2 announcements, LoadBalancer IP pools, and Hubble observability.

> [!NOTE]
> **This is a Day 0 (Infrastructure Provisioning) project.**
>
> | Phase | Scope | Description | Status |
> |-------|-------|-------------|:------:|
> | **Day 0** | Infrastructure Provisioning | Creating VMs on Proxmox, bootstrapping Talos cluster, installing Cilium CNI | ✅ This project |
> | **Day 1** | Application Deployment | GitOps (ArgoCD/Flux), Ingress, monitoring, workload deployment | ❌ Out of scope |
> | **Day 2** | Ongoing Operations | Upgrades, scaling, backup, alerting, incident response | ❌ Out of scope |

## 🚀 Key Features

- **Declarative Infrastructure**: Fully managed by Terraform using a local module (`modules/proxmox-talos`) with the `bpg/proxmox` and `siderolabs/talos` providers.
- **Talos Linux**: Security-hardened, minimal, immutable, and ephemeral Kubernetes node OS.
- **Cilium CNI (Kube-Proxy Replacement)**: High-performance routing, network policies, and load balancing powered by eBPF.
- **L2 Announcements & IP Pools**: Built-in bare-metal/homelab LoadBalancer support, allowing services to acquire IPs from a local pool (`192.168.100.200 - 192.168.100.240`).
- **Hubble Observability**: Real-time network visibility and flow logging with Hubble UI and Relay.
- **Automated CNI Cleanup**: Custom provisioner to purge default flannel components and `kube-proxy`.
- **Local Path Provisioner**: Configures dynamic hostPath-based Persistent Volume provisioning utilizing `/var/mnt/local-path-provisioner` across nodes as the default StorageClass, deployed using a local Helm chart.

---

## 📂 Project Structure

- **[main.tf](file:///Users/timi/lab-learn/k8s-tf-example/main.tf)**: Root configuration — calls the local `proxmox-talos` module to provision VMs and bootstrap the cluster.
- **[modules/proxmox-talos/](file:///Users/timi/lab-learn/k8s-tf-example/modules/proxmox-talos)**: Local module containing the core logic for provisioning Talos VMs on Proxmox, generating machine configs, and bootstrapping.
- **[cilium.tf](file:///Users/timi/lab-learn/k8s-tf-example/cilium.tf)**: Installs the Cilium Helm chart, configures L2 announcement policies, LoadBalancer IP pools, and cleans up legacy networking.
- **[local-storage.tf](file:///Users/timi/lab-learn/k8s-tf-example/local-storage.tf)**: Deploys Rancher Local Path Provisioner using a Helm release pointing to a local chart in **[charts/local-path-provisioner](file:///Users/timi/lab-learn/k8s-tf-example/charts/local-path-provisioner)**, configuring dynamic local storage provisioning (Persistent Volumes) and setting `local-path` as the default StorageClass.
- **[.gitignore](file:///Users/timi/lab-learn/k8s-tf-example/.gitignore)**: Prevents checking in sensitive credentials, kubeconfig, and Talos configs.

---

## 🛠️ Prerequisites

Before you begin, ensure you have:
1. A running **Proxmox VE** instance (configured at `https://192.168.100.252:8006/` or customized).
2. The **Talos Linux ISO/Image** uploaded to your Proxmox storage.
3. The **Terraform CLI** installed locally.
4. Access to your Proxmox API token/credentials (configured via environment variables or provider block).

---

## ⚙️ Configuration & Customization

### VM Configuration
In **[main.tf](file:///Users/timi/lab-learn/k8s-tf-example/main.tf)**, you can modify VM resource sizes, IP allocations, and node structure:

```hcl
module "talos" {
    source  = "./modules/proxmox-talos"
    # ...
    control_nodes = {
        "talos-control" = "pve"
    }
    worker_nodes = {
        "talos-worker-01" = "pve"
        "talos-worker-02" = "pve"
        "talos-worker-03" = "pve"
    }
    # Customize VM cores and memory
    proxmox_control_vm_cores  = 2
    proxmox_control_vm_memory = 6144
    proxmox_worker_vm_cores   = 1
    proxmox_worker_vm_memory  = 2048
}
```

### Cilium LoadBalancer IP Pool
You can change the range of IP addresses assigned to LoadBalancer services in **[cilium.tf](file:///Users/timi/lab-learn/k8s-tf-example/cilium.tf)**:

```yaml
spec:
  cidrs:
    - 192.168.100.200-192.168.100.240
```

### Local Path Storage
The local path provisioner is configured in **[local-storage.tf](file:///Users/timi/lab-learn/k8s-tf-example/local-storage.tf)** to dynamically provision volumes using node-local directories:
- **Deployment Method**: Deployed as a Helm release (`helm_release.local_path_provisioner`) pointing to the local chart at **[charts/local-path-provisioner](file:///Users/timi/lab-learn/k8s-tf-example/charts/local-path-provisioner)**.
- **Default Storage Path**: `/var/mnt/local-path-provisioner` on each cluster node (customized in the Helm release values, as `/var` is the persistent and writable directory on Talos Linux).
- **StorageClass Name**: `local-path` (automatically created and set as the default StorageClass).
- **Volume Binding Mode**: `WaitForFirstConsumer` to ensure pods are scheduled on the node before their volume is provisioned.

---

## ⚡ Deployment Guide

### 1. Initialize Terraform
Install the necessary providers and modules:
```bash
terraform init
```

### 2. Plan and Apply
Review the execution plan and deploy the VMs:
```bash
terraform plan
terraform apply
```

### 3. Download the Client Configurations and Test
The cluster kubeconfig and talosconfig are outputted as sensitive values. You can extract and set them up using:
```bash
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talos_config > talos_config.yaml
export KUBECONFIG=$(pwd)/kubeconfig
export TALOSCONFIG=$(pwd)/talos_config.yaml
```

If you wish to make this permanent run:
```bash
mkdir -p ~/.talos
cp talos_config.yaml ~/.talos/config
mkdir -p ~/.kube
cp kubeconfig ~/.kube/config
```

> [!WARNING]
> Keep your `kubeconfig` and `talos_config.yaml` files secure! These files contain administrative access credentials to your cluster and are listed in **[.gitignore](file:///Users/timi/lab-learn/k8s-tf-example/.gitignore)** to prevent accidental exposure.

### 4. Verify CNI & Hubble Status
Once deployed, check that Cilium is running and Hubble is active:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium
```

---

## 🧹 Post-Deployment Cleanups
The configuration includes a resource that automatically handles removing the legacy CNI elements (e.g., `kube-flannel` and `kube-proxy`) from the cluster to prevent interference with Cilium's eBPF features. See `terraform_data.clean_default_cni_and_proxy` in **[cilium.tf](file:///Users/timi/lab-learn/k8s-tf-example/cilium.tf)**.
