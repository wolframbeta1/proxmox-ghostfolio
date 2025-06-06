#!/usr/bin/env bash

# Ghostfolio LXC Auto-Installer for Proxmox VE
# Inspired by Community-Scripts RustDesk Server Script

set -e

### --- CONFIG --- ###
CTID=${CTID:-110}                      # Default Container ID
HOSTNAME=${HOSTNAME:-ghostfolio}        # Default Hostname
PASSWORD=${PASSWORD:-ghostfolio123}     # Default root password
DISK_SIZE=${DISK_SIZE:-8}               # Disk Size in GB
RAM_SIZE=${RAM_SIZE:-2048}              # Memory in MB
CPU_CORES=${CPU_CORES:-2}               # CPU Cores
BRIDGE=${BRIDGE:-vmbr0}                 # Network Bridge
IPV4=${IPV4:-dhcp}                      # IPv4 (use dhcp or static)

TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

### --- CREATE LXC --- ###
echo "[INFO] Downloading LXC template..."
pct template local download ubuntu-22.04 || true

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


# README.md

# Proxmox Ghostfolio LXC Installer

This script automatically creates an LXC container and installs [Ghostfolio](https://github.com/ghostfolio/ghostfolio) on your Proxmox VE server.

## Usage

Run the following command on your Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/wolframbeta1/proxmox-ghostfolio/main/ghostfolio-lxc.sh)"
```

## Features

- Creates a secure, unprivileged Ubuntu 22.04 LXC container
- Installs Node.js 20, PostgreSQL, and Ghostfolio
- Configures PostgreSQL for Ghostfolio
- Starts Ghostfolio using PM2 for process management
- Outputs container IP and login info

## Default Settings

| Parameter        | Value               |
|------------------|---------------------|
| CTID             | 110                 |
| Hostname         | ghostfolio          |
| Root Password    | ghostfolio123        |
| Disk Size        | 8 GB                |
| RAM Size         | 2048 MB             |
| CPU Cores        | 2                   |
| Network Bridge   | vmbr0               |
| IP Address       | DHCP                |

> **Note**: You can modify these defaults by adjusting the script before running.

## License

This project is licensed under the MIT License.
