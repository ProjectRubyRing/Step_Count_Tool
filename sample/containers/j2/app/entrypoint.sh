#!/bin/bash
# コンテナ起動スクリプト (containers 配下は推測の対象外)
set -eu

APP_ENV="j2"
APP_PORT=8080

echo "starting app (${APP_ENV})"
exec /opt/app/bin/server --env "$APP_ENV" --port "$APP_PORT"
