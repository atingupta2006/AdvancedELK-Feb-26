# Stop + disable services
sudo systemctl stop filebeat logstash kibana elasticsearch || true
sudo systemctl disable filebeat logstash kibana elasticsearch || true

# Remove packages and clean
sudo dnf remove -y elasticsearch kibana logstash filebeat || true
sudo dnf autoremove -y || true
sudo dnf clean all || true

# Remove configs, data, logs, training files
sudo rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
sudo rm -rf /etc/kibana /var/lib/kibana /var/log/kibana
sudo rm -rf /etc/logstash /var/lib/logstash /var/log/logstash
sudo rm -rf /etc/filebeat /var/lib/filebeat /var/log/filebeat
sudo rm -rf /opt/capstone
sudo rm -f ~/GH/data/raw/access.log ~/GH/data/raw/app.log || true

# Remove repo and GPG keys (force)
sudo rm -f /etc/yum.repos.d/elasticsearch.repo
sudo rpm -q gpg-pubkey* | xargs -r -n1 rpm -e || true

# Revert sysctl change and reload
sudo sed -i '/^vm.max_map_count/d' /etc/sysctl.conf || true
sudo sysctl -p || true

# Re-enable firewall and reload systemd
sudo systemctl enable --now firewalld || true
sudo systemctl daemon-reload || true
sudo systemctl reset-failed || true

# Clean logs and caches
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s || true
sudo rm -rf /var/log/*elastic* /var/log/*kibana* /var/log/*logstash* /var/log/*filebeat* || true
sudo rm -rf /var/cache/dnf || true