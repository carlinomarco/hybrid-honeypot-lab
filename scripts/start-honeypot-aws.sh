#!/bin/bash
# start-honeypot-aws.sh
# Starts the Cowrie honeypot on the AWS EC2 instance
# Run as: ubuntu user (script will switch to cowrie internally)
#
# Usage: ./start-honeypot-aws.sh

set -e

COWRIE_HOME="/home/cowrie/cowrie"
COWRIE_ENV="$COWRIE_HOME/cowrie-env"

echo "[*] Starting Cowrie honeypot on AWS..."

# Check if cowrie user exists
if ! id "cowrie" &>/dev/null; then
    echo "[!] Error: cowrie user does not exist. Run setup first."
    exit 1
fi

# Ensure iptables redirect is active (22 → 2222)
echo "[*] Checking iptables NAT redirect..."
if ! sudo iptables -t nat -L PREROUTING | grep -q "redir ports 2222"; then
    echo "[*] Adding iptables redirect: port 22 → 2222"
    sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
else
    echo "[+] iptables redirect already active"
fi

# Start Cowrie as cowrie user
sudo -u cowrie bash <<EOF
cd $COWRIE_HOME
source $COWRIE_ENV/bin/activate
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
sleep 2
PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
EOF

echo "[+] Cowrie started. Tailing live log (Ctrl+C to stop):"
sudo -u cowrie bash -c "tail -f $COWRIE_HOME/var/log/cowrie/cowrie.log"
