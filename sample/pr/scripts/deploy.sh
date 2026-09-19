#!/bin/bash
#
# デプロイスクリプト
#
set -euo pipefail

readonly ENV_NAME="pr"
readonly LOG_DIR="/var/log/deploy"

# ログ出力
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# 事前チェック
precheck() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi

    command -v terraform >/dev/null 2>&1 || {
        log "terraform が見つかりません"
        exit 1
    }
}

main() {
    precheck
    log "デプロイを開始します: $ENV_NAME"

    cat <<EOF > /tmp/deploy.conf
# この行はヒアドキュメント内
env=$ENV_NAME
log=$LOG_DIR
EOF

    terraform init -input=false
    terraform apply -auto-approve

    log "デプロイが完了しました"
}

main "$@"
