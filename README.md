# Proxmox Ghostfolio LXC Installer

[](https://ghostfolio.io)

This script automatically creates an LXC container and installs [Ghostfolio](https://github.com/ghostfolio/ghostfolio) on your Proxmox VE server.

## Usage

Run the following command on your Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/wolframbeta1/proxmox-ghostfolio/main/ghostfolio-lxc.sh)"
```

> **Hinweis**: Die oben genannte URL verweist auf Ihr ursprüngliches Skript. Wenn Sie die Vorteile der neuesten Überarbeitungen nutzen möchten, stellen Sie bitte sicher, dass die URL auf die aktualisierte Version Ihres Skripts verweist, sobald diese auf GitHub verfügbar ist.

## Features

  * Creates a secure, unprivileged Ubuntu 22.04 LXC container

  * Installs Node.js **22**, PostgreSQL, and Ghostfolio

  * Configures PostgreSQL for Ghostfolio

  * Starts Ghostfolio using PM2 for process management

  * Automatically attempts to determine the container's IP address

  * Configures UFW (Uncomplicated Firewall) to allow access to Ghostfolio's port if UFW is active in the container

  * Outputs container IP and login info

## Default Settings

| **Parameter** | **Value** |
|---------------|-----------|
| LXC Name      | `Ghostfolio` |
| Root User     | `root`    |
| Root Password | **Randomly Generated** (saved to `~/Ghostfolio.creds` on Proxmox host) |
| Disk Size     | 8 GB      |
| RAM Size      | 2048 MB   |
| CPU Cores     | 2         |
| Network Bridge| `vmbr0`   |
| IP Address    | DHCP      |

> **Note**: You can modify these defaults by adjusting the script before running.

## Ghostfolio Application Access

After the installation is complete, you can access the Ghostfolio web application via your browser at `http://<LXC_IP_Address>:3333`.

The default login credentials for the Ghostfolio application are:

  * **Username:** `admin@ghostfol.io`

  * **Password:** `admin`

> **IMPORTANT**: Please change these default Ghostfolio app login credentials immediately after your first successful login for security reasons\!

## License

This project is licensed under the MIT License.
