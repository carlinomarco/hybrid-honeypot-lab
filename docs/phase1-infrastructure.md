# Phase 1 — Local Infrastructure (pfSense + Admin-PC)

## Overview

Goal: Build the network foundation and security gateway for the hybrid honeypot lab.

---

## 1.1 pfSense Firewall

**Software:** pfSense CE 2.8.1  
**Platform:** Oracle VirtualBox VM

### VM Configuration

| Setting | Value |
|---|---|
| OS Type | BSD / FreeBSD 64-bit |
| RAM | 1024 MB |
| Disk | 16 GB VDI |
| EFI | Disabled (standard BIOS for reliability) |

### Network Adapters

| Adapter | Mode | Interface | Purpose |
|---|---|---|---|
| Adapter 1 | NAT | WAN (em0) | Internet access via VirtualBox |
| Adapter 2 | Internal Network (`intnet`) | LAN (em1) | Admin-PC private network |
| Adapter 3 | Bridged (physical Ethernet) | DMZ (em2) | Raspberry Pi honeypot zone |

### pfSense Setup Wizard Settings

| Field | Value |
|---|---|
| Hostname | pfsense |
| Domain | home.arpa |
| Primary DNS | 8.8.8.8 |
| Secondary DNS | 8.8.4.4 |
| Timezone | Europe/Zurich |
| WAN Type | DHCP |
| LAN IP | 192.168.1.1/24 |
| DHCP Range | 192.168.1.100 – 192.168.1.199 |
| Admin Password | (changed from default) |

> **Important:** Uncheck "Block RFC1918 Private Networks" and "Block Bogon Networks" on the WAN setup page. Because WAN uses NAT, the internet arrives from a private IP range (10.0.x.x) — leaving these checked causes pfSense to block its own internet access.

---

## 1.2 Key Problem: Bridged WAN vs NAT

**Problem:** Initial WAN adapter was set to Bridged mode. pfSense got a red blinking WAN indicator — no internet.

**Cause:** Home routers often reject virtual MAC addresses. The pfSense VM tried to get a DHCP lease directly from the home router (Layer 2), which rejected it silently.

**Solution:** Switch WAN adapter to NAT mode.  
VirtualBox becomes a mini-router between pfSense and the physical network. The home router only ever sees the physical PC — the VM's complexity is hidden behind it. This is a Layer 3 solution, much more stable than Layer 2 bridging for virtual lab environments.

---

## 1.3 DMZ Configuration

The DMZ (Demilitarized Zone) isolates the Raspberry Pi honeypot. Even if the Pi is fully compromised, the attacker cannot reach the Admin-PC or LAN.

### Steps

1. `Interfaces > Assignments` → find `em2` in "Available network ports" → click **Add**
2. Click on the new `OPT1` → enable it → rename to `DMZ`
3. Set IPv4 type to **Static IPv4**
4. IP: `172.16.1.1`, Subnet: `/24`
5. Save → Apply Changes
6. `Services > DHCP Server > DMZ tab` → Enable → Range: `172.16.1.10` – `172.16.1.200`

### Firewall Rules

| Rule | Source | Destination | Action | Reason |
|---|---|---|---|---|
| Allow outbound | DMZ subnets | Any | Pass | Lets Pi download updates, resolve DNS |
| Block lateral | DMZ subnets | LAN subnets | Block | Prevents attacker pivoting from Pi to Admin-PC |

---

## 1.4 Admin-PC (Ubuntu 24.04 LTS)

### VM Configuration

| Setting | Value |
|---|---|
| OS | Ubuntu 24.04 LTS |
| RAM | 6144 MB (upgraded from 2 GB — required for ELK Stack) |
| Disk | 25 GB |
| Network | Internal Network (`intnet`) |
| Received IP | 192.168.1.101 (from pfSense DHCP) |

Access pfSense WebGUI at: `http://192.168.1.1`

### VirtualBox Display Fix (black screen on login)

If Ubuntu shows a black screen after login:
- Settings → Display → Video Memory: **128 MB**
- Settings → Display → **Disable 3D Acceleration**

---

## Network Map

```
Internet
    │
    ▼ (NAT)
pfSense WAN — em0 — 10.0.x.x (VirtualBox gives this)
    │
    ├── LAN — em1 — 192.168.1.1/24
    │       └── Admin-PC: 192.168.1.101
    │
    └── DMZ — em2 — 172.16.1.1/24
            └── Raspberry Pi: 172.16.1.10
```

---

## Milestone Result

✅ pfSense 2.8.1 running with stable WAN (NAT), LAN, and DMZ  
✅ Admin-PC gets IP from pfSense DHCP, can access WebGUI  
✅ DMZ created and isolated from LAN  
✅ pfSense WebGUI accessible at `http://192.168.1.1`
