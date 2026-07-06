# Proxmox VE Talos Kubernetes Cluster with GitOps (Flux CD & GitHub)

This repository contains the Terraform and GitOps configurations to deploy, bootstrap, and manage a secure, production-grade **Talos Linux Kubernetes Cluster** on **Proxmox Virtual Environment (VE)**. It integrates eBPF-powered **Cilium CNI**, local dynamic persistent storage, cluster monitoring, and git-based reconciliation (**Flux CD**) using a **GitHub repository** for fully automated GitOps.

> [!NOTE]
> **Project Scope: Day 0 to Day 1 GitOps Bootstrap**
>
> | Phase | Scope | Description | Status |
> |-------|-------|-------------|:------:|
> | **Day 0** | Infrastructure & CNI Bootstrap | Provision VMs on Proxmox, bootstrap Talos Linux, and install initial bootstrapping Cilium (kube-proxy-free) | ✅ Built-in |
> | **Day 1** | GitOps & Core Infrastructure | Bootstrapping GitOps via Flux Operator, then reconcile core infra (Cilium updates, Local Path storage, Metrics Server, and Flux Web UI) using GitOps | ✅ Built-in |
> | **Day 2+** | App Workloads | Deploy workloads, ingress controllers, databases, etc. declaratively via the GitOps repo | 🔄 Managed via GitOps |

---

## 🚀 Key Features

- **Declarative Infrastructure (Day 0)**: VM provisioning on Proxmox and Talos cluster bootstrap fully managed by Terraform using the `bpg/proxmox` and `siderolabs/talos` providers.
- **Talos Linux Node OS (Day 0)**: Security-hardened, minimal, immutable, and ephemeral Kubernetes node OS.
- **Cilium CNI (Day 0 / Day 1)**: Bootstrapped initially via Terraform (Day 0) to provide essential cluster networking, and subsequently updated and managed (including L2 Announcements and LoadBalancer IP pools `192.168.100.200 - 192.168.100.240`) via GitOps (Day 1).
- **Hubble Observability (Day 1)**: Real-time network visibility and flow logging with Hubble UI and Relay, managed via the Cilium Helm Release in GitOps.
- **Dynamic Local Storage (Day 1)**: Rancher Local Path Provisioner deployed via GitOps and configured at `/var/local-path-provisioner` (the persistent path on Talos Linux) as the default `local-path` StorageClass.
- **Automated GitOps (Day 0)**: Installs the ControlPlane Flux Operator and applies the `FluxInstance` via Terraform to establish the GitOps reconciliation loop.
- **Flux Web UI (Day 1)**: Exposed via a static LoadBalancer IP (`192.168.100.202`) to monitor sync status, managed declaratively under GitOps.
- **Cluster Monitoring & Kubelet Certificates (Day 1)**: Metrics Server and [kubelet-serving-cert-approver.yaml](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/metrics-server/kubelet-serving-cert-approver.yaml) (which automatically approves node Kubelet certificates on Talos) are deployed via GitOps.

---

## 📂 Project Structure

### Infrastructure-as-Code (Terraform)
All infrastructure-as-code files are located under the [iac/terraform/proxmox/](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox) directory:
- **[main.tf](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/main.tf)**: Call to the local `modules/proxmox-talos` module to provision Proxmox VMs and initialize the Talos cluster.
- **[bootstrap-cilium.tf](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/bootstrap-cilium.tf)**: Bootstraps initial Cilium Helm release, default L2 announcement policies, and LoadBalancer IP pools on Day 0 (configured to ignore subsequent changes to allow GitOps lifecycle management).
- **[bootstrap-flux.tf](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/bootstrap-flux.tf)**: Provisions the ControlPlane Flux Operator and bootstraps the `FluxInstance` CR pointing to the GitHub GitOps repository.
- **[outputs.tf](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/outputs.tf)**: Returns endpoints, node IPs, and configuration files.
- **[variables.tf](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/variables.tf)** & **[terraform.tfvars](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/terraform.tfvars)**: Customizable parameters (VM size, node IPs, GitHub owner/repo, etc.).
- **[scripts/](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/scripts)**:
  - **[set-config.sh](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/scripts/set-config.sh)**: Automates fetching `kubeconfig`/`talos_config` and writing them to standard local paths.
  - **[remove-tf.sh](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/scripts/remove-tf.sh)**: Helper to clean up local Terraform state files and cache (for developers).

