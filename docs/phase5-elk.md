# Phase 5 — SIEM & Log Analysis (ELK Stack)

## Overview

Goal: Centralize attack data from both sensors (Raspberry Pi + AWS) into a single Elasticsearch database and visualize it in Kibana.

**Stack:** Elasticsearch 8.x · Logstash 8.x · Kibana 8.x · Filebeat 8.x  
**Data flow:**
```
Pi Cowrie  → Filebeat → Logstash (192.168.1.101:5044) → Elasticsearch → Kibana
AWS Cowrie → Filebeat → WireGuard VPN → Logstash → Elasticsearch → Kibana
```

---

## 5.1 Install ELK Stack on Admin-PC

### Add Elastic Repository

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

### Install All Three Components

```bash
sudo apt install elasticsearch kibana logstash -y
```

### Enable and Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now elasticsearch
sudo systemctl enable --now kibana
sudo systemctl enable --now logstash
```

> **RAM Warning:** ELK Stack requires significant memory. Elasticsearch alone needs ~1 GB. The Admin-PC VM was upgraded from 2 GB to **6 GB RAM** after the VM froze during initial startup. See Problem 5.1 below.

---

## 5.2 Elasticsearch Credentials

```bash
# Reset the elastic superuser password
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
# Save the generated password somewhere secure
```

**Verify Elasticsearch is running:**
```bash
curl -k -u elastic:<PASSWORD> https://localhost:9200
# Should return cluster info JSON
```

---

## 5.3 Kibana Setup

**Generate enrollment token:**
```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

**Get verification code:**
```bash
sudo /usr/share/kibana/bin/kibana-verification-code
```

Open browser on Admin-PC → `http://localhost:5601`  
Enter enrollment token → enter 6-digit verification code → login with `elastic` / `<PASSWORD>`

---

## 5.4 Logstash Pipeline

See: [`configs/logstash/cowrie.conf`](../configs/logstash/cowrie.conf)

```bash
# Deploy config
sudo cp configs/logstash/cowrie.conf /etc/logstash/conf.d/cowrie.conf

# Restart Logstash
sudo systemctl restart logstash
sudo systemctl is-active logstash
```

> **Note:** Remove any GeoIP filter blocks if Logstash gets stuck — see Problem 5.2.

---

## 5.5 Kibana Data View

`Stack Management > Data Views > Create data view`

| Field | Value |
|---|---|
| Name | cowrie |
| Index pattern | cowrie-* |
| Timestamp field | @timestamp |

---

## 5.6 Filebeat on Raspberry Pi

```bash
# Install Elastic repo on Pi (same GPG key setup as above)
sudo apt install filebeat -y

# Deploy config
sudo cp configs/filebeat/filebeat-pi.yml /etc/filebeat/filebeat.yml

sudo systemctl enable --now filebeat

# Verify connection
sudo journalctl -u filebeat -n 20 --no-pager
# Look for: "Connection to 192.168.1.101:5044 established"
# Look for: "events acked: N"
```

---

## 5.7 Filebeat on AWS

```bash
# Install Elastic repo on AWS (same GPG key setup as above)
sudo apt install filebeat -y

# Clear default config and deploy ours
sudo truncate -s 0 /etc/filebeat/filebeat.yml
sudo cp configs/filebeat/filebeat-aws.yml /etc/filebeat/filebeat.yml

sudo systemctl enable --now filebeat

# Verify connection (routes through WireGuard VPN to 192.168.1.101)
sudo journalctl -u filebeat -n 10 --no-pager
# Look for: "Connection to 192.168.1.101:5044 established"
```

---

## 5.8 Verify Full Pipeline

**Count events in Elasticsearch:**
```bash
curl -k -u elastic:<PASSWORD> https://localhost:9200/cowrie-*/_count
```

**Final result:**
```json
{"count": 15, "_shards": {"total": 1, "successful": 1}}
```

- 8 events from Raspberry Pi (`sensor: raspberry-pi`)
- 7 events from AWS (`sensor: aws-cloud-sensor`)

Both sensors confirmed delivering data through the full pipeline. ✅

**In Kibana Discover:**
1. Switch data view to `cowrie`
2. Set time range to "Last 1 year" (events may not be in the last 15 minutes)
3. Filter by `sensor: raspberry-pi` vs `sensor: aws-cloud-sensor` to compare sources

---

## 5.9 Problems & Solutions

### Problem 5.1 — Admin-PC Froze During ELK Install

**Symptom:** Ubuntu VM became completely unresponsive after starting all three ELK services.

**Cause:** VM had only 2 GB RAM. Elasticsearch JVM heap alone requires ~1 GB, and the combined memory usage of Elasticsearch + Kibana + Logstash exceeded available RAM.

**Solution:**
1. Power off VM via VirtualBox Machine menu
2. Settings → System → Motherboard → Base Memory: **6144 MB**
3. Restart VM → all three services started stably with ~948 MB free

### Problem 5.2 — Logstash Stuck in "Deactivating" State

**Symptom:** After adding a GeoIP filter, Logstash entered permanent "deactivating" — never stopped, never started. `sudo systemctl kill logstash` didn't work, Java process stayed in memory.

**Cause:** The GeoIP database download was blocked by network/permission issues. The GeoIP worker thread hung indefinitely, blocking Logstash shutdown.

**Solution:**
```bash
# Remove GeoIP filter from cowrie.conf
# Force-kill stuck Java process
sudo pkill -9 -f logstash
sudo systemctl start logstash
```

GeoIP enrichment can be re-added once basic pipeline is verified stable.

### Problem 5.3 — AWS Filebeat i/o timeout (already documented in Phase 4)

See Phase 4 problem section — solved by adding pfSense firewall rules to allow WireGuard subnet to reach LAN.

---

## 5.10 Final Snapshot

```bash
# VirtualBox
# Right-click Admin-PC → Take Snapshot → Name: PHASE_5_ELK_RUNNING

# AWS
# EC2 → Elastic Block Store → Volumes → Select 8 GiB → Actions → Create snapshot
# Name: Cloud-Sensor-V2-Phase5-Complete
```

---

## Milestone Result

✅ ELK Stack (Elasticsearch + Kibana + Logstash) running on Admin-PC  
✅ Kibana accessible at `http://localhost:5601`  
✅ Logstash pipeline receiving Filebeat data on port 5044  
✅ Filebeat running on Raspberry Pi → 8 events delivered  
✅ Filebeat running on AWS → 7 events delivered via WireGuard VPN  
✅ Total: 15 events confirmed in Elasticsearch  
✅ `cowrie-*` Data View created in Kibana  
✅ Both sensors tagged and filterable by `sensor` field  
✅ Full hybrid pipeline operational: Pi + AWS → Logstash → Elasticsearch → Kibana
