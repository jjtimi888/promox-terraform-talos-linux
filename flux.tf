# Copyright (c) Timi

# 1. Create the flux-system namespace
resource "kubernetes_namespace_v1" "flux_system" {
  depends_on = [null_resource.wait_for_k8s_nodes]

  metadata {
    name = "flux-system"
  }
}

# 2. Generate SSH Key Pair for Flux Git Repository Authentication
resource "tls_private_key" "flux_deploy_key" {
  algorithm = "ED25519"
}

# 3. Create the flux-system secret containing SSH Deploy Key (known_hosts will be patched dynamically on Day 0)
resource "kubernetes_secret_v1" "flux_deploy_secret" {
  metadata {
    name      = "flux-system"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data = {
    identity = tls_private_key.flux_deploy_key.private_key_openssh
  }

  lifecycle {
    ignore_changes = [
      data["known_hosts"]
    ]
  }
}

# 4. Install ControlPlane Flux Operator using Helm
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
      kubernetes.io/hostname: "${var.forgejo_pin_node}"
    web:
      networkPolicy:
        create: false
    EOT
  ]

  # Ensure namespace and Forgejo service are available
  depends_on = [kubernetes_namespace_v1.flux_system, helm_release.forgejo]
}

# 5. Custom Service to expose the Web UI via Cilium LoadBalancer on Static IP
resource "kubernetes_service_v1" "flux_operator_web_lb" {
  metadata {
    name      = "flux-operator-web-lb"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
    annotations = {
      "io.cilium/lb-ipam-ips" = var.flux_web_ip
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/name"     = "flux-operator"
      "app.kubernetes.io/instance" = "flux-operator"
    }

    port {
      name        = "http-web"
      port        = 80
      target_port = 9080
    }

    type                    = "LoadBalancer"
    external_traffic_policy = "Cluster"
  }

  depends_on = [helm_release.flux_operator]
}

