# Phase 4 — Hybrid Connectivity (WireGuard VPN)

## Overview

Goal: Build an encrypted site-to-site VPN tunnel between the local pfSense lab and the AWS cloud sensor, so log data from AWS can reach the Logstash instance on the Admin-PC.

**Protocol:** WireGuard  
**Topology:** pfSense (10.100.0.1) ↔ AWS EC2 (10.100.0.2)  
**Result:** AWS Filebeat can send logs to `192.168.1.101:5044` (Admin-PC) as if it were on the same network.

---

## 4.1 AWS — Install WireGuard and Generate Keys

```bash
sudo apt update && sudo apt install wireguard -y

# Generate private key, derive public key from it
wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey

# Read public key — you will need this for the pfSense peer configuration
sudo cat /etc/wireguard/publickey
```

---

## 4.2 AWS — Create WireGuard Config

```bash
sudo nano /etc/wireguard/wg0.conf
```

See template: [`configs/wireguard/wg0-aws.conf`](../configs/wireguard/wg0-aws.conf)

Key values used in this project:
- AWS VPN IP: `10.100.0.2/24`
- Listen Port: `51820`
- Allowed routes: `10.100.0.0/24, 192.168.1.0/24, 172.16.1.0/24`
- PersistentKeepalive: `25` (sends heartbeat every 25 seconds to keep tunnel alive)

---

## 4.3 pfSense — Install WireGuard Package

1. `System > Package Manager > Available Packages`
2. Search: `wireguard` → Install

---

## 4.4 pfSense — Create Tunnel

`VPN > WireGuard > Tunnels > Add Tunnel`

| Field | Value |
|---|---|
| Description | VPN-to-AWS |
| Listen Port | 51820 |
| Interface Address | 10.100.0.1/24 |

Click **Generate** to create the key pair. **Copy the public key** — you need it for the AWS config.

---

## 4.5 pfSense — Add AWS as Peer

`VPN > WireGuard > Peers > Add Peer`

| Field | Value |
|---|---|
| Tunnel | tun_wg0 |
| Description | AWS-Cloud-Sensor |
| Public Key | `<AWS_PUBLIC_KEY>` |
| Endpoint | `<AWS_PUBLIC_IP>` |
| Endpoint Port | 51820 |
| Allowed IPs | `10.100.0.2/32, 172.31.0.0/16` |
| Keep Alive | 25 |

---

## 4.6 AWS — Update Config with pfSense Public Key

Edit `/etc/wireguard/wg0.conf` and replace `PFSENSE_PUBLIC_KEY` with the key from pfSense.

---

## 4.7 AWS Security Group — Open WireGuard Port

AWS Console → EC2 → Security Groups → Edit Inbound Rules → Add:

| Type | Port | Source |
|---|---|---|
| Custom UDP | 51820 | 0.0.0.0/0 |

---

## 4.8 Start VPN on AWS

```bash
sudo wg-quick up wg0
sudo wg show
```

**Expected output:**
```
interface: wg0
  public key: <AWS_PUBLIC_KEY>
  private key: (hidden)
  listening port: 51820

peer: <PFSENSE_PUBLIC_KEY>
  endpoint: <PFSENSE_IP>:58297
  allowed ips: 10.100.0.0/24, 192.168.1.0/24, 172.16.1.0/24
  latest handshake: 1 minute, 2 seconds ago
  transfer: 244 B received, 124 B sent
```

A handshake timestamp + transfer data = tunnel is live. ✅

**Enable auto-start on reboot:**
```bash
sudo systemctl enable wg-quick@wg0
```

---

## 4.9 pfSense — Verify VPN Status

`VPN > WireGuard > Status` → peer should show RX/TX data flowing.

---

## 4.10 Ping Test (pfSense → AWS)

`Diagnostics > Ping`
- Hostname: `10.100.0.2`
- IP Protocol: IPv4
- Source address: LAN
- Pings: 3

**Result: 0% packet loss** ✅

---

## 4.11 pfSense Firewall Rules

Two rules are required to allow traffic to flow through the tunnel into the LAN:

**Rule 1 — WireGuard interface:**  
`Firewall > Rules > WireGuard > Add`
- Action: Pass
- Protocol: Any
- Source: Any
- Destination: Any
- Description: Allow WireGuard traffic

**Rule 2 — LAN interface:**  
`Firewall > Rules > LAN > Add`
- Action: Pass
- Protocol: Any
- Source: Network `10.100.0.0/24` (WireGuard subnet)
- Destination: Any
- Description: Allow WireGuard to LAN

> **Why two rules?** Rule 1 lets traffic enter the WireGuard interface. Rule 2 lets it pass from the VPN subnet into the LAN (192.168.1.x) to reach the Admin-PC.

---

## 4.12 Problem: AWS Cannot Reach Admin-PC (i/o timeout)

**Symptom:** AWS Filebeat reported `dial tcp 192.168.1.101:5044: i/o timeout` despite VPN tunnel being active.

**Cause:** pfSense was dropping traffic from the WireGuard subnet destined for the LAN. The WireGuard interface rule alone was not enough — a separate LAN rule was needed to allow the VPN subnet to reach LAN hosts.

**Solution:** Added both firewall rules described in 4.11.

**Verification:**
```bash
# From AWS terminal
ping -c 3 192.168.1.101
# → 0% packet loss ✅
```

---

## 4.13 EBS Snapshot After Phase 4

```
AWS Console → EC2 → Elastic Block Store → Volumes
→ Select 8 GiB volume → Actions → Create snapshot
→ Name: Cloud-Sensor-V2-Phase4-Complete
```

Also take a VirtualBox snapshot of the Admin-PC:
- Right-click `Admin-PC` → Take Snapshot → Name: `PHASE_4_COMPLETE_STABLE`

---

## Milestone Result

✅ WireGuard tunnel established: pfSense ↔ AWS (10.100.0.1 ↔ 10.100.0.2)  
✅ Ping test: 0% packet loss  
✅ pfSense shows RX/TX data flowing in WireGuard Status  
✅ AWS can reach Admin-PC at 192.168.1.101 through VPN  
✅ Auto-start on AWS reboot configured  
✅ Snapshots taken on both AWS and VirtualBox
