#!/bin/bash
#
# ビルドステージ: コンテナイメージのビルド (push_image.sh は未配置 → j1 から推測)
#
set -euo pipefail

readonly ENV_NAME="j2"
readonly IMAGE="app"

tag="$(git rev-parse --short HEAD)"

docker build \
    --build-arg ENV_NAME="$ENV_NAME" \
    -t "${IMAGE}:${tag}" .

echo "${tag}" > image_tag.txt
