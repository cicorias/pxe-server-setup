#!/bin/bash
# 02-packages.sh
# Package installation for PXE server setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if it exists
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo -e "${RED}Error: config.sh not found.${NC}"
    echo "Please copy config.sh.example to config.sh and configure your settings:"
    echo "  cp $SCRIPT_DIR/config.sh.example $SCRIPT_DIR/config.sh"
    echo "  nano $SCRIPT_DIR/config.sh"
    echo
    echo "Required network settings must be configured before installing packages."
    exit 1
fi

# Validate required network configuration
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "SUBNET" "NETMASK" "GATEWAY")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required network configuration variables in config.sh:${NC}"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo
    echo "Please edit $SCRIPT_DIR/config.sh and set all required network variables."
    exit 1
fi

echo "=== PXE Server Package Installation ==="

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to update package lists
update_packages() {
    echo -e "${BLUE}Updating package lists...${NC}"
    if apt update; then
        echo -e "${GREEN}Package lists updated successfully${NC}"
    else
        echo -e "${RED}Failed to update package lists${NC}"
        exit 1
    fi
}

# Function to upgrade existing packages
upgrade_packages() {
    echo -e "${BLUE}Upgrading existing packages...${NC}"
    echo "This may take several minutes..."
    
    # Use DEBIAN_FRONTEND=noninteractive to avoid prompts
    if DEBIAN_FRONTEND=noninteractive apt upgrade -y; then
        echo -e "${GREEN}System packages upgraded successfully${NC}"
    else
        echo -e "${YELLOW}Warning: Some packages failed to upgrade${NC}"
        echo "Continuing with installation..."
    fi
}

# Function to install core packages
install_core_packages() {
    echo -e "${BLUE}Installing core system packages...${NC}"
    
    local core_packages=(
        "curl"              # For downloading files
        "wget"              # Alternative download tool
        "unzip"             # For extracting archives
        "rsync"             # For file synchronization
        "tree"              # For directory listing
        "htop"              # System monitoring
        "net-tools"         # Network utilities (netstat, etc.)
        "iproute2"          # Modern network utilities
        "iptables"          # Firewall rules
        "systemd"           # Service management
        "git"               # Version control
        "build-essential"   # Essential packages for building software
        "nmap"              # Network exploration tool and security/port scanner
        "ipcalc"            # IP address calculator
    )
    
    echo "Installing: ${core_packages[*]}"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${core_packages[@]}"; then
        echo -e "${GREEN}Core packages installed successfully${NC}"
    else
        echo -e "${RED}Failed to install core packages${NC}"
        exit 1
    fi
}

# Function to install TFTP server
install_tftp_server() {
    echo -e "${BLUE}Installing TFTP server...${NC}"
    
    local tftp_packages=(
        "tftpd-hpa"         # TFTP server daemon
        "tftp-hpa"          # TFTP client for testing
        "grub-efi-amd64"    # GRUB EFI bootloader for UEFI PXE
        "grub-efi-amd64-signed" # Signed GRUB EFI bootloader
    )
    
    echo "Installing: ${tftp_packages[*]}"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${tftp_packages[@]}"; then
        echo -e "${GREEN}TFTP server installed successfully${NC}"
        
        # Check service status
        echo -n "Checking TFTP service status... "
        if systemctl is-enabled tftpd-hpa >/dev/null 2>&1; then
            echo -e "${GREEN}Enabled${NC}"
        else
            echo -e "${YELLOW}Disabled (will be configured later)${NC}"
        fi
    else
        echo -e "${RED}Failed to install TFTP server${NC}"
        exit 1
    fi
}

# Function to install NFS server
install_nfs_server() {
    echo -e "${BLUE}Installing NFS server...${NC}"
    
    local nfs_packages=(
        "nfs-kernel-server" # NFS kernel server
        "nfs-common"        # NFS common utilities
        "rpcbind"           # RPC port mapper
    )
    
    echo "Installing: ${nfs_packages[*]}"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${nfs_packages[@]}"; then
        echo -e "${GREEN}NFS server installed successfully${NC}"
        
        # Check service status
        echo -n "Checking NFS service status... "
        if systemctl is-enabled nfs-kernel-server >/dev/null 2>&1; then
            echo -e "${GREEN}Enabled${NC}"
        else
            echo -e "${YELLOW}Disabled (will be configured later)${NC}"
        fi
    else
        echo -e "${RED}Failed to install NFS server${NC}"
        exit 1
    fi
}

