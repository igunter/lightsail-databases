#!/usr/bin/env bash
#
# One-off helper: seeds a .account metadata file (from db-account.template) into
# /etc/mysql-accounts/databases for every existing MySQL/MariaDB database that
# doesn't already have one. Existing .account files are left untouched.
#
# Usage: sudo bash seed-db-accounts.sh

MYSQL_ADMIN_CNF="${MYSQL_ADMIN_CNF:-/root/.my.cnf}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
META_DIR="/etc/mysql-accounts/databases"
TEMPLATE_FILE="$(dirname "$0")/db-account.template"

SYSTEM_SCHEMAS="information_schema mysql performance_schema sys"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (try: sudo bash seed-db-accounts.sh)."
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template file not found: ${TEMPLATE_FILE}"
    exit 1
fi

if [ ! -f "$MYSQL_ADMIN_CNF" ]; then
    echo "MySQL admin credentials file not found at ${MYSQL_ADMIN_CNF}."
    exit 1
fi

mkdir -p "$META_DIR"

databases="$("$MYSQL_BIN" --defaults-extra-file="$MYSQL_ADMIN_CNF" -N -e "SHOW DATABASES;" 2>/dev/null)"
if [ -z "$databases" ]; then
    echo "No databases found."
    exit 0
fi

created=0
skipped=0

for dbname in $databases; do
    case " $SYSTEM_SCHEMAS " in
        *" $dbname "*) continue ;;
    esac

    meta_path="${META_DIR}/${dbname}.account"

    if [ -f "$meta_path" ]; then
        echo "Skipping ${dbname}: .account already exists."
        skipped=$((skipped + 1))
        continue
    fi

    cp "$TEMPLATE_FILE" "$meta_path"
    sed -i "s/^DBNAME=.*/DBNAME=\"${dbname}\"/" "$meta_path"
    sed -i "s/^CREATED=.*/CREATED=\"$(date +%F)\"/" "$meta_path"
    chmod 600 "$meta_path"
    echo "Seeded ${dbname}: created ${meta_path} - edit it with the database's real DBUSER/HOST_SCOPE/STATUS."
    created=$((created + 1))
done

echo ""
echo "Done. Created ${created}, skipped ${skipped}."
