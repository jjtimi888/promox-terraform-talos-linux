# Copyright (c) Timi

resource "helm_release" "forgejo" {
  name             = "forgejo"
  repository       = "oci://code.forgejo.org/forgejo-helm"
  chart            = "forgejo"
  version          = "17.1.1"
  namespace        = "forgejo"
  create_namespace = true

  # Ensure the local path provisioner is running before deploying Forgejo
  depends_on = [helm_release.local_path_provisioner]

  values = [
    <<-EOT
    # Disable default database subcharts (PostgreSQL and Redis Cluster)
    redis-cluster:
      enabled: false
    postgresql-ha:
      enabled: false
    postgresql:
      enabled: false

    # Pin Forgejo Image Tag to 15.0.3-rootless
    image:
      repository: forgejo/forgejo
      tag: "15.0.3-rootless"

    # Configure SQLite database inside the Forgejo container
    gitea:
      config:
        database:
          DB_TYPE: sqlite3
          PATH: /data/gitea/gitea.db
        server:
          ROOT_URL: "http://${var.forgejo_ip}:3000/"
          DOMAIN: "${var.forgejo_ip}"
          SSH_DOMAIN: "${var.forgejo_ip}"

      # Initial Administrator Credentials
      admin:
        username: "${var.forgejo_admin_user}"
        password: "${var.forgejo_admin_password}"
        email: "${var.forgejo_admin_email}"
        passwordMode: keepUpdated

    # Storage and Persistence
    persistence:
      enabled: true
      storageClass: "local-path"
      size: 10Gi
      annotations:
        helm.sh/resource-policy: null

    # Pin pod to worker node for local-path dynamic directories
    nodeSelector:
      kubernetes.io/hostname: "${var.forgejo_pin_node}"

    # Expose HTTP Service on static Cilium IP
    service:
      http:
        type: LoadBalancer
        annotations:
          io.cilium/lb-ipam-ips: "${var.forgejo_ip}"
      ssh:
        type: ClusterIP
    EOT
  ]
}

# Wait for Forgejo to be ready and responsive
resource "null_resource" "wait_for_forgejo" {
  depends_on = [helm_release.forgejo]

  provisioner "local-exec" {
    command = <<-EOT
      echo "$KUBECONFIG_CONTENT" > forgejo_kubeconfig
      export KUBECONFIG=forgejo_kubeconfig

      echo "Waiting for Forgejo deployment rollout..."
      kubectl rollout status deployment/forgejo -n forgejo --timeout=300s

      echo "Checking HTTP response at http://${var.forgejo_ip}:3000..."
      for i in {1..30}; do
        if curl -sk --connect-timeout 2 "http://${var.forgejo_ip}:3000" > /dev/null; then
          echo "Forgejo HTTP endpoint is ready!"
          rm forgejo_kubeconfig
          exit 0
        fi
        echo "Waiting for HTTP endpoint... attempt $i/30"
        sleep 5
      done
      echo "Timeout waiting for Forgejo HTTP"
      rm forgejo_kubeconfig
      exit 1
    EOT

    environment = {
      KUBECONFIG_CONTENT = module.talos.kubeconfig
    }
  }
}

