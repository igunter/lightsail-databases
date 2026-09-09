#!/usr/bin/env bash
#
# MySQL Accounts - permanently delete a revoked database and its user.
#
# Usage: sudo bash delete.sh
# Can be run directly, or is invoked by index.sh's "Delete Database" option.

set -euo pipefail

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
META_DIR="/etc/mysql-accounts/databases"
BACKUP_DIR="/var/backups/mysql-accounts"
QUEUE_DIR="/etc/mysql-accounts/backup-cleanup-queue"
GRACE_DAYS=28
DBNAME_RE='^[a-zA-Z_][a-zA-Z0-9_]{0,62}$'

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash delete.sh)."
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

read_account_meta() {
    local meta_path="${META_DIR}/${DBNAME}.account"

    DBUSER="-"
    HOST_SCOPE="%"
    STATUS="unknown"
    CREATED="-"

    if [ -f "$meta_path" ]; then
        # shellcheck disable=SC1090
        source "$meta_path"
    fi
}

database_exists() {
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" --batch --skip-column-names -e "SHOW DATABASES LIKE '${1}';" 2>/dev/null | grep -Fxq "$1"
}

prompt_database_name() {
    ORPHAN_DATABASE=0
    while true; do
        read -rp "Database name to delete: " DBNAME
        if [[ ! "$DBNAME" =~ $DBNAME_RE ]]; then
            echo "Invalid database name."
            continue
        fi
        if [ ! -f "${META_DIR}/${DBNAME}.account" ]; then
            if database_exists "$DBNAME"; then
                echo "No metadata found for '${DBNAME}'."
                echo "This is an unmanaged database. It can only be deleted as an orphan."
                DBUSER="-"
                HOST_SCOPE="%"
                STATUS="orphan"
                ORPHAN_DATABASE=1
                break
            fi
            echo "No metadata found for '${DBNAME}', and the database does not exist."
            continue
        fi
        read_account_meta
        if [ "$STATUS" != "revoked" ]; then
            echo "Database '${DBNAME}' is not revoked. Revoke access first before deleting."
            continue
        fi
        break
    done
}

confirm_deletion() {
    echo ""
    echo "About to permanently delete database '${DBNAME}':"
    echo "  User: ${DBUSER}"
    echo "  Metadata: ${META_DIR}/${DBNAME}.account"
    echo ""
    if [ "$ORPHAN_DATABASE" -eq 1 ]; then
        echo "No metadata is available, so this will create a backup and drop only the database."
    else
        echo "This will create a backup, drop the database, and drop the dedicated database user."
    fi
    read -rp "Type '${DBNAME}' to confirm permanent deletion: " confirm_input
    if [ "$confirm_input" != "$DBNAME" ]; then
        echo "Confirmation did not match. Aborting - nothing was deleted."
        return 1
    fi
}

backup_database() {
    local backup_script
    backup_script="$(dirname "$0")/backup-now.sh"

    if [ ! -f "$backup_script" ]; then
        echo "backup-now.sh not found next to delete.sh."
        return 1
    fi

    bash "$backup_script" "$DBNAME"
}

queue_backup_cleanup() {
    mkdir -p "$QUEUE_DIR"
    local eligible_date
    eligible_date="$(date -d "+${GRACE_DAYS} days" +%F)"
    echo "$eligible_date" > "${QUEUE_DIR}/${DBNAME}"
    echo "Backup for ${DBNAME} will be auto-deleted on ${eligible_date} (${GRACE_DAYS} days) - see cleanup-backups.sh."
}

drop_database_and_user() {
    if [ "$ORPHAN_DATABASE" -eq 1 ]; then
        "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "DROP DATABASE \`${DBNAME}\`;"
    else
        "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "DROP USER '${DBUSER}'@'${HOST_SCOPE}'; DROP DATABASE \`${DBNAME}\`; FLUSH PRIVILEGES;"
    fi
    rm -f "${META_DIR}/${DBNAME}.account"
}

delete_database() {
    require_root
    ensure_mysql_admin_creds
    prompt_database_name

    if ! confirm_deletion; then
        return
    fi

    backup_database
    queue_backup_cleanup
    drop_database_and_user

    echo ""
    echo "Database '${DBNAME}' deleted."
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    delete_database
fi
