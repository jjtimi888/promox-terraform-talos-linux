# Homelab Cluster GitOps Structure (Flux Operator)

This directory contains the Flux CD GitOps structure for the `homelab-cluster`, configured for use with the **ControlPlane Flux Operator**.

## Directory Layout

- **`apps/`**: Application workloads (e.g. databases, web servers, custom services).
- **`infrastructure/`**: Core infrastructure components (e.g. ingress controllers, cert-manager, storage systems).
- **`clusters/homelab-cluster/`**: Bootstrapping configurations and Flux sync setup.
  - **`flux-system/`**: Contains the **`FluxInstance`** custom resource configuration instead of legacy `gotk-` components.
  - **`infrastructure.yaml`**: The Flux Kustomization linking to `infrastructure/`.
  - **`apps.yaml`**: The Flux Kustomization linking to `apps/` (depends on `infrastructure`).