### GitOps Resources
The GitOps configuration layout is located under the [gitops/](file:///Users/timi/lab-learn/k8s-tf-example/gitops) directory:
- **[gitops/flux/](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux)**:
  - **`clusters/homelab-cluster/`**: Contains the bootstrapping configurations:
    - **`flux-system/flux-instance.yaml`**: The **`FluxInstance`** custom resource configuration syncing from GitHub. See [flux-instance.yaml](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/clusters/homelab-cluster/flux-system/flux-instance.yaml).
    - **`kustomization.yaml`**: Root Kustomization linking to all resources.
    - **`infrastructure.yaml`**: The Flux Kustomization linking to `./gitops/flux/infrastructure`.
    - **`apps.yaml`**: The Flux Kustomization linking to `./gitops/flux/apps` (depends on infrastructure).
  - **`infrastructure/`**: Core infrastructure workloads:
    - **[cilium/](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/cilium)**: Manages Cilium chart version updates, L2 Announcement policies, and LoadBalancer IP pools.
    - **[local-path-provisioner/](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/local-path-provisioner)**: Deploys Rancher Local Path Provisioner using a local Helm chart.
    - **[metrics-server/](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/metrics-server)**: Installs Metrics Server and [kubelet-serving-cert-approver.yaml](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/metrics-server/kubelet-serving-cert-approver.yaml).
    - **[flux-operator-web-lb.yaml](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/infrastructure/flux-operator-web-lb.yaml)**: Exposes the Flux Web UI via a LoadBalancer service.
  - **`apps/`**: Placeholders for application workloads managed via GitOps.

---

## 🛠️ Prerequisites

1. A running **Proxmox VE** instance (configured at `https://192.168.100.252:8006/` or customized in [terraform.tfvars](file:///Users/timi/lab-learn/k8s-tf-example/iac/terraform/proxmox/terraform.tfvars)).
2. **Talos Linux OS image** uploaded to Proxmox.
3. **Terraform CLI**, **kubectl**, and **talosctl** installed locally.
4. Credentials configured via environment variables (`PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD`).

---

## ⚡ Deployment & Setup Guide

### 1. Initialize and Apply Terraform
Navigate to the Terraform configuration directory, initialize the working directory, and apply the configuration to spin up the cluster and install all bootstrap applications:
```bash
cd iac/terraform/proxmox
terraform init
terraform apply
```

### 2. Configure Local Clients (kubeconfig & talosconfig)
From the `iac/terraform/proxmox` directory, run the helper script to generate the configuration files and copy them to standard directories (`~/.kube/config` and `~/.talos/config`):
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

# Verify Flux
kubectl get pods -n flux-system
```

---

## 🔗 Service Endpoints & Access

Once deployment completes, the following services are available:

| Service | Protocol/URL | Default Credentials / Settings |
|---------|--------------|--------------------------------|
| **GitOps Repository** | `https://github.com/<github_owner>/<github_repository>` | The GitHub repository set in `github_owner` and `github_repository` variables. |
| **Flux Operator Web UI** | [http://192.168.100.202/](http://192.168.100.202/) | Access via web browser to inspect GitOps sync state |

---

## 🔄 Day 1 GitOps Reconciliation Flow

After the Day 0 Terraform apply completes, the cluster is automatically configured with a self-healing reconciliation loop:

```mermaid
graph TD
    A[Local Developer] -->|git push| B(GitHub Repository: GitOps Fleet)
    B -->|HTTPS sync| C[Flux Source Controller]
    C -->|Reconcile Manifests| D[Flux Kustomize Controller]
    D -->|Apply Changes| E[Kubernetes Cluster API]
    E -->|Pod/Service/PVC| F[Running Resources]
    
    subgraph GitOps Loop
        C
        D
    end
```

To deploy new applications or modify cluster settings:
1. Clone your GitOps fleet repository from GitHub:
   ```bash
   git clone https://github.com/<github_owner>/<github_repository>.git
   ```
2. Place your Kubernetes manifests or Helm releases in `gitops/flux/apps/` or `gitops/flux/infrastructure/`.
3. Reference them in the `kustomization.yaml` under `gitops/flux/clusters/homelab-cluster/`.
4. Commit and push your changes. Flux will apply them within minutes automatically.

---

## 🧹 Tear Down & Reset
To fully destroy the Kubernetes cluster and delete all resources from Proxmox, run the following from `iac/terraform/proxmox/`:
```bash
terraform destroy
```
If you wish to do a clean reset of the local Terraform states, run:
```bash
./scripts/remove-tf.sh -y
```
