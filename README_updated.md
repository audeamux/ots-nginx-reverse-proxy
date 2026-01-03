# OTS deployment script (Redis + Nginx + HTTPS)

Deploy **OTS (One-Time Secret)** on a single Debian/Ubuntu host using **systemd**.

This project installs and configures:

- **Redis** (local-only)
- **OTS** as a **non-root** systemd service
- **Nginx** as a reverse proxy with **self-signed HTTPS** (port **443**)
- **HTTP → HTTPS** redirect (port **80**)
- **UFW** firewall rules (SSH + HTTP + HTTPS)

It also includes an **optional Let’s Encrypt outline** (commented) to show the production path.

---

## What is OTS?

This repo deploys **Luzifer’s OTS** project. citeturn0search0turn0search1

OTS is a **one-time secret sharing** app. You paste a secret, share a generated link, and the recipient can view it **once**. In Luzifer/ots:

- The secret is encrypted in the browser using **AES-256** before upload. citeturn0search0
- The generated URL contains the secret ID and the password/key; the password is **never sent** to the server. citeturn0search0
- The secret is deleted on the **first read**. citeturn0search0

Typical use: share passwords, API tokens, or recovery codes without leaving the plaintext secret in chat/email history.

---

## Requirements

- Debian/Ubuntu host with **systemd**
- Root access (run via `sudo`)
- Outbound internet access (packages + OTS download)

---

## Quick start

Clone the repo and run:

```bash
chmod +x deploy-ots.sh
sudo ./deploy-ots.sh
```

Open in a browser:

```text
https://<server-ip>/
```

Notes:

- The script uses a **self-signed certificate**, so your browser will warn. This is expected for local testing.
- Nginx proxies requests to OTS on `http://127.0.0.1:3000`.

---

## What this deploys

### Redis

- Installed from the upstream Redis APT repository.
- Configured to bind to `127.0.0.1` and `::1` (not exposed to the network).
- Not opened through the firewall.

### OTS

- Downloaded from a pinned GitHub release.
- Installed under `/opt/ots`.
- Runs as a dedicated system user: `ots`.
- Managed as `ots.service` by systemd.
- Includes basic systemd hardening options.

### Nginx

- Listens on:
  - `80/tcp` (redirects to HTTPS)
  - `443/tcp` (serves HTTPS)
- Proxies to `http://127.0.0.1:3000` (OTS).
- Uses `server_name _;` so it works by IP or hostname.
- Generates a self-signed certificate in:
  - `/etc/nginx/certs/ots.crt`
  - `/etc/nginx/certs/ots.key`

### UFW

- Allows:
  - `22/tcp` (SSH)
  - `80/tcp` (HTTP redirect)
  - `443/tcp` (HTTPS)

---

## Files and services

### Packages installed

- `wget`, `curl`, `vim`
- `gnupg`, `lsb-release`, `ca-certificates`
- `ufw`, `nginx`, `redis`

### Files created or updated

- `/etc/apt/sources.list.d/redis.list`
- `/etc/redis/redis.conf`
- `/opt/ots/*`
- `/etc/systemd/system/ots.service`
- `/etc/nginx/conf.d/ots_app.conf`
- `/etc/nginx/certs/ots.crt`
- `/etc/nginx/certs/ots.key`

### Services enabled and restarted

- `redis-server`
- `ots.service`
- `nginx`
- `ufw`

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
ss -lntp | egrep ':(80|443|3000|6379)\b' || true
```

Expected behavior:

- `:80` is open (nginx redirect)
- `:443` is open (nginx HTTPS)
- `:3000` is bound to localhost (ots)
- `:6379` is bound to localhost (redis)

Test from the server:

```bash
curl -kI https://127.0.0.1/ | head -n1
curl -I  http://127.0.0.1:3000/ | head -n1
```

---

## Optional TLS (Let’s Encrypt / certbot)

The script includes a commented outline for Let’s Encrypt. Use this for a real deployment with a real DNS name.

High-level requirements:

- A DNS name (for example: `ots.example.com`) pointing to the server
- Inbound access for ACME validation (commonly port 80)

Example commands:

```bash
sudo apt-get update -y
sudo apt-get install -y certbot python3-certbot-nginx

DOMAIN="ots.example.com"
EMAIL="you@example.com"

sudo certbot --nginx -d "${DOMAIN}" --redirect --non-interactive --agree-tos -m "${EMAIL}"

sudo ufw allow 'Nginx Full'
sudo ufw reload
```

---

## Troubleshooting

### Nginx fails to start

```bash
nginx -t
journalctl -u nginx -xe --no-pager
```

### OTS service fails

```bash
systemctl --no-pager -l status ots.service
journalctl -u ots.service -xe --no-pager
```

### Redis issues

```bash
grep -E '^\s*bind ' /etc/redis/redis.conf || true
ss -lntp | grep :6379 || true
```

---

## Uninstall

If your repo includes an uninstall script:

```bash
chmod +x uninstall-ots.sh
sudo ./uninstall-ots.sh
```

Manual uninstall (safe default):

```bash
sudo systemctl disable --now ots.service nginx redis-server ufw || true

sudo rm -f /etc/systemd/system/ots.service
sudo rm -f /etc/nginx/conf.d/ots_app.conf
sudo rm -rf /etc/nginx/certs
sudo rm -rf /opt/ots
sudo rm -f /etc/apt/sources.list.d/redis.list

sudo systemctl daemon-reload
```

Remove packages (optional):

```bash
sudo apt-get remove -y nginx redis ufw
sudo apt-get autoremove -y
```

---

## Security notes

- OTS runs as a dedicated `ots` user and uses systemd hardening options.
- Redis is bound to localhost and not opened in UFW.
- For production, use Let’s Encrypt (trusted certs), set up monitoring, and consider log retention.

---

## Credits

- OTS application by **Luzifer**: `github.com/Luzifer/ots` citeturn0search0
