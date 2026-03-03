# How to Enable and Test X-Pack Security

**Target stack**: Elasticsearch 9.x | Kibana 9.x  
**Environment**: CentOS Stream 9; single machine; private internal network; firewall not enabled (as in Module 00).

This guide gives step-by-step instructions to enable and verify X-Pack security in the training environment. In this course, security is **explained and enabled in Module 06, Lab 7** ([labs-05-08-scale-security.md](../hands-on/module-06/labs-05-08-scale-security.md)). Use this document as a single reference or to enable security earlier (e.g. before Lab 8).

---

## 1. When You Need It

**X-Pack security** provides authentication, role-based access control (RBAC), TLS for transport/HTTP, and audit logging. The following **require security to be enabled**:

| What | Why |
|------|-----|
| **Module 06, Labs 8–14** | Logstash multi-pipeline (authenticated output), Fleet, ES\|QL, observability, troubleshooting |
| **Module 07 (Capstone)** | Full platform with RBAC, alerting, and security controls |
| **Fleet and Elastic Agent** | Enrollment and agent policies require security |
| **RBAC and audit logging** | Creating roles, users, and reviewing audit logs |

Labs 1–6 in Module 06 (and all earlier modules) run with **security disabled**. Turn security on when you reach Lab 7 or before starting Lab 8.

---

## 2. Prerequisites

Before you start, confirm:

- [ ] **Module 00** setup is done: Elasticsearch and Kibana are installed and running.
- [ ] Security is **disabled** (default after Module 00).
- [ ] You have **sudo** access and use **Linux bash**.
- [ ] Config paths are the default ones: `/etc/elasticsearch/elasticsearch.yml`, `/etc/kibana/kibana.yml`. (CentOS Stream 9 RPM install as in Module 00; adjust only if you use archive installs.)

**Quick check** — Elasticsearch responds without authentication:

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9200
```

**Expected**: `200`. If you get `401`, security is already enabled; you can skip to [section 6](#6-validate-and-log-in-to-kibana) to verify login.

---

## 3. Enable Security in Elasticsearch

### 3.1 Backup and update config

Use in-place edits so you do **not** duplicate YAML keys (duplicate keys can break the config).

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
```

```bash
sudo sed -i 's/xpack.security.enabled: false/xpack.security.enabled: true/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/xpack.security.enrollment.enabled: false/xpack.security.enrollment.enabled: true/' /etc/elasticsearch/elasticsearch.yml
```

- `xpack.security.enabled: true` — turns on authentication and authorization.
- For **single-node training only**, transport SSL can stay off (Module 00 sets `xpack.security.transport.ssl.enabled: false`). **Production must use TLS.**

### 3.2 Validate config

Confirm the settings were applied:

```bash
grep -E 'xpack\.security\.(enabled|enrollment\.enabled)' /etc/elasticsearch/elasticsearch.yml
```

**Expected output** (order may vary):

```text
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
```

If you still see `false`, fix the file manually (e.g. `sudo vim /etc/elasticsearch/elasticsearch.yml`) and run the `grep` again.

---

## 4. Restart Elasticsearch and Set Passwords

### 4.1 Restart Elasticsearch

```bash
sudo systemctl restart elasticsearch
```

Wait for Elasticsearch to become ready (usually 15–30 seconds).

### 4.2 Validate Elasticsearch is running

```bash
sudo systemctl is-active elasticsearch
```

**Expected**: `active`.

```bash
sudo systemctl status elasticsearch
```

