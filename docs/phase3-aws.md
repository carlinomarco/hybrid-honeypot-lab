# Phase 3 — AWS Cloud Sensor (EC2)

**Status:** ✅ Complete  
**Duration:** ~6 hours  
**Instance:** Cloud-Sensor-V2 · `13.51.13.199` · eu-north-1 (Stockholm)

---

## Goal

Deploy a public-facing honeypot on AWS EC2 to capture real-world global attack data. Unlike the home lab (hidden behind home router NAT), an AWS instance has a real public IP — bots and scanners start probing it within minutes of launch.

---

## Instance Specifications

| Parameter | Value |
|-----------|-------|
| Provider | AWS EC2 |
| Region | eu-north-1 (Stockholm) |
| Instance Type | t2.micro (Free Tier eligible) |
| vCPU / RAM | 1 vCPU / 1 GiB RAM |
| OS | Ubuntu 24.04 LTS (64-bit x86) |
| Storage | 8 GiB EBS (gp3) |
| Key Pair | honeypot-key.pem (RSA 2048-bit) |
| Public IP | 13.51.13.199 |

---

## Security Groups (Cloud Firewall)

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | 0.0.0.0/0 (Anywhere) | Honeypot bait — open to the internet |
| 8022 | TCP | My IP only | Admin SSH — management access |

**Design principle:** Port 22 is the bait (open to all). Port 8022 is the back door (only you). This way even if an attacker scans every port, they can never reach the management interface.

---

## Step-by-Step Setup

### 1. Launch EC2 Instance

- Service: EC2 > Launch Instance
- AMI: Ubuntu 24.04 LTS (64-bit x86)
- Instance type: t2.micro
- Key pair: create new → `honeypot-key` → RSA → .pem format → download immediately
- Network settings: add both security group rules (port 22 open, port 8022 My IP)

### 2. Key Management (Admin-PC)

```bash
# Store key securely on Admin-PC
mkdir -p ~/keys
mv ~/Downloads/honeypot-key.pem ~/keys/
chmod 400 ~/keys/honeypot-key.pem
# chmod 400 = read-only by owner — OpenSSH rejects keys with wider permissions
```

### 3. First Login

```bash
ssh -i ~/keys/honeypot-key.pem ubuntu@13.51.13.199
```

### 4. System Update & Dependencies

```bash
sudo apt update && sudo apt upgrade -y && sudo apt install -y \
  git python3-virtualenv libssl-dev libffi-dev build-essential \
  python3-minimal python3-pip python3.12-venv
```

### 5. Ubuntu 24.04 SSH Port Migration

Ubuntu 24.04 uses `ssh.socket` by default which causes "Broken pipe" errors when changing ports. Switch to classic `ssh.service` first:

```bash
sudo nano /etc/ssh/sshd_config
# Find: #Port 22 → change to: Port 8022

sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```

**⚠️ Do not close the current terminal window until you verify the new connection works:**

```bash
# Open new terminal — test port 8022
ssh -i ~/keys/honeypot-key.pem -p 8022 ubuntu@13.51.13.199
```

### 6. Install Cowrie

```bash
sudo adduser --disabled-password cowrie
# Press Enter for all prompts

sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git && cd cowrie
python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .
```

### 7. Port Redirection via iptables

Cowrie runs as non-root and cannot bind port 22 directly. Use iptables NAT to redirect:

```bash
# Exit cowrie user first
exit

# Apply redirect rule (as ubuntu user)
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
```

This intercepts all traffic at kernel level before any process sees it — attackers connect to port 22 and are silently handed to Cowrie on 2222.

### 8. Start Cowrie

```bash
sudo su - cowrie
cd cowrie
source cowrie-env/bin/activate
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
tail -f var/log/cowrie/cowrie.log
```

> **Note:** `PYTHONPATH=src` is required on Ubuntu 24.04 due to filesystem structure differences — without it, module imports fail.

---

## Self-Attack Validation

From Windows host (simulating a real attacker):

```bash
ssh root@13.51.13.199
# No PEM key, no special port — exactly what a botnet does
```

**Expected results:**
- Password prompt from Cowrie fake shell
- Any password accepted → fake interactive shell
- Admin-PC log shows: connection source IP, SSH client version, hassh fingerprint, encryption algorithms

---

## Snapshot (Recovery Baseline)

Before starting Phase 4 (VPN), a snapshot was created:

1. AWS Console > EC2 > Instances > Stop Cloud-Sensor-V2
2. EC2 > Elastic Block Store > Volumes
3. Select the 8 GiB volume → Actions > Create Snapshot
4. Name: `Cloud-Sensor-V2-PreVPN-Working`

This allows full state restoration if VPN configuration breaks network connectivity.

---

## Key Learnings

- Ubuntu 24.04 uses `ssh.socket` not `ssh.service` — must switch before changing ports
- `PYTHONPATH=src` required for Cowrie startup on Ubuntu 24.04
- iptables PREROUTING redirect is more reliable than authbind in cloud environments
- Always take an EBS snapshot before major configuration changes
- Never click "Terminate" — always "Stop" (terminate destroys the instance permanently)
