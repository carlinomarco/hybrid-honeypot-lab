# Screenshots

This folder contains screenshots documenting the project setup and results.

## Contents

| File | Description |
|---|---|
| `pfsense-dashboard.png` | pfSense WebGUI — main dashboard showing WAN/LAN/DMZ status |
| `pfsense-dmz-rules.png` | pfSense firewall rules for the DMZ interface |
| `pfsense-wireguard-status.png` | WireGuard VPN status showing active tunnel with pfSense ↔ AWS |
| `cowrie-running-pi.png` | Cowrie status on Raspberry Pi (PID confirmed) |
| `cowrie-running-aws.png` | Cowrie status on AWS EC2 (PYTHONPATH startup) |
| `cowrie-live-log.png` | Live Cowrie log showing incoming SSH connection with hassh fingerprint |
| `kibana-dashboard.png` | Kibana Discover view showing cowrie-* index with 15 events |
| `kibana-dataview.png` | Kibana Data View setup for cowrie-* index pattern |
| `elasticsearch-count.png` | curl output confirming 15 events in Elasticsearch |
| `wireguard-aws-show.png` | `sudo wg show` output on AWS showing active handshake |

## Adding Screenshots

To add a screenshot:
1. Take a screenshot during your lab session
2. Name it descriptively (see table above)
3. Place it in this folder
4. Commit: `git add screenshots/ && git commit -m "docs: add screenshots"`
