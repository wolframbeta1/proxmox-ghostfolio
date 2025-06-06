#!/usr/bin/env bash

# Ghostfolio LXC Auto-Installer for Proxmox VE

set -e

### --- CONFIG --- ###
# Find next available CTID
NEXTID=$(pvesh get /cluster/nextid)
CTID=${CTID:-$NEXTID}

HOSTNAME=${HOSTNAME:-ghostfolio}
PASSWORD=${PASSWORD:-ghostfolio123}
DISK_SIZE=${DISK_SIZE:-8}
RAM_SIZE=${RAM_SIZE:-2048}
CPU_CORES=${CPU_CORES:-2}
BRIDGE=${BRIDGE:-vmbr0}
IPV4=${IPV4:-dhcp}

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

### --- CHECK AND DOWNLOAD TEMPLATE --- ###
if ! pveam list local | grep -q "$TEMPLATE"; then
  echo "[INFO] Template not found locally. Attempting to download..."
  pveam update
  pveam download local "$TEMPLATE"
fi

### --- CREATE LXC --- ###
echo "[INFO] Creating LXC container (CTID: $CTID)"
pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --cores $CPU_CORES \
    --memory $RAM_SIZE \
    --rootfs local-lvm:$DISK_SIZE \
    --net0 name=eth0,bridge=$BRIDGE,ip=$IPV4 \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --password $PASSWORD

### --- START LXC --- ###
echo "[INFO] Starting container..."
pct start $CTID
sleep 5

### --- INSTALL GHOSTFOLIO --- ###
echo "[INFO] Installing Ghostfolio inside container..."
pct exec $CTID -- bash -c "\
    apt update && apt upgrade -y && \
    apt install -y curl git build-essential postgresql && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt install -y nodejs && \
    sudo -u postgres psql -c \"CREATE USER ghostfolio WITH PASSWORD 'ghostfolio';\" && \
    sudo -u postgres psql -c \"CREATE DATABASE ghostfolio OWNER ghostfolio;\" && \
    git clone https://github.com/ghostfolio/ghostfolio.git /opt/ghostfolio && \
    cd /opt/ghostfolio && \
    cp .env.example .env && \
    sed -i \"s|DATABASE_URL=.*|DATABASE_URL=postgresql://ghostfolio:ghostfolio@localhost:5432/ghostfolio|g\" .env && \
    sed -i \"s|NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$(openssl rand -hex 32)|g\" .env && \
    npm install && npm run build && \
    npm install -g pm2 && \
    pm2 start npm --name ghostfolio -- run start && \
    pm2 startup systemd && pm2 save"

### --- INFO --- ###
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "\n[INFO] Ghostfolio Installation Completed!"
echo "[INFO] Access Ghostfolio at: http://$IP:3000"
echo "[INFO] Default PostgreSQL User: ghostfolio"
echo "[INFO] Default PostgreSQL Password: ghostfolio"
echo "[INFO] Container root password: $PASSWORD"
