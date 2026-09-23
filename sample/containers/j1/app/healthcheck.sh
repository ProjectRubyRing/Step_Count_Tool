#!/bin/bash
# ヘルスチェック (j1 のみ配置 / 他環境へは推測しない)
set -eu

curl -fsS "http://localhost:8080/health" > /dev/null
