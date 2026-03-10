#!/bin/bash
# start-honeypot-pi.sh
# Starts the Cowrie honeypot on the Raspberry Pi 5 (local DMZ sensor)
# Run as: pi user (will switch to cowrie internally)
#
# Usage: bash scripts/start-honeypot-pi.sh

set -e

COWRIE_HOME="/home/cowrie/cowrie"
COWRIE_USER="cowrie"

echo "================================================"
echo "  Hybrid-SOC — Starting Local Honeypot Sensor  "
echo "================================================"

# Check we are not running as root
if [ "$EUID" -eq 0 ]; then
  echo "[ERROR] Do not run this script as root."
  exit 1
fi

echo "[1/3] Switching to cowrie user environment..."
sudo -u "$COWRIE_USER" bash << 'EOF'
  cd /home/cowrie/cowrie
  source cowrie-env/bin/activate

  echo "[2/3] Starting Cowrie daemon..."
  AUTHBIND_ENABLED=yes cowrie start

  echo "[3/3] Verifying status..."
  sleep 2
  cowrie status
EOF

echo ""
echo "[OK] Honeypot is running."
echo "     Monitor logs: sudo -u cowrie bash -c 'cd ~/cowrie && tail -f var/log/cowrie/cowrie.log'"
echo "     Stop:         sudo -u cowrie bash -c 'cd ~/cowrie && source cowrie-env/bin/activate && cowrie stop'"
