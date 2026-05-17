# Hybrid-SOC: Cyber Security Research Lab

A hybrid honeypot research environment combining local hardware (pfSense firewall + Raspberry Pi 5) with AWS cloud infrastructure, monitored through an ELK Stack SIEM.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Phase 1 — Local Infrastructure](#phase-1--local-infrastructure-pfsense--admin-pc)
4. [Phase 2 — Honeypot Deployment (Raspberry Pi)](#phase-2--honeypot-deployment-raspberry-pi)
5. [Phase 3 — Cloud Sensor (AWS EC2)](#phase-3--cloud-sensor-aws-ec2)
6. [Phase 4 — Hybrid Connectivity (WireGuard VPN)](#phase-4--hybrid-connectivity-wireguard-vpn)
7. [Phase 5 — SIEM & Log Analysis (ELK Stack)](#phase-5--siem--log-analysis-elk-stack)
8. [Problems & Solutions](#problems--solutions)
9. [Key Findings](#key-findings)

---

## Project Overview

**Goal:** Build a hybrid cyber-security research lab that studies real-world attack behavior by deploying medium-interaction honeypots both locally and in the cloud.

**Objectives:**
- **Strategic Deception** — Deploy convincing honeypots that waste attacker resources
- **Threat Intelligence** — Collect data on attack origins, brute-force credentials, and malware
- **Network Hardening Proof** — Demonstrate that pfSense can isolate a compromised device from the LAN

**Why "Hybrid"?**  
The local Raspberry Pi operates inside a controlled DMZ behind pfSense. The AWS EC2 instance provides a public IP that receives real global attack traffic within minutes of being turned on. Together they enable a direct comparison between local and internet-facing threat data.

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────┐
│           pfSense Firewall (VM)             │
│  WAN (NAT) ── LAN (intnet) ── DMZ (em2)     │
└────────────┬───────────────────┬────────────┘
             │                   │
      ┌──────▼──────┐    ┌───────▼────────┐
      │  Admin-PC   │    │ Raspberry Pi 5  │
      │  Ubuntu LAN │    │  Cowrie Honeypot│
      │ 192.168.1.x │    │  172.16.1.x/DMZ │
      └──────┬──────┘    └────────────────┘
             │
             │  WireGuard VPN (10.100.0.0/24)
             │
      ┌──────▼──────────────────┐
      │     AWS EC2 (t2.micro)  │
      │   Cloud-Sensor-V2       │
      │   Cowrie + Filebeat     │
      │   Public IP exposed     │
      └─────────────────────────┘

Log Pipeline:
Pi Cowrie ──► Filebeat ──► Logstash (Admin-PC 5044)
AWS Cowrie ──► Filebeat ──► WireGuard VPN ──► Logstash
                                    │
                             Elasticsearch
                                    │
                               Kibana Dashboards
```

---

## Phase 1 — Local Infrastructure (pfSense + Admin-PC)

### 1.1 pfSense Firewall Setup

**Software:** pfSense CE 2.8.1  
**Platform:** Oracle VirtualBox VM

**VM Configuration:**
| Setting | Value |
|---|---|
| OS Type | BSD / FreeBSD 64-bit |
| RAM | 1024 MB |
| Disk | 16 GB VDI |
| EFI | Disabled |

**Network Adapters:**
| Adapter | Mode | Interface | Purpose |
|---|---|---|---|
| Adapter 1 | NAT | WAN (em0) | Internet access |
| Adapter 2 | Internal Network (`intnet`) | LAN (em1) | Lab internal network |
| Adapter 3 | Bridged (physical Ethernet) | DMZ (em2) | Raspberry Pi connection |

**Key Configuration Steps:**
- WAN set to DHCP (receives IP from VirtualBox NAT: `10.0.x.x`)
- LAN IP set to `192.168.1.1/24` with DHCP range `.100`–`.199`
- Unchecked "Block RFC1918" and "Block Bogon" — required because NAT source is a private IP range
- DNS: `8.8.8.8` (primary), `8.8.4.4` (secondary)
- Timezone: `Europe/Zurich`
- Admin password changed from default `pfsense` to custom

**Why NAT instead of Bridged for WAN?**  
Bridged mode failed because the home router rejected the virtual MAC address. NAT mode lets VirtualBox act as a transparent mini-router, hiding pfSense from the home network entirely. This is a Layer 3 vs Layer 2 stability trade-off.

---

### 1.2 DMZ Configuration

The DMZ isolates the honeypot — even if the Raspberry Pi is fully compromised, the attacker cannot reach the LAN.

**Steps:**
1. Navigate to `Interfaces > Assignments`, add `em2` as `OPT1`
2. Enable interface, rename to `DMZ`
3. Set static IPv4: `172.16.1.1/24`
4. Enable DHCP server on DMZ: range `172.16.1.10`–`172.16.1.200`

**DMZ Firewall Rules:**
- Allow DMZ → Any (for updates and DNS)
- Block DMZ → LAN (prevents lateral movement from a compromised honeypot)

---

### 1.3 Admin-PC (Ubuntu 24.04 LTS)

**VM Configuration:**
| Setting | Value |
|---|---|
| OS | Ubuntu 24.04 LTS |
| RAM | 6144 MB (upgraded from 2 GB for ELK Stack) |
| Disk | 25 GB |
| Network | Internal Network (`intnet`) |

Receives IP `192.168.1.101` from pfSense DHCP. Accesses pfSense WebGUI at `http://192.168.1.1`.

---

## Phase 2 — Honeypot Deployment (Raspberry Pi)

### 2.1 Hardware

- **Device:** Raspberry Pi 5
- **OS:** Raspberry Pi OS 64-bit (Debian-based)
- **Connection:** Physical Ethernet → pfSense DMZ interface (Adapter 3, Bridged, Promiscuous Mode: Allow All)
- **DHCP Lease:** `172.16.1.10` from pfSense DMZ

Promiscuous mode is enabled so pfSense can capture all traffic from the Pi, including spoofed MAC addresses used by some attack tools.

---

### 2.2 Cowrie Installation

**What is Cowrie?**  
Cowrie is a medium-interaction SSH/Telnet honeypot. It presents a fake shell to attackers, logs all commands, captures uploaded files, and records full session replays — without ever giving access to the real system.

```bash
# Install dependencies
sudo apt install git python3-virtualenv libssl-dev libffi-dev \
  build-essential libpython3-dev python3-minimal authbind virtualenv -y

# Create restricted service user (no sudo rights)
sudo adduser --disabled-password --gecos "" cowrie

# Switch to cowrie user and clone
sudo su - cowrie
git clone https://github.com/cowrie/cowrie
cd cowrie

# Create isolated Python environment
virtualenv --python=python3 cowrie-env
source cowrie-env/bin/activate

# Install Cowrie and register the package
pip install -r requirements.txt
pip install -e .
```

**Why a dedicated user with no sudo?**  
Privilege separation ensures that an attacker who "escapes" the honeypot shell is still trapped in a low-privilege account with no access to system files or the real Pi user account.

---

### 2.3 Configuration

Cowrie uses a `.local` override file so that custom settings survive future package updates:

```bash
cp etc/cowrie.cfg.dist etc/cowrie.cfg
touch etc/cowrie.cfg.local
nano etc/cowrie.cfg.local
```

**`etc/cowrie.cfg.local`:**
```ini
[honeypot]
hostname = smart-sensor-office-01
```

---

### 2.4 Port Redirection (Port 22 → Cowrie)

Most automated bots only scan port 22. Cowrie runs on port 2222 by default, so the real SSH daemon must be moved first.

**Move real SSH to port 2224:**
```bash
sudo nano /etc/ssh/sshd_config
# Change: Port 22 → Port 2224
sudo systemctl restart ssh
```

**Grant Cowrie permission to bind port 22 (authbind):**
```bash
sudo touch /etc/authbind/byport/22
sudo chown cowrie:cowrie /etc/authbind/byport/22
sudo chmod 770 /etc/authbind/byport/22
```

**Update `etc/cowrie.cfg.local`:**
```ini
[honeypot]
hostname = smart-sensor-office-01

[ssh]
listen_port = 22
```

**Start Cowrie with authbind:**
```bash
AUTHBIND_ENABLED=yes cowrie start
cowrie status
# cowrie is running (PID: 1846)
```

**Verification:**
```bash
netstat -tuln
# Confirms 0.0.0.0:22 LISTEN under Cowrie PID
```

**Live log monitoring:**
```bash
tail -f var/log/cowrie/cowrie.log
```

---

## Phase 3 — Cloud Sensor (AWS EC2)

### 3.1 Instance Provisioning

| Setting | Value |
|---|---|
| Service | EC2 (Elastic Compute Cloud) |
| AMI | Ubuntu 24.04 LTS (64-bit x86) |
| Instance Type | t2.micro (Free Tier — 1 vCPU, 1 GiB RAM) |
| Key Pair | `honeypot-key` — RSA 2048-bit, `.pem` format |
| Instance Name | Cloud-Sensor-V2 |

---

### 3.2 Security Group (AWS Firewall)

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | `0.0.0.0/0` | Honeypot bait — open to world |
| 8022 | TCP | My IP only | Admin SSH management |
| 51820 | UDP | `0.0.0.0/0` | WireGuard VPN |

Port 22 is intentionally open to the entire internet to attract automated bots and scanners.

---

### 3.3 Initial Server Hardening

```bash
# Connect for the first time
ssh -i ~/keys/honeypot-key.pem ubuntu@<PUBLIC_IP>

# Update and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-virtualenv libssl-dev libffi-dev \
  build-essential python3-minimal python3-pip python3.12-venv

# Harden PEM key permissions
chmod 400 ~/keys/honeypot-key.pem
```

---

### 3.4 Move Real SSH to Port 8022

```bash
sudo nano /etc/ssh/sshd_config
# Change: #Port 22 → Port 8022

# Use classic ssh.service (more stable than ubuntu's ssh.socket for port changes)
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```

Reconnect on new port:
```bash
ssh -i ~/keys/honeypot-key.pem -p 8022 ubuntu@<PUBLIC_IP>
```

---

### 3.5 Cowrie Installation on AWS

```bash
# Create service user
sudo adduser --disabled-password cowrie

# Switch and install
sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git
cd cowrie

python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .
```

---

### 3.6 NAT Redirect Port 22 → Cowrie (2222)

```bash
# Exit cowrie user first
exit

# Redirect all port 22 traffic to Cowrie's internal port
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
```

**Start Cowrie on AWS:**
```bash
sudo su - cowrie
cd cowrie
source cowrie-env/bin/activate
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
tail -f var/log/cowrie/cowrie.log
```

**Self-Attack Validation:**  
From a separate machine, attempt a standard SSH connection to the public IP — Cowrie intercepts it, presents a fake login prompt, and logs the session. The Admin-PC live log stream shows the attacker's IP, SSH version, and encryption fingerprint (`hassh`) in real time.

---

## Phase 4 — Hybrid Connectivity (WireGuard VPN)

A site-to-site VPN connects the local pfSense lab to the AWS cloud sensor, allowing log data from AWS to reach the Logstash instance on the Admin-PC.

### 4.1 AWS — Generate WireGuard Keys

```bash
sudo apt update && sudo apt install wireguard -y

# Generate key pair
wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
```

**`/etc/wireguard/wg0.conf` (AWS):**
```ini
[Interface]
PrivateKey = <AWS_PRIVATE_KEY>
Address = 10.100.0.2/24
ListenPort = 51820
MTU = 1420

[Peer]
PublicKey = <PFSENSE_PUBLIC_KEY>
AllowedIPs = 10.100.0.0/24, 192.168.1.0/24, 172.16.1.0/24
PersistentKeepalive = 25
```

---

### 4.2 pfSense — Install and Configure WireGuard

1. `System > Package Manager > Available Packages` → search `wireguard` → Install
2. `VPN > WireGuard > Tunnels > Add Tunnel`:
   - Description: `VPN-to-AWS`
   - Listen Port: `51820`
   - Interface Address: `10.100.0.1/24`
   - Generate keys → copy public key

3. `VPN > WireGuard > Peers > Add Peer`:
   - Tunnel: `tun_wg0`
   - Public Key: `<AWS_PUBLIC_KEY>`
   - Endpoint: `<AWS_PUBLIC_IP>`
   - Endpoint Port: `51820`
   - Allowed IPs: `10.100.0.2/32, 172.31.0.0/16`
   - Keep Alive: `25`

---

### 4.3 Start VPN and Verify

**AWS:**
```bash
sudo wg-quick up wg0
sudo wg show
# latest handshake: ~1 minute ago → tunnel is active
sudo systemctl enable wg-quick@wg0  # auto-start on reboot
```

**pfSense ping test:**  
`Diagnostics > Ping` → Hostname: `10.100.0.2` → Result: **0% packet loss** ✅

**pfSense firewall rules required:**
- `Firewall > Rules > WireGuard`: Pass Any from Any to Any (allow VPN traffic)
- `Firewall > Rules > LAN`: Pass Any from `10.100.0.0/24` to Any (allow VPN subnet into LAN)

---

## Phase 5 — SIEM & Log Analysis (ELK Stack)

### 5.1 Install ELK Stack on Admin-PC

```bash
# Add Elastic repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update

# Install all three components
sudo apt install elasticsearch kibana logstash -y

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable --now elasticsearch
sudo systemctl enable --now kibana
sudo systemctl enable --now logstash
```

**Elasticsearch credentials:**
```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

---

### 5.2 Logstash Pipeline — Cowrie Log Ingestion

**`/etc/logstash/conf.d/cowrie.conf`:**
```
input {
  beats {
    port => 5044
    host => "0.0.0.0"
  }
}

filter {
  json {
    source => "message"
    skip_on_invalid_json => true
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    index => "cowrie-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "<ELASTICSEARCH_PASSWORD>"
    ssl_certificate_verification => false
  }
}
```

```bash
sudo systemctl restart logstash
```

---

### 5.3 Kibana Setup

```bash
# Generate enrollment token
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana

# Get verification code
sudo /usr/share/kibana/bin/kibana-verification-code
```

Access at `http://localhost:5601`. Login: `elastic` / `<password>`

**Create Data View:**  
`Stack Management > Data Views > Create data view`  
- Name: `cowrie`  
- Index pattern: `cowrie-*`  
- Timestamp field: `@timestamp`

---

### 5.4 Filebeat — Raspberry Pi

```bash
# Install Elastic repo on Pi (same steps as above)
sudo apt install filebeat -y
```

**`/etc/filebeat/filebeat.yml`:**
```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /home/cowrie/cowrie/var/log/cowrie/cowrie.json*
    json.keys_under_root: true
    json.add_error_key: true
    fields:
      sensor: raspberry-pi
    fields_under_root: true

output.logstash:
  hosts: ["192.168.1.101:5044"]
```

```bash
sudo systemctl enable --now filebeat
```

---

### 5.5 Filebeat — AWS Cloud Sensor

**`/etc/filebeat/filebeat.yml`:**
```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /home/cowrie/cowrie/var/log/cowrie/cowrie.json*
    json.keys_under_root: true
    json.add_error_key: true
    fields:
      sensor: aws-cloud-sensor
    fields_under_root: true

output.logstash:
  hosts: ["192.168.1.101:5044"]
```

AWS Filebeat routes through the WireGuard VPN to reach Logstash on the Admin-PC.

```bash
sudo systemctl enable --now filebeat
```

---

### 5.6 Verify Full Pipeline

```bash
# Check event count in Elasticsearch
curl -k -u elastic:<password> https://localhost:9200/cowrie-*/_count

# Expected result:
# {"count": 15, ...}
# 8 events from Raspberry Pi + 7 events from AWS
```

**Full data flow:**
```
Raspberry Pi → Filebeat → Logstash (5044) → Elasticsearch → Kibana
AWS EC2      → Filebeat → WireGuard VPN → Logstash (5044) → Elasticsearch → Kibana
```

---

## Problems & Solutions

### Problem 1 — Bridged WAN Mode Failure
**Phase:** 1  
**Symptom:** pfSense WAN showed red blinking dots; Admin-PC had no internet.  
**Cause:** Home router rejected the virtual MAC address of pfSense in Bridged mode (Layer 2 issue).  
**Solution:** Switched WAN adapter to NAT mode. VirtualBox acts as a mini-router; the home network only sees the physical host PC.

---

### Problem 2 — Cowrie Missing Binary (`bin/cowrie: No such file or directory`)
**Phase:** 2  
**Symptom:** `bin/cowrie start` returned "No such file or directory".  
**Cause:** Modern Cowrie requires an editable install to register the package entry points.  
**Solution:**
```bash
pip install -e .
```

---

### Problem 3 — SSH Connection Refused After Pi Reboot
**Phase:** 2  
**Symptom:** `ssh pi@172.16.1.10 -p 2224` returned "Connection refused" after reboot.  
**Cause:** Cowrie was not configured to auto-start; after reboot, the real SSH daemon reclaimed port 22 and the management port (2224) was not listening.  
**Solution:** Connect via port 22 (real SSH was accessible because Cowrie wasn't running), then manually start Cowrie. Auto-start via systemd is a planned improvement.

---

### Problem 4 — Admin-PC Freeze During ELK Install
**Phase:** 5  
**Symptom:** Ubuntu VM became completely unresponsive after starting Elasticsearch, Kibana, and Logstash simultaneously.  
**Cause:** VM had only 2 GB RAM; Elasticsearch alone requires ~1 GB, and combined services exceeded available memory.  
**Solution:** Powered off VM, increased RAM allocation from 2048 MB to 6144 MB in VirtualBox settings. All services ran stably after restart.

---

### Problem 5 — Logstash Stuck in "Deactivating" State
**Phase:** 5  
**Symptom:** After adding a GeoIP filter to the pipeline, Logstash entered a permanent "deactivating" state and blocked Java processes in memory.  
**Cause:** The GeoIP database download was blocked by network/permission issues, causing shutdown workers to hang indefinitely.  
**Solution:**
```bash
# Remove GeoIP filter from pipeline config
# Force-kill stuck Java process
sudo pkill -9 -f logstash
sudo systemctl start logstash
```
GeoIP enrichment can be re-added once the base pipeline is stable.

---

### Problem 6 — AWS Filebeat Connection Timeout (i/o timeout)
**Phase:** 5  
**Symptom:** AWS Filebeat reported `dial tcp 192.168.1.101:5044: i/o timeout` despite VPN being active.  
**Cause:** pfSense was blocking traffic from the WireGuard subnet (10.100.0.0/24) to the LAN. Two missing firewall rules were identified.  
**Solution:** Added two pfSense rules:
1. `Firewall > Rules > WireGuard`: Pass Any → Any (allow all VPN traffic through)
2. `Firewall > Rules > LAN`: Pass from `10.100.0.0/24` → Any (allow VPN subnet to reach LAN hosts)

Result: `ping 192.168.1.101` from AWS → 0% packet loss. Filebeat connected immediately.

---

### Problem 7 — Host Internet Lost When Pi Connected (NIC Contention)
**Phase:** 2  
**Symptom:** Windows host PC lost internet when the Raspberry Pi established an SSH connection through the bridged DMZ adapter.  
**Cause:** VirtualBox Bridged mode shares the physical NIC. Both Windows and pfSense attempted to use the same chip simultaneously, causing driver conflict.  
**Solution:** In Windows Ethernet adapter properties, unchecked all protocols except `VirtualBox NDIS6 Bridged Networking Driver`. This gives pfSense exclusive control of the port.

---

## Key Findings

- Within minutes of exposing the AWS EC2 instance on port 22 with `0.0.0.0/0`, automated bots from multiple countries began attempting SSH connections
- Cowrie captured attacker SSH client versions, encryption fingerprints (`hassh`), and all typed commands
- The `sensor` field in Filebeat allows filtering by source (Raspberry Pi vs AWS) inside Kibana, enabling a direct comparison between attack patterns on a hidden local DMZ vs. a public cloud IP
- The WireGuard VPN tunnel maintained stable connectivity with 0% packet loss and sub-second handshake latency between pfSense and AWS

---

## Repository Structure

```
hybrid-soc/
├── README.md                   # This file
├── docs/
│   ├── phase1-infrastructure.md
│   ├── phase2-honeypot.md
│   ├── phase3-aws.md
│   ├── phase4-vpn.md
│   └── phase5-elk.md
├── configs/
│   ├── cowrie/
│   │   └── cowrie.cfg.local
│   ├── logstash/
│   │   └── cowrie.conf
│   ├── filebeat/
│   │   ├── filebeat-pi.yml
│   │   └── filebeat-aws.yml
│   └── wireguard/
│       └── wg0-aws.conf
└── screenshots/
    └── README.md
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Firewall / Router | pfSense CE 2.8.1 |
| Hypervisor | Oracle VirtualBox |
| Local Honeypot | Raspberry Pi 5 + Cowrie |
| Cloud Honeypot | AWS EC2 t2.micro + Cowrie |
| VPN | WireGuard (site-to-site) |
| Log Shipper | Filebeat 8.x |
| Log Processor | Logstash 8.x |
| Database | Elasticsearch 8.x |
| Visualization | Kibana 8.x |
| Admin OS | Ubuntu 24.04 LTS |
| Cloud OS | Ubuntu 24.04 LTS |

---

*Project developed as part of a cybersecurity research initiative — LBS Bozen, 2026.*
