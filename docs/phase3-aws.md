# Phase 3 — Cloud Infrastructure (AWS EC2)

## Overview

Goal: Deploy a public-facing honeypot on AWS to capture real global attack data from internet-facing bots and scanners.

---

## 3.1 Instance Provisioning

| Parameter | Value |
|---|---|
| Service | EC2 (Elastic Compute Cloud) |
| Region | eu-north-1 (Stockholm) |
| AMI | Ubuntu 24.04 LTS (64-bit x86) |
| Instance Type | t2.micro (Free Tier — 1 vCPU, 1 GiB RAM) |
| Instance Name | Cloud-Sensor-V2 |
| Key Pair | `honeypot-key` — RSA 2048-bit, `.pem` format |
| Storage | 8 GiB EBS (gp3) |

> **Why t2.micro?** Free Tier eligible. 1 vCPU and 1 GiB RAM is sufficient for Cowrie — it's a lightweight Python process, not a full production server.

> **Why Ubuntu 24.04?** Cowrie is optimized for Debian-based systems. LTS provides the longest security support window, important for a lab that runs continuously.

---

## 3.2 Security Group Configuration

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | `0.0.0.0/0` (Anywhere) | **Honeypot bait** — open to the entire internet |
| 8022 | TCP | My IP only | Admin SSH management (secure back door) |
| 51820 | UDP | `0.0.0.0/0` | WireGuard VPN (added in Phase 4) |

> **Why open port 22 to everyone?** This is intentional. Setting source to `0.0.0.0/0` allows any IP on the internet to attempt a connection — this is the "bait." Automated bots and scanners will find it within minutes. Without this, the honeypot collects no data.

---

## 3.3 Initial Server Setup

**Copy PEM key to Admin-PC and harden permissions:**
```bash
mkdir -p ~/keys
mv ~/Downloads/honeypot-key.pem ~/keys/
chmod 400 ~/keys/honeypot-key.pem
# 400 = readable only by owner. OpenSSH refuses keys with looser permissions.
```

**First connection (using default port 22):**
```bash
ssh -i ~/keys/honeypot-key.pem ubuntu@<PUBLIC_IP>
```

**Update and install dependencies:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-virtualenv libssl-dev libffi-dev \
  build-essential python3-minimal python3-pip python3.12-venv
```

---

## 3.4 Move Real SSH to Port 8022

This frees port 22 for Cowrie. We also fix a Ubuntu 24.04 quirk where the `ssh.socket` listener interferes with port changes.

```bash
sudo nano /etc/ssh/sshd_config
# Change: #Port 22 → Port 8022

# Ubuntu 24.04 fix: switch from socket to classic service
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```

> **Why disable `ssh.socket`?** Ubuntu 24.04 uses systemd socket activation by default. When you change the port and restart, the socket listener can conflict — causing "Broken pipe" disconnections. The classic `ssh.service` is more stable for non-standard ports.

**Add port 8022 to AWS Security Group before reconnecting:**  
AWS Console → EC2 → Security Groups → Edit Inbound Rules → Add:
- Type: Custom TCP, Port: 8022, Source: My IP

**Reconnect on new port:**
```bash
ssh -i ~/keys/honeypot-key.pem -p 8022 ubuntu@<PUBLIC_IP>
```

---

## 3.5 Cowrie Installation on AWS

```bash
# Create restricted service user
sudo adduser --disabled-password cowrie

# Switch and set up
sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git
cd cowrie

python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .   # Required for entry point registration
```

---

## 3.6 iptables Port Redirect (22 → Cowrie on 2222)

On AWS, we use iptables instead of authbind. Traffic arriving on port 22 is redirected at the kernel level to Cowrie's internal listener on port 2222.

```bash
# Exit cowrie user first
exit

# Kernel-level NAT redirect
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
```

---

## 3.7 Start Cowrie on AWS

```bash
sudo su - cowrie
cd cowrie
source cowrie-env/bin/activate

# PYTHONPATH required for Ubuntu 24.04 path compatibility
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
# → cowrie is running

tail -f var/log/cowrie/cowrie.log
```

---

## 3.8 Self-Attack Validation

From a separate machine (not the Admin-PC), attempt a standard SSH connection:

```bash
ssh root@<AWS_PUBLIC_IP>
# Do NOT use your .pem key, do NOT use port 8022
# This simulates a real botnet connection
```

**Expected result on Admin-PC log stream:**
```
New connection: [YOUR_IP]:[PORT] to [SENSOR_IP]:2222
login attempt: root / password123
```

Cowrie intercepted the connection, logged the attacker's IP, SSH client version, and `hassh` fingerprint.

---

## 3.9 EBS Snapshot (Backup Before Phase 4)

Before starting VPN work, create a snapshot so any VPN misconfiguration can be rolled back:

1. AWS Console → EC2 → Elastic Block Store → Volumes
2. Select the 8 GiB volume → Actions → Create snapshot
3. Name: `Cloud-Sensor-V2-PreVPN-Working`

---

## Milestone Result

✅ AWS EC2 t2.micro running Ubuntu 24.04 (Cloud-Sensor-V2)  
✅ Port 22 open to the entire internet as honeypot bait  
✅ Admin access secured on port 8022 (IP-restricted)  
✅ Cowrie running and logging real attack attempts  
✅ Self-attack validation confirmed iptables redirect working  
✅ EBS snapshot created before Phase 4
