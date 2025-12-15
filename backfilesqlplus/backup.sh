#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/arphost-backup/backup.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

DATE="$(date +%Y-%m-%d_%H%M%S)"
DATE_RFC="$(date -R)"
ARCHIVE_NAME="${RUN_NAME}_${SERVER_NAME}_${DATE}.tar.gz"
WORK_RUN="${WORKDIR}/${DATE}"
LOG_FILE="${LOG_DIR}/${RUN_NAME}_${DATE}.log"

mkdir -p "$WORKDIR" "$LOCAL_STORE" "$LOG_DIR"
mkdir -p "$WORK_RUN"

log() { echo "[$(date -R)] $*" | tee -a "$LOG_FILE" ; }

cleanup() {
  # Always remove workdir; keep archive + logs
  rm -rf "$WORK_RUN" || true
}
trap cleanup EXIT

# -------- Notification helpers --------
notify_discord() {
  [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] || return 0
  local msg="$1"
  curl -fsSL -H "Content-Type: application/json" \
    -d "{\"content\": \"${msg//\"/\\\"}\"}" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

notify_telegram() {
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  local msg="$1"
  curl -fsSL \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$msg" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null || true
}

notify_sendgrid() {
  [[ -n "${SENDGRID_API_KEY:-}" && -n "${SENDGRID_TO:-}" && -n "${SENDGRID_FROM:-}" ]] || return 0
  local subject="$1"
  local content="$2"
  curl -fsSL https://api.sendgrid.com/v3/mail/send \
    -H "Authorization: Bearer ${SENDGRID_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"personalizations\": [{\"to\": [{\"email\": \"${SENDGRID_TO}\"}]}],
      \"from\": {\"email\": \"${SENDGRID_FROM}\"},
      \"subject\": \"${subject}\",
      \"content\": [{\"type\": \"text/plain\", \"value\": \"${content//\"/\\\"}\"}]
    }" >/dev/null || true
}

notify_email() {
  [[ -n "${EMAIL_TO:-}" && -n "${EMAIL_FROM:-}" ]] || return 0
  local subject="$1"
  local body="$2"

  # Prefer msmtp (more common than ssmtp these days)
  if command -v msmtp >/dev/null 2>&1; then
    local msmtp_conf
    msmtp_conf="$(mktemp)"
    chmod 600 "$msmtp_conf"
    cat >"$msmtp_conf" <<EOF
defaults
auth on
tls ${SMTP_TLS:-on}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ${LOG_DIR}/msmtp.log

account backup
host ${SMTP_HOST}
port ${SMTP_PORT}
user ${SMTP_USER}
password ${SMTP_PASS}
from ${EMAIL_FROM}

account default : backup
EOF

    {
      echo "From: ${EMAIL_FROM_NAME:-Backup} <${EMAIL_FROM}>"
      echo "To: ${EMAIL_TO}"
      echo "Subject: ${subject}"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/plain; charset=UTF-8"
      echo
      echo "$body"
      echo
      echo "---- LOG ----"
      tail -n 200 "$LOG_FILE"
    } | msmtp -C "$msmtp_conf" -t

    rm -f "$msmtp_conf"
  elif command -v ssmtp >/dev/null 2>&1; then
    {
      echo "From: ${EMAIL_FROM_NAME:-Backup} <${EMAIL_FROM}>"
      echo "To: ${EMAIL_TO}"
      echo "Subject: ${subject}"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/plain; charset=UTF-8"
      echo
      echo "$body"
      echo
      echo "---- LOG ----"
      tail -n 200 "$LOG_FILE"
    } | ssmtp -f "${EMAIL_FROM}" "${EMAIL_TO}"
  else
    log "WARN: No msmtp/ssmtp found; skipping email."
  fi
}

notify_all() {
  local subject="$1"
  local message="$2"

  IFS=',' read -r -a chans <<< "${NOTIFY_CHANNELS:-}"
  for ch in "${chans[@]}"; do
    ch="$(echo "$ch" | xargs)"
    case "$ch" in
      discord)   notify_discord "${subject} - ${message}" ;;
      telegram)  notify_telegram "${subject} - ${message}" ;;
      sendgrid)  notify_sendgrid "$subject" "$message" ;;
      email)     notify_email "$subject" "$message" ;;
      "" ) : ;;
      *) log "WARN: Unknown notify channel: $ch" ;;
    esac
  done
}

