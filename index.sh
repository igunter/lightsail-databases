#!/usr/bin/env bash
#
# MySQL Accounts - admin menu for managing MySQL/MariaDB databases.
# See readme.md for usage.

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
META_DIR="/etc/mysql-accounts/databases"
SYSTEM_SCHEMAS="information_schema mysql performance_schema sys"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash index.sh)."
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

list_databases() {
    local databases
    databases="$($MYSQL_BIN --defaults-extra-file="$MYSQL_ADMIN_CNF" -N -e "SHOW DATABASES;" 2>/dev/null | tr '\n' ' ')"
    if [ -z "$databases" ]; then
        echo "No databases found."
        return 0
    fi

    printf "%-20s %-12s %-10s\n" "DATABASE" "USER" "STATUS"
    printf "%-20s %-12s %-10s\n" "--------" "----" "------"

    local db
    for db in $databases; do
        if [ "$db" = "Database" ]; then
            continue
        fi
        case " $SYSTEM_SCHEMAS " in
            *" $db "*) continue ;;
        esac
        local meta_path="${META_DIR}/${db}.account"
        local dbuser="-"
        local status="unknown"
        if [ -f "$meta_path" ]; then
            # shellcheck disable=SC1090
            source "$meta_path"
            dbuser="$DBUSER"
            status="$STATUS"
        fi
        printf "%-20s %-12s %-10s\n" "$db" "$dbuser" "$status"
    done
}

create_account() {
    local create_script
    create_script="$(dirname "$0")/create.sh"

    if [ ! -f "$create_script" ]; then
        echo "create.sh not found next to index.sh."
        return
    fi

    bash "$create_script"
}

revoke_access() {
    local revoke_script
    revoke_script="$(dirname "$0")/revoke.sh"

    if [ ! -f "$revoke_script" ]; then
        echo "revoke.sh not found next to index.sh."
        return
    fi

    bash "$revoke_script"
}

restore_access() {
    local restore_script
    restore_script="$(dirname "$0")/restore.sh"

    if [ ! -f "$restore_script" ]; then
        echo "restore.sh not found next to index.sh."
        return
    fi

    bash "$restore_script"
}

delete_database() {
    local delete_script
    delete_script="$(dirname "$0")/delete.sh"

    if [ ! -f "$delete_script" ]; then
        echo "delete.sh not found next to index.sh."
        return
    fi

    bash "$delete_script"
}

show_menu() {
    echo ""
    echo "===== MySQL Accounts ====="
    echo "1) List Databases"
    echo "2) Create Database"
    echo "3) Revoke Access"
    echo "4) Restore Access"
    echo "5) Delete Database"
    echo "6) Exit"
    echo "=========================="
}

main() {
    require_root
    ensure_mysql_admin_creds

    while true; do
        show_menu
        read -rp "Select an option [1-6]: " choice
        echo ""

        case "$choice" in
            1) list_databases ;;
            2) create_account ;;
            3) revoke_access ;;
            4) restore_access ;;
            5) delete_database ;;
            6) echo "Goodbye."; exit 0 ;;
            *) echo "Invalid option, please select 1-6." ;;
        esac
    done
}

main
