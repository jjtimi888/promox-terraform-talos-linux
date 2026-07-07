# Homelab Cluster GitOps Structure (Flux Operator)

This directory contains the Flux CD GitOps structure for the `homelab-cluster`, configured for use with the **ControlPlane Flux Operator**.

## Directory Layout

- **`apps/`**: Core applications bootstrapped by Flux CD. In this hybrid setup, it contains bootstrap manifests such as [argo-root.yaml](file:///Users/timi/lab-learn/k8s-tf-example/gitops/flux/apps/argo-root.yaml) to initialize Argo CD.
- **`infrastructure/`**: Core infrastructure components (e.g. ingress controllers, cert-manager, storage systems).
- **`clusters/homelab-cluster/`**: Bootstrapping configurations and Flux sync setup.
  - **`flux-system/`**: Contains the **`FluxInstance`** custom resource configuration instead of legacy `gotk-` components.
  - **`infrastructure.yaml`**: The Flux Kustomization linking to `infrastructure/`.
  - **`apps.yaml`**: The Flux Kustomization linking to `apps/` (depends on `infrastructure`).
