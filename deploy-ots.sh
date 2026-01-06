#!/usr/bin/env bash
#
# Automated deployment of OTS (one-time secret) behind Nginx with Redis.
# Target: Debian/Ubuntu with systemd
#
# Notes:
# - Intended for a single-host setup: OTS + Redis on the same machine, Nginx as reverse proxy.
# - TLS is outlined but commented (no TLS cert / no domain).
# - Used self-signed cert instead

set -euo pipefail

#----------------Helpers
NC="\033[0m"
print_color() {
  local color="${1:-}"
  local msg="${2:-}"
  local COLOR

  case "$color" in
    green) COLOR="\033[0;32m" ;;
    red)   COLOR="\033[0;31m" ;;
    *)     COLOR="$NC" ;;
  esac

  echo -e "${COLOR}${msg}${NC}"
}

check_service_status() {
  local svc="$1"
  local status

  status="$(systemctl is-active "$svc" 2> /dev/null || true)"
  if [[ "$status" == "active" ]]; then
    print_color green "$svc service is active"
  else
    print_color red "$svc service is not active (status: $status)"
    systemctl --no-pager -l status "$svc" || true
    exit 1
  fi
}

if [[ "${EUID}" -ne 0 ]]; then
  print_color red "Please run as root (e.g., sudo $0)"
  exit 1
fi

#----------------Prereqs
print_color green "Updating apt and installing prerequisites..."
apt-get update -y
apt-get install -y wget curl vim gnupg lsb-release ca-certificates ufw nginx

#----------------Redis
print_color green "Installing Redis..."
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/redis.list

apt-get update -y
apt-get install -y redis

print_color green "Configuring Redis..."
sed -i 's/^supervised .*/supervised systemd/g' /etc/redis/redis.conf

# Keep Redis local-only
if grep -qE '^\s*bind\s+' /etc/redis/redis.conf; then
  sed -i 's/^\s*bind\s.*/bind 127.0.0.1 ::1/g' /etc/redis/redis.conf
else
  echo "bind 127.0.0.1 ::1" >> /etc/redis/redis.conf
fi

systemctl enable redis-server
systemctl restart redis-server
check_service_status redis-server

#----------------OTS User
print_color green "Ensuring a dedicated 'ots' service user exists..."
if ! getent passwd ots >/dev/null; then
  useradd --system --home-dir /opt/ots --shell /usr/sbin/nologin ots
fi

#----------------OTS
OTS_VERSION="v1.20.1"
OTS_TARBALL="ots_linux_amd64.tgz"
OTS_BIN="/opt/ots/ots"

print_color green "Installing OTS (${OTS_VERSION})..."
mkdir -p /opt/ots
wget -q "https://github.com/Luzifer/ots/releases/download/${OTS_VERSION}/${OTS_TARBALL}" \
  -O /opt/ots/${OTS_TARBALL}
tar -xzf /opt/ots/${OTS_TARBALL} -C /opt/ots
rm -f /opt/ots/${OTS_TARBALL} 
chmod +x "${OTS_BIN}"

[[ -x "$OTS_BIN" ]] || { print_color red "OTS binary not found at $OTS_BIN"; exit 1; }

# Ownership for non-root service execution
chown -R ots:ots /opt/ots

#----------------Systemd Service
print_color green "Configuring OTS as a systemd service..."
cat > /etc/systemd/system/ots.service <<EOF
[Unit]
Description=OTS App
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=ots
Group=ots
WorkingDirectory=/opt/ots
ExecStart=${OTS_BIN}
Restart=on-failure
RestartSec=2

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictRealtime=true
MemoryDenyWriteExecute=true
UMask=027

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ots.service
systemctl restart ots.service
check_service_status ots.service

#----------------Nginx
print_color green "Configuring Nginx..."
print_color green "Creating a self-signed cert..."

mkdir -p /etc/nginx/certs
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /etc/nginx/certs/ots.key \
  -out /etc/nginx/certs/ots.crt \
  -subj "/CN=ots.local"
chmod 600 /etc/nginx/certs/ots.key

print_color green "Configuring Nginx reverse proxy for OTS..."

rm -f /etc/nginx/sites-enabled/default || true  # Remove pre-existing config to prevent conflicts

cat > /etc/nginx/conf.d/ots_app.conf <<'EOF'
server {
  listen 80 default_server;
  server_name _;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2 default_server;
  server_name _;

  ssl_certificate     /etc/nginx/certs/ots.crt;
  ssl_certificate_key /etc/nginx/certs/ots.key;

  access_log /var/log/nginx/custom-access-logs.log;

  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

  location / {
    proxy_pass http://127.0.0.1:3000;
  }
}
EOF

nginx -t
systemctl enable nginx
systemctl restart nginx
check_service_status nginx

#----------------Let’s Encrypt Optional
# TLS is commented out because this assignment does not have a real DNS name, and uses self-signed cert.
# In a real deployment, use a domain name and certbot to enable HTTPS.
: <<'TLS_SETUP'

# apt-get update -y
# apt-get install -y certbot python3-certbot-nginx
#
# DOMAIN="ots.example.com"
#
# # Certbot to configure nginx, HTTPS, and redirect
# certbot --nginx -d "${DOMAIN}" --redirect --non-interactive --agree-tos -m you@example.com
#
# # Open firewall for HTTPS
# ufw allow 'Nginx Full'   # ports 80 and 443
# ufw reload
#
# nginx -t && systemctl reload nginx
# certbot renew --dry-run

TLS_SETUP

#----------------Firewall
print_color green "Configuring UFW firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw reload
check_service_status ufw

print_color green "UFW status:"
ufw status verbose

#----------------Done
SERVER_IP="$(hostname -I | awk '{print $1}')"
print_color green "All set! Visit: https://${SERVER_IP}/"    # self-signed cert, browser warning is expected