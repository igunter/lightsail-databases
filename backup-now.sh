#!/usr/bin/env bash
#
# MySQL Accounts - create a backup of a database now.
#
# Usage: sudo bash backup-now.sh <database-name>
# Can be run directly, or is invoked by delete.sh/cron.

set -euo pipefail

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQL_DUMP_BIN="${MYSQL_DUMP_BIN:-mysqldump}"
BACKUP_DIR="/var/backups/mysql-accounts"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash backup-now.sh <database-name>)."
        exit 1
    fi
}

bootstrap_mysql_admin_creds() {
    echo "MySQL admin credentials file not found at ${MYSQL_ADMIN_CNF}."
    echo "Let's set it up now - these credentials will be saved so you aren't asked again."
    local admin_user admin_password

    read -rp "MySQL admin username [root]: " admin_user
    admin_user="${admin_user:-root}"

    while true; do
        read -rsp "MySQL admin password: " admin_password
        echo ""
        if MYSQL_PWD="$admin_password" "$MYSQL_BIN" --user="$admin_user" --batch --skip-column-names -e "SELECT 1;" >/dev/null 2>&1; then
            break
        fi
        echo "Could not connect with those credentials. Please try again."
    done

    mkdir -p "$(dirname "$MYSQL_ADMIN_CNF")"
    cat > "$MYSQL_ADMIN_CNF" <<EOF
[client]
user=${admin_user}
password=${admin_password}
EOF
    chmod 600 "$MYSQL_ADMIN_CNF"
    echo "Saved MySQL admin credentials to ${MYSQL_ADMIN_CNF}."
}

ensure_mysql_admin_creds() {
    if [ ! -f "$MYSQL_ADMIN_CNF" ]; then
        bootstrap_mysql_admin_creds
    fi
    chmod 600 "$MYSQL_ADMIN_CNF"
}

backup_database() {
    local dbname="$1"
    mkdir -p "$BACKUP_DIR"
    local backup_path="${BACKUP_DIR}/${dbname}-$(date +%Y%m%d%H%M%S).sql.gz"
    "$MYSQL_DUMP_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" "$dbname" | gzip > "$backup_path"
    echo "Backed up '${dbname}' to ${backup_path}."
}

main() {
    require_root
    ensure_mysql_admin_creds

    if [ $# -ne 1 ]; then
        echo "Usage: sudo bash backup-now.sh <database-name>"
        exit 1
    fi

    backup_database "$1"
}

main "$@"