# 6. Pre-create Forgejo Organization, Repository and register Flux Deploy Key
resource "null_resource" "forgejo_repo_setup" {
  depends_on = [
    null_resource.wait_for_forgejo,
    tls_private_key.flux_deploy_key
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -eo pipefail
      echo "$KUBECONFIG_CONTENT" > forgejo_kubeconfig
      export KUBECONFIG=forgejo_kubeconfig

      # Wait for a running Forgejo pod to prevent race condition
      pod_name=""
      for i in {1..30}; do
        pod_name=$(kubectl get pods -n forgejo -l app=forgejo --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$pod_name" ]; then
          break
        fi
        echo "Waiting for a running Forgejo pod... attempt $i/30"
        sleep 5
      done

      if [ -z "$pod_name" ]; then
        echo "Error: No running Forgejo pod found!"
        rm forgejo_kubeconfig
        exit 1
      fi

      echo "Using Forgejo pod: $pod_name"

      # 1. Generate API token for admin user (with scopes needed for repo, org, and user/token cleanup)
      token_name="flux-bootstrap-$(date +%s)"
      token=$(kubectl exec -n forgejo $pod_name -c forgejo -- gitea admin user generate-access-token --username "${var.forgejo_admin_user}" --token-name "$token_name" --scopes "write:repository,write:organization,write:user" --raw)
      token=$(echo "$token" | tr -d '\r\n')

      if [ -z "$token" ] || [[ "$token" == *error* ]]; then
        echo "Error: Failed to generate Gitea admin token!"
        rm forgejo_kubeconfig
        exit 1
      fi

      # 2. Create Organization if it does not exist
      org_status=$(curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: token $token" "http://${var.forgejo_ip}:3000/api/v1/orgs/${var.forgejo_org}")
      if [ "$org_status" -ne 200 ]; then
        echo "Organization '${var.forgejo_org}' does not exist. Creating..."
        curl -f -s -X POST -H "Authorization: token $token" -H "Content-Type: application/json" \
          -d '{"username": "${var.forgejo_org}"}' \
          "http://${var.forgejo_ip}:3000/api/v1/orgs"
      else
        echo "Organization '${var.forgejo_org}' already exists."
      fi

      # 3. Create repository 'gitops-fleet' if it does not exist
      http_status=$(curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: token $token" "http://${var.forgejo_ip}:3000/api/v1/repos/${var.forgejo_org}/gitops-fleet")
      if [ "$http_status" -ne 200 ]; then
        echo "Repository gitops-fleet does not exist. Creating..."
        curl -f -s -X POST -H "Authorization: token $token" -H "Content-Type: application/json" \
          -d '{"name": "gitops-fleet", "private": true, "auto_init": true}' \
          "http://${var.forgejo_ip}:3000/api/v1/orgs/${var.forgejo_org}/repos"
      else
        echo "Repository gitops-fleet already exists."
      fi

      # 4. Add deploy key if not exists
      keys_json=$(curl -s -H "Authorization: token $token" "http://${var.forgejo_ip}:3000/api/v1/repos/${var.forgejo_org}/gitops-fleet/keys")
      if echo "$keys_json" | grep -q "flux-deploy-key"; then
        echo "Deploy key flux-deploy-key already exists in repository."
      else
        echo "Adding deploy key to repository..."
        curl -f -s -X POST -H "Authorization: token $token" -H "Content-Type: application/json" \
          -d '{"title": "flux-deploy-key", "key": "'"$DEPLOY_KEY"'", "read_only": true}' \
          "http://${var.forgejo_ip}:3000/api/v1/repos/${var.forgejo_org}/gitops-fleet/keys"
      fi

      # 5. Initialize clusters/${var.talos_cluster_name}/kustomization.yaml if it does not exist
      kust_status=$(curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: token $token" \
        "http://${var.forgejo_ip}:3000/api/v1/repos/${var.forgejo_org}/gitops-fleet/contents/clusters/${var.talos_cluster_name}/kustomization.yaml")
      if [ "$kust_status" -ne 200 ]; then
        echo "Initializing kustomization.yaml..."
        kust_content="YXBpVmVyc2lvbjoga3VzdG9taXplLmNvbmZpZy5rOHMuaW8vdjFiZXRhMQpraW5kOiBLdXN0b21pemF0aW9uCnJlc291cmNlczogW10="
        curl -f -s -X POST -H "Authorization: token $token" -H "Content-Type: application/json" \
          -d '{"content": "'"$kust_content"'", "message": "Initialize clusters/'"${var.talos_cluster_name}"' directory", "branch": "main"}' \
          "http://${var.forgejo_ip}:3000/api/v1/repos/${var.forgejo_org}/gitops-fleet/contents/clusters/${var.talos_cluster_name}/kustomization.yaml"
      else
        echo "kustomization.yaml already exists."
      fi

      # 6. Clean up access token to avoid SQLite database token pollution
      curl -s -X DELETE -H "Authorization: token $token" "http://${var.forgejo_ip}:3000/api/v1/users/${var.forgejo_admin_user}/tokens/$token_name" || true

      # 7. Fetch Forgejo SSH host key dynamically and patch flux-system secret
      host_key=""
      for i in {1..15}; do
        if kubectl exec -n forgejo $pod_name -c forgejo -- ls /data/ssh/gitea.rsa.pub &>/dev/null; then
          host_key=$(kubectl exec -n forgejo $pod_name -c forgejo -- cat /data/ssh/gitea.rsa.pub 2>/dev/null || true)
        elif kubectl exec -n forgejo $pod_name -c forgejo -- ls /data/ssh/ssh_host_ed25519_key.pub &>/dev/null; then
          host_key=$(kubectl exec -n forgejo $pod_name -c forgejo -- cat /data/ssh/ssh_host_ed25519_key.pub 2>/dev/null || true)
        fi

        if [ -n "$host_key" ] && ([[ "$host_key" == ssh-ed25519* ]] || [[ "$host_key" == ssh-rsa* ]]); then
          break
        fi
        echo "Waiting for Forgejo SSH host key generation... attempt $i/15"
        sleep 5
      done

      if [ -z "$host_key" ]; then
        echo "Error: Forgejo SSH host key not found!"
        rm forgejo_kubeconfig
        exit 1
      fi

      key_type=$(echo "$host_key" | awk '{print $1}')
      key_val=$(echo "$host_key" | awk '{print $2}')
      known_hosts_content="[forgejo-ssh.forgejo.svc.cluster.local]:22 $key_type $key_val
forgejo-ssh.forgejo.svc.cluster.local $key_type $key_val"

      echo "Patching flux-system secret with Forgejo SSH host key..."
      known_hosts_base64=$(printf '%s' "$known_hosts_content" | base64 | tr -d '\r\n ')
      kubectl patch secret flux-system -n flux-system -p "{\"data\":{\"known_hosts\":\"$known_hosts_base64\"}}"

      rm forgejo_kubeconfig
    EOT

    environment = {
      KUBECONFIG_CONTENT = module.talos.kubeconfig
      DEPLOY_KEY         = trimspace(tls_private_key.flux_deploy_key.public_key_openssh)
    }
  }
}

# 7. Apply FluxInstance Custom Resource via Null Resource Local-Exec
# This avoids plan-time validation errors since the CRD is installed by Helm.
resource "null_resource" "flux_instance" {
  depends_on = [
    helm_release.flux_operator,
    kubernetes_secret_v1.flux_deploy_secret,
    kubernetes_service_v1.flux_operator_web_lb,
    null_resource.forgejo_repo_setup
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
          url: "ssh://git@forgejo-ssh.forgejo.svc.cluster.local:22/${var.forgejo_org}/gitops-fleet.git"
          ref: "refs/heads/main"
          path: "./clusters/${var.talos_cluster_name}"
          pullSecret: "flux-system"
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
      echo "$KUBECONFIG_CONTENT" > flux_kubeconfig_destroy
      export KUBECONFIG=flux_kubeconfig_destroy

      echo "Deleting FluxInstance Custom Resource..."
      kubectl delete fluxinstance flux -n flux-system --ignore-not-found=true

      echo "Waiting for FluxInstance to be deleted..."
      kubectl wait --for=delete fluxinstance/flux -n flux-system --timeout=120s || true

      echo "Deleting Flux CRDs to prevent Helm uninstall warnings..."
      kubectl delete crd \
        fluxinstances.fluxcd.controlplane.io \
        fluxreports.fluxcd.controlplane.io \
        resourcesetinputproviders.fluxcd.controlplane.io \
        resourcesets.fluxcd.controlplane.io --ignore-not-found=true || true

      rm flux_kubeconfig_destroy
    EOT

    environment = {
      KUBECONFIG_CONTENT = self.triggers.kubeconfig
    }
  }
}
