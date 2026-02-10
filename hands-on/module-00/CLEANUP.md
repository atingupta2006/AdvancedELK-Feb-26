# Cleanup: Remove Elastic Stack and training artifacts (CentOS Stream 9)

This guide shows how to completely remove the software and configuration created during Module 00 (Environment Setup). These commands are destructive and will permanently remove data and configuration created for the training environment. Run each command on the training host as a user with appropriate privileges.

Order of operations (recommended):
1. Remove data and indices from Elasticsearch (if the cluster is running and you want to delete data).
2. Stop services.
3. Uninstall packages.
4. Remove configuration and data directories (or restore backups where available).
5. Revert system settings (sysctl, firewall).
6. Clean leftover packages and caches.

---

## 1) (Optional) Delete Elasticsearch indices, templates, ILM

If Elasticsearch is still running and you want to remove all cluster data, run (this deletes indices and templates):

```bash
# list indices
curl -s http://localhost:9200/_cat/indices?v

# delete all capstone and training indices (example)
curl -s -X DELETE "http://localhost:9200/capstone-*" | jq
curl -s -X DELETE "http://localhost:9200/*-training-*" | jq

# delete index templates and component templates if present
curl -s -X DELETE "http://localhost:9200/_index_template/capstone-*" | jq || true
curl -s -X DELETE "http://localhost:9200/_component_template/capstone-common" | jq || true
```

Explanation: remove training data from the running cluster before uninstalling; adjust index patterns to your environment.

---

## 2) Stop and disable services

```bash
sudo systemctl stop filebeat || true
sudo systemctl stop logstash || true
sudo systemctl stop kibana || true
sudo systemctl stop elasticsearch || true

sudo systemctl disable filebeat logstash kibana elasticsearch || true
```

Explanation: stop services and disable autostart to avoid processes running while files are deleted.

---

## 3) Uninstall packages

```bash
sudo dnf remove -y elasticsearch kibana logstash filebeat || true

# optionally remove packages installed as dependencies that are no longer needed
sudo dnf autoremove -y || true
```

Explanation: removes Elastic packages and then removes orphaned dependencies.

---

## 4) Remove config, data and log directories

The common locations for Elastic components are removed below. If you previously created backups (e.g., `*.bak`), you can restore them instead of removing them.

```bash
# Elasticsearch
sudo rm -rf /etc/elasticsearch
sudo rm -rf /var/lib/elasticsearch
sudo rm -rf /var/log/elasticsearch

# Kibana
sudo rm -rf /etc/kibana
sudo rm -rf /var/lib/kibana
sudo rm -rf /var/log/kibana

# Logstash
sudo rm -rf /etc/logstash
sudo rm -rf /var/lib/logstash
sudo rm -rf /var/log/logstash

# Filebeat
sudo rm -rf /etc/filebeat
sudo rm -rf /var/lib/filebeat
sudo rm -rf /var/log/filebeat

# Optional training data directories
sudo rm -rf /opt/capstone || true
sudo rm -rf ~/GH/data/raw/access.log ~/GH/data/raw/app.log || true

# Clean Logstash pipelines registry if present
sudo rm -rf /var/lib/logstash/pipeline || true
```

Explanation: removes configs and persistent data produced by each service. If you want to preserve backups, move `*.bak` files to `/tmp` before deleting directories.

---

## 5) Remove Yum repo and GPG key

```bash
sudo rm -f /etc/yum.repos.d/elasticsearch.repo
sudo rpm -q gpg-pubkey* | xargs -r -n1 rpm -e || true
```

Explanation: removes the Elastic yum repo configuration and attempts to remove imported GPG keys (the `rpm -e` step may list multiple keys; inspect before removing in sensitive systems).

---

## 6) Revert system configuration

### Remove `vm.max_map_count` line from `/etc/sysctl.conf` (if you added it)

```bash
sudo sed -i.bak '/^vm.max_map_count\s*=\s*/d' /etc/sysctl.conf || true
sudo sysctl -p || true
```

Explanation: deletes the `vm.max_map_count` setting and reloads kernel settings; a `.bak` copy of the file is kept as `/etc/sysctl.conf.bak`.

### Re-enable and start firewall (if you disabled it for training)

```bash
sudo systemctl enable --now firewalld || true
sudo firewall-cmd --state || true
```

Explanation: restore `firewalld` so the host returns to a default-protected state.

---

## 7) Remove systemd unit cache / reload

```bash
sudo systemctl daemon-reload || true
sudo systemctl reset-failed || true
```

Explanation: ensure systemd has no stale units or failed service records.

---

## 8) Clean package manager caches

```bash
sudo dnf clean all || true
sudo rm -rf /var/cache/dnf || true
```

Explanation: frees disk space by cleaning DNF caches.

---

## 9) Optional: Remove log & journal data

```bash
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s || true
sudo rm -rf /var/log/*elastic* /var/log/*kibana* /var/log/*logstash* /var/log/*filebeat* || true
```

Explanation: cleans systemd journal and logs related to the Elastic stack; use with caution as this removes historical logs.

---

## 10) Verify cleanup

```bash
# ensure no services are active
sudo systemctl status elasticsearch kibana logstash filebeat || true

# ensure no package installed
dnf list installed | egrep 'elasticsearch|kibana|logstash|filebeat' || true

# check directories removed
ls -ld /etc/elasticsearch /var/lib/elasticsearch /etc/kibana /etc/logstash /etc/filebeat || true
```

Explanation: basic checks to confirm removal.

---

## Rollback / restore backups

If you created backups of configuration files before editing (e.g., `elasticsearch.yml.bak`), restore them as needed. Example:

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml.bak /etc/elasticsearch/elasticsearch.yml || true
sudo cp /etc/kibana/kibana.yml.bak /etc/kibana/kibana.yml || true
```

Explanation: restores previously backed-up config files if you plan to reinstall later.

---

## Final notes

- These commands assume the default package and directory layout for CentOS Stream 9.
- Inspect each command before running in production; some steps are irreversible.
- If you want me to produce a non-destructive safety script (create tarball backups of the directories before deletion), I can add that.
