# Copyright (c) Timi

locals {
  kubeconfig = yamldecode(module.talos.kubeconfig)
  cluster    = local.kubeconfig.clusters[0].cluster
  user       = local.kubeconfig.users[0].user
}

# Wait for the Kubernetes API server to become reachable after bootstrap.
# The talos_cluster_health check uses skip_kubernetes_checks = true,
# so it doesn't verify API server TCP connectivity.
# This actively polls instead of blindly sleeping.
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [module.talos]

  provisioner "local-exec" {
    command     = <<-EOT
      for i in $(seq 1 30); do
        if curl -sk --connect-timeout 2 ${local.cluster.server}/version > /dev/null 2>&1; then
          echo "K8s API is ready"
          exit 0
        fi
        echo "Waiting for K8s API... attempt $i/30"
        sleep 5
      done
      echo "K8s API not reachable after 150s"
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

provider "kubernetes" {
  host                   = local.cluster.server
  client_certificate     = base64decode(local.user.client-certificate-data)
  client_key             = base64decode(local.user.client-key-data)
  cluster_ca_certificate = base64decode(local.cluster.certificate-authority-data)
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.server
    client_certificate     = base64decode(local.user.client-certificate-data)
    client_key             = base64decode(local.user.client-key-data)
    cluster_ca_certificate = base64decode(local.cluster.certificate-authority-data)
  }
}

provider "kubectl" {
  host                   = local.cluster.server
  client_certificate     = base64decode(local.user.client-certificate-data)
  client_key             = base64decode(local.user.client-key-data)
  cluster_ca_certificate = base64decode(local.cluster.certificate-authority-data)
  load_config_file       = false
}

resource "helm_release" "cilium" {
  depends_on = [null_resource.wait_for_k8s_api]
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    ipam:
      mode: kubernetes
    kubeProxyReplacement: true
    k8sServiceHost: localhost
    k8sServicePort: 7445

    cgroup:
      autoMount:
        enabled: false
      hostRoot: /sys/fs/cgroup

    securityContext:
      capabilities:
        ciliumAgent:
          - CHOWN
          - KILL
          - NET_ADMIN
          - NET_RAW
          - IPC_LOCK
          - SYS_ADMIN
          - SYS_RESOURCE
          - DAC_OVERRIDE
          - FOWNER
          - SETGID
          - SETUID
        cleanCiliumState:
          - NET_ADMIN
          - SYS_ADMIN
          - SYS_RESOURCE

    hubble:
      enabled: true

    l2announcements:
      enabled: true

    EOT
  ]
}

resource "kubectl_manifest" "cilium_l2_announcement_policy" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v2alpha1
    kind: CiliumL2AnnouncementPolicy
    metadata:
      name: default-l2-policy
      namespace: kube-system
    spec:
      interfaces:
        - ^e.*
      externalIPs: true
      loadBalancerIPs: true
  YAML
  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "cilium_lb_ip_pool" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v2
    kind: CiliumLoadBalancerIPPool
    metadata:
      name: default-lb-pool
    spec:
      blocks:
        - start: "${var.lb_pool_start}"
          stop: "${var.lb_pool_stop}"
  YAML
  depends_on = [helm_release.cilium]
}

resource "null_resource" "wait_for_k8s_nodes" {
  depends_on = [
    helm_release.cilium,
    kubectl_manifest.cilium_l2_announcement_policy,
    kubectl_manifest.cilium_lb_ip_pool
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > temp_kubeconfig
      export KUBECONFIG=temp_kubeconfig
      for i in {1..30}; do
        nodes_output=$(kubectl get nodes --no-headers 2>&1)
        status=$?
        if [ $status -eq 0 ] && [ ! -z "$nodes_output" ]; then
          if echo "$nodes_output" | grep -q "NotReady"; then
            echo "Some nodes are not ready yet..."
          else
            echo "All nodes are Ready!"
            rm temp_kubeconfig
            exit 0
          fi
        else
          echo "K8s API not fully stable yet: $nodes_output"
        fi
        sleep 5
      done
      echo "Timeout waiting for nodes to be Ready"
      rm temp_kubeconfig
      exit 1
    EOT

    environment = {
      KUBECONFIG_CONTENT = module.talos.kubeconfig
    }
  }
}

