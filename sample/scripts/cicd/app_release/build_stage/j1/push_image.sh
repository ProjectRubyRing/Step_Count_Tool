#!/bin/bash
#
# ビルドステージ: イメージを ECR へ登録
#
set -euo pipefail

readonly REGISTRY="123456789012.dkr.ecr.ap-northeast-1.amazonaws.com"

tag="$(cat image_tag.txt)"

aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

docker tag "app:${tag}" "${REGISTRY}/app:${tag}"
docker push "${REGISTRY}/app:${tag}"
