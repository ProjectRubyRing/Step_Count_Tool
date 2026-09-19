#!/bin/bash
# バックアップスクリプト
set -eu

BACKUP_DIR="/backup"
RETENTION_DAYS=7

backup() {
    tar czf "${BACKUP_DIR}/$(date +%Y%m%d).tar.gz" /etc /opt
}

cleanup() {
    find "$BACKUP_DIR" -mtime "+${RETENTION_DAYS}" -delete
}

backup
cleanup
