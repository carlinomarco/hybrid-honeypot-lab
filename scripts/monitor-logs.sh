#!/bin/bash
# monitor-logs.sh
# Live monitoring of Cowrie attack logs with color-coded output
# Works on both Raspberry Pi and AWS EC2
#
# Usage: bash scripts/monitor-logs.sh

COWRIE_LOG="/home/cowrie/cowrie/var/log/cowrie/cowrie.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "================================================"
echo "  Hybrid-SOC — Live Attack Monitor             "
echo "  Press Ctrl+C to stop                         "
echo "================================================"
echo ""

if [ ! -f "$COWRIE_LOG" ]; then
  echo "Log file not found at $COWRIE_LOG"
  echo "Is Cowrie running? Run: cowrie status"
  exit 1
fi

# Tail the log and color-code by event type
tail -f "$COWRIE_LOG" | while read line; do
  if echo "$line" | grep -q "New connection"; then
    echo -e "${CYAN}[NEW CONNECTION]${NC} $line"
  elif echo "$line" | grep -q "login attempt"; then
    echo -e "${YELLOW}[LOGIN ATTEMPT]${NC}  $line"
  elif echo "$line" | grep -q "login succeeded"; then
    echo -e "${RED}[LOGIN SUCCESS]${NC}  $line"
  elif echo "$line" | grep -q "CMD"; then
    echo -e "${RED}[COMMAND]${NC}        $line"
  elif echo "$line" | grep -q "Connection lost"; then
    echo -e "${GREEN}[DISCONNECTED]${NC}   $line"
  else
    echo "                 $line"
  fi
done
