#!/bin/bash
set -e

IMAGE="sunqb/acemcp-relay"
TAG="${1:-latest}"

echo ">>> 构建多平台镜像并推送 ${IMAGE}:${TAG}"
docker buildx build \
  --builder colima-builder \
  --platform linux/amd64,linux/arm64 \
  -t "${IMAGE}:${TAG}" \
  --push \
  .

echo ">>> 完成"