# Function to install HTTP server
install_http_server() {
    echo -e "${BLUE}Installing HTTP server ($HTTP_SERVICE)...${NC}"
    
    case "$HTTP_SERVICE" in
        "apache2")
            local http_packages=("apache2")
            ;;
        "nginx")
            local http_packages=("nginx")
            ;;
        *)
            echo -e "${RED}Error: Unsupported HTTP service: $HTTP_SERVICE${NC}"
            echo "Supported options: apache2, nginx"
            exit 1
            ;;
    esac
    
    echo "Installing: ${http_packages[*]}"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${http_packages[@]}"; then
        echo -e "${GREEN}HTTP server ($HTTP_SERVICE) installed successfully${NC}"
        
        # Check service status
        echo -n "Checking HTTP service status... "
        if systemctl is-enabled "$HTTP_SERVICE" >/dev/null 2>&1; then
            echo -e "${GREEN}Enabled${NC}"
        else
            echo -e "${YELLOW}Disabled (will be configured later)${NC}"
        fi
        
        # Start the service if not running
        if ! systemctl is-active "$HTTP_SERVICE" >/dev/null 2>&1; then
            echo "Starting $HTTP_SERVICE service..."
            systemctl start "$HTTP_SERVICE"
        fi
    else
        echo -e "${RED}Failed to install HTTP server${NC}"
        exit 1
    fi
}

# Function to install DHCP server (optional)
install_dhcp_server() {
    echo -e "${BLUE}Installing DHCP server (optional)...${NC}"
    
    local dhcp_packages=(
        "isc-dhcp-server"   # ISC DHCP server
    )
    
    echo "Installing: ${dhcp_packages[*]}"
    echo "Note: DHCP server will be configured only if local DHCP mode is selected"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${dhcp_packages[@]}"; then
        echo -e "${GREEN}DHCP server installed successfully${NC}"
        
        # Stop and disable by default - will be configured later if needed
        echo "Stopping and disabling DHCP service (will be enabled if local DHCP is configured)..."
        systemctl stop isc-dhcp-server 2>/dev/null || true
        systemctl disable isc-dhcp-server 2>/dev/null || true
    else
        echo -e "${RED}Failed to install DHCP server${NC}"
        exit 1
    fi
}

# Function to install DNS server (optional)
install_dns_server() {
    echo -e "${BLUE}Installing DNS server (optional)...${NC}"
    
    local dns_packages=(
        "bind9"             # BIND9 DNS server
        "bind9utils"        # BIND9 utilities
        "bind9-dnsutils"    # DNS utilities (dig, nslookup, etc.)
    )
    
    echo "Installing: ${dns_packages[*]}"
    echo "Note: DNS server will be configured to provide local name resolution"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${dns_packages[@]}"; then
        echo -e "${GREEN}DNS server installed successfully${NC}"
        
        # Stop and disable by default - will be configured later if needed
        echo "Stopping and disabling DNS service (will be enabled after configuration)..."
        systemctl stop bind9 2>/dev/null || true
        systemctl disable bind9 2>/dev/null || true
    else
        echo -e "${RED}Failed to install DNS server${NC}"
        exit 1
    fi
}

# Note: Syslinux/PXELINUX packages removed - UEFI-only PXE server uses GRUB2

# Function to install additional utilities
install_utilities() {
    echo -e "${BLUE}Installing additional utilities...${NC}"
    
    local utility_packages=(
        "p7zip-full"        # 7zip archive support
        "genisoimage"       # ISO creation tools
        "squashfs-tools"    # SquashFS filesystem tools
        "cpio"              # Archive utility
        "xorriso"           # ISO manipulation
        "dosfstools"        # FAT filesystem tools
    )
    
    echo "Installing: ${utility_packages[*]}"
    
    if DEBIAN_FRONTEND=noninteractive apt install -y "${utility_packages[@]}"; then
        echo -e "${GREEN}Additional utilities installed successfully${NC}"
    else
        echo -e "${YELLOW}Warning: Some additional utilities failed to install${NC}"
        echo "Core PXE functionality should still work"
    fi
}

