#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Ensure the script is being run as root (required for systemctl and sudo -u)
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Try running: sudo update-pretix" 
   exit 1
fi

echo "====================================="
echo "Starting Pretix Update Process"
echo "====================================="

echo "====================================="
echo "Creating Pre-Update Backups"
echo "====================================="
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/pretix/backups/pre_update_$TIMESTAMP"

# Create backup directory
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "Backing up PostgreSQL database..."
sudo -u postgres pg_dump pretix > "$BACKUP_DIR/pretix_db.sql"

echo "Backing up Pretix data directory (including .secret and media)..."
rsync -a /var/pretix/data/ "$BACKUP_DIR/data_dir_backup/"

echo "Backups successfully saved to $BACKUP_DIR"
echo "Proceeding with the update..."

# Execute the following block of commands as the 'pretix' user
# The 'EOF' is quoted to prevent variable expansion by the root shell
sudo -u pretix bash << 'EOF'
# Exit on error within the subshell
set -e 

echo "[1/5] Activating virtual environment..."
source /var/pretix/venv/bin/activate

echo "[2/5] Upgrading pretix and gunicorn via pip..."
pip3 install -U --upgrade-strategy eager pretix gunicorn

echo "[3/5] Running database migrations..."
python -m pretix migrate

echo "[4/5] Rebuilding static files..."
python -m pretix rebuild

echo "[5/5] Updating assets..."
python -m pretix updateassets
EOF

# If the script gets here, the pretix user commands succeeded
echo "====================================="
echo "Application updated successfully."
echo "Restarting system services..."
echo "====================================="

# Run the service restarts as root
systemctl restart pretix-web pretix-worker

echo "Done! Pretix is now updated and restarted."
