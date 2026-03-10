#!/bin/bash
# start-honeypot-aws.sh
# Starts the Cowrie honeypot on the AWS EC2 cloud sensor
# Run as: ubuntu user (will switch to cowrie internally)
#
# Usage: bash scripts/start-honeypot-aws.sh

set -e

COWRIE_HOME="/home/cowrie/cowrie"

echo "================================================"
echo "  Hybrid-SOC — Starting Cloud Honeypot Sensor  "
echo "================================================"

echo "[1/4] Checking iptables redirect rule..."
if ! sudo iptables -t nat -L PREROUTING | grep -q "redir ports 2222"; then
  echo "      Rule not found — applying port 22 → 2222 redirect..."
  sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
  echo "      Redirect applied."
else
  echo "      Redirect already active."
fi

echo "[2/4] Switching to cowrie user environment..."
sudo -u cowrie bash << 'EOF'
  cd /home/cowrie/cowrie
  source cowrie-env/bin/activate

  echo "[3/4] Starting Cowrie daemon..."
  PYTHONPATH=src python3 -m cowrie.scripts.cowrie start

  echo "[4/4] Verifying status..."
  sleep 2
  PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
EOF

echo ""
echo "[OK] Cloud sensor is running."
echo "     Monitor logs: sudo -u cowrie bash -c 'cd ~/cowrie && tail -f var/log/cowrie/cowrie.log'"
echo "     Stop:         sudo -u cowrie bash -c 'cd ~/cowrie && source cowrie-env/bin/activate && PYTHONPATH=src python3 -m cowrie.scripts.cowrie stop'"
