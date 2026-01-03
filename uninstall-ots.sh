#!/usr/bin/env bash

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

if [[ "${EUID}" -ne 0 ]]; then
  print_color red "Please run as root"
  exit 1
fi

#----------------Removing OTS service and files
print_color green "Stopping and disabling ots.service..."
systemctl disable --now ots.service 2>/dev/null || true

print_color green "Stopping and disabling nginx..."
sudo systemctl disable --now nginx

print_color green "Removing systemd unit..."
rm -f /etc/systemd/system/ots.service
systemctl daemon-reload

print_color green "Removing Nginx OTS config..."
rm -f /etc/nginx/conf.d/ots_app.conf

print_color green "Removing OTS install directory..."
rm -rf /opt/ots

print_color green "Removing OTS service user..."
userdel ots

#----------------Verify
print_color green "Verifying uninstall..."

if ss -lnt | grep -q ':3000'; then
  print_color red "OTS may still be runningon port 3000"
  exit 1
fi

if systemctl is-active --quiet nginx; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1/ || true)"
  if [[ "$code" == "200" ]]; then
    print_color red "Nginx may stil be running. Still returns 200 on http://127.0.0.1/"
    exit 1
  fi
fi

print_color green "Done."