**Expected**: "active (running)" with no error lines. If there are errors, see [section 8 (Troubleshooting)](#8-troubleshooting).

### 4.3 Set password for the `elastic` user

The `elastic` user is the superuser; you will use it to log into Kibana.

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

When prompted, enter a password (e.g. `Training123!`). **Write it down** — you will need it for Kibana and for API calls.  
*(Path is for RPM install; on archive installs the script is in `$ES_HOME/bin/`.)*

### 4.4 Validate Elasticsearch security (optional)

Check that the cluster responds and now requires authentication:

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9200
```

**Expected**: `401` (Unauthorized). Then with credentials (replace `YOUR_PASSWORD`):

```bash
curl -s -u elastic:YOUR_PASSWORD http://127.0.0.1:9200/_cluster/health?pretty
```

**Expected**: JSON with `"status" : "green"` (or `"yellow"` on a single-node cluster). If you get `401`, the password is wrong; run step 4.3 again.

---

## 5. Configure Kibana to Use Credentials

Kibana must connect to Elasticsearch as the `kibana_system` user. You will add the username to `kibana.yml` and store the password in the Kibana keystore.

### 5.1 Backup and update Kibana config

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak
```

```bash
sudo sed -i '$ a\\' /etc/kibana/kibana.yml
sudo sed -i '$ a\elasticsearch.username: "kibana_system"' /etc/kibana/kibana.yml
```

### 5.2 Validate Kibana config

```bash
grep elasticsearch.username /etc/kibana/kibana.yml
```

**Expected**: `elasticsearch.username: "kibana_system"`.

### 5.3 Set password for `kibana_system`

Run this while Elasticsearch is running (after step 4).

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

Enter a password (e.g. `Kibana123!`). Record it if you need to reuse it later.

### 5.4 Store the password in the Kibana keystore

```bash
sudo /usr/share/kibana/bin/kibana-keystore add elasticsearch.password
```

When prompted, enter the **same** `kibana_system` password you set in step 5.3. If the key already exists, choose **Overwrite**.  
*(Path is for RPM install; on archive installs the script is in `$KIBANA_HOME/bin/`.)*

### 5.5 Restart Kibana

```bash
sudo systemctl restart kibana
```

Wait for Kibana to start (often 30–60 seconds).

### 5.6 Validate Kibana is running

```bash
sudo systemctl is-active kibana
```

**Expected**: `active`.

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5601/api/status
```

**Expected**: `200`. If you get `503`, wait a bit and try again; Kibana may still be starting.

---

## 6. Validate and Log In to Kibana

### 6.1 Open Kibana in the browser

- URL: **http://127.0.0.1:5601**
- You should see the **login page** (username and password fields).

### 6.2 Log in

- **Username**: `elastic`
- **Password**: the password you set in step 4.3

**Expected**: You reach the Kibana home or dashboard list. No error message.

### 6.3 Quick validation checklist

| Check | How to verify |
|-------|----------------|
| Elasticsearch security on | `curl -s http://127.0.0.1:9200` returns `401` |
| Cluster healthy | `curl -s -u elastic:PASSWORD http://127.0.0.1:9200/_cluster/health?pretty` shows `green` or `yellow` |
| Kibana login works | You can log in at http://127.0.0.1:5601 as `elastic` |
| Stack Management available | In Kibana: **Menu (☰) → Management → Stack Management** loads without error |

If all four pass, security is enabled and working. You can continue with **Module 06, Lab 7** steps 5–9 (roles, users, RBAC, audit) in [labs-05-08-scale-security.md](../hands-on/module-06/labs-05-08-scale-security.md).

---

## 7. How to Test RBAC (Optional)

To confirm roles and users work:

1. In Kibana: **Menu (☰) → Management → Stack Management → Security → Roles** → Create a role (e.g. read-only on `web-logs-*`).
2. **Security → Users** → Create a user and assign that role.
3. Open a **private/incognito** browser window, go to http://127.0.0.1:5601, and log in as the new user.
4. Confirm they only see what the role allows (e.g. Discover with `web-logs-*` only).

For the **full RBAC and audit flow** (custom roles, test users, audit logging), follow **Module 06, Lab 7**, steps 5–9 in [labs-05-08-scale-security.md](../hands-on/module-06/labs-05-08-scale-security.md).

---

## 8. Troubleshooting

### Elasticsearch does not start after enabling security

- **Check logs**: `sudo journalctl -u elasticsearch -n 50 --no-pager`
- **Typical causes**:
  - Duplicate YAML keys in `elasticsearch.yml` (e.g. two `xpack.security.enabled`). Fix by editing the file and leaving only one of each key.
  - Syntax error (indentation, colons). Compare with the backup: `diff /etc/elasticsearch/elasticsearch.yml.bak /etc/elasticsearch/elasticsearch.yml`
- **Recover**: Restore backup and re-apply only the two `sed` commands from section 3.1:  
  `sudo cp /etc/elasticsearch/elasticsearch.yml.bak /etc/elasticsearch/elasticsearch.yml` then run the two `sed` lines again.

### Kibana shows "Kibana server is not ready" or red status

- **Cause**: Kibana cannot authenticate to Elasticsearch (wrong `kibana_system` password or keystore not set).
- **Fix**:
  1. Reset `kibana_system` password again:  
     `sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i`
  2. Update the keystore:  
     `sudo /usr/share/kibana/bin/kibana-keystore add elasticsearch.password`  
     (choose "Overwrite" if asked.)
  3. Restart Kibana: `sudo systemctl restart kibana`
- **Check Kibana logs**: `sudo journalctl -u kibana -n 30 --no-pager` for "Unable to retrieve version" or "authentication" errors.

### Login to Kibana returns "Invalid username or password"

- You are using the **elastic** user password (set in step 4.3), not the `kibana_system` password.
- If you forgot the `elastic` password, reset it:  
  `sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i`  
  Then log in to Kibana with the new password.

### curl returns 401 but I did not enable security

- Security is already enabled (e.g. by a previous run of this guide or Lab 7). Use `elastic` and its password for API calls:  
  `curl -s -u elastic:YOUR_PASSWORD http://127.0.0.1:9200/_cluster/health?pretty`

### sed did not change the config (grep still shows false)

- Your `elasticsearch.yml` might use different spacing or comments. Edit manually:  
  `sudo vim /etc/elasticsearch/elasticsearch.yml`  
  Set `xpack.security.enabled: true` and `xpack.security.enrollment.enabled: true`, then save and restart Elasticsearch.

---

## 9. Rules and Guidelines

- **Training default**: Security is **off** for Modules 00–06 Labs 1–6. It is turned **on** in Module 06, Lab 7 (or earlier using this doc).
- **Single-node training**: Leaving `xpack.security.transport.ssl.enabled: false` is acceptable. **Production must enable TLS** for transport and, if used, HTTP.
- **No duplicate YAML keys**: Use the in-place `sed` commands (or careful manual edit). Do not append security settings at the end of the file if the keys already exist.

---

## 10. Cross-Links

- **Module 06, Lab 7** — Full enable + RBAC + audit: [labs-05-08-scale-security.md](../hands-on/module-06/labs-05-08-scale-security.md)
- **Module 07** and **Lab 8** — Require security; complete Lab 7 or this guide first.