fail() {
  local msg="$1"
  log "ERROR: $msg"
  notify_all "Backup FAILED: ${SERVER_NAME}" "$msg"
  exit 1
}

# -------- Backup steps --------
log "Starting backup: $SERVER_NAME ($RUN_NAME) at $DATE_RFC"
log "Work: $WORK_RUN"
log "Log:  $LOG_FILE"

# 1) Database dumps
mkdir -p "$WORK_RUN/db/mysql" "$WORK_RUN/db/postgres"

dump_mysql() {
  local host="$1" port="$2" user="$3" pass="$4" db="$5"
  log "MySQL dump: $db @ ${host}:${port}"
  MYSQL_PWD="$pass" mysqldump --single-transaction --quick --routines --triggers \
    -h "$host" -P "$port" -u "$user" "$db" \
    > "${WORK_RUN}/db/mysql/${db}.sql" \
    || fail "mysqldump failed for db=$db"
}

dump_postgres() {
  local host="$1" port="$2" user="$3" pass="$4" db="$5"
  log "Postgres dump: $db @ ${host}:${port}"
  PGPASSWORD="$pass" pg_dump -h "$host" -p "$port" -U "$user" -d "$db" \
    -F c -f "${WORK_RUN}/db/postgres/${db}.dump" \
    || fail "pg_dump failed for db=$db"
}

if [[ -n "${MYSQL_DBS:-}" ]]; then
  IFS=';' read -r -a entries <<< "$MYSQL_DBS"
  for e in "${entries[@]}"; do
    IFS='|' read -r h p u pw db <<< "$e"
    [[ -n "$db" ]] && dump_mysql "$h" "$p" "$u" "$pw" "$db"
  done
else
  log "No MYSQL_DBS configured; skipping MySQL."
fi

if [[ -n "${POSTGRES_DBS:-}" ]]; then
  IFS=';' read -r -a entries <<< "$POSTGRES_DBS"
  for e in "${entries[@]}"; do
    IFS='|' read -r h p u pw db <<< "$e"
    [[ -n "$db" ]] && dump_postgres "$h" "$p" "$u" "$pw" "$db"
  done
else
  log "No POSTGRES_DBS configured; skipping Postgres."
fi

# 2) File copy (rsync into work dir)
mkdir -p "$WORK_RUN/files"
RSYNC_EXCLUDE_ARGS=()
if [[ -n "${RSYNC_EXCLUDES:-}" ]]; then
  for pat in $RSYNC_EXCLUDES; do
    RSYNC_EXCLUDE_ARGS+=(--exclude "$pat")
  done
fi

for d in $BACKUP_DIRS; do
  [[ -d "$d" ]] || { log "WARN: missing dir: $d (skipping)"; continue; }
  safe_name="$(echo "$d" | sed 's#/#_#g' | sed 's/^_//')"
  mkdir -p "${WORK_RUN}/files/${safe_name}"
  log "Rsync: $d -> ${WORK_RUN}/files/${safe_name}"
  rsync -a --delete "${RSYNC_EXCLUDE_ARGS[@]}" "$d/" "${WORK_RUN}/files/${safe_name}/" \
    >>"$LOG_FILE" 2>&1 || fail "rsync failed for $d"
done

# 3) Create archive into LOCAL_STORE
ARCHIVE_PATH="${LOCAL_STORE}/${ARCHIVE_NAME}"
log "Creating archive: $ARCHIVE_PATH"
tar -C "$WORKDIR" -czf "$ARCHIVE_PATH" "$DATE" >>"$LOG_FILE" 2>&1 || fail "tar failed"
ls -laht "$ARCHIVE_PATH" | tee -a "$LOG_FILE"

