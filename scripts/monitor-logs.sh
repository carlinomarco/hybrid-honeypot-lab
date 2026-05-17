#!/bin/bash
# monitor-logs.sh
# Monitor Cowrie logs in real time — run from Admin-PC or directly on sensor
#
# Usage:
#   Local (on Pi or AWS):    ./monitor-logs.sh
#   Remote (from Admin-PC):  ./monitor-logs.sh pi
#                            ./monitor-logs.sh aws

COWRIE_LOG="/home/cowrie/cowrie/var/log/cowrie/cowrie.log"
PI_IP="172.16.1.10"
PI_PORT="2224"
AWS_IP="13.51.13.199"    # Update this if your AWS IP changes
AWS_PORT="8022"
KEY="$HOME/keys/honeypot-key.pem"

case "$1" in
  pi)
    echo "[*] Monitoring Raspberry Pi honeypot logs..."
    ssh pi@$PI_IP -p $PI_PORT "sudo tail -f $COWRIE_LOG"
    ;;
  aws)
    echo "[*] Monitoring AWS Cloud-Sensor-V2 logs..."
    ssh -i $KEY ubuntu@$AWS_IP -p $AWS_PORT "sudo -u cowrie tail -f $COWRIE_LOG"
    ;;
  "")
    echo "[*] Monitoring local Cowrie logs..."
    sudo -u cowrie tail -f $COWRIE_LOG
    ;;
  *)
    echo "Usage: $0 [pi|aws]"
    echo "  pi   — SSH into Raspberry Pi and tail logs"
    echo "  aws  — SSH into AWS EC2 and tail logs"
    echo "  (no arg) — tail local logs"
    exit 1
    ;;
esac
