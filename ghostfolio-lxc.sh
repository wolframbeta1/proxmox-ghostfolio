#!/usr/bin/env bash
# Ghostfolio LXC Auto-Installer for Proxmox VE

function header_info {
  clear
  cat << "EOF"
    ___   ____  ______          __    __
  / _ | / / / /_  __/__ __ _  ___  / /__ _/ /____ ___
 / __ |/ / /   / / / -_)  ' \/ _ \/ / _ `/ __/ -_|_-<
/_/ |_/_/_/   /_/  \__/_/_/_/ .__/_/\_,_/\__/\__/___/
                            /_/
    Ghostfolio LXC Auto-Installer for Proxmox VE
EOF
}

set -eEuo pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occurred.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON" 1>&2
  [ ! -z ${CTID-} ] && cleanup_ctid
  exit $EXIT
}
function warn() { msg "\e[93m[WARNING]\e[39m $1"; }
function info() { msg "\e[36m[INFO]\e[39m $1"; }
function msg() { echo -e "$1"; }
function cleanup_ctid() {
  info "Cleaning up incomplete container $CTID..."
  if pct status $CTID &>/dev/null; then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID || warn "Failed to stop container $CTID."
    fi
    pct destroy $CTID || warn "Failed to destroy container $CTID."
  fi
}

CONTAINER_NAME="Ghostfolio"
LXC_ROOT_PASSWORD="$(openssl rand -base64 12)"
DISK_SIZE=8
RAM_SIZE=2048
CPU_CORES=2
BRIDGE=vmbr0
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

header_info
echo "Loading Proxmox API information..."
pveam update >/dev/null 2>&1 || warn "pveam update failed."
CTID=$(pvesh get /cluster/nextid)
info "Next available Container ID: $CTID"

function select_storage() {
  local CLASS=$1
  local CONTENT
  local CONTENT_LABEL
  case $CLASS in
    container) CONTENT='rootdir'; CONTENT_LABEL='Container';;
    template) CONTENT='vztmpl'; CONTENT_LABEL='Template';;
    *) die "Invalid storage class.";;
  esac

  local -a MENU
  MSG_MAX_LENGTH=0
  while read -r line; do
    local TAG=$(echo "$line" | awk '{print $1}')
    local TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    local FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf("%9sB", $6)}')
    local ITEM="  Type: $TYPE Free: $FREE "
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content "$CONTENT" | awk 'NR>1')

  if [ $((${#MENU[@]} / 3)) -eq 0 ]; then die "No valid storage found."; fi
  local STORAGE
  if [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    STORAGE=${MENU[0]}
  else
    STORAGE=$(whiptail --backtitle "Ghostfolio Installer" --title "Storage Pools" --radiolist \
      "Choose storage for ${CONTENT_LABEL}:" 16 $((MSG_MAX_LENGTH + 23)) 6 \
      "${MENU[@]}" 3>&1 1>&2 2>&3) || die "Storage selection aborted."
  fi
  printf %s "$STORAGE"
}

TEMPLATE_STORAGE=$(select_storage template)
CONTAINER_STORAGE=$(select_storage container)

msg "Checking and downloading LXC template if needed..."
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  info "Downloading template..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" || die "Template download failed."
fi

info "Creating LXC Container (ID: $CTID, Name: $CONTAINER_NAME)..."
PCT_OPTIONS=(
  -arch $(dpkg --print-architecture)
  -features keyctl=1,nesting=1
  -hostname "$CONTAINER_NAME"
  -tags proxmox-helper-scripts,ghostfolio
  -onboot 1
  -cores "$CPU_CORES"
  -memory "$RAM_SIZE"
  -password "$LXC_ROOT_PASSWORD"
  -net0 name=eth0,bridge="$BRIDGE",ip=dhcp
  -unprivileged 1
  -rootfs "$CONTAINER_STORAGE:$DISK_SIZE"
)

pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >/dev/null || die "Container creation failed."
echo "$CONTAINER_NAME root password: $LXC_ROOT_PASSWORD" >>~/$CONTAINER_NAME.creds

pct start "$CTID"
sleep 10

info "Getting container IP..."
set +e
max_attempts=12
attempt=1
IP=""
while [[ $attempt -le $max_attempts ]]; do
  IP=$(pct exec "$CTID" ip a show dev eth0 | grep -oP 'inet \K[^/]+' || true)
  [[ -n "$IP" ]] && break
  sleep 5
  ((attempt++))
done
set -e

[[ -z "$IP" ]] && warn "No IP found." || info "IP address: $IP"

msg "Installing Ghostfolio inside container..."
pct exec "$CTID" -- bash -c "\
  export DEBIAN_FRONTEND=noninteractive; \
  apt update && apt upgrade -y && \
  apt install -y curl git build-essential postgresql && \
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
  apt install -y nodejs && \
  sudo -u postgres psql -c \"CREATE USER ghostfolio WITH PASSWORD 'ghostfolio';\" && \
  sudo -u postgres psql -c \"CREATE DATABASE ghostfolio OWNER ghostfolio;\" && \
  git clone --depth 1 https://github.com/ghostfolio/ghostfolio.git /opt/ghostfolio && \
  cd /opt/ghostfolio && \
  cp .env.example .env && \
  sed -i \"s|DATABASE_URL=.*|DATABASE_URL=postgresql://ghostfolio:ghostfolio@localhost:5432/ghostfolio|g\" .env && \
  sed -i \"s|NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=\\$(openssl rand -hex 32)|g\" .env && \
  npm install && \
  npm install -g nx && \
  export PATH=\"\\$(npm prefix -g)/bin:\\$PATH\" && \
  npx nx build api --configuration=production && \
  npx nx build web --configuration=production && \
  npm install -g pm2 && \
  pm2 start npm --name ghostfolio -- start && \
  pm2 startup systemd && \
  pm2 save && \
  if command -v ufw &> /dev/null; then \
    if ufw status | grep -q 'Status: active'; then \
      ufw allow 3333/tcp && ufw reload; \
    fi; \
  fi"

info "Installation complete."
header_info
echo
info "LXC container '$CTID' ($CONTAINER_NAME) successfully created."
echo
info "Access Ghostfolio: \e[1;34mhttp://$IP:3333\e[0m"
echo
info "Login: \e[33madmin@ghostfol.io / admin\e[0m"
warm "Please change the default Ghostfolio password!"
