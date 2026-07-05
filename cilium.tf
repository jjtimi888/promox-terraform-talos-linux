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
  kubernetes {
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
  version    = "1.19.5"
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

    bpf:
      hostLegacyRouting: true

    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
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
        - eth0
      externalIPs: true
      loadBalancerIPs: true
  YAML
  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "cilium_lb_ip_pool" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v2alpha1
    kind: CiliumLoadBalancerIPPool
    metadata:
      name: default-lb-pool
      namespace: kube-system
    spec:
      cidrs:
        - 192.168.100.200-192.168.100.240
  YAML
  depends_on = [helm_release.cilium]
}

resource "terraform_data" "clean_default_cni_and_proxy" {
  input = module.talos.kubeconfig

  provisioner "local-exec" {
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > kubeconfig_temp
      export KUBECONFIG=kubeconfig_temp
      trap "rm -f kubeconfig_temp" EXIT
      kubectl delete daemonset kube-flannel -n kube-system --ignore-not-found
      kubectl delete configmap kube-flannel-cfg -n kube-system --ignore-not-found
      kubectl delete serviceaccount flannel -n kube-system --ignore-not-found
      kubectl delete clusterrole flannel --ignore-not-found
      kubectl delete clusterrolebinding flannel --ignore-not-found
      kubectl delete daemonset kube-proxy -n kube-system --ignore-not-found
    EOT
    environment = {
      KUBECONFIG_CONTENT = self.input
    }
  }

  depends_on = [helm_release.cilium]
}

