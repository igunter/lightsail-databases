#!/usr/bin/env bash
#
# MySQL Accounts - create a new database and dedicated database user.
#
# Usage: sudo bash create.sh
# Can be run directly, or is invoked by index.sh's "Create Database" option.

set -euo pipefail

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
META_DIR="/etc/mysql-accounts/databases"
DB_ACCOUNT_TEMPLATE="$(dirname "$0")/db-account.template"

DBNAME_RE='^[a-zA-Z_][a-zA-Z0-9_]{0,62}$'
DBUSER_RE='^[a-zA-Z_][a-zA-Z0-9_]{0,62}$'
HOST_SCOPE_RE='^([%a-zA-Z0-9._:-]+)$'

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash create.sh)."
        exit 1
    fi
}

ensure_mysql_admin_creds() {
    if [ ! -f "$MYSQL_ADMIN_CNF" ]; then
        echo "MySQL admin credentials file not found at ${MYSQL_ADMIN_CNF}."
        echo "Create it with a root/admin account and 600 permissions before running this tool."
        exit 1
    fi

    chmod 600 "$MYSQL_ADMIN_CNF"
}

prompt_database_name() {
    while true; do
        read -rp "Database name: " DBNAME
        if [[ ! "$DBNAME" =~ $DBNAME_RE ]]; then
            echo "Invalid database name. Use letters, numbers, or underscores, starting with a letter or underscore."
            continue
        fi
        if database_exists "$DBNAME"; then
            echo "A database named '${DBNAME}' already exists. Choose another."
            continue
        fi
        break
    done
}

prompt_db_user() {
    while true; do
        read -rp "Database username: " DBUSER
        if [[ ! "$DBUSER" =~ $DBUSER_RE ]]; then
            echo "Invalid database username. Use letters, numbers, or underscores, starting with a letter or underscore."
            continue
        fi
        if user_exists "$DBUSER"; then
            echo "A database user named '${DBUSER}' already exists. Choose another."
            continue
        fi
        break
    done
}

prompt_password() {
    while true; do
        read -rsp "Password: " DBPASSWORD
        echo ""
        if [ "${#DBPASSWORD}" -lt 8 ]; then
            echo "Password must be at least 8 characters."
            continue
        fi
        read -rsp "Confirm password: " PASSWORD_CONFIRM
        echo ""
        if [ "$DBPASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo "Passwords do not match."
            continue
        fi
        break
    done
}

prompt_host_scope() {
    while true; do
        read -rp "Host scope [%%]: " HOST_SCOPE
        HOST_SCOPE="${HOST_SCOPE:-%}"
        if [[ ! "$HOST_SCOPE" =~ $HOST_SCOPE_RE ]]; then
            echo "Invalid host scope. Use % or a host/IP value without spaces."
            continue
        fi
        break
    done
}

database_exists() {
    local name="$1"
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" --batch --skip-column-names -e "SHOW DATABASES LIKE '${name}';" 2>/dev/null | grep -Fxq "$name"
}

user_exists() {
    local name="$1"
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" --batch --skip-column-names -e "SELECT User FROM mysql.user WHERE User='${name}';" 2>/dev/null | grep -Fxq "$name"
}

create_database_and_user() {
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "CREATE DATABASE \`${DBNAME}\`;"
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "CREATE USER '${DBUSER}'@'${HOST_SCOPE}' IDENTIFIED BY '${DBPASSWORD}';"
    "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "GRANT ALL PRIVILEGES ON \`${DBNAME}\`.* TO '${DBUSER}'@'${HOST_SCOPE}'; FLUSH PRIVILEGES;"
}

write_account_meta() {
    mkdir -p "$META_DIR"
    local meta_path="${META_DIR}/${DBNAME}.account"
    cat > "$meta_path" <<EOF
DBNAME="${DBNAME}"
DBUSER="${DBUSER}"
HOST_SCOPE="${HOST_SCOPE}"
STATUS="active"
CREATED="$(date +%F)"
EOF
    chmod 600 "$meta_path"
}

create_account() {
    require_root
    ensure_mysql_admin_creds
    prompt_database_name
    prompt_db_user
    prompt_password
    prompt_host_scope

    create_database_and_user
    write_account_meta

    echo ""
    echo "Database '${DBNAME}' created."
    echo "  Database user: ${DBUSER}"
    echo "  Host scope:    ${HOST_SCOPE}"
    echo "  Metadata:      ${META_DIR}/${DBNAME}.account"
    echo "  Password:      ${DBPASSWORD}"
    echo "Remember: do not store this password in plaintext after creation."
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_account
fi
