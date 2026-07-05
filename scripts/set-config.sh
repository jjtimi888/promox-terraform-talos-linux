echo "[+] Generating kubeconfig and talos_config"

terraform output -raw kubeconfig > kubeconfig
terraform output -raw talos_config > talos_config.yaml
cp talos_config.yaml ~/.talos/config
cp kubeconfig ~/.kube/config

echo "[+] Kubeconfig and talos_config generated and copied to ~/.kube/config and ~/.talos/config"