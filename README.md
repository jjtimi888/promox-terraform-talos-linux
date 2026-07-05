# Proxmox VE Talos Kubernetes Cluster with GitOps (Flux CD & Forgejo)

This repository contains the Terraform configurations to deploy, bootstrap, and manage a secure, production-grade **Talos Linux Kubernetes Cluster** on **Proxmox Virtual Environment (VE)**. It integrates eBPF-powered **Cilium CNI**, local dynamic persistent storage, cluster monitoring, a local Git server (**Forgejo**), and git-based reconciliation (**Flux CD**) for fully automated GitOps.

> [!NOTE]
> **Project Scope: Day 0 to Day 1 GitOps Bootstrap**
>
> | Phase | Scope | Description | Status |
> |-------|-------|-------------|:------:|
> | **Day 0** | Infrastructure & CNI | Provision VMs on Proxmox, bootstrap Talos Linux, install Cilium (kube-proxy-free) and Local Path storage | ✅ Built-in |
> | **Day 1** | GitOps & Core Apps | Pre-deploy Forgejo (Git server), Metrics Server, and Flux Operator to bootstrap GitOps reconciliation | ✅ Built-in |
> | **Day 2+** | App Workloads | Deploy workloads, ingress controllers, databases, etc. declaratively via the GitOps repo | 🔄 Managed via GitOps |

---

## 🚀 Key Features

