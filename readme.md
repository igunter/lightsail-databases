# MySQL Accounts

This script administers MySQL/MariaDB databases and dedicated database users on a server.

## How to Run the Script

Connect to your server in a terminal window (Putty, Terminal, etc.) and run the following command:

If this is the first time you are running this script, then you need to run the following command:

```bash
sudo git clone https://github.com/igunter/lightsail-databases.git /mysql-accounts && cd /mysql-accounts && sudo bash seed-accounts.sh && sudo bash index.sh
```

Otherwise run:

```bash
cd /mysql-accounts && sudo bash index.sh
```

If you want to update the script later:

```bash
cd /mysql-accounts && sudo git pull && sudo bash index.sh
```

## Security Notes

- The scripts use a root/admin MySQL credentials file such as /root/.my.cnf with 600 permissions. They do not prompt for root database credentials on every run.
- The database user's password is only shown once at creation time. It is not written into the metadata sidecar file.
- The default host scope is % for compatibility, but you can change it to a specific IP or host if you want to restrict access.

## What the Script Does

After running the script, you will be shown a menu of options:
- List Databases
- Create Database
- Revoke Access
- Restore Access
- Delete Database

### List Databases

This option lists the databases found on the server and shows the corresponding metadata status for each one.

### Create Database

This option runs create.sh and asks you for:
- Database name
- Database username
- Database password (with confirmation)
- Host scope

It then creates the database, creates a dedicated database user, grants privileges for that database only, writes a metadata file in /etc/mysql-accounts/databases/<dbname>.account, and prints the password once for you to keep securely.

### Revoke Access

This option runs revoke.sh. It prompts for the database name and then blocks the database user from connecting by revoking privileges or locking the account when the server supports it. The metadata status is changed to revoked.

### Restore Access

This option runs restore.sh. It prompts for the database name and restores the user's access, changing the metadata status back to active.

### Delete Database

This option runs delete.sh. The database must already have its access revoked before deletion is allowed. You will be shown a summary and must type the database name again to confirm. Then the script creates a backup, queues the backup for later cleanup, drops the database user, and drops the database.

#### Backup cleanup (cleanup-backups.sh)

Backups are not deleted immediately when a database is removed. Instead, delete.sh queues the backup for cleanup after a grace period of 28 days. The cleanup script is meant to run on a daily cron schedule. Add it to root's crontab, for example:

```bash
sudo crontab -e
```

```bash
0 3 * * * bash /mysql-accounts/cleanup-backups.sh >> /var/log/mysql-accounts-backup-cleanup.log 2>&1
```
