#!/bin/bash
set -eo pipefail

usage() {
  echo "Usage: $0 -e [dev]"
  exit 1
}

# Parse flags
while getopts "e:" opt; do
  case "$opt" in
    e) ADH_OPS_ENV="$OPTARG" ;;
    *) usage ;;
  esac
done
if [[ -z "$ADH_OPS_ENV" ]]; then
  usage
fi

GIT_ROOT_DIR="$(git rev-parse --show-toplevel)"
GIT_HASH=$(git rev-parse --short HEAD)
EPOCH_TIMESTAMP=$(date +%s)

ADH_APPS_NAMESPACE='adh-api'
ADH_OBSERVABILITY_NAMESPACE='observability'

# Update local git repository
# git pull

# Setup local cluster with docker registry when environment is DEV
if [[ "$ADH_OPS_ENV" == "dev" ]]; then
  # Create cluster
  $GIT_ROOT_DIR/ops/dev/create_cluster.sh

  # Set registry endpoints and image tag
  DEV_REGISTRY_ENDPOINT="localhost:5001"
  DEV_IMAGE_TAG="${GIT_HASH}-dev-${EPOCH_TIMESTAMP}"

  # Build and push local Docker images, filtering for only the apps used on the environment
  find "$GIT_ROOT_DIR" -name 'Dockerfile' -type f | grep "$(find "$GIT_ROOT_DIR/ops/$ADH_OPS_ENV" -mindepth 2 -type d | awk -F/ '{print $NF}')" | while read -r dockerfile; do
    # Extract app name from the two parent folders
    app_name=$(echo "$dockerfile" | awk -F'/' '{print $(NF-2) "-" $(NF-1)}')

    # Generate image tag
    image_name="${DEV_REGISTRY_ENDPOINT}/adiffhunting-api/${app_name}:${DEV_IMAGE_TAG}"

    echo "Building image: $image_name"
    docker build -t "$image_name" -f "$dockerfile" $GIT_ROOT_DIR/dev
    docker push "$image_name"
  done
fi

# Deploy database
helm repo add dgraph https://charts.dgraph.io
helm repo update
helm upgrade --install dgraph dgraph/dgraph \
  --namespace $ADH_APPS_NAMESPACE --create-namespace \
  --values $GIT_ROOT_DIR/ops/$ADH_OPS_ENV/database/dgraph/values.yaml \
  --version '24.1.4' --set "image.tag=v25.2.0"
# UI to interact with database
helm upgrade --install dgraph-ui dgraph/ratel \
  --namespace $ADH_APPS_NAMESPACE --create-namespace \
  --values $GIT_ROOT_DIR/ops/$ADH_OPS_ENV/database/dgraph-ui/values.yaml

# Only deploy observability on non-dev environments
if [[ ! "$ADH_OPS_ENV" == "dev" ]]; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update

  helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace $ADH_OBSERVABILITY_NAMESPACE --create-namespace \
    --values $GIT_ROOT_DIR/ops/$ADH_OPS_ENV/observability/prometheus-stack/values.yaml \
    --version '69.8.2'
  helm upgrade --install promtail grafana/promtail \
    --namespace $ADH_OBSERVABILITY_NAMESPACE --create-namespace \
    --values $GIT_ROOT_DIR/ops/$ADH_OPS_ENV/observability/promtail/values.yaml \
    --version '6.16.6'
  helm upgrade --install loki grafana/loki \
    --namespace $ADH_OBSERVABILITY_NAMESPACE --create-namespace \
    --values $GIT_ROOT_DIR/ops/$ADH_OPS_ENV/observability/loki/values.yaml \
    --version '6.28.0'
fi

# Apply k8s decrypted manifests
find "$GIT_ROOT_DIR/ops/$ADH_OPS_ENV" -name '*.yaml' | while read -r file; do
  # Check if the file contains the necessary fields (apiVersion, kind, metadata)
  if grep -q apiVersion: "$file" && grep -q kind: "$file" && grep -q metadata: "$file"; then
    echo "---"
    # Attempt to decrypt the file with `sops`. If decryption fails, output the raw file content
    sops -d "$file" 2>/dev/null || cat "$file"
  fi
done | {
  # If the environment is "dev", modify the image lines to pull from local registry
  if [[ "$ADH_OPS_ENV" == "dev" ]]; then
    sed -E "s/(image:[[:space:]]*)(.*):(DEV_IMAGE_TAG)/\\1${DEV_REGISTRY_ENDPOINT}\\/\\2:${DEV_IMAGE_TAG}/"
  else
    cat
  fi
} | kubectl apply -n "$ADH_APPS_NAMESPACE" --force -f -

printf '\n\n'
echo 'All resources were applied'
printf '\n'

node_ip=$(kubectl get nodes --namespace $ADH_APPS_NAMESPACE -o jsonpath="{.items[0].status.addresses[0].address}")
dgraph_ui_node_port=$(kubectl get --namespace $ADH_APPS_NAMESPACE -o jsonpath="{.spec.ports[0].nodePort}" services dgraph-ui)
dgraph_alpha_node_port=$(kubectl get --namespace $ADH_APPS_NAMESPACE -o jsonpath="{.spec.ports[0].nodePort}" services dgraph-alpha)
echo "Connect to UI database via: http://$node_ip:$dgraph_ui_node_port (set 'Dgraph Connection String' to 'http://$node_ip:$dgraph_alpha_node_port')"
