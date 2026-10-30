#!/bin/bash
# ===== RUN ON THE SOURCE SERVER (Ubuntu 16.04), as root =====
# ---------- EDIT THIS SECTION ----------
NAME="html"                      # job name, letters/numbers only
SRC_DIR="/var/www/html"          # folder to back up
DEST_USER="it"                   # user on the destination server
DEST_HOST="1.2.3.4"              # destination server IP
DEST_DIR="backup-html"           # folder in the destination user's home (no ~/)
KEEP=7                           # number of snapshots to keep
CRON_TIME="0 0 * * *"            # schedule, 0 0 = 00:00 server time
# ---------------------------------------

KEY="/root/.ssh/backup_${NAME}"
SCRIPT="/usr/local/bin/backup-${NAME}.sh"
LOG="/var/log/backup-${NAME}.log"
REMOTE="${DEST_USER}@${DEST_HOST}"

[ "$(id -u)" -eq 0 ] || { echo "Run this as root"; exit 1; }
[ -d "$SRC_DIR" ] || { echo "Source folder $SRC_DIR does not exist"; exit 1; }

# --- 1. Install rsync (falls back to old-releases for EOL Ubuntu) ---
if ! command -v rsync >/dev/null 2>&1; then
  echo ">> Installing rsync..."
  apt-get update >/dev/null 2>&1
  if ! apt-get install -y rsync; then
    echo ">> Repo unreachable, switching to old-releases.ubuntu.com"
    cp -n /etc/apt/sources.list /etc/apt/sources.list.bak
    sed -i -E 's#https?://([a-z]{2}\.)?archive\.ubuntu\.com#http://old-releases.ubuntu.com#g; s#https?://security\.ubuntu\.com#http://old-releases.ubuntu.com#g' /etc/apt/sources.list
    apt-get update && apt-get install -y rsync
  fi
fi
command -v rsync >/dev/null || { echo "FAILED: could not install rsync"; exit 1; }

# --- 2. Trust destination host key (OpenSSH 7.2 has no accept-new) ---
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if ! ssh-keygen -F "$DEST_HOST" >/dev/null 2>&1; then
  ssh-keyscan -t ed25519 "$DEST_HOST" >> /root/.ssh/known_hosts 2>/dev/null
  echo ">> Destination host key fingerprint (compare with destination):"
  ssh-keygen -lf <(ssh-keyscan -t ed25519 "$DEST_HOST" 2>/dev/null)
fi

# --- 3. Passwordless SSH key for cron ---
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "backup-${NAME}@$(hostname)"
fi
if ! ssh -i "$KEY" -o BatchMode=yes "$REMOTE" "echo ok" >/dev/null 2>&1; then
  echo ">> Sending key to destination, enter the password for ${DEST_USER} ONCE:"
  if ! ssh-copy-id -i "${KEY}.pub" "$REMOTE"; then
    echo
    echo "ssh-copy-id failed. Add this line to ~/.ssh/authorized_keys on the destination,"
    echo "then run this script again:"
    echo
    cat "${KEY}.pub"
    exit 1
  fi
fi
ssh -i "$KEY" -o BatchMode=yes "$REMOTE" "command -v rsync >/dev/null && mkdir -p ~/${DEST_DIR} && echo ok" \
  | grep -q ok || { echo "FAILED: passwordless login or rsync on destination not ready"; exit 1; }
echo ">> Passwordless connection OK"

# --- 4. Write the backup script ---
cat > "$SCRIPT" <<EOF
#!/bin/bash
set -euo pipefail
SRC="${SRC_DIR}/"
REMOTE="${REMOTE}"
DIR="${DEST_DIR}"
KEEP=${KEEP}
SSH="ssh -i ${KEY} -o BatchMode=yes"
NOW=\$(date +%F_%H%M%S)

echo "\$(date '+%F %T') starting snapshot \$NOW"
rsync -az --numeric-ids --stats -e "\$SSH" --link-dest=../latest \\
  "\$SRC" "\$REMOTE:\$DIR/\$NOW.partial/"
\$SSH "\$REMOTE" "cd ~/\$DIR && mv \$NOW.partial \$NOW && ln -sfn \$NOW latest && ls -1d 20*[0-9] | head -n -\$KEEP | xargs -r rm -rf"
echo "\$(date '+%F %T') snapshot \$NOW done"
EOF
chmod 700 "$SCRIPT"

# --- 5. Install cron job (no duplicates if re-run) ---
( crontab -l 2>/dev/null | grep -v "$SCRIPT"
  echo "$CRON_TIME flock -n /var/run/backup-${NAME}.lock $SCRIPT >> $LOG 2>&1"
) | crontab -

# --- 6. Test run now ---
echo ">> Running first backup (may take a while, this one is full)..."
if "$SCRIPT" >> "$LOG" 2>&1; then
  echo
  echo "=== SUCCESS ==="
  ssh -i "$KEY" "$REMOTE" "ls -la ~/${DEST_DIR}/latest/ | head -15"
else
  echo "=== FAILED === check: tail -30 $LOG"; exit 1
fi
echo
echo "Cron     : $(crontab -l | grep "$SCRIPT")"
echo "Timezone : $(date '+%Z %z')  <- cron schedule follows this clock"
echo "Log      : tail $LOG"