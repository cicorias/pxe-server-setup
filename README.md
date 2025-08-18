# Ubuntu 24.04 PXE Server Setup

A comprehensive installation and setup script collection for creating a PXE (Preboot Execution Environment) server on Ubuntu 24.04 LTS using native Ubuntu packages.

## Overview

This project provides automated, idempotent scripts to set up a fully functional PXE server capable of network booting and installing multiple operating systems. The setup uses standard Ubuntu 24.04 packages without relying on iPXE.

## Features

- ✅ Native Ubuntu 24.04 package support (no iPXE dependency)
- ✅ Flexible DHCP configuration (local or existing network DHCP)
- ✅ Support for multiple ISO files
- ✅ Idempotent installation scripts
- ✅ Organized project structure
- ✅ Automated setup process

## Prerequisites

- Ubuntu 24.04 LTS (Server or Desktop)
- Root or sudo access
- Network connectivity
- Minimum 20GB free disk space for ISO storage
- Static IP address (recommended)

## Project Structure

```
pxe-server-setup/
├── README.md                 # This file
├── .gitignore               # Git ignore configuration
├── scripts/                 # Installation and setup scripts
│   ├── 01-prerequisites.sh # System prerequisites and validation
│   ├── 02-packages.sh      # Package installation
│   ├── 03-tftp-setup.sh    # TFTP server configuration
│   ├── 04-dhcp-setup.sh    # DHCP server configuration (optional)
│   ├── 05-nfs-setup.sh     # NFS server configuration
│   ├── 06-http-setup.sh    # HTTP server configuration
│   ├── 07-pxe-menu.sh      # PXE boot menu configuration
│   ├── 08-iso-manager.sh   # ISO management utilities
│   └── config.sh           # Configuration variables
├── artifacts/              # Generated files (excluded from git)
│   ├── iso/               # ISO storage directory
│   ├── tftp/              # TFTP root directory
│   └── http/              # HTTP root directory
└── docs/                   # Additional documentation
    └── troubleshooting.md  # Common issues and solutions
```

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/pxe-server-setup.git
cd pxe-server-setup
```

### 2. Configure Settings (Required)

**⚠️ Configuration is mandatory** - Edit the configuration file to match your network environment:

```bash
cp scripts/config.sh.example scripts/config.sh
nano scripts/config.sh
```

**Required Network Settings:**
- `NETWORK_INTERFACE` - Your network interface (e.g., eth0, ens192)
- `PXE_SERVER_IP` - Static IP address for the PXE server  
- `SUBNET` - Network subnet (e.g., 10.1.1.0)
- `NETMASK` - Subnet mask (e.g., 255.255.255.0)
- `GATEWAY` - Default gateway IP address

**Example Configuration:**
```bash
NETWORK_INTERFACE="eth0"
PXE_SERVER_IP="10.1.1.1"
SUBNET="10.1.1.0"
NETMASK="255.255.255.0"
GATEWAY="10.1.1.1"
```

### 3. Run Installation

Execute the main installation script:

```bash
sudo ./install.sh
```

Or run individual scripts in order:

```bash
cd scripts
sudo ./01-prerequisites.sh
sudo ./02-packages.sh
# ... continue with remaining scripts
```

## Configuration Options

### DHCP Configuration

The setup supports two DHCP modes:

#### Option 1: Local DHCP Server
- Installs and configures ISC DHCP server locally
- Recommended for isolated networks or testing
- Run: `sudo ./scripts/04-dhcp-setup.sh --local`

#### Option 2: Existing Network DHCP
- Uses existing DHCP server on the network
- Requires DHCP server configuration for PXE options
- Run: `sudo ./scripts/04-dhcp-setup.sh --external`

### Adding ISO Files

Place ISO files in the `artifacts/iso/` directory and run:

```bash
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04-server.iso
```

## Services Installed

- **TFTP Server** (tftpd-hpa): Serves boot files
- **NFS Server**: Provides network file system for installations
- **HTTP Server** (nginx): Serves installation files
- **DHCP Server** (isc-dhcp-server): Optional local DHCP service
- **Syslinux**: Provides PXE boot loaders

## Network Requirements

### Ports Used
- DHCP: 67/68 (UDP) - if using local DHCP
- TFTP: 69 (UDP)
- HTTP: 80 (TCP)
- NFS: 2049 (TCP/UDP)

### IP Configuration
Ensure your PXE server has a static IP address:

```bash
# Example /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 10.1.1.1/24
      gateway4: 10.1.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

## Usage

### Prerequisites Setup

**⚠️ Configuration is mandatory before running any scripts:**

```bash
# 1. Configure network settings (REQUIRED)
cp scripts/config.sh.example scripts/config.sh
nano scripts/config.sh

# Set these required variables:
# NETWORK_INTERFACE="eth0"
# PXE_SERVER_IP="10.1.1.1" 
# SUBNET="10.1.1.0"
# NETMASK="255.255.255.0"
# GATEWAY="10.1.1.1"

# 2. Run prerequisites check
sudo ./scripts/01-prerequisites.sh

# 3. Install packages
sudo ./scripts/02-packages.sh

# 4. Configure TFTP server
sudo ./scripts/03-tftp-setup.sh
```

### Complete Installation

Run the automated installation for a full PXE server setup:

```bash
sudo ./install.sh
```

### Manual Step-by-Step Installation

