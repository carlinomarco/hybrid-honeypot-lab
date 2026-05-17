# Phase 2 — IoT Sensor: Raspberry Pi 5 Honeypot

## Overview

Goal: Deploy a physical medium-interaction SSH honeypot inside the pfSense DMZ using a Raspberry Pi 5 and Cowrie.

---

## 2.1 Hardware Preparation

**Device:** Raspberry Pi 5  
**OS:** Raspberry Pi OS 64-bit (Debian-based)  
**Power:** USB-C 27W (official Pi 5 adapter recommended)  
**Network:** Physical Ethernet cable → PC's Ethernet port → pfSense DMZ (Adapter 3, Bridged)

### VirtualBox DMZ Bridging

To connect the physical Pi to the virtual pfSense DMZ:

1. pfSense VM → Settings → Network → Adapter 3
2. Change "Attached to": **Bridged Adapter**
3. Select your **physical Ethernet card**
4. Promiscuous Mode: **Allow All**

> **Why Promiscuous Mode?** Allows pfSense to see all traffic from the Pi, including packets with spoofed MAC addresses used by some attack tools. Essential for a honeypot — you don't want to miss any data.

### Windows NIC Contention Fix

**Problem:** When the Pi connected, the Windows host lost internet.

**Cause:** Both Windows and VirtualBox tried to use the same physical Ethernet chip simultaneously — driver conflict.

**Fix:**
1. Open Windows → Network Connections → Ethernet adapter → Properties
2. Uncheck everything **except** `VirtualBox NDIS6 Bridged Networking Driver`
3. Windows now ignores the port, giving pfSense exclusive control

### Verify Pi is on DMZ

After connecting, check `Status > DHCP Leases` in pfSense WebGUI.  
The Pi should appear with IP `172.16.1.10`.

---

## 2.2 Cowrie Installation

**What is Cowrie?**  
Cowrie is a medium-interaction SSH/Telnet honeypot. It allows attackers to "log in" and interact with a fake shell and filesystem. It logs every command typed, every file uploaded, and every session — without ever exposing the real hardware.

Unlike low-interaction honeypots (which only fake a login prompt), Cowrie lets attackers explore a simulated environment, generating much richer threat data.

### Install Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install git python3-virtualenv libssl-dev libffi-dev \
  build-essential libpython3-dev python3-minimal authbind virtualenv -y
```

### Create Restricted Service User

```bash
# No password, no sudo rights — privilege separation
sudo adduser --disabled-password --gecos "" cowrie
```

> **Why a separate user?** If an attacker somehow escapes the honeypot shell, they land in the `cowrie` account — a low-privilege user with no access to system files or the `pi` user account.

### Clone and Install

```bash
sudo su - cowrie
git clone https://github.com/cowrie/cowrie.git
cd cowrie

# Isolated Python environment — prevents library conflicts
virtualenv --python=python3 cowrie-env
source cowrie-env/bin/activate

pip install -r requirements.txt

# Editable install — required for modern Cowrie to register entry points
pip install -e .
```

---

## 2.3 Configuration

Cowrie uses a `.local` override file. This way your custom settings survive future Cowrie updates.

```bash
# Never edit cowrie.cfg directly — it says "DO NOT EDIT"
touch etc/cowrie.cfg.local
nano etc/cowrie.cfg.local
```

See: [`configs/cowrie/cowrie.cfg.local`](../configs/cowrie/cowrie.cfg.local)

---

## 2.4 Port Redirection — Move Real SSH to Port 2224

Most automated bots only scan port 22. Cowrie defaults to port 2222. To intercept real attacks, Cowrie must sit on port 22 — so the real SSH daemon must move.

```bash
# Move real SSH management to port 2224
sudo nano /etc/ssh/sshd_config
# Change: Port 22 → Port 2224
sudo systemctl restart ssh
```

**Reconnect on new port from Admin-PC:**
```bash
ssh pi@172.16.1.10 -p 2224
```

### Grant Cowrie Permission to Use Port 22 (authbind)

Linux blocks non-root users from binding ports below 1024. `authbind` grants specific port permissions without giving full root access.

```bash
sudo touch /etc/authbind/byport/22
sudo chown cowrie:cowrie /etc/authbind/byport/22
sudo chmod 770 /etc/authbind/byport/22
```

Update `etc/cowrie.cfg.local` to set `listen_port = 22`.

---

## 2.5 Start and Verify

```bash
# Start with authbind flag
AUTHBIND_ENABLED=yes cowrie start

# Verify
cowrie status
# → cowrie is running (PID: 1846)

# Check port
netstat -tuln
# → 0.0.0.0:22  LISTEN  (Cowrie's PID)

# Live log stream
tail -f var/log/cowrie/cowrie.log
```

### Self-Test from Admin-PC

```bash
ssh root@172.16.1.10 -p 22
# → Cowrie presents fake login prompt
# → Admin-PC live log shows: New connection, hassh fingerprint, SSH client version
```

---

## 2.6 Problems & Solutions

### SSH Connection Refused After Reboot

**Symptom:** `ssh pi@172.16.1.10 -p 2224` → "Connection refused" after Pi rebooted.

**Cause:** Cowrie was not configured to auto-start. After reboot, the real SSH daemon reclaimed port 22, and port 2224 wasn't listening.

**Solution:** Connect via port 22 (real SSH, since Cowrie wasn't running), then start Cowrie manually:

```bash
ssh pi@172.16.1.10 -p 22
sudo su - cowrie && cd cowrie
source cowrie-env/bin/activate
AUTHBIND_ENABLED=yes cowrie start
```

**Future fix:** Add Cowrie to systemd for auto-start on boot.

### DNS Resolution Failure (`Temporary failure in name resolution`)

**Symptom:** `sudo apt update` failed on Pi.

**Fix (three steps):**
1. pfSense: `Services > DHCP Server > DMZ` → add DNS `8.8.8.8`
2. pfSense: `Firewall > Rules > DMZ` → add Pass rule allowing DMZ to reach Any
3. Manual override on Pi: `echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf`

---

## Milestone Result

✅ Raspberry Pi 5 deployed in pfSense DMZ (IP: `172.16.1.10`)  
✅ Cowrie running on port 22 via authbind (PID: 1846)  
✅ Real SSH management moved to port 2224  
✅ Live log stream confirmed: SSH fingerprints, attacker IPs, session recording  
✅ Self-test from Admin-PC: Cowrie intercepted connection and logged it
