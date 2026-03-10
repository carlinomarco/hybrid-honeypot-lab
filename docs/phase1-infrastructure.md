# Phase 1 — Local Infrastructure (pfSense)

**Status:** ✅ Complete  
**Duration:** ~6 hours  

---

## Goal

Establish the core network and security gateway. Build a fully isolated lab environment with pfSense controlling all traffic between the internet, the admin workstation, and the honeypot DMZ zone.

---

## Hardware & Software

| Component | Details |
|-----------|---------|
| Hypervisor | Oracle VirtualBox |
| Firewall OS | pfSense CE 2.8.1 (FreeBSD 64-bit) |
| Admin OS | Ubuntu 24.04 LTS |
| Host Machine | Windows PC (Intel i9-10850K) |

---

## Network Interface Layout

| Adapter | VirtualBox Mode | pfSense Interface | Subnet | Purpose |
|---------|----------------|-------------------|--------|---------|
| Adapter 1 | NAT | WAN (em0) | DHCP from VBox | Internet access |
| Adapter 2 | Internal Network (intnet) | LAN (em1) | 192.168.1.0/24 | Admin-PC network |
| Adapter 3 | Bridged (Physical Ethernet) | DMZ (em2) | 172.16.1.0/24 | Honeypot zone |

---

## Step-by-Step Setup

### 1. pfSense VM Creation (VirtualBox)

- Name: `pfSense-Firewall`
- Type: BSD / FreeBSD (64-bit)
- RAM: 1024 MB
- Disk: 16 GB VDI
- EFI: **disabled** (standard BIOS boot)
- Filesystem: ZFS (Stripe, no redundancy)

### 2. WAN Interface (em0)

- Mode: NAT
- IP: DHCP from VirtualBox (receives 10.0.2.x)
- **Critical:** Uncheck "Block RFC1918 Private Networks" and "Block Bogon Networks" in the Setup Wizard — required because NAT delivers a private IP range

### 3. LAN Interface (em1)

- Mode: Internal Network (`intnet`)
- Static IP: `192.168.1.254/24`
- DHCP Server: enabled, range `192.168.1.100–199`

### 4. DMZ Interface (em2)

- Mode: Bridged Adapter (physical Ethernet port)
- Promiscuous Mode: **Allow All**
- Static IP: `172.16.1.1/24`
- DHCP Server: enabled, range `172.16.1.10–200`
- Added via: Interfaces > Assignments > Add (em2) > renamed to DMZ

### 5. Admin-PC VM (Ubuntu 24.04)

- RAM: 2 GB, Disk: 25 GB
- Network: Internal Network (`intnet`) — same as pfSense LAN
- Receives IP `192.168.1.101` automatically from pfSense DHCP
- Verification: browser → `http://192.168.1.254` → pfSense WebGUI

---

## Key Problem & Solution

### Problem: Bridged WAN — Layer 2 MAC Rejection

Initially the WAN adapter was set to **Bridged Networking**. pfSense tried to act as a physical device on the home network, requesting an IP directly from the home router. The home router rejected the virtual MAC address — pfSense had no internet access.

**Symptom:** Admin-PC had internal IP (192.168.1.101) but browser timed out loading the WebGUI — pfSense could not reach the outside world.

### Solution: Switch WAN to NAT

NAT mode makes VirtualBox act as a mini-router between the physical PC and pfSense. The home router only sees the Windows host — it has no idea pfSense exists. This is a Layer 3 solution vs the Layer 2 Bridged approach.

**Result:** pfSense WebGUI accessible at `http://192.168.1.254`, internet working correctly.

---

## pfSense Setup Wizard Settings

| Setting | Value | Reason |
|---------|-------|--------|
| Hostname | pfSense | Internal firewall name |
| Domain | home.arpa | Default local domain |
| Primary DNS | 8.8.8.8 | Google DNS |
| Secondary DNS | 8.8.4.4 | Google DNS fallback |
| Timezone | Europe/Rome | Accurate log timestamps |
| Block RFC1918 | **Unchecked** | Required for NAT mode |
| Block Bogon | **Unchecked** | Required for NAT mode |
| Admin Password | (changed) | Replaced default 'pfsense' |

---

## Verification Checklist

- [x] pfSense boots from hard disk (not ISO)
- [x] WebGUI accessible at `http://192.168.1.254`
- [x] Admin-PC receives IP in range 192.168.1.100–199
- [x] Admin-PC can browse the internet through pfSense
- [x] DMZ interface active at 172.16.1.1
- [x] DHCP Leases show both Admin-PC and Raspberry Pi
