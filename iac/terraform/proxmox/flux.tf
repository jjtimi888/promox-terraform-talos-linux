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

  lifecycle {
    ignore_changes = [values]
  }

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
    kubeconfig    = module.talos.kubeconfig
    manifest_sha1 = sha1(file("${path.module}/../../../gitops/homelab/clusters/homelab-cluster/flux-system/flux-instance.yaml"))
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > flux_kubeconfig
      export KUBECONFIG=flux_kubeconfig

      echo "Applying FluxInstance Custom Resource from GitOps manifests..."
      kubectl apply -f ${path.module}/../../../gitops/homelab/clusters/homelab-cluster/flux-system/flux-instance.yaml

      rm flux_kubeconfig
    EOT

    environment = {
      KUBECONFIG_CONTENT = self.triggers.kubeconfig
    }
  }

}

