# Module 00 – Environment Setup

> **Platform**: CentOS Stream 9  
> **Stack**: Elasticsearch 9.x, Kibana 9.x, Logstash 9.x, Filebeat 9.x  
> **Requirements**: User with sudo access
> **Training note**: All students in this environment have sudo access; use `sudo` freely.

---

## Setup

### 1) Install tools

```bash
sudo dnf update -y 
sudo dnf install epel-release -y
sudo dnf install -y curl wget jq htop vim
```

Explanation: update package metadata and install common utilities used during the labs (network tools, JSON parser, system monitor, editor).

### 2) System config

Edit `/etc/sysctl.conf` and ensure this line exists:

```text
vm.max_map_count=262144
```

Explanation: sets the kernel limit for the maximum number of memory map areas a process may have; Elasticsearch/Lucene uses many mmap regions, and 262144 avoids "unable to mmap" errors on larger workloads.

Commands:

```bash
sudo sysctl -w vm.max_map_count=262144
```

```bash
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

```bash
sudo sysctl -p
```

Explanation: `sysctl -p` reloads kernel settings so `vm.max_map_count` takes effect for Elasticsearch.

```bash
sudo systemctl stop firewalld
```

```bash
sudo systemctl disable firewalld
```

Explanation: stopping the firewall removes a common connectivity barrier in the training environment so services can communicate locally.

### 3) Add Elastic repo

```bash
sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
```

Backup + overwrite repo file (do not append):

```bash
sudo cp /etc/yum.repos.d/elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo.bak 2>/dev/null || true
```

```bash
sudo vim /etc/yum.repos.d/elasticsearch.repo
```

Paste exactly:

```ini
[elasticsearch]
name=Elasticsearch repository for 9.x packages
baseurl=https://artifacts.elastic.co/packages/9.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
type=rpm-md
```

Explanation: importing the GPG key and adding the repo ensures `dnf` installs official Elastic packages and verifies their integrity.

### 4) Install Elastic Stack packages

```bash
sudo dnf makecache
sudo dnf install -y elasticsearch kibana logstash filebeat
```

Explanation: installs the core Elastic components used in labs: Elasticsearch (data), Kibana (UI), Logstash (ingest), Filebeat (lightweight shipper).

### 5) Configure Elasticsearch (disable security for training)

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak 2>/dev/null || true
```

```bash
sudo vim /etc/elasticsearch/elasticsearch.yml
```

Replace the file content with:

```yaml
# Paths - Essential for RPM installations
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# Node Identity
cluster.name: elk-training
node.name: node-1

# Network - Use 0.0.0.0 to allow external & local connections
network.host: 0.0.0.0
http.port: 9200

# Single Node Mode
discovery.type: single-node

# Security - The master "off" switch
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

Explanation: `network.host: 0.0.0.0` binds to all interfaces for accessibility in the lab; `single-node` simplifies cluster formation; security is disabled for early labs to remove auth complexity. Explicitly disabling SSL components is required when autoconfiguration has already populated the keystore.

Important: if you see this line in the file, DELETE it (it can block startup in this training setup):

```text
cluster.initial_master_nodes: ...
```

### 6) Configure Kibana

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak 2>/dev/null || true
```

```bash
sudo vim /etc/kibana/kibana.yml
```

Replace the file content with:

```yaml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://127.0.0.1:9200"]
```

Explanation: configuring Kibana to listen on all interfaces and connect to the local Elasticsearch instance.

### 7) Start services

##### Run this before starting the service:
```bash
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch
sudo chmod -R 775 /var/lib/elasticsearch
sudo chmod -R 775 /var/log/elasticsearch
```

```bash
sudo systemctl daemon-reload
```

Explanation: reload systemd to pick up any new or changed unit files.

```bash
sudo systemctl enable elasticsearch kibana
```

Explanation: enable configures services to start automatically on boot.

```bash
sudo systemctl start elasticsearch kibana
```

```bash
# 1. Check if the directories actually exist
ls -ld /var/lib/elasticsearch /var/log/elasticsearch
```

```bash
# 2. Check the end of the log file directly
sudo tail -n 50 /var/log/elasticsearch/elk-training.log
```

```bash
# 3. Check systemd detailed errors
sudo journalctl -u elasticsearch -n 50 --no-pager
```

Explanation: starts Elasticsearch and Kibana so the stack is running for the labs.

```bash
sleep 60
```

Explanation: wait briefly to allow services to finish starting before checking health.

```bash
curl http://127.0.0.1:9200
```

Explanation: a quick health check — Elasticsearch responds with cluster info when running.

```bash
sudo systemctl status elasticsearch --no-pager
```

```bash
sudo systemctl status kibana --no-pager
```

Explanation: view service status and recent logs to confirm successful start.

---

## Editor (editing system files)

Only use `vim` to edit system files in this training. Example:

```bash
sudo vim /etc/elasticsearch/elasticsearch.yml
```

Editor note: use `vim` for system file edits as shown; avoid running graphical editors as root to reduce accidental permission changes.

**Success**: Elasticsearch returns JSON cluster info

Access Kibana: `http://127.0.0.1:5601` (wait 1-2 minutes if not ready)
