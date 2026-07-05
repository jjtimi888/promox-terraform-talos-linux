# Copyright (c) Timi

resource "kubernetes_namespace_v1" "local_path_storage" {
  depends_on = [null_resource.wait_for_k8s_nodes]

  metadata {
    name = "local-path-storage"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "local_path_provisioner" {
  name      = "local-path-provisioner"
  chart     = "./charts/local-path-provisioner"
  namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name

  values = [
    <<-EOT
    image:
      repository: docker.io/rancher/local-path-provisioner
      tag: v0.0.36
    storageClass:
      create: true
      name: local-path
      defaultClass: true
      reclaimPolicy: Delete
    nodePathMap:
      - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
        paths:
          - /var/mnt/local-path-provisioner
    configmap:
      name: local-path-config
      helperPod:
        tolerations:
          - key: node.kubernetes.io/disk-pressure
            operator: Exists
            effect: NoSchedule
    EOT
  ]
}
