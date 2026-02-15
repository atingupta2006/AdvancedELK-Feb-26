# CLEANUP — Minimal destructive cleanup (LOCAL ONLY)

> WARNING: These commands are destructive and irreversible. They remove Elastic Stack packages, configuration, data, and logs from the local host only. THIS DOES NOT MODIFY THE GIT REPOSITORY OR ANY REMOTE.

Run the following block on the training host as root (or via sudo). It performs a complete, non-interactive cleanup.

```bash
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
```

If you want a safer interactive script that prompts before each destructive step or that first tars backups to `/tmp/elastic-backup-$(date +%s).tar.gz`, tell me and I'll create it.