- **Declarative Infrastructure**: Fully managed by Terraform using the `bpg/proxmox` and `siderolabs/talos` providers.
- **Talos Linux Node OS**: Security-hardened, minimal, immutable, and ephemeral Kubernetes node OS.
- **Cilium CNI (Kube-Proxy Replacement)**: High-performance routing, eBPF-based load balancing, L2 Announcements, and LoadBalancer IP pools (`192.168.100.200 - 192.168.100.240`).
- **Hubble Observability**: Real-time network visibility and flow logging with Hubble UI and Relay.
- **Dynamic Local Storage**: Rancher Local Path Provisioner configured at `/var/local-path-provisioner` (the persistent path on Talos Linux) as the default `local-path` StorageClass.
- **Private Git Server (Forgejo)**: Deployed automatically on a static LoadBalancer IP (`192.168.100.201:3000`). Auto-configures an admin account, creates the `homelab` organization, and sets up a private `gitops-fleet` repository.
- **Automated GitOps (Flux CD)**: Installs the ControlPlane Flux Operator, generates ED25519 deploy keys, registers them with Forgejo, automatically fetches SSH host keys for mutual trust, and configures the `FluxInstance` to sync the cluster state from the `gitops-fleet` repo.
- **Flux Web UI**: Exposed via a static LoadBalancer IP (`192.168.100.202`) to monitor sync status.
- **Cluster Monitoring**: Metrics Server pre-installed along with [kubelet-serving-cert-approver](file:///Users/timi/lab-learn/k8s-tf-example/manifests/kubelet-serving-cert-approver.yaml) to automatically approve node Kubelet certificates on Talos.

---

## 📂 Project Structure

- **[main.tf](file:///Users/timi/lab-learn/k8s-tf-example/main.tf)**: Call to the local `modules/proxmox-talos` module to provision Proxmox VMs and initialize the Talos cluster.
- **[cilium.tf](file:///Users/timi/lab-learn/k8s-tf-example/cilium.tf)**: Installs the Cilium Helm chart, configures L2 announcement policies, LoadBalancer IP pools, and purges flannel/kube-proxy.
- **[local-storage.tf](file:///Users/timi/lab-learn/k8s-tf-example/local-storage.tf)**: Deploys Rancher Local Path Provisioner using the local Helm chart in `charts/local-path-provisioner`.
- **[forgejo.tf](file:///Users/timi/lab-learn/k8s-tf-example/forgejo.tf)**: Provisions Forgejo Git Server, database persistence, and exposes it via LoadBalancer.
- **[flux.tf](file:///Users/timi/lab-learn/k8s-tf-example/flux.tf)**: Provisions Flux CD, sets up SSH deploy keys and known hosts, initializes the repo structure in Forgejo, and bootstraps the `FluxInstance` CR.
- **[metrics-server.tf](file:///Users/timi/lab-learn/k8s-tf-example/metrics-server.tf)**: Installs Metrics Server and `kubelet-serving-cert-approver` for node/pod resource usage statistics.
- **[outputs.tf](file:///Users/timi/lab-learn/k8s-tf-example/outputs.tf)**: Returns endpoints, node IPs, and configuration files.
- **[variables.tf](file:///Users/timi/lab-learn/k8s-tf-example/variables.tf)** & **[terraform.tfvars](file:///Users/timi/lab-learn/k8s-tf-example/terraform.tfvars)**: Customizable parameters (VM size, node IPs, passwords, etc.).
- **[scripts/](file:///Users/timi/lab-learn/k8s-tf-example/scripts)**:
  - **[set-config.sh](file:///Users/timi/lab-learn/k8s-tf-example/scripts/set-config.sh)**: Automates fetching `kubeconfig`/`talos_config` and writing them to standard paths.
  - **[remove-tf.sh](file:///Users/timi/lab-learn/k8s-tf-example/scripts/remove-tf.sh)**: Helper to clean up local Terraform state files and cache (for developers).

---

## 🛠️ Prerequisites

1. A running **Proxmox VE** instance (configured at `https://192.168.100.252:8006/` or customized in `terraform.tfvars`).
2. **Talos Linux OS image** uploaded to Proxmox.
3. **Terraform CLI**, **kubectl**, and **talosctl** installed locally.
4. Credentials configured via environment variables (`PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD`).

---

## ⚡ Deployment & Setup Guide

### 1. Initialize and Apply Terraform
Initialize the working directory and apply the configuration to spin up the cluster and install all bootstrap applications:
```bash
terraform init
terraform apply
```

### 2. Configure Local Clients (kubeconfig & talosconfig)
Run the helper script to generate the configuration files and copy them to standard directories (`~/.kube/config` and `~/.talos/config`):
```bash
./scripts/set-config.sh
```

You can now test access to the cluster:
```bash
kubectl get nodes -o wide
talosctl containers -n <control-plane-ip>
```

### 3. Verify Deployed Services
Check the statuses of the core services and their corresponding pods:
```bash
# Verify Cilium & storage
kubectl get pods -n kube-system
kubectl get sc

# Verify Forgejo
kubectl get pods -n forgejo

# Verify Flux
kubectl get pods -n flux-system
```

---

## 🔗 Service Endpoints & Access

Once deployment completes, the following services are available:

| Service | Protocol/URL | Default Credentials / Settings |
|---------|--------------|--------------------------------|
| **Forgejo Git Server** | [http://192.168.100.201:3000/](http://192.168.100.201:3000/) | Username: `git-admin` / Password: `admin@6868` |
| **GitOps Repository** | [http://192.168.100.201:3000/homelab/gitops-fleet](http://192.168.100.201:3000/homelab/gitops-fleet) | Pre-populated with `./clusters/talos-cluster/kustomization.yaml` |
| **Flux Operator Web UI** | [http://192.168.100.202/](http://192.168.100.202/) | Access via web browser to inspect GitOps sync state |

---

## 🔄 Day 1 GitOps Reconciliation Flow

After the Day 0 Terraform apply completes, the cluster is automatically configured with a self-healing reconciliation loop:

```mermaid
graph TD
    A[Local Developer] -->|git push| B(Forgejo Repository: gitops-fleet)
    B -->|SSH sync| C[Flux Source Controller]
    C -->|Reconcile Manifests| D[Flux Kustomize Controller]
    D -->|Apply Changes| E[Kubernetes Cluster API]
    E -->|Pod/Service/PVC| F[Running Resources]
    
    subgraph GitOps Loop
        C
        D
    end
```

To deploy new applications or modify cluster settings:
1. Clone the GitOps fleet repository:
   ```bash
   git clone http://192.168.100.201:3000/homelab/gitops-fleet.git
   ```
2. Place your Kubernetes manifests or Helm releases in the repository.
3. Reference them in the `kustomization.yaml` under `./clusters/talos-cluster/`.
4. Commit and push your changes. Flux will apply them within minutes automatically.

---

## 🧹 Tear Down & Reset
To fully destroy the Kubernetes cluster and delete all resources from Proxmox:
```bash
terraform destroy
```
If you wish to do a clean reset of the local Terraform states, run:
```bash
./scripts/remove-tf.sh -y
```
