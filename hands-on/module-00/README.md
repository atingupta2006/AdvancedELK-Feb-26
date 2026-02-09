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
sudo dnf install -y curl wget jq ctop vim
```

### 2) System config

Edit `/etc/sysctl.conf` and ensure this line exists:

```text
vm.max_map_count=262144
```

Commands:

```bash
sudo vim /etc/sysctl.conf
```

```bash
sudo sysctl -p
```

```bash
sudo systemctl stop firewalld
```

```bash
sudo systemctl disable firewalld
```

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

### 4) Install Elastic Stack packages

```bash
sudo dnf install -y elasticsearch kibana logstash filebeat
```

### 5) Configure Elasticsearch (disable security for training)

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak 2>/dev/null || true
```

```bash
sudo vim /etc/elasticsearch/elasticsearch.yml
```

Replace the file content with:

```yaml
cluster.name: elk-training
node.name: node-1
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
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
elasticsearch.hosts: ["http://localhost:9200"]
```

### 7) Start services

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable elasticsearch kibana
```

```bash
sudo systemctl start elasticsearch kibana
```

```bash
sleep 60
```

```bash
curl http://localhost:9200
```

```bash
sudo systemctl status elasticsearch --no-pager
```

```bash
sudo systemctl status kibana --no-pager
```

---

## Editor (editing system files)

Only use `vim` to edit system files in this training. Example:

```bash
sudo vim /etc/elasticsearch/elasticsearch.yml
```

Do not use `vim` or run the VS Code GUI as root.

**Success**: Elasticsearch returns JSON cluster info

Access Kibana: `http://localhost:5601` (wait 1-2 minutes if not ready)
