# Module 00 – Environment Setup

> **Platform**: CentOS Stream 9  
> **Stack**: Elasticsearch 9.x, Kibana 9.x, Logstash 9.x, Filebeat 9.x  
> **Requirements**: User with sudo access
> **Training note**: All students in this environment have sudo access; use `sudo` freely.

---

## Setup

```bash
# Install tools
sudo dnf install -y curl wget jq
# (curl/wget for downloads, jq for JSON parsing)

# System config
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p
sudo systemctl stop firewalld
sudo systemctl disable firewalld
# (disable firewall for training network simplicity)

# Add Elastic repo
sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

Edit the repo file with nano (only use nano). Overwrite the file (do not append).

Backup existing file, open nano, replace contents, save:

```bash
sudo cp /etc/yum.repos.d/elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo.bak || true
sudo nano /etc/yum.repos.d/elasticsearch.repo
```

Replace the file contents with the block below and save.

```text
[elasticsearch]
name=Elasticsearch repository for 9.x packages
baseurl=https://artifacts.elastic.co/packages/9.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
type=rpm-md
```

# Install everything
sudo dnf install -y elasticsearch kibana logstash filebeat
# (installs the Elastic Stack packages)

# Configure Elasticsearch

Edit the Elasticsearch config with nano (only use nano). Overwrite the file (do not append).

Backup existing file, open nano, replace contents, save:

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak || true
sudo nano /etc/elasticsearch/elasticsearch.yml
```

Replace the file contents with the block below and save (disables security for training):

```yaml
cluster.name: elk-training
node.name: node-1
network.host: 0.0.0.0
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.enrollment.enabled: false
```

# Configure Kibana

Edit the Kibana config with nano (only use nano). Overwrite the file (do not append).

Backup existing file, open nano, replace contents, save:

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak || true
sudo nano /etc/kibana/kibana.yml
```

Replace the file contents with the block below and save (points Kibana at local ES):

```yaml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
```

# Start services
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch kibana
sudo systemctl start elasticsearch kibana

# Wait for services to start
sleep 60

# Verify Elasticsearch
curl http://localhost:9200

# Check service status
sudo systemctl status elasticsearch --no-pager
sudo systemctl status kibana --no-pager
```

---

## Editor (editing system files)

Only use `nano` to edit system files in this training. Example:

```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```

Do not use `vim` or run the VS Code GUI as root.

**Success**: Elasticsearch returns JSON cluster info

Access Kibana: `http://localhost:5601` (wait 1-2 minutes if not ready)
