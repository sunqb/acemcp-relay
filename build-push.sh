#!/bin/bash
set -e

IMAGE="sunqb/acemcp-relay"
TAG="${1:-latest}-amd64"

echo ">>> 构建镜像并推送 ${IMAGE}:${TAG}"
docker build \
  --platform linux/amd64 \
  -t "${IMAGE}:${TAG}" \
  .

docker push "${IMAGE}:${TAG}"

echo ">>> 完成"
