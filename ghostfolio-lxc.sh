#!/usr/bin/env bash

# Ghostfolio LXC Auto-Installer for Proxmox VE

# Farben/Icons
YW=$(echo "\033[33m"); GN=$(echo "\033[1;92m"); RD=$(echo "\033[01;31m"); BL=$(echo "\033[36m"); CL=$(echo "\033[m")
CM="\t✔️\t${CL}"; CROSS="\t✖️\t${CL}"; INFO="\t💡\t${CL}"

set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

function error_handler() { printf "\n${RD}[ERROR]${CL} in line ${RD}$1${CL}: Command ${YW}$2${CL}\n"; exit 1; }
function msg_info() { echo -e "${YW}[INFO]${CL} $1"; }
function msg_ok() { echo -e "${GN}[OK]${CL} $1"; }
function msg_error() { echo -e "${RD}[ERROR]${CL} $1"; }

NEXTID=$(pvesh get /cluster/nextid)
CTID=${CTID:-$NEXTID}

CONTAINER_NAME="Ghostfolio"
PASSWORD=${PASSWORD:-root} # Container root password
DISK_SIZE=${DISK_SIZE:-8}
RAM_SIZE=${RAM_SIZE:-2048}
CPU_CORES=${CPU_CORES:-2}
BRIDGE=${BRIDGE:-vmbr0}
IPV4=${IPV4:-dhcp}

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

msg_info "Validating Storage"
if ! pvesm status -content rootdir >/dev/null; then msg_error "No valid container storage found."; exit 1; fi
if ! pvesm status -content vztmpl >/dev/null; then msg_error "No valid template storage found."; exit 1; fi
msg_ok "Storage validated"

msg_info "Checking Template"
if ! pveam list local | grep -q "$TEMPLATE"; then
  msg_info "Template not found locally. Downloading..."
  pveam update
  pveam download local "$TEMPLATE"
fi
msg_ok "Template ready"

msg_info "Creating LXC Container (CTID: $CTID)"
pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $CONTAINER_NAME \
    --cores $CPU_CORES \
    --memory $RAM_SIZE \
    --rootfs local-lvm:$DISK_SIZE \
    --net0 name=eth0,bridge=$BRIDGE,ip=$IPV4 \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --password $PASSWORD
msg_ok "Container created"

msg_info "Starting Container"
pct start $CTID
sleep 5
msg_ok "Container started"

msg_info "Installing Ghostfolio (v2.175.0) inside Container"
pct exec $CTID -- bash -c "\
    apt update && apt upgrade -y && \
    apt install -y curl git build-essential postgresql && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt install -y nodejs && \
    sudo -u postgres psql -c \"CREATE USER ghostfolio WITH PASSWORD 'ghostfolio';\" && \
    sudo -u postgres psql -c \"CREATE DATABASE ghostfolio OWNER ghostfolio;\" && \
    git clone --branch v2.175.0 --depth 1 https://github.com/ghostfolio/ghostfolio.git /opt/ghostfolio && \
    cd /opt/ghostfolio && \
    cp .env.example .env && \
    sed -i \"s|DATABASE_URL=.*|DATABASE_URL=postgresql://ghostfolio:ghostfolio@localhost:5432/ghostfolio|g\" .env && \
    sed -i \"s|NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$(openssl rand -hex 32)|g\" .env && \
    npm install && \
    npm run build && \
    npm install -g pm2 && \
    pm2 start npm --name ghostfolio -- start && \
    pm2 startup systemd && pm2 save"
msg_ok "Ghostfolio installed"

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo -e "${GN}\nInstallation Completed Successfully!${CL}"
echo -e "Access Ghostfolio at: ${BL}http://$IP:3333${CL}  (ab v2.170: Port 3333!)"
echo -e "Container Name: ${YW}$CONTAINER_NAME${CL}"
echo -e "Root Login: ${YW}root${CL} / Password: ${YW}root${CL} (per pct enter oder SSH, NICHT Ghostfolio!)"
echo -e "Ghostfolio App Login (Default): ${YW}admin@ghostfol.io${CL} / Password: ${YW}admin${CL}"
echo -e "Disk Size: ${YW}${DISK_SIZE}GB${CL}"
echo -e "RAM Size: ${YW}${RAM_SIZE}MB${CL}"
echo -e "CPU Cores: ${YW}$CPU_CORES${CL}"
echo -e "Network Bridge: ${YW}$BRIDGE${CL}"
echo -e "IP Address: ${YW}$IP${CL}"
