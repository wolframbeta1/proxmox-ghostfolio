#!/usr/bin/env bash
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Customization for Ghostfolio
# Based on original script by wolframbeta1 and tteck's Proxmox VE Helper Scripts template.

function header_info {
  clear
  cat <<"EOF"
    ___   ____  ______          __    __
  / _ | / / / /_  __/__ __ _  ___  / /__ _/ /____ ___
 / __ |/ / /   / / / -_)  ' \/ _ \/ / _ `/ __/ -_|_-<
/_/ |_/_/_/   /_/  \__/_/_/_/ .__/_/\_,_/\__/\__/___/
                            /_/
    Ghostfolio LXC Auto-Installer for Proxmox VE
EOF
}

# --- Standard tteck error handling and messaging ---
set -eEuo pipefail
shopt -s expand_aliases # <--- FIX: Added hyphen here!
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
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG "$REASON""
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG "$REASON""
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function cleanup_ctid() {
  info "Cleaning up incomplete container $CTID..."
  if pct status $CTID &>/dev/null; then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID || warn "Failed to stop container $CTID. Attempting to destroy anyway."
    fi
    pct destroy $CTID || warn "Failed to destroy container $CTID. Manual cleanup may be required."
  fi
}
# --- End of tteck error handling and messaging ---

# --- Custom Ghostfolio Parameters ---
CONTAINER_NAME="Ghostfolio"
# Generated password for LXC root access (8 chars base64)
LXC_ROOT_PASSWORD="$(openssl rand -base64 8)"
DISK_SIZE=${DISK_SIZE:-8}    # GB
RAM_SIZE=${RAM_SIZE:-2048}   # MB
CPU_CORES=${CPU_CORES:-2}
BRIDGE=${BRIDGE:-vmbr0}     # Proxmox network bridge
# We explicitly use Ubuntu 22.04 for Ghostfolio due to its dependencies
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
# --- End of Custom Ghostfolio Parameters ---


header_info
echo "Loading Proxmox API information..."
# Ensure pveam is updated before checking templates
pveam update >/dev/null 2>&1 || warn "pveam update failed, continuing without update check. Template may not be latest."

# Automatically get the next available CTID
CTID=$(pvesh get /cluster/nextid)
info "Next available Container ID: $CTID"


