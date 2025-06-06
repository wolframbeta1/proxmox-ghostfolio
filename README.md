# Proxmox Ghostfolio LXC Installer

[![Ghostfolio](https://img.shields.io/badge/Ghostfolio-Install-brightgreen?style=for-the-badge&logo=proxmox&logoColor=white)](https://ghostfolio.io)

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
