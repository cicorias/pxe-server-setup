# Ubuntu 24.04 PXE Server Setup

A comprehensive installation and setup script collection for creating a PXE (Preboot Execution Environment) server on Ubuntu 24.04 LTS (including 24.04.03) using native Ubuntu packages.

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

- Ubuntu 24.04 LTS (including 24.04.03 - Server or Desktop)
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
│   ├── 09-uefi-pxe-setup.sh # UEFI PXE support (Generation 2 VMs)
│   └── config.sh           # Configuration variables
├── artifacts/              # Generated files (excluded from git)
│   ├── iso/               # ISO storage directory
│   ├── tftp/              # TFTP root directory
│   └── http/              # HTTP root directory
└── docs/                   # Additional documentation
    └── troubleshooting.md  # Common issues and solutions
```

## Current Implementation Status

### ✅ Completed Scripts:
- **01-prerequisites.sh** - System validation and requirements checking
- **02-packages.sh** - Package installation with verification 
- **03-tftp-setup.sh** - TFTP server configuration and PXE boot files
- **04-dhcp-setup.sh** - DHCP server (local/external modes) with PXE options
- **05-nfs-setup.sh** - NFS server for serving installation media
- **06-http-setup.sh** - HTTP server configuration (nginx)
- **07-pxe-menu.sh** - PXE boot menu creation with professional interface
- **08-iso-manager.sh** - ISO management and mounting utilities with automatic PXE integration
- **09-uefi-pxe-setup.sh** - UEFI PXE support for Generation 2 VMs

### 📋 Core Services Status:
- ✅ **TFTP Server** (tftpd-hpa) - Serving PXE boot files
- ✅ **DHCP Server** (isc-dhcp-server) - Network boot configuration  
- ✅ **NFS Server** (nfs-kernel-server) - Installation media serving
- ✅ **HTTP Server** (nginx) - Web-based installations and configs

## Preparation Steps

### Install Required Packages

Before setting up the PXE server, install the necessary packages on your Ubuntu 24.04 system:

```bash
sudo apt update && \
  sudo apt install -y git wget curl net-tools build-essential nmap ipcalc
```

### Download Ubuntu ISO

Download the Ubuntu 24.04.3 LTS Server ISO that will be used for network installations:

```bash
mkdir -p $HOME/Downloads
cd ~/Downloads
wget https://mirrors.egr.msu.edu/ubuntu-iso/24.04.3/ubuntu-24.04.3-live-server-amd64.iso
```

**Note:** This ISO will be added to the PXE server using the `08-iso-manager.sh` script after the initial setup is complete.

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
# Basic installation (prompts for DHCP configuration)
sudo ./install.sh

# Full installation with UEFI support and local DHCP
sudo ./install.sh --uefi --local-dhcp

# Installation for external DHCP server
sudo ./install.sh --external-dhcp

# View all options
sudo ./install.sh --help
```

Or run individual scripts in order:

```bash
cd scripts
sudo ./01-prerequisites.sh
sudo ./02-packages.sh
sudo ./03-tftp-setup.sh
sudo ./04-dhcp-setup.sh
sudo ./05-nfs-setup.sh
sudo ./06-http-setup.sh
sudo ./07-pxe-menu.sh
sudo ./09-uefi-pxe-setup.sh  # Optional: for Generation 2 VM support
# Add ISOs with: sudo ./08-iso-manager.sh add <iso-file>
```

### UEFI Support (Generation 2 VMs)

For modern UEFI systems and Generation 2 VMs, run the UEFI setup script:

```bash
sudo ./scripts/09-uefi-pxe-setup.sh
```

This script:
- Installs GRUB EFI bootloader (`bootx64.efi`)
- Configures DHCP for automatic client architecture detection
- Creates GRUB menu for UEFI boot
- Enables both BIOS (Generation 1) and UEFI (Generation 2) VM support

## Rerun and Resetup -- Repeated here for ISO Download and ALL the Steps...