# --- Storage selection function (from tteck template) ---
# Set the CONTENT and CONTENT_LABEL variables for select_storage
function select_storage() {
  local CLASS=$1
  local CONTENT
  local CONTENT_LABEL
  case $CLASS in
  container)
    CONTENT='rootdir'
    CONTENT_LABEL='Container'
    ;;
  template)
    CONTENT='vztmpl'
    CONTENT_LABEL='Container template'
    ;;
  *) false || die "Invalid storage class." ;;
  esac 

  # Query all storage locations
  local -a MENU
  MSG_MAX_LENGTH=0 # Reset for this function
  while read -r line; do
    local TAG=$(echo "$line" | awk '{print $1}')
    local TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    local FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    local ITEM="  Type: $TYPE Free: $FREE "
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content "$CONTENT" | awk 'NR>1')

  # Select storage location
  if [ $((${#MENU[@]} / 3)) -eq 0 ]; then
    warn "'$CONTENT_LABEL' needs to be selected for at least one storage location."
    die "Unable to detect valid storage location."
  elif [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    printf %s "${MENU[0]}" # Return the single option directly
  else
    local STORAGE
    while [ -z "${STORAGE:+x}" ]; do
      STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
        "Which storage pool would you like to use for the ${CONTENT_LABEL,,}?\n\n" \
        16 $((MSG_MAX_LENGTH + 23)) 6 \
        "${MENU[@]}" 3>&1 1>&2 2>&3) || die "Menu aborted by user."
    done
    printf %s "$STORAGE"
  fi
}
# --- End of storage selection function ---

header_info # Refresh header
info "Selecting storage for template and container..."
TEMPLATE_STORAGE=$(select_storage template)
info "Using '$TEMPLATE_STORAGE' for template storage."

CONTAINER_STORAGE=$(select_storage container)
info "Using '$CONTAINER_STORAGE' for container storage."

# Download template if not present
msg "Checking and downloading LXC template if needed (Patience)..."
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  info "Template '$TEMPLATE' not found locally on '$TEMPLATE_STORAGE'. Downloading..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" || die "A problem occurred while downloading the LXC template."
else
  info "Template '$TEMPLATE' already available on '$TEMPLATE_STORAGE'."
fi


info "Creating LXC Container (ID: $CTID, Name: $CONTAINER_NAME)..."
PCT_OPTIONS=(
    -arch $(dpkg --print-architecture)
    -features keyctl=1,nesting=1
    -hostname "$CONTAINER_NAME"
    -tags proxmox-helper-scripts,ghostfolio
    -onboot 1 # Start with Proxmox
    -cores "$CPU_CORES"
    -memory "$RAM_SIZE"
    -password "$LXC_ROOT_PASSWORD"
    -net0 name=eth0,bridge="$BRIDGE",ip=dhcp
    -unprivileged 1
    -rootfs "$CONTAINER_STORAGE:$DISK_SIZE"
)

pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" >/dev/null \
    || die "A problem occurred while trying to create container."

# Save password to a file in the Proxmox root directory
echo "$CONTAINER_NAME root password: $LXC_ROOT_PASSWORD" >>~/$CONTAINER_NAME.creds
info "LXC root password saved to ~/$CONTAINER_NAME.creds"

msg "Starting LXC Container $CTID..."
pct start "$CTID"
# Give container some time to start and get an IP
sleep 10


# --- Get container IP with retry logic (from tteck template) ---
info "Attempting to get container IP address..."
set +eEuo pipefail # Temporarily disable strict mode for IP lookup retry
max_attempts=12 # 12 attempts * 5 seconds = 60 seconds
attempt=1
IP=""
while [[ $attempt -le $max_attempts ]]; do
  IP=$(pct exec "$CTID" ip a show dev eth0 | grep -oP 'inet \K[^/]+')
  if [[ -n "$IP" ]]; then
    info "IP address found: $IP"
    break
  else
    warn "Attempt $attempt/$max_attempts: IP address not found for $CTID. Pausing for 5 seconds..."
    sleep 5
    ((attempt++))
  fi
done

if [[ -z "$IP" ]]; then
  warn "Maximum number of attempts reached. IP address not found. Please check network configuration in Proxmox and container."
  IP="NOT FOUND"
else
  # Double check if IP is actually reachable (optional, but good for robustness)
  ping -c 1 -W 1 "$IP" &>/dev/null || warn "Container IP ($IP) is not reachable from Proxmox host. Network issue possible."
fi
set -eEuo pipefail # Re-enable strict mode
# --- End of IP retrieval ---


msg "Installing Ghostfolio inside container $CTID..."
# The installation commands are executed in a single bash session within the container
# This ensures that PATH changes for npm global installs are consistent.
pct exec "$CTID" -- bash -c "\
    export DEBIAN_FRONTEND=noninteractive; \
    
    # Update and upgrade system
    echo '--- Updating system ---' && \
    apt update -y && apt upgrade -y || die 'System update failed'; \
    
    # Install required dependencies
    echo '--- Installing dependencies (curl, git, build-essential, postgresql, nodejs) ---' && \
    apt install -y curl git build-essential postgresql || die 'Dependency installation failed'; \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || die 'Node.js repository setup failed'; \
    apt install -y nodejs || die 'Node.js installation failed'; \
    
    # Configure PostgreSQL for Ghostfolio
    echo '--- Configuring PostgreSQL ---' && \
    sudo -u postgres psql -c \"CREATE USER ghostfolio WITH PASSWORD 'ghostfolio';\" || die 'PostgreSQL user creation failed'; \
    sudo -u postgres psql -c \"CREATE DATABASE ghostfolio OWNER ghostfolio;\" || die 'PostgreSQL database creation failed'; \
    
    # Clone Ghostfolio repository
    echo '--- Cloning Ghostfolio repository ---' && \
    git clone --depth 1 https://github.com/ghostfolio/ghostfolio.git /opt/ghostfolio || die 'Ghostfolio clone failed'; \
    
    # Configure Ghostfolio environment
    echo '--- Configuring Ghostfolio environment variables ---' && \
    cd /opt/ghostfolio || die 'Failed to change directory to /opt/ghostfolio'; \
    cp .env.example .env || die 'Failed to copy .env.example'; \
    sed -i \"s|DATABASE_URL=.*|DATABASE_URL=postgresql://ghostfolio:ghostfolio@localhost:5432/ghostfolio|g\" .env || die 'Failed to set DATABASE_URL'; \
    sed -i \"s|NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=\$(openssl rand -hex 32)|g\" .env || die 'Failed to set NEXTAUTH_SECRET'; \
    
    # Install Node.js dependencies and build Ghostfolio
    echo '--- Installing Node.js dependencies and building Ghostfolio ---' && \
    npm install || die 'npm install failed'; \
    npm run build || die 'npm run build failed'; \
    
    # Install PM2 globally and start Ghostfolio
    echo '--- Installing PM2 and starting Ghostfolio service ---' && \
    npm install -g pm2 || die 'PM2 global installation failed'; \
    
    # Ensure PM2 is in PATH for this session by explicitly adding npm's global bin directory
    export PATH=\"\$(npm prefix -g)/bin:\$PATH\"; \
    
    # Check if PM2 is now available
    if ! command -v pm2 &> /dev/null; then \
        die 'PM2 command not found after installation and PATH adjustment.'; \
    fi; \
    
    pm2 start npm --name ghostfolio -- start || die 'PM2 failed to start Ghostfolio'; \
    pm2 startup systemd || die 'PM2 startup configuration failed'; \
    pm2 save || die 'PM2 save failed'; \
    
    # Configure Uncomplicated Firewall (UFW) if active
    echo '--- Checking and configuring UFW (if active) ---' && \
    if command -v ufw &> /dev/null; then \
        if ufw status | grep -q \"Status: active\"; then \
            info 'UFW is active. Allowing port 3333/tcp.'; \
            ufw allow 3333/tcp || warn 'Failed to add UFW rule for port 3333. Check UFW logs.'; \
            ufw reload || warn 'Failed to reload UFW. Check UFW logs.'; \
        else \
            info 'UFW is not active.'; \
        fi; \
    else \
        info 'UFW command not found (UFW not installed or not in PATH).'; \
    fi; \
    
    echo '--- Ghostfolio installation and configuration complete inside container ---'
" || die "Ghostfolio installation within container failed."

info "Ghostfolio installation process in container $CTID completed."


# --- Final success message ---
header_info
echo
info "LXC container '$CTID' ($CONTAINER_NAME) was successfully created and configured."
echo
info "Access Ghostfolio at: \e[1;34mhttp://$IP:3333\e[0m"
echo
info "Container details:"
info "  Container ID: \e[33m$CTID\e[0m"
info "  Container Name: \e[33m$CONTAINER_NAME\e[0m"
info "  IP Address: \e[33m$IP\e[0m"
info "  LXC Root Login: \e[33mroot\e[0m / Password: \e[33m$LXC_ROOT_PASSWORD\e[0m (access via 'pct enter $CTID' or SSH)"
info "  Ghostfolio App Login (Default): \e[33madmin@ghostfol.io\e[0m / Password: \e[33madmin\e[0m"
warn "Please change the default Ghostfolio app login password immediately after first access!"
echo
info "Disk Size: \e[33m${DISK_SIZE}GB\e[0m"
info "RAM Size: \e[33m${RAM_SIZE}MB\e[0m"
info "CPU Cores: \e[33m$CPU_CORES\e[0m"
info "Network Bridge: \e[33m$BRIDGE\e[0m"
echo
warn "If you face connectivity issues, check your Proxmox firewall settings and ensure port 3333 is open."
