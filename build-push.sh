#!/bin/bash
set -e

IMAGE="sunqb/acemcp-relay"
TAG="${1:-latest}"

echo ">>> 构建镜像并推送 ${IMAGE}:${TAG}"
docker build \
  -t "${IMAGE}:${TAG}" \
  .

docker push "${IMAGE}:${TAG}"

echo ">>> 完成"
