#!/bin/bash
# start-honeypot-pi.sh
# Starts the Cowrie honeypot on the Raspberry Pi
# Run as: pi user (script will switch to cowrie internally)
#
# Usage: ./start-honeypot-pi.sh

set -e

COWRIE_HOME="/home/cowrie/cowrie"
COWRIE_ENV="$COWRIE_HOME/cowrie-env"

echo "[*] Starting Cowrie honeypot on Raspberry Pi..."

# Check if cowrie user exists
if ! id "cowrie" &>/dev/null; then
    echo "[!] Error: cowrie user does not exist. Run setup first."
    exit 1
fi

# Check if cowrie directory exists
if [ ! -d "$COWRIE_HOME" ]; then
    echo "[!] Error: Cowrie directory not found at $COWRIE_HOME"
    exit 1
fi

# Switch to cowrie user and start
sudo -u cowrie bash <<EOF
cd $COWRIE_HOME
source $COWRIE_ENV/bin/activate
AUTHBIND_ENABLED=yes cowrie start
sleep 2
cowrie status
EOF

echo "[+] Checking port 22 listener..."
netstat -tuln | grep :22 || ss -tuln | grep :22

echo "[+] Cowrie started. Tailing live log (Ctrl+C to stop):"
sudo -u cowrie bash -c "tail -f $COWRIE_HOME/var/log/cowrie/cowrie.log"
