#!/bin/bash

# Multi-Node Elasticsearch Setup — Automated SSH Execution
# Target: VirtualBox VM at 192.168.56.101
# User: osboxes | Pass: osboxes.org

set -e

VM_IP="192.168.56.101"
VM_USER="osboxes"
VM_PASS="osboxes.org"

echo "========================================="
echo "Elasticsearch Multi-Node Setup (VirtualBox)"
echo "Target: $VM_IP"
echo "========================================="
echo ""

# ============== SECTION 0: SYSTEM PRECHECK ==============
echo "[1/5] RUNNING SYSTEM PRECHECK..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
echo "=== Memory Check ==="
free -h

echo ""
echo "=== CPU Count ==="
nproc

echo ""
echo "=== Disk Space ==="
df -h

echo ""
echo "=== Elasticsearch Status ==="
sudo systemctl status elasticsearch || echo "Not running (expected)"
EOF

echo "✓ Precheck complete. Press Enter to continue..."
read

# ============== SECTION 1: STOP SERVICES ==============
echo "[2/5] STOPPING SERVICES..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
echo "Stopping Elasticsearch..."
sudo systemctl stop elasticsearch 2>/dev/null || true

echo "Stopping Kibana..."
sudo systemctl stop kibana 2>/dev/null || true

echo "Killing any leftover Java processes..."
sudo pkill -9 java 2>/dev/null || true

sleep 5
echo "✓ Services stopped"
EOF

echo "✓ Services stopped"
echo ""

# ============== SECTION 2: CLEAN DATA ==============
echo "[3/5] CLEANING DATA + LOGS..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
echo "Clearing Elasticsearch data..."
sudo rm -rf /var/lib/elasticsearch/*

echo "Clearing Elasticsearch logs..."
sudo rm -rf /var/log/elasticsearch/*

echo "Clearing Kibana data..."
sudo rm -rf /var/lib/kibana/* 2>/dev/null || true

echo "Clearing Kibana logs..."
sudo rm -rf /var/log/kibana/* 2>/dev/null || true

echo "Resetting ownership..."
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch
sudo chown -R kibana:kibana /var/lib/kibana 2>/dev/null || true
sudo chown -R kibana:kibana /var/log/kibana 2>/dev/null || true

echo "✓ Cleanup complete"
EOF

echo "✓ Data cleaned"
echo ""

# ============== SECTION 3: CONFIGURE HEAP ==============
echo "[4/5] SETTING JVM HEAP (1GB for VirtualBox)..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
echo "Creating heap override file..."
echo -e "-Xms1g\n-Xmx1g" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null

echo "Verifying heap settings..."
cat /etc/elasticsearch/jvm.options.d/heap.options

echo "✓ Heap configured to 1GB"
EOF

echo "✓ Heap configured"
echo ""

# ============== SECTION 4: CONFIGURE ELASTICSEARCH ==============
echo "[5/5] CONFIGURING ELASTICSEARCH (Single-Node Lab)..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
# Backup original config
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.backup.$(date +%F)

# Write minimal clean config
sudo tee /etc/elasticsearch/elasticsearch.yml > /dev/null <<'ESCONFIG'
# ========================= Elasticsearch Configuration =========================

# Paths
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# Cluster and node identity
cluster.name: elk-lab
node.name: node-1

# Network
network.host: 0.0.0.0
http.port: 9200

# Single-node mode (for testing on one VM)
discovery.type: single-node

# Security disabled for lab
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
ESCONFIG

echo "✓ Config written"
echo ""

echo "Verifying config..."
grep -E 'cluster\.name|node\.name|discovery\.type' /etc/elasticsearch/elasticsearch.yml

echo ""
echo "Config complete!"
EOF

echo "✓ Elasticsearch configured"
echo ""

# ============== SECTION 5: START ELASTICSEARCH ==============
echo "STARTING ELASTICSEARCH..."

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'EOF'
echo "Starting Elasticsearch..."
sudo systemctl start elasticsearch

echo "Waiting 30 seconds for startup..."
sleep 30

echo "Checking status..."
sudo systemctl is-active elasticsearch

echo ""
echo "Testing HTTP API..."
curl -s http://127.0.0.1:9200/_cluster/health?pretty || echo "Still starting, wait a bit more..."

echo "✓ Elasticsearch started"
EOF

echo ""
echo "========================================="
echo "✅ SETUP COMPLETE!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. SSH to VM: ssh osboxes@192.168.56.101"
echo "2. Check status: curl -s http://127.0.0.1:9200/_cluster/health?pretty"
echo "3. View logs: sudo journalctl -u elasticsearch -n 50 --no-pager"
echo ""
