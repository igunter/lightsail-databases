#!/usr/bin/env bash
#
# MySQL Accounts - revoke a database user's access.
#
# Usage: sudo bash revoke.sh
# Can be run directly, or is invoked by index.sh's "Revoke Access" option.

set -euo pipefail

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
META_DIR="/etc/mysql-accounts/databases"
DBNAME_RE='^[a-zA-Z_][a-zA-Z0-9_]{0,62}$'

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash revoke.sh)."
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

write_account_meta() {
    local meta_path="${META_DIR}/${DBNAME}.account"
    cat > "$meta_path" <<EOF
DBNAME="${DBNAME}"
DBUSER="${DBUSER}"
HOST_SCOPE="${HOST_SCOPE}"
STATUS="revoked"
CREATED="${CREATED}"
EOF
    chmod 600 "$meta_path"
}

prompt_database_name() {
    while true; do
        read -rp "Database name to revoke: " DBNAME
        if [[ ! "$DBNAME" =~ $DBNAME_RE ]]; then
            echo "Invalid database name."
            continue
        fi
        if [ ! -f "${META_DIR}/${DBNAME}.account" ]; then
            echo "No metadata found for '${DBNAME}'. Run create.sh first."
            continue
        fi
        read_account_meta
        if [ "$STATUS" = "revoked" ]; then
            echo "Access for '${DBNAME}' is already revoked."
            continue
        fi
        break
    done
}

mysql_supports_account_lock() {
    local version
    version="$($MYSQL_BIN --defaults-extra-file="$MYSQL_ADMIN_CNF" --batch --skip-column-names -e "SELECT VERSION();" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
    if [[ "$version" =~ ^8\. ]] || [[ "$version" =~ ^10\.(4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30) ]] || [[ "$version" =~ ^11\. ]]; then
        return 0
    fi
    return 1
}

revoke_access() {
    require_root
    ensure_mysql_admin_creds
    prompt_database_name

    if mysql_supports_account_lock; then
        "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "ALTER USER '${DBUSER}'@'${HOST_SCOPE}' ACCOUNT LOCK; FLUSH PRIVILEGES;"
    else
        "$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -e "REVOKE ALL PRIVILEGES ON \`${DBNAME}\`.* FROM '${DBUSER}'@'${HOST_SCOPE}'; FLUSH PRIVILEGES;"
    fi

    write_account_meta

    echo ""
    echo "Access for '${DBNAME}' revoked."
    echo "  User: ${DBUSER}"
    echo "  Status: revoked"
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    revoke_access
fi