For granular control, run individual scripts in order:

```bash
cd scripts

# 1. System prerequisites and validation
sudo ./01-prerequisites.sh

# 2. Package installation
sudo ./02-packages.sh

# 3. TFTP server configuration
sudo ./03-tftp-setup.sh

# 4. DHCP configuration (choose one)
sudo ./04-dhcp-setup.sh --local     # For local DHCP server
sudo ./04-dhcp-setup.sh --external  # For existing network DHCP

# 5. NFS server configuration
sudo ./05-nfs-setup.sh

# 6. HTTP server configuration (nginx)
sudo ./06-http-setup.sh

# 7. PXE boot menu creation
sudo ./07-pxe-menu.sh

# 8. Add ISO files
sudo ./08-iso-manager.sh add ubuntu-24.04-server.iso
```

### ISO Management

```bash
# Add single ISO
sudo ./scripts/08-iso-manager.sh add <iso-file>

# Add multiple ISOs
sudo ./scripts/08-iso-manager.sh add *.iso

# List available ISOs
sudo ./scripts/08-iso-manager.sh list

# Remove ISO
sudo ./scripts/08-iso-manager.sh remove <iso-file>
```

### Service Management

```bash
# Check service status
systemctl status tftpd-hpa nfs-kernel-server nginx

# View service logs
sudo journalctl -u tftpd-hpa -f    # TFTP logs
sudo journalctl -u nginx -f        # HTTP logs
sudo journalctl -u nfs-kernel-server -f  # NFS logs

# Restart services
sudo systemctl restart tftpd-hpa
sudo systemctl restart nginx
sudo systemctl restart nfs-kernel-server
```

### TFTP Server Configuration

The TFTP server is configured automatically by the `03-tftp-setup.sh` script:

```bash
# Configure TFTP server
sudo ./scripts/03-tftp-setup.sh

# Manual TFTP testing
tftp 10.1.1.1
> get test.txt
> quit

# Check TFTP port
sudo netstat -ulpn | grep :69

# View TFTP configuration
cat /etc/default/tftpd-hpa

# TFTP directory structure
ls -la /var/lib/tftpboot/
```

**TFTP Features:**
- Serves PXE boot files from `/var/lib/tftpboot/`
- Binds to configured server IP (default: 10.1.1.1:69)
- Includes automatic verification test
- Creates proper directory structure for PXE components
- Sets secure permissions and runs as tftp user

**Troubleshooting TFTP:**
```bash
# Check if TFTP is listening
sudo ss -ulpn | grep :69

# Test TFTP connectivity
sudo ufw allow 69/udp  # If firewall is enabled
tftp localhost -c get test.txt

# Check TFTP logs
sudo journalctl -u tftpd-hpa -n 50

# Restart TFTP service
sudo systemctl restart tftpd-hpa
```

### Configuration Updates

```bash
# Update PXE menu
sudo nano artifacts/tftp/pxelinux.cfg/default
sudo systemctl restart tftpd-hpa

# Update network configuration
sudo nano scripts/config.sh
# Re-run relevant setup scripts

# Update HTTP document root
sudo nano /etc/nginx/sites-available/pxe
sudo systemctl reload nginx
```

## Usage Examples

### Adding Ubuntu 24.04 Server ISO

```bash
# Download ISO
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Add to PXE server
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04-live-server-amd64.iso
```

### Adding Multiple ISOs

```bash
# Add multiple distributions
for iso in *.iso; do
    sudo ./scripts/08-iso-manager.sh add "$iso"
done
```

### Listing Available Boot Options

```bash
sudo ./scripts/08-iso-manager.sh list
```

## Troubleshooting

### Common Issues

1. **TFTP Timeout**: Check firewall rules and TFTP service status
2. **DHCP Not Offering IP**: Verify DHCP configuration and network settings
3. **ISO Not Booting**: Ensure ISO is properly extracted and menu configured

For detailed troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md)

### Logs

Check service logs for debugging:

```bash
# TFTP logs
sudo journalctl -u tftpd-hpa -f

# DHCP logs (if using local)
sudo journalctl -u isc-dhcp-server -f

# HTTP server logs
sudo tail -f /var/log/nginx/access.log
```

## Maintenance

### Updating PXE Menu

Edit the PXE menu configuration:

```bash
sudo nano /artifacts/tftp/pxelinux.cfg/default
sudo systemctl restart tftpd-hpa
```

### Removing ISOs

```bash
sudo ./scripts/08-iso-manager.sh remove ubuntu-24.04-server.iso
```

### Backup Configuration

```bash
sudo tar -czf pxe-backup-$(date +%Y%m%d).tar.gz \
    /etc/dhcp/ \
    /etc/default/tftpd-hpa \
    /etc/exports \
    artifacts/tftp/pxelinux.cfg/
```

## Security Considerations

- Limit PXE server access to trusted networks
- Use firewall rules to restrict service access
- Regularly update ISOs and system packages
- Monitor logs for unauthorized access attempts
- Consider network segmentation for PXE services

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check existing issues for solutions
- Review the troubleshooting guide

## Acknowledgments

- Ubuntu community for comprehensive documentation
- SYSLINUX project for PXE boot loaders
- Contributors and testers

---

**Version**: 1.0.0  
**Last Updated**: 2024  
**Tested On**: Ubuntu 24.04 LTS