# Function to clean up package cache
cleanup_packages() {
    echo -e "${BLUE}Cleaning up package cache...${NC}"
    
    if apt autoremove -y && apt autoclean; then
        echo -e "${GREEN}Package cleanup completed${NC}"
    else
        echo -e "${YELLOW}Warning: Package cleanup had some issues${NC}"
    fi
}

# Function to verify all installations
verify_installations() {
    echo -e "${BLUE}Verifying package installations...${NC}"
    
    echo "Service status:"
    
    # Use systemctl status instead of list-unit-files
    echo -n "  TFTP server... "
    if systemctl status tftpd-hpa >/dev/null 2>&1 || systemctl list-unit-files tftpd-hpa.service >/dev/null 2>&1; then
        echo -e "${GREEN}Installed${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi
    
    echo -n "  NFS server... "
    if systemctl status nfs-server >/dev/null 2>&1 || systemctl list-unit-files nfs-server.service >/dev/null 2>&1; then
        echo -e "${GREEN}Installed${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi
    
    echo -n "  HTTP server... "
    if systemctl status nginx >/dev/null 2>&1 || systemctl list-unit-files nginx.service >/dev/null 2>&1; then
        echo -e "${GREEN}Installed${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi
    
    echo -n "  DHCP server... "
    if systemctl status isc-dhcp-server >/dev/null 2>&1 || systemctl list-unit-files isc-dhcp-server.service >/dev/null 2>&1; then
        echo -e "${GREEN}Installed${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi
    
    echo
    echo "Key files and commands:"
    
    # Check ISO creation command
    echo -n "  ISO creation (mkisofs)... "
    if command -v "mkisofs" >/dev/null 2>&1; then
        echo -e "${GREEN}Available${NC}"
    else
        echo -e "${YELLOW}Missing${NC}"
    fi
    
    # Check file synchronization command
    echo -n "  File synchronization (rsync)... "
    if command -v "rsync" >/dev/null 2>&1; then
        echo -e "${GREEN}Available${NC}"
    else
        echo -e "${YELLOW}Missing${NC}"
    fi
    
    # Check archive extraction command
    echo -n "  Archive extraction (7z)... "
    if command -v "7z" >/dev/null 2>&1; then
        echo -e "${GREEN}Available${NC}"
    else
        echo -e "${YELLOW}Missing${NC}"
    fi
}

# Function to display next steps
show_next_steps() {
    echo
    echo -e "${GREEN}=== Package installation completed successfully! ===${NC}"
    echo
    echo "Installed services:"
    echo "  - TFTP Server (tftpd-hpa)"
    echo "  - NFS Server (nfs-kernel-server)"
    echo "  - HTTP Server ($HTTP_SERVICE)"
    echo "  - DHCP Server (isc-dhcp-server) - disabled by default"
    echo "  - GRUB2 EFI (for UEFI-only PXE boot)"
    echo
    echo "Next steps:"
    echo "1. Configure network settings: sudo ./03-tftp-setup.sh"
    echo "2. Set up DHCP (if needed): sudo ./04-dhcp-setup.sh --local"
    echo "3. Configure NFS: sudo ./05-nfs-setup.sh"
    echo "4. Set up HTTP server: sudo ./06-http-setup.sh"
    echo "5. Create PXE menu: sudo ./07-pxe-menu.sh"
    echo "6. Add ISO files: sudo ./08-iso-manager.sh add <iso-file>"
    echo
    echo "Or run all remaining steps: sudo ../install.sh (from scripts directory)"
    echo
}

# Main execution
main() {
    echo "Starting package installation for PXE server setup..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo

    check_root
    update_packages
    upgrade_packages
    install_core_packages
    install_tftp_server
    install_nfs_server
    install_http_server
    install_dhcp_server
    install_dns_server
    install_utilities
    cleanup_packages
    verify_installations
    show_next_steps
}

# Run main function
main "$@"
