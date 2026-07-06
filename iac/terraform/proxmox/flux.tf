# Copyright (c) Timi

# 1. Create the flux-system namespace
resource "kubernetes_namespace_v1" "flux_system" {
  depends_on = [null_resource.wait_for_k8s_nodes]

  metadata {
    name = "flux-system"
  }
}

# 2. Install ControlPlane Flux Operator using Helm
resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  version          = "0.53.0"
  namespace        = kubernetes_namespace_v1.flux_system.metadata[0].name
  create_namespace = false

  values = [
    <<-EOT
    nodeSelector:
      kubernetes.io/hostname: "${var.primary_worker_node}"
    web:
      enabled: true
      networkPolicy:
        create: false
    EOT
  ]

  # Ensure namespace is available
  depends_on = [kubernetes_namespace_v1.flux_system]
}

# 3. Apply FluxInstance Custom Resource via Null Resource Local-Exec
# This avoids plan-time validation errors since the CRD is installed by Helm.
resource "null_resource" "flux_instance" {
  depends_on = [
    helm_release.flux_operator
  ]

  triggers = {
    kubeconfig = module.talos.kubeconfig
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > flux_kubeconfig
      export KUBECONFIG=flux_kubeconfig

      echo "Applying FluxInstance Custom Resource..."
      cat <<'EOF' | kubectl apply -f -
      apiVersion: fluxcd.controlplane.io/v1
      kind: FluxInstance
      metadata:
        name: flux
        namespace: flux-system
      spec:
        distribution:
          version: "2.x"
          registry: "ghcr.io/fluxcd"
        components:
          - source-controller
          - kustomize-controller
          - helm-controller
          - notification-controller
        cluster:
          type: kubernetes
          multitenant: false
          networkPolicy: false
        sync:
          kind: GitRepository
          url: "https://github.com/${var.github_owner}/${var.github_repository}.git"
          ref: "refs/heads/main"
          path: "./gitops/homelab/clusters/homelab-cluster"
      EOF

      rm flux_kubeconfig
    EOT

    environment = {
      KUBECONFIG_CONTENT = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > flux_destroy_kubeconfig
      export KUBECONFIG=flux_destroy_kubeconfig

      echo "Deleting FluxInstance Custom Resource..."
      kubectl delete fluxinstance flux -n flux-system --ignore-not-found=true --timeout=90s || true

      rm flux_destroy_kubeconfig
    EOT

    environment = {
      KUBECONFIG_CONTENT = self.triggers.kubeconfig
    }
  }
}