```shell
# download the ISO
mkdir -p $HOME/Downloads
cd ~/Downloads
wget https://mirrors.egr.msu.edu/ubuntu-iso/24.04.3/ubuntu-24.04.3-live-server-amd64.iso

# just run the cleanup twice -- not 100% sure what the issue is but looks like a race condition...
# this should be the directory you cloned to and just pulled
cd pxe-server-setup
sudo ./scripts/99-cleanup.sh
sudo ./scripts/99-cleanup.sh

# now run the main install.sh
sudo ./install.sh --uefi --local-dhcp

# now add the ISO to bootloader
sudo ./scripts/08-iso-manager.sh add $HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso
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

### Virtual Machine Support

The PXE server supports both BIOS and UEFI network booting:

#### Hyper-V Virtual Machines

**Generation 1 VMs (BIOS PXE)**:
- Uses SYSLINUX boot loader (`pxelinux.0`)
- Full featured menu with diagnostic tools
- Configured automatically during initial setup

**Generation 2 VMs (UEFI PXE)**:
- Uses GRUB EFI boot loader (`bootx64.efi`)
- Simplified GRUB menu interface
- Requires additional UEFI setup:

```bash
sudo ./scripts/09-uefi-pxe-setup.sh
```

**VM Configuration Requirements**:
- **Network**: Connect to same virtual switch as PXE server
- **Boot Order**: Network Adapter first, Hard Drive second
- **Generation 2**: Secure Boot must be **disabled**
- **DHCP Range**: Client will receive IP in 10.1.1.100-200

#### Other Hypervisors

The PXE server works with any hypervisor supporting standard PXE network boot:
- **VMware**: Enable "Boot from Network" in VM settings
- **VirtualBox**: Set Network Adapter to first boot device
- **QEMU/KVM**: Use `-boot n` for network boot priority

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

# 5. Validate PXE server components
./scripts/validate-pxe.sh
```

### PXE Server Validation

Use the validation script to check the status of all PXE server components:

```bash
# Quick validation of all services
./scripts/validate-pxe.sh

# Check individual services
systemctl status tftpd-hpa isc-dhcp-server nfs-kernel-server

# Test network connectivity
ping 10.1.1.1
showmount -e 10.1.1.1
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
systemctl status tftpd-hpa isc-dhcp-server nfs-kernel-server nginx

# View service logs
sudo journalctl -u tftpd-hpa -f    # TFTP logs
sudo journalctl -u isc-dhcp-server -f  # DHCP logs
sudo journalctl -u nginx -f        # HTTP logs
sudo journalctl -u nfs-kernel-server -f  # NFS logs

# Restart services
sudo systemctl restart tftpd-hpa
sudo systemctl restart isc-dhcp-server
sudo systemctl restart nginx
sudo systemctl restart nfs-kernel-server
```

### Script Reference

| Script | Purpose | Prerequisites | Key Features |
|--------|---------|---------------|--------------|
| `01-prerequisites.sh` | System validation | Root access | ✅ OS version, disk space, network validation |
| `02-packages.sh` | Package installation | Prerequisites passed | ✅ Service installation & verification |
| `03-tftp-setup.sh` | TFTP server setup | Packages installed | ✅ PXE boot files, service configuration |
| `04-dhcp-setup.sh` | DHCP configuration | Network config set | ✅ Local/external modes, PXE options |
| `05-nfs-setup.sh` | NFS server setup | Network config set | ✅ ISO serving, directory structure |
| `06-http-setup.sh` | HTTP server setup | NFS configured | 🚧 Web installations, configs |
| `07-pxe-menu.sh` | PXE menu creation | HTTP configured | 🚧 Boot menu, ISO integration |
| `08-iso-manager.sh` | ISO management | All services ready | 🚧 Add/remove/list ISOs |
| `09-uefi-pxe-setup.sh` | UEFI PXE support | TFTP & DHCP ready | ✅ Generation 2 VM, GRUB EFI |
| `validate-pxe.sh` | System validation | Any time | ✅ Service status, connectivity tests |

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

### DHCP Server Configuration

The PXE server supports both local DHCP and integration with existing network DHCP servers:

#### Local DHCP Server

```bash
# Configure local DHCP server (creates ISC DHCP server)
sudo ./scripts/04-dhcp-setup.sh --local

# Check DHCP service status
sudo systemctl status isc-dhcp-server

# Monitor DHCP requests and leases
sudo journalctl -u isc-dhcp-server -f
sudo tail -f /var/lib/dhcp/dhcpd.leases

# Check DHCP configuration
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
```

