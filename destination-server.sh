#!/bin/bash
# ===== RUN ON THE DESTINATION SERVER, as the backup user (not root) =====
BACKUP_DIR="$HOME/backup-html"     # must match DEST_DIR in the source script

if ! command -v rsync >/dev/null 2>&1; then
  echo ">> Installing rsync..."
  if command -v apt-get >/dev/null; then sudo apt-get update && sudo apt-get install -y rsync
  elif command -v dnf >/dev/null; then sudo dnf install -y rsync
  else sudo yum install -y rsync; fi
fi
command -v rsync >/dev/null || { echo "FAILED: rsync is not installed"; exit 1; }

mkdir -p "$BACKUP_DIR"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

echo
echo "=== SERVER READY ==="
echo "User   : $(whoami)"
echo "IP     : $(hostname -I | awk '{print $1}')"
echo "Folder : $BACKUP_DIR"
echo "Disk   : $(df -h "$BACKUP_DIR" | awk 'NR==2{print $4" free"}')"