# 4) Upload (selectable)
upload_archive() {
  case "${UPLOAD_METHOD:-}" in
    local_move)
      [[ -n "${LOCAL_MOVE_DIR:-}" ]] || fail "LOCAL_MOVE_DIR not set"
      mkdir -p "$LOCAL_MOVE_DIR"
      log "Moving archive to: $LOCAL_MOVE_DIR"
      mv -f "$ARCHIVE_PATH" "${LOCAL_MOVE_DIR}/" || fail "local_move failed"
      ;;

    s3)
      command -v aws >/dev/null 2>&1 || fail "aws cli not installed"
      [[ -n "${S3_BUCKET:-}" ]] || fail "S3_BUCKET not set"
      log "Uploading to S3: ${S3_BUCKET}/${ARCHIVE_NAME}"
      AWS_REGION="${AWS_REGION:-}" aws s3 cp "$ARCHIVE_PATH" "${S3_BUCKET}/${ARCHIVE_NAME}" \
        >>"$LOG_FILE" 2>&1 || fail "S3 upload failed"
      ;;

    ftp)
      [[ -n "${FTP_HOST:-}" && -n "${FTP_USER:-}" && -n "${FTP_PASS:-}" ]] || fail "FTP config missing"
      remote="ftp://${FTP_HOST}${FTP_REMOTE_DIR%/}/${ARCHIVE_NAME}"
      log "Uploading via FTP: $remote"
      curl -fsSL --user "${FTP_USER}:${FTP_PASS}" -T "$ARCHIVE_PATH" "$remote" \
        >>"$LOG_FILE" 2>&1 || fail "FTP upload failed"
      ;;

    sftp)
      command -v sftp >/dev/null 2>&1 || fail "sftp not installed"
      [[ -n "${SSH_HOST:-}" && -n "${SSH_USER:-}" && -n "${SSH_KEY:-}" ]] || fail "SFTP config missing"
      log "Uploading via SFTP to ${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_DIR}"
      sftp -i "$SSH_KEY" -oBatchMode=yes "${SSH_USER}@${SSH_HOST}" <<EOF >>"$LOG_FILE" 2>&1
mkdir ${SSH_REMOTE_DIR}
cd ${SSH_REMOTE_DIR}
put ${ARCHIVE_PATH}
EOF
      ;;

    scp)
      command -v scp >/dev/null 2>&1 || fail "scp not installed"
      [[ -n "${SSH_HOST:-}" && -n "${SSH_USER:-}" && -n "${SSH_KEY:-}" ]] || fail "SCP config missing"
      log "Uploading via SCP to ${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_DIR}"
      scp -i "$SSH_KEY" -oBatchMode=yes "$ARCHIVE_PATH" "${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_DIR%/}/" \
        >>"$LOG_FILE" 2>&1 || fail "SCP upload failed"
      ;;

    rsync)
      command -v rsync >/dev/null 2>&1 || fail "rsync not installed"
      [[ -n "${SSH_HOST:-}" && -n "${SSH_USER:-}" && -n "${SSH_KEY:-}" ]] || fail "RSYNC config missing"
      log "Uploading via rsync to ${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_DIR}"
      rsync -av -e "ssh -i ${SSH_KEY} -oBatchMode=yes" "$ARCHIVE_PATH" \
        "${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_DIR%/}/" >>"$LOG_FILE" 2>&1 || fail "rsync upload failed"
      ;;

    rclone)
      command -v rclone >/dev/null 2>&1 || fail "rclone not installed"
      [[ -n "${RCLONE_REMOTE:-}" ]] || fail "RCLONE_REMOTE not set"
      dest="${RCLONE_REMOTE%/}/${RCLONE_REMOTE_DIR%/}/"
      log "Uploading via rclone to ${dest}"
      rclone copy "$ARCHIVE_PATH" "$dest" --stats 30s >>"$LOG_FILE" 2>&1 || fail "rclone upload failed"
      ;;

    *)
      fail "Unknown UPLOAD_METHOD: ${UPLOAD_METHOD:-<empty>}"
      ;;
  esac
}

upload_archive

# 5) Local retention
if [[ "${KEEP_LOCAL:-0}" -gt 0 ]]; then
  log "Applying local retention: keep ${KEEP_LOCAL} files in ${LOCAL_STORE}"
  # Only remove matching archives for this run name; keep newest N
  ls -1t "${LOCAL_STORE}/${RUN_NAME}_${SERVER_NAME}_"*.tar.gz 2>/dev/null \
    | tail -n +"$((KEEP_LOCAL + 1))" \
    | while read -r old; do
        log "Deleting old archive: $old"
        rm -f "$old" || true
      done
fi

log "Backup COMPLETE: ${ARCHIVE_NAME}"
notify_all "Backup OK: ${SERVER_NAME}" "Backup completed: ${ARCHIVE_NAME}"

exit 0
