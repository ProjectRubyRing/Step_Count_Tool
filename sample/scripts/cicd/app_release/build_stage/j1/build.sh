#!/bin/bash
#
# ビルドステージ: コンテナイメージのビルド
#
set -euo pipefail

readonly ENV_NAME="j1"
readonly IMAGE="app"

tag="$(git rev-parse --short HEAD)"

docker build \
    --build-arg ENV_NAME="$ENV_NAME" \
    -t "${IMAGE}:${tag}" .

echo "${tag}" > image_tag.txt
