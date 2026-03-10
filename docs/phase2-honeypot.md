# Phase 2 — Raspberry Pi 5 Honeypot (IoT Sensor)

**Status:** ✅ Complete  
**Duration:** ~8 hours  

---

## Goal

Deploy a physical medium-interaction SSH honeypot inside the pfSense DMZ. The Raspberry Pi runs Cowrie — software that emulates a vulnerable server, lets attackers "log in", and silently records everything they do.

---

## Hardware

| Component | Details |
|-----------|---------|
| Device | Raspberry Pi 5 |
| Power | USB-C 27W (official adapter — required) |
| Network | Ethernet → physical port → pfSense DMZ (em2) |
| OS | Raspberry Pi OS 64-bit |
| Assigned IP | 172.16.1.10 (DHCP from pfSense DMZ) |

---

## What is Cowrie?

Cowrie is a **medium-interaction honeypot** — the industry standard for SSH/Telnet traps.

| Feature | Description |
|---------|-------------|
| Interaction level | Medium — attackers can log in and use a fake shell |
| What it logs | Every command, every file upload, full session replay |
| What it prevents | Attackers never reach real hardware |
| Why weak crypto | Intentionally uses legacy algorithms so old attack tools can connect |

---

## Step-by-Step Setup

### 1. Flash Raspberry Pi OS

- Use **Raspberry Pi Imager**
- OS: Raspberry Pi OS (64-bit)
- Advanced Settings:
  - Enable SSH: ✅
  - Allow Password Authentication: ✅ *(critical — without this SSH refuses all connections)*
  - Hostname: `honeypot-pi`
  - Username: `pi`

### 2. Physical Connection

```
Raspberry Pi 5 (Ethernet) ──→ PC physical Ethernet port
                                       ↓
                           pfSense Adapter 3 (DMZ)
                           [Bridged, Promiscuous: Allow All]
```

Verify in pfSense: **Status > DHCP Leases** → should show `raspberrypi` at `172.16.1.10`

### 3. DNS Fix

```bash
# On the Raspberry Pi — fixes "Temporary failure in name resolution"
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Also add in pfSense:
# Services > DHCP Server > DMZ > DNS Servers: 8.8.8.8
# Firewall > Rules > DMZ > Add: Pass DMZ subnet to Any
```

### 4. NIC Contention Fix (Windows Host)

If Windows loses internet when SSH-ing to the Pi:

1. Open **Windows Ethernet Properties** (ncpa.cpl)
2. Find the physical Ethernet adapter
3. Uncheck **all protocols** except `VirtualBox NDIS6 Bridged Networking Driver`
4. Click OK

This gives pfSense exclusive control of the port — Windows ignores it completely.

### 5. Install Cowrie Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install git python3-virtualenv libssl-dev libffi-dev \
  build-essential libpython3-dev python3-minimal authbind virtualenv -y
```

### 6. Create Cowrie User

```bash
# Never run Cowrie as root or pi — privilege separation is critical
sudo adduser --disabled-password --gecos "" cowrie
sudo su - cowrie
```

### 7. Install Cowrie

```bash
git clone https://github.com/cowrie/cowrie.git
cd cowrie
virtualenv --python=python3 cowrie-env
source cowrie-env/bin/activate
pip install -r requirements.txt
pip install -e .   # Required for modern Cowrie — links source to system commands
```

### 8. Configure the Honeypot

```bash
# Never edit cowrie.cfg directly — use the local override file
touch etc/cowrie.cfg.local
nano etc/cowrie.cfg.local
```

See [configs/cowrie-pi.cfg.local](../configs/cowrie-pi.cfg.local) for the full configuration.

### 9. Port Management

Real SSH must vacate port 22 before Cowrie can use it:

```bash
# Move real SSH to port 2224
sudo nano /etc/ssh/sshd_config
# Change: Port 22 → Port 2224
sudo systemctl restart ssh

# Reconnect with: ssh pi@172.16.1.10 -p 2224
```

```bash
# Grant Cowrie permission to bind port 22 without root
sudo touch /etc/authbind/byport/22
sudo chown cowrie:cowrie /etc/authbind/byport/22
sudo chmod 770 /etc/authbind/byport/22
```

### 10. Start & Verify

```bash
AUTHBIND_ENABLED=yes cowrie start
cowrie status           # → cowrie is running (PID: 2032)
netstat -tuln           # → 0.0.0.0:22 LISTEN confirmed
tail -f var/log/cowrie/cowrie.log
```

---

## Verification

Self-test from Admin-PC:

```bash
ssh root@172.16.1.10   # standard port, no key — simulates a real attacker
```

**Expected results:**
- Password prompt appears (Cowrie fake shell)
- Log shows: new connection, SSH version, encryption algorithm, hassh fingerprint
- Any password accepted → fake interactive shell presented

---

## Shutdown Sequence

```bash
# Always shut down in this order to preserve log integrity
cowrie stop
deactivate
exit                    # return to pi user
sudo shutdown now
```

---

## Key Learnings

- `pip install -e .` is required — modern Cowrie needs editable install to create the binary
- `cowrie.cfg.local` overrides `cowrie.cfg` — never edit the base file
- Promiscuous Mode on Adapter 3 is essential — captures all traffic including spoofed packets
- TripleDES deprecation warnings are intentional — Cowrie uses weak crypto to attract old attack tools
