# Hybrid Honeypot Lab

> Graduation project — LBS Bozen 2026  
> A hybrid cyber-security research lab combining local hardware with AWS cloud infrastructure to study real-world attack behavior.

---

## Architecture Overview[ Internet / Attackers ]
│
▼
┌─────────────┐        ┌──────────────────┐
│  AWS EC2    │        │  pfSense Firewall │
│  Cloud      │        │  WAN / LAN / DMZ  │
│  Sensor     │        └────────┬─────────┘
│  (Cowrie)   │                 │
└─────────────┘         ┌───────┴────────┐
│                │               │
│              LAN             DMZ
│         (Admin-PC)    (Raspberry Pi 5)
│                        (Cowrie Honeypot)
│
Site-to-Site VPN (planned)
│
┌──────┴──────┐
│  ELK Stack  │
│  (planned)  │
└─────────────┘

---

## Project Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | Local Infrastructure (pfSense) | ✅ Complete |
| 2 | IoT Sensor — Raspberry Pi 5 Honeypot | ✅ Complete |
| 3 | Cloud Infrastructure (AWS EC2) | ✅ Complete |
| 4 | Hybrid Connectivity (Site-to-Site VPN) | 🔄 In progress |
| 5 | SIEM & Monitoring (ELK Stack) | ⏳ Planned |

---

## Phase 1 — Local Infrastructure

**Goal:** Build the network foundation and security gateway.

- Deployed pfSense 2.8.1 CE on VirtualBox (FreeBSD 64-bit)
- Configured three network interfaces: WAN (NAT), LAN (Internal), DMZ (Bridged)
- Enabled DHCP server on LAN (`192.168.1.100–199`) and DMZ (`172.16.1.10–200`)
- Set static DMZ IP: `172.16.1.1/24`
- Admin-PC: Ubuntu 24.04 LTS on Internal Network (`intnet`)

**Key problem solved:** Bridged WAN caused Layer 2 MAC rejection from home router → fixed by switching to NAT mode, which stabilized internet access through VirtualBox as intermediary.

---

## Phase 2 — Raspberry Pi 5 Honeypot

**Goal:** Deploy a physical medium-interaction honeypot in the DMZ.

**Hardware setup:**
- Raspberry Pi 5 powered via USB-C (27W official adapter)
- Ethernet connected to pfSense DMZ interface (Adapter 3, Bridged, Promiscuous: Allow All)
- Assigned IP `172.16.1.10` via pfSense DHCP

**Cowrie installation:**
```bashsudo adduser --disabled-password cowrie
sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git
cd cowrie
virtualenv --python=python3 cowrie-env
source cowrie-env/bin/activate
pip install -r requirements.txt
pip install -e .

**Configuration** (`etc/cowrie.cfg.local`):
```ini[honeypot]
hostname = smart-sensor-office-01[ssh]
listen_port = 22

**Port management:**
- Real SSH moved to port `2224` (`/etc/ssh/sshd_config`)
- Authbind used to allow Cowrie (non-root) to bind port 22
```bashsudo touch /etc/authbind/byport/22
sudo chown cowrie:cowrie /etc/authbind/byport/22
sudo chmod 770 /etc/authbind/byport/22
AUTHBIND_ENABLED=yes cowrie start

**Verification:**
```bashcowrie status         # → cowrie is running (PID: 2032)
netstat -tuln         # → 0.0.0.0:22 LISTEN confirmed
tail -f var/log/cowrie/cowrie.log

---

## Phase 3 — AWS Cloud Sensor

**Goal:** Deploy a public-facing honeypot to capture global attack data.

**Instance details:**
- Provider: AWS EC2 (eu-north-1, Stockholm)
- Instance: `t2.micro` — Free Tier eligible
- OS: Ubuntu 24.04 LTS (64-bit x86)
- Key pair: `honeypot-key.pem` (RSA 2048-bit)
- Public IP: `13.51.13.199` (Cloud-Sensor-V2)

**Security Groups:**
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | 0.0.0.0/0 | Honeypot bait — open to all |
| 8022 | TCP | My IP only | Admin SSH management |

**Port architecture:**
- Real SSH moved to `8022` using `ssh.service` (not `ssh.socket`) to avoid Ubuntu 24.04 socket conflicts
- iptables NAT redirects all port 22 traffic to Cowrie on port 2222:
```bashsudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222

**Cowrie startup (Ubuntu 24.04 specific):**
```bashsudo su - cowrie
cd cowrie
source cowrie-env/bin/activate
pip install -e .
PYTHONPATH=src python3 -m cowrie.scripts.cowrie start
PYTHONPATH=src python3 -m cowrie.scripts.cowrie status
tail -f var/log/cowrie/cowrie.log

**Validation:** Self-attack from Windows PC confirmed Cowrie interception — fake shell presented, session logged with SSH version, encryption algorithms, and hassh fingerprint.

---

## Phase 4 — Site-to-Site VPN *(In Progress)*

**Goal:** Securely connect home lab and AWS to consolidate attack logs.

- Tunnel: IPsec or WireGuard between pfSense and AWS VPC
- Static routes to forward cloud honeypot logs back to Admin-PC
- EBS Snapshot taken before VPN configuration: `Cloud-Sensor-V2-PreVPN-Working`

---

## Phase 5 — SIEM & Monitoring *(Planned)*

**Goal:** Turn raw attack data into visual threat intelligence.

- Filebeat/Logstash to ingest logs from Pi 5 and AWS
- Elasticsearch for storage and indexing
- Kibana dashboards: attacker origin countries, top targeted ports, brute-force password lists
- Final Matura analysis: compare local DMZ attacks vs global AWS attacks

---

## Tech Stack

![pfSense](https://img.shields.io/badge/pfSense-212121?style=flat&logo=pfsense&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry_Pi-C51A4A?style=flat&logo=raspberry-pi&logoColor=white)
![AWS](https://img.shields.io/badge/AWS_EC2-232F3E?style=flat&logo=amazon-aws&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu_24.04-E95420?style=flat&logo=ubuntu&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
![Elasticsearch](https://img.shields.io/badge/ELK_Stack-005571?style=flat&logo=elasticsearch&logoColor=white)

**Networking:** pfSense · DMZ · NAT · VLANs · iptables · DHCP · DNS  
**Security:** Cowrie · Honeypot · Authbind · SSH hardening · AWS Security Groups  
**Cloud:** AWS EC2 · VPC · EBS Snapshots · IAM  
**Monitoring:** Cowrie logs · ELK Stack (planned) · Kibana (planned)

---

## Author

**Marco Carlino** — LBS Bozen, Graduation 2026  
[linkedin.com/in/carlino-marco](https://linkedin.com/in/carlino-marco) · [carlinomarco4@gmail.com](mailto:carlinomarco4@gmail.com)
