#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="health-checks-demo:local"
CLUSTER_NAME="k8s-labs"

echo "Building the Docker image ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" ./app

echo "Loading the image into the kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

echo "Done. The image is now available on every node of the cluster."