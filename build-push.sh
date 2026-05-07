#!/bin/bash
set -e

IMAGE="sunqb/acemcp-relay"
TAG="${1:-latest}"

echo ">>> 构建镜像 ${IMAGE}:${TAG}"
docker build -t "${IMAGE}:${TAG}" .

echo ">>> 推送镜像 ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

echo ">>> 完成"
