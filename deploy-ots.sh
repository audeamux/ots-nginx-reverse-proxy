#!/usr/bin/env bash
#
# Automated deployment of OTS (one-time secret) behind Nginx with Redis.
# Target: Debian/Ubuntu with systemd
#
# Notes:
# - Intended for a single-host setup: OTS + Redis on the same machine, Nginx as reverse proxy.
# - TLS is outlined but commented (no TLS cert / no domain).

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

  status="$(systemctl is-active "$svc" 2>/dev/null || true)"
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
apt-get install -y wget curl vim gnupg lsb-release ca-certificates ufw

#----------------Redis
print_color green "Installing Redis..."
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/redis.list

apt-get update -y
apt-get install -y redis

print_color green "Configuring Redis..."
sed -i 's/^supervised .*/supervised systemd/g' /etc/redis/redis.conf

# Safer default: keep Redis local-only
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
OTS_VERSION="v0.25.0"

print_color green "Installing OTS (${OTS_VERSION})..."
mkdir -p /opt/ots
wget -q "https://github.com/Luzifer/ots/releases/download/${OTS_VERSION}/ots_linux_amd64.tar.gz" \
  -O /opt/ots/ots_linux_amd64.tar.gz
tar -xzf /opt/ots/ots_linux_amd64.tar.gz -C /opt/ots
rm -f /opt/ots/ots_linux_amd64.tar.gz
chmod +x /opt/ots/ots_linux_amd64

# Ownership for non-root service execution
chown -R ots:ots /opt/ots

#----------------Systemd Service
print_color green "Configuring OTS as a systemd service..."
cat > /etc/systemd/system/ots.service <<'EOF'
[Unit]
Description=OTS App
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=ots
Group=ots
WorkingDirectory=/opt/ots
ExecStart=/opt/ots/ots_linux_amd64
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
print_color green "Installing Nginx..."
apt-get install -y nginx

print_color green "Configuring Nginx reverse proxy for OTS..."

rm -f /etc/nginx/sites-enabled/default || true  # Remove pre-existing config to prevent conflicts

cat > /etc/nginx/conf.d/ots_app.conf <<'EOF'
log_format custom_log '"Request: $request\n Status: $status\n Request_URI: $request_uri\n Host: $host\n Client_IP: $remote_addr\n Proxy_IP(s): $proxy_add_x_forwarded_for\n Proxy_Hostname: $proxy_host\n Real_IP: $http_x_real_ip\n User_Client: $http_user_agent"';

server {
    listen 80 default_server;
    server_name _;

    access_log /var/log/nginx/custom-access-logs.log custom_log;

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

#----------------TLS Optional
# TLS is commented out because this assignment does not have a real DNS name / cert.
# In a real deployment, use a domain name and Let's Encrypt (certbot) to enable HTTPS.
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
ufw allow ssh
ufw allow 'Nginx HTTP'
ufw --force enable
ufw reload
check_service_status ufw

print_color green "UFW status:"
ufw status verbose

#----------------Done
SERVER_IP="$(hostname -I | awk '{print $1}')"
print_color green "All set! Visit: http://${SERVER_IP}/"    # (or your DNS name) on port 80
