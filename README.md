# OTS deployment script (Redis + Nginx)

Deploy **OTS (One-Time Secret)** on a single Debian/Ubuntu host using **systemd**.  
This project installs and configures:

- **Redis** (local-only)
- **OTS** as a **non-root** systemd service
- **Nginx** as a reverse proxy on **port 80**
- **UFW** firewall rules (SSH + HTTP)

It also includes an **optional TLS outline** (commented) to show the production path without requiring a domain/certificate for an assignment.

---

## Contents

- [What this deploys](#what-this-deploys)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration notes](#configuration-notes)
- [What the script changes](#what-the-script-changes)
- [Ports and firewall](#ports-and-firewall)
- [Optional TLS](#optional-tls)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Security notes](#security-notes)
- [License](#license)

---

## What this deploys

### Components

- **Redis**
  - Installed from the upstream Redis APT repository.
  - Configured to bind to `127.0.0.1` and `::1`.
  - Not exposed through the firewall.

- **OTS**
  - Downloaded from a pinned GitHub release.
  - Installed under `/opt/ots`.
  - Runs as a dedicated system user: `ots`.
  - Managed as `ots.service` by systemd.
  - Includes basic systemd hardening options.

- **Nginx**
  - Listens on port `80`.
  - Proxies requests to `http://127.0.0.1:3000` (OTS).
  - Uses `server_name _;` to accept requests by IP or hostname.

- **UFW**
  - Allows `OpenSSH` and `Nginx HTTP`.
  - Keeps Redis private.

---

## Requirements

- Debian/Ubuntu host with **systemd**
- Root access (run via `sudo`)
- Outbound internet access (packages + OTS download)

---

## Quick start

Clone the repo and run the script:

```bash
chmod +x deploy-ots.sh
sudo ./deploy-ots.sh
```

Open in a browser:

```text
http://<server-ip>/
```

---

## Configuration notes

- This is a **single-host** deployment.
- Redis remains local-only by default. If you need Redis reachable from another host, you must:
  - change Redis `bind` settings
  - add authentication and network controls
  - open `6379/tcp` intentionally (not recommended for this assignment)

---

## What the script changes

### Packages installed

- `wget`, `curl`, `vim`
- `gnupg`, `lsb-release`, `ca-certificates`
- `ufw`
- `redis`
- `nginx`

### Files created or updated

- `/etc/apt/sources.list.d/redis.list`
- `/etc/redis/redis.conf`
- `/opt/ots/*`
- `/etc/systemd/system/ots.service`
- `/etc/nginx/conf.d/ots_app.conf`

### Services enabled and restarted

- `redis-server`
- `ots.service`
- `nginx`
- `ufw`

---

## Ports and firewall

UFW allows:

- `22/tcp` (SSH)
- `80/tcp` (HTTP)

Redis remains private:

- `6379/tcp` is **not** opened by the firewall
- Redis binds to loopback (`127.0.0.1`, `::1`)

---

## Optional TLS

TLS is included as an outline in the script but commented.  
In a real deployment, enable HTTPS with:

- a DNS name (for example: `ots.example.com`)
- public DNS pointing to your server
- inbound access for ACME validation (commonly port 80)

Recommended approach using certbot:

```bash
sudo apt-get update -y
sudo apt-get install -y certbot python3-certbot-nginx

DOMAIN="ots.example.com"
EMAIL="you@example.com"

sudo certbot --nginx   -d "${DOMAIN}"   --redirect   --non-interactive   --agree-tos   -m "${EMAIL}"

sudo ufw allow 'Nginx Full'
sudo ufw reload
```

---

## Verification

Check service status:

```bash
systemctl status redis-server --no-pager
systemctl status ots.service --no-pager
systemctl status nginx --no-pager
```

Confirm listeners:

```bash
ss -lntp | egrep ':(80|3000|6379)\b' || true
```

Expected behavior:

- `:80` is open (nginx)
- `:3000` is bound to localhost (ots)
- `:6379` is bound to localhost (redis)

Test HTTP locally:

```bash
curl -I http://127.0.0.1/
```

---

## Troubleshooting

### Nginx fails to start

Validate configuration:

```bash
nginx -t
journalctl -u nginx -xe --no-pager
```

### OTS service fails

Inspect status and logs:

```bash
systemctl --no-pager -l status ots.service
journalctl -u ots.service -xe --no-pager
```

### Redis issues

Confirm bind settings and listening socket:

```bash
grep -E '^\s*bind ' /etc/redis/redis.conf || true
ss -lntp | grep :6379 || true
```

---

## Uninstall

Stop and disable services:

```bash
sudo systemctl disable --now ots.service nginx redis-server ufw
```

Remove created files:

```bash
sudo rm -f /etc/systemd/system/ots.service
sudo rm -f /etc/nginx/conf.d/ots_app.conf
sudo rm -rf /opt/ots
sudo rm -f /etc/apt/sources.list.d/redis.list
sudo systemctl daemon-reload
```

Remove packages (optional):

```bash
sudo apt-get remove -y nginx redis ufw
sudo apt-get autoremove -y
```

Remove the service user (optional):

```bash
sudo userdel ots
```

---

## Security notes

- OTS runs as a dedicated `ots` user and uses systemd hardening options.
- Redis is bound to localhost and not opened in UFW.
- For production, add HTTPS, log retention, monitoring, and backups.

---

## License

Choose a license for your repo (MIT is common for scripts).  
If you do not add a license file, default copyright rules apply.
