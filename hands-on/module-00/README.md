# Module 00 – Environment Setup

> **Platform**: CentOS Stream 9  
> **Stack**: Elasticsearch 9.x, Kibana 9.x, Logstash 9.x, Filebeat 9.x  
> **Requirements**: User with sudo access

---

## Setup

```bash
# Install tools
sudo dnf install -y curl wget jq

# System config
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p
sudo systemctl stop firewalld
sudo systemctl disable firewalld

# Add Elastic repo
sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
cat <<EOF | sudo tee /etc/yum.repos.d/elasticsearch.repo
[elasticsearch]
name=Elasticsearch repository for 9.x packages
baseurl=https://artifacts.elastic.co/packages/9.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
type=rpm-md
EOF

# Install everything
sudo dnf install -y elasticsearch kibana logstash filebeat

# Configure Elasticsearch
cat <<EOF | sudo tee /etc/elasticsearch/elasticsearch.yml
cluster.name: elk-training
node.name: node-1
network.host: 0.0.0.0
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
EOF

# Configure Kibana
cat <<EOF | sudo tee /etc/kibana/kibana.yml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
EOF

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

**Success**: Elasticsearch returns JSON cluster info

Access Kibana: `http://localhost:5601` (wait 1-2 minutes if not ready)
