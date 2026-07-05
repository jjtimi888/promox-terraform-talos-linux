# Copyright (c) Timi

locals {
  kubeconfig = yamldecode(module.talos.kubeconfig)
  cluster    = local.kubeconfig.clusters[0].cluster
  user       = local.kubeconfig.users[0].user
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