**Local DHCP Features:**
- Automatic PXE boot options for BIOS and UEFI clients
- Architecture-specific boot file selection
- Configurable IP range and lease times
- Integration with PXE server IP settings
- Support for static reservations

#### External DHCP Server

```bash
# Configure for existing network DHCP
sudo ./scripts/04-dhcp-setup.sh --external

# Run DHCP validation check
sudo /usr/local/bin/pxe-dhcp-check
```

**Required DHCP Options for External Server:**
- **Option 66** (TFTP Server Name): `10.1.1.1`
- **Option 67** (Boot Filename): `pxelinux.0` (BIOS) or `bootx64.efi` (UEFI)
- **Next Server**: `10.1.1.1`

**External DHCP Examples:**

*Windows DHCP Server:*
```
1. Open DHCP Management Console
2. Configure Scope Options:
   - Option 066: 10.1.1.1
   - Option 067: pxelinux.0
3. Restart DHCP service
```

*pfSense DHCP:*
```
Services → DHCP Server → Network booting:
- Next Server: 10.1.1.1
- Default BIOS file: pxelinux.0
- UEFI 64 bit file: bootx64.efi
```

*ISC DHCP (dhcpd.conf):*
```bash
subnet 10.1.1.0 netmask 255.255.255.0 {
    next-server 10.1.1.1;
    option tftp-server-name "10.1.1.1";
    filename "pxelinux.0";
}
```

**Troubleshooting DHCP:**
```bash
# Test DHCP lease renewal
sudo dhclient -r eth0 && sudo dhclient eth0

# Monitor DHCP traffic
sudo tcpdump -i eth0 port 67 or port 68

# Check for DHCP conflicts (if nmap available)
sudo nmap --script broadcast-dhcp-discover

# Verify PXE options
sudo dhcping -c 10.1.1.1 -s 10.1.1.1
```

### NFS Server Configuration

The NFS server provides installation media and files to PXE clients during the boot and installation process:

```bash
# Configure NFS server for serving ISO files
sudo ./scripts/05-nfs-setup.sh

# Check NFS service status
sudo systemctl status nfs-kernel-server rpcbind

# View NFS exports
sudo exportfs -v
showmount -e 10.1.1.1

# Monitor NFS activity
sudo journalctl -u nfs-kernel-server -f
nfsstat -s
```

**NFS Features:**
- Serves installation media from `/srv/nfs/iso/`
- Supports kickstart/preseed configs in `/srv/nfs/kickstart/` and `/srv/nfs/preseed/`
- Network-restricted access (10.1.1.0/24 only)
- Read-only mounts for security
- Automated service startup and verification

**NFS Directory Structure:**
```
/srv/nfs/
├── iso/          (mounted ISO files for installation)
├── kickstart/    (Red Hat/CentOS automated install configs)
├── preseed/      (Debian/Ubuntu automated install configs)
└── scripts/      (post-installation scripts)
```

**Testing NFS:**
```bash
# Test NFS mount from PXE server
mkdir /tmp/nfs_test
sudo mount -t nfs 10.1.1.1:/srv/nfs/iso /tmp/nfs_test
ls -la /tmp/nfs_test
sudo umount /tmp/nfs_test

# Check NFS exports
sudo exportfs -v

# Validate PXE server components
./scripts/validate-pxe.sh
```

**Troubleshooting NFS:**
```bash
# Check NFS ports
sudo ss -tlpn | grep :2049  # NFS
sudo ss -ulpn | grep :111   # RPC portmapper

# Test NFS connectivity
rpcinfo -p 10.1.1.1

# Check export permissions
sudo exportfs -ra  # Re-export all
sudo showmount -e localhost

# NFS service logs
sudo journalctl -u nfs-kernel-server -n 50
sudo journalctl -u rpcbind -n 20
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
# Download ISO (latest 24.04.03 recommended)
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso

# Add to PXE server
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04.3-live-server-amd64.iso
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

**Version**: 1.1.0  
**Last Updated**: 2024  
**Tested On**: Ubuntu 24.04 LTS (including 24.04.03)
