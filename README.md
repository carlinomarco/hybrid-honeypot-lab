# Hybrid Honeypot Lab

> **Graduation Project — LBS Bozen 2026**  
> A hybrid cyber-security research lab combining local hardware with AWS cloud infrastructure to study real-world attack behavior.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    HYBRID-SOC NETWORK                       │
│                                                             │
│   [ Internet / Global Attackers ]                           │
│              │                                              │
│              ▼                                              │
│   ┌──────────────────┐      ┌─────────────────────┐         │
│   │   AWS EC2        │      │  pfSense Firewall   │         │
│   │  Cloud Sensor    │      │  WAN │ LAN │ DMZ    │         │
│   │  (Cowrie)        │      └────────────┬────────┘         │
│   └──────────────────┘                   │                  │
│            │                    ┌────────┴────────┐         │
│            │                  LAN               DMZ         │
│            │              (Admin-PC)       (Raspberry Pi 5) │
│            │              Ubuntu 24.04      Cowrie Honeypot │
│            │                                                │
│   Site-to-Site VPN ──────────────── (Phase 4, planned)      │
│            │                                                │
│   ┌────────┴────────┐                                       │
│   │   ELK Stack     │  ← Centralized SIEM (Phase 5)         │
│   │  Elasticsearch  │                                       │
│   │  Kibana         │                                       │
│   └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Project Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | Local Infrastructure (pfSense) | ✅ Complete |
| 2 | IoT Sensor — Raspberry Pi 5 Honeypot | ✅ Complete |
| 3 | Cloud Infrastructure (AWS EC2) | ✅ Complete |
| 4 | Hybrid Connectivity (Site-to-Site VPN) | 🔄 In Progress |
| 5 | SIEM & Monitoring (ELK Stack) | ⏳ Planned |

---

## Phase 1 — Local Infrastructure

**Goal:** Build the network foundation and security gateway.

| Adapter | Mode | Interface | Role |
|---------|------|-----------|------|
| Adapter 1 | NAT | WAN (em0) | Internet via VirtualBox |
| Adapter 2 | Internal Network (intnet) | LAN (em1) | Admin-PC private network |
| Adapter 3 | Bridged (Physical Ethernet) | DMZ (em2) | Raspberry Pi honeypot zone |

**Network addresses:**
- LAN: `192.168.1.0/24` — Gateway `192.168.1.254`
- DMZ: `172.16.1.0/24` — Gateway `172.16.1.1`
- Admin-PC: `192.168.1.101` (DHCP from pfSense)
- Raspberry Pi: `172.16.1.10` (DHCP from pfSense DMZ)

**Key problem solved:** Bridged WAN caused Layer 2 MAC rejection from home router.  
**Fix:** Switched to NAT — VirtualBox acts as intermediary router, making internet access stable.

---

## Phase 2 — Raspberry Pi 5 Honeypot

**Goal:** Deploy a physical medium-interaction SSH honeypot inside the DMZ.

**What is Cowrie?**  
Cowrie is the industry standard SSH/Telnet honeypot. It lets attackers "log in" to a fake system, records every command they type, every file they upload, and every session — without ever exposing real hardware.

**Installation:**

```bash
sudo adduser --disabled-password cowrie
sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git && cd cowrie
virtualenv --python=python3 cowrie-env
source cowrie-env/bin/activate
pip install -r requirements.txt && pip install -e .
```

**Configuration** (`etc/cowrie.cfg.local`):

```ini
[honeypot]
hostname = smart-sensor-office-01

[ssh]
listen_port = 22
```

**Port management:**

```bash
# Give Cowrie permission to use port 22 without root
sudo touch /etc/authbind/byport/22
sudo chown cowrie:cowrie /etc/authbind/byport/22
sudo chmod 770 /etc/authbind/byport/22

# Start honeypot
AUTHBIND_ENABLED=yes cowrie start

# Verify
cowrie status          # → cowrie is running (PID: 2032)
netstat -tuln          # → 0.0.0.0:22 LISTEN confirmed
tail -f var/log/cowrie/cowrie.log
```

---

## Phase 3 — AWS Cloud Sensor

**Goal:** Deploy a public-facing honeypot to capture global attack data.

**Instance details:**

| Parameter | Value |
|-----------|-------|
| Region | eu-north-1 (Stockholm) |
| Instance | t2.micro — Free Tier eligible |
| OS | Ubuntu 24.04 LTS (64-bit) |
| Public IP | 13.51.13.199 (Cloud-Sensor-V2) |
| Key pair | honeypot-key.pem (RSA 2048-bit) |

**Security Groups:**

| Port | Source | Purpose |
|------|--------|---------|
| 22 | 0.0.0.0/0 (Anywhere) | Honeypot bait — open to all |
| 8022 | My IP only | Admin SSH management |

**Port redirect via iptables:**

```bash
# Redirect all port 22 traffic to Cowrie on port 2222
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
```

**Ubuntu 24.04 SSH fix** (prevents lockout when changing ports):

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```

**Cowrie startup on AWS:**

```bash
sudo su - cowrie && cd cowrie
source cowrie-env/bin/activate
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
tail -f var/log/cowrie/cowrie.log
```

**Admin connection:**

```bash
ssh -i ~/keys/honeypot-key.pem -p 8022 ubuntu@13.51.13.199
```

---

## Phase 4 — Site-to-Site VPN *(In Progress)*

**Goal:** Encrypted tunnel between pfSense (home lab) and AWS VPC to consolidate logs.

- Protocol: IPsec or WireGuard
- Routes: cloud honeypot logs → Admin-PC (192.168.1.101)
- EBS Snapshot taken before start: `Cloud-Sensor-V2-PreVPN-Working`

---

## Phase 5 — SIEM & Monitoring *(Planned)*

**Goal:** Visualize attack data for the final Matura analysis.

- **Filebeat / Logstash** — collect logs from Pi 5 and AWS
- **Elasticsearch** — store and index all events
- **Kibana** — dashboards: attacker origin map, brute-force passwords, top targeted ports
- **Final analysis:** compare local DMZ attacks vs global AWS attacks

---

## Tech Stack

![pfSense](https://img.shields.io/badge/pfSense-212121?style=flat&logo=pfsense&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry_Pi_5-C51A4A?style=flat&logo=raspberry-pi&logoColor=white)
![AWS](https://img.shields.io/badge/AWS_EC2-232F3E?style=flat&logo=amazon-aws&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu_24.04-E95420?style=flat&logo=ubuntu&logoColor=white)
![Cowrie](https://img.shields.io/badge/Cowrie_Honeypot-333333?style=flat&logo=gnu-bash&logoColor=white)
![Elasticsearch](https://img.shields.io/badge/ELK_Stack-005571?style=flat&logo=elasticsearch&logoColor=white)

**Networking:** pfSense · DMZ · NAT · iptables · DHCP · DNS  
**Security:** Cowrie · Authbind · SSH hardening · AWS Security Groups  
**Cloud:** AWS EC2 · VPC · EBS Snapshots  
**Monitoring:** ELK Stack · Kibana *(planned)*

---

## Author

**Marco Carlino** — LBS Bozen, Graduation 2026  
[![LinkedIn](https://img.shields.io/badge/LinkedIn-carlino--marco-0077B5?style=flat&logo=linkedin)](https://linkedin.com/in/carlino-marco)
[![Email](https://img.shields.io/badge/Email-carlinomarco4@gmail.com-D14836?style=flat&logo=gmail&logoColor=white)](mailto:carlinomarco4@gmail.com)
