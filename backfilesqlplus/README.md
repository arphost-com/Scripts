```markdown
# ARPHost Backup Script (Bash)
# We use this to backup local files and SQL Databases on servers and securely transfer them offsite.
If you need support or services check out https://arphost.com

This backup system creates a **single compressed archive** containing:

- Selected filesystem directories (via `rsync`)
- Optional **MySQL** dumps
- Optional **PostgreSQL** dumps
- A timestamped log file for each run
- Optional upload to a remote target
- Notifications to one or more alert channels

---

## What It Produces

- **Archive:**  
  `LOCAL_STORE/<RUN_NAME>_<SERVER_NAME>_<timestamp>.tar.gz`

- **Log:**  
  `LOG_DIR/<RUN_NAME>_<timestamp>.log`

The working directory (`WORKDIR`) is temporary and is removed after each run.

---

## Requirements

### Core
- `bash`
- `rsync`
- `tar`
- `curl`
- `openssh-client`

### Optional (depending on features enabled)
- MySQL backups: `mysqldump` (`mysql-client`)
- PostgreSQL backups: `pg_dump` (`postgresql-client`)
- S3 uploads: `aws` CLI
- Cloud storage (Dropbox / Google Drive / etc.): `rclone`
- Email notifications: `msmtp` (preferred) or `ssmtp`

---

## Installation

1. **Place files**
```

/usr/local/sbin/backup.sh
/etc/arphost-backup/backup.env

````

2. **Set permissions**
```bash
chmod +x /usr/local/sbin/backup.sh
chmod 600 /etc/arphost-backup/backup.env
````

3. **Test run**

   ```bash
   sudo bash /usr/local/sbin/backup.sh
   ```

---

## Configuration (`backup.env`)

The script loads configuration from:

* Default: `/etc/arphost-backup/backup.env`
* Override:

  ```bash
  ENV_FILE=/path/to/backup.env bash /usr/local/sbin/backup.sh
  ```

---

## Example `backup.env` Template (Safe)

> **Do not store real credentials in documentation or repositories.**

```bash
# -------- Core --------
SERVER_NAME="example-server"
RUN_NAME="example-backup"
WORKDIR="/backup/work"
LOCAL_STORE="/backup/archives"
KEEP_LOCAL=14
LOG_DIR="/backup/logs"

# Directories to back up (space-separated)
BACKUP_DIRS="/var/www /etc/nginx /etc/letsencrypt"

# Optional rsync excludes
RSYNC_EXCLUDES="cache tmp *.log"

# -------- MySQL backups --------
MYSQL_DBS="db-host|3306|dbuser|dbpass|dbname"

# -------- PostgreSQL backups --------
POSTGRES_DBS="db-host|5432|pguser|pgpass|dbname"

# -------- Upload method --------
# local_move | s3 | ftp | sftp | scp | rsync | rclone
UPLOAD_METHOD="scp"

# SSH-based uploads
SSH_HOST="backup.example.com"
SSH_USER="backupuser"
SSH_KEY="/root/.ssh/id_rsa"
SSH_REMOTE_DIR="/remote/backup/path"

# -------- Notifications --------
# email,sendgrid,discord,telegram
NOTIFY_CHANNELS="email,discord"

# Email (SMTP)
EMAIL_TO="alerts@example.com"
EMAIL_FROM="backup@example.com"
EMAIL_FROM_NAME="Backup System"
SMTP_HOST="smtp.example.com"
SMTP_PORT="587"
SMTP_USER="smtp_user"
SMTP_PASS="smtp_password"
SMTP_TLS="on"

# Discord
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXX/XXXX"

# Telegram
TELEGRAM_BOT_TOKEN="123456:ABCDEF"
TELEGRAM_CHAT_ID="123456789"

# SendGrid
SENDGRID_API_KEY="SG.xxxxxx"
SENDGRID_TO="alerts@example.com"
SENDGRID_FROM="backup@example.com"
```

---

## Upload Methods

### SCP (SSH)

```bash
UPLOAD_METHOD="scp"
```

### SFTP

```bash
UPLOAD_METHOD="sftp"
```

### rsync over SSH

```bash
UPLOAD_METHOD="rsync"
```

### Amazon S3

```bash
UPLOAD_METHOD="s3"
S3_BUCKET="s3://my-bucket/backups"
AWS_REGION="us-east-1"
```

### rclone (Dropbox / Google Drive / OneDrive / S3 / etc.)

```bash
UPLOAD_METHOD="rclone"
RCLONE_REMOTE="gdrive:Backups"
RCLONE_REMOTE_DIR="example-server"
```

### Local move

```bash
UPLOAD_METHOD="local_move"
LOCAL_MOVE_DIR="/mnt/offsite/backups"
```

---

## Database Configuration

### MySQL

Format:

```
host|port|user|password|database
```

Multiple databases:

```bash
MYSQL_DBS="host1|3306|user|pass|db1;host2|3306|user|pass|db2"
```

### PostgreSQL

```bash
POSTGRES_DBS="host|5432|pguser|pgpass|dbname"
```

---

## Local Retention Policy

* Archives are kept in `LOCAL_STORE`
* `KEEP_LOCAL=14` keeps the newest 14 archives
* Set `KEEP_LOCAL=0` to disable pruning

---

## Running Manually

```bash
sudo bash /usr/local/sbin/backup.sh
```

---

## Scheduling with Cron

Create `/etc/cron.d/arphost-backup`:

```bash
0 2 * * * root ENV_FILE=/etc/arphost-backup/backup.env bash /usr/local/sbin/backup.sh >/dev/null 2>&1
```

---

## Troubleshooting

### Host Key Verification Failed / SCP Connection Closed

This happens when the SSH host key is unknown or changed.

Fix safely:

```bash
ssh-keygen -R backup.example.com
ssh-keyscan -H backup.example.com >> /root/.ssh/known_hosts
ssh -i /root/.ssh/id_rsa backupuser@backup.example.com
```

Once SSH works interactively, the backup upload will work.

---

### SSH Key Permissions

```bash
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/known_hosts
```

---

### Permission Denied (publickey)

Add your key to the remote server:

```bash
ssh-copy-id -i /root/.ssh/id_rsa.pub backupuser@backup.example.com
```

---

### Remote Directory Missing

```bash
ssh -i /root/.ssh/id_rsa backupuser@backup.example.com "mkdir -p /remote/backup/path"
```

---

## Current Error Explanation

If you see:

* `Host key verification failed`
* `scp: Connection closed`
* `ERROR: SCP upload failed`

Your system does not yet trust the remote SSH host.
Fix it by accepting and storing the host key as shown above.

---

## Support

If SSH still fails, run:

```bash
ssh -vvv -i /root/.ssh/id_rsa backupuser@backup.example.com
```

Redact sensitive values and review the output to determine whether the failure is due to:

* host key mismatch
* missing authorized keys
* incorrect permissions
* disabled SSH access

```
```

