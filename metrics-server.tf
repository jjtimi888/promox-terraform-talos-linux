# Copyright (c) Timi

data "kubectl_file_documents" "kubelet_serving_cert_approver_docs" {
  content = file("${path.module}/manifests/kubelet-serving-cert-approver.yaml")
}

resource "kubectl_manifest" "kubelet_serving_cert_approver" {
  for_each  = data.kubectl_file_documents.kubelet_serving_cert_approver_docs.manifests
  yaml_body = each.value

  depends_on = [null_resource.wait_for_k8s_nodes]
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  cleanup_on_fail  = true

  depends_on = [
    null_resource.wait_for_k8s_nodes,
    kubectl_manifest.kubelet_serving_cert_approver
  ]
}
