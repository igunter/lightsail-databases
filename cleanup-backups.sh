#!/usr/bin/env bash
#
# MySQL Accounts - prune queued database backups after their grace period.
#
# Usage: bash cleanup-backups.sh
# Intended for daily cron execution.

set -euo pipefail

BACKUP_DIR="/var/backups/mysql-accounts"
QUEUE_DIR="/etc/mysql-accounts/backup-cleanup-queue"
MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash cleanup-backups.sh)."
        exit 1
    fi
}

cleanup_backups() {
    [ -d "$QUEUE_DIR" ] || return 0

    local entry
    for entry in "$QUEUE_DIR"/*; do
        [ -f "$entry" ] || continue
        local dbname
        dbname="$(basename "$entry")"
        local eligible_date
        eligible_date="$(cat "$entry")"
        if [ -z "$eligible_date" ]; then
            continue
        fi

        if [ "$(date +%F)" \< "$eligible_date" ]; then
            continue
        fi

        if [ -f "$MYSQL_ADMIN_CNF" ] && "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" --batch --skip-column-names -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -Fxq "$dbname"; then
            echo "Database '${dbname}' still exists; cancelling cleanup queue entry."
            rm -f "$entry"
            continue
        fi

        local backup_path
        backup_path="${BACKUP_DIR}/${dbname}-"
        find "$BACKUP_DIR" -maxdepth 1 -type f -name "${dbname}-*.sql.gz" -print0 | while IFS= read -r -d '' file; do
            rm -f "$file"
            echo "Removed backup ${file}."
        done
        rm -f "$entry"
    done
}

main() {
    require_root
    cleanup_backups
}

main
