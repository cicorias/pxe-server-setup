#!/bin/bash
# 03-tftp-setup.sh
# TFTP server configuration for PXE server setup

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
    echo "Required network settings must be configured before setting up TFTP."
    exit 1
fi

# Validate required network configuration
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "SUBNET" "NETMASK" "GATEWAY" "TFTP_ROOT")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required configuration variables in config.sh:${NC}"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo
    echo "Please edit $SCRIPT_DIR/config.sh and set all required variables."
    exit 1
fi

echo "=== TFTP Server Configuration ==="

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to backup existing configuration
backup_config() {
    echo -n "Backing up existing TFTP configuration... "
    local backup_dir="/root/pxe-backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -f /etc/default/tftpd-hpa ]]; then
        cp /etc/default/tftpd-hpa "$backup_dir/"
    fi
    
    if [[ -d "$TFTP_ROOT" ]]; then
        cp -r "$TFTP_ROOT" "$backup_dir/tftpboot_backup" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}OK${NC}"
    echo "  Backup location: $backup_dir"
}

# Function to configure TFTP server
configure_tftp() {
    echo -e "${BLUE}Configuring TFTP server...${NC}"
    
    # Stop TFTP service if running
    echo -n "Stopping TFTP service... "
    systemctl stop tftpd-hpa 2>/dev/null || true
    echo -e "${GREEN}OK${NC}"
    
    # Create TFTP root directory
    echo -n "Creating TFTP root directory ($TFTP_ROOT)... "
    mkdir -p "$TFTP_ROOT"
    chmod 755 "$TFTP_ROOT"
    chown tftp:tftp "$TFTP_ROOT" 2>/dev/null || chown nobody:nogroup "$TFTP_ROOT"
    echo -e "${GREEN}OK${NC}"
    
    # Configure TFTP daemon
    echo -n "Configuring TFTP daemon settings... "
    cat > /etc/default/tftpd-hpa << EOF
# /etc/default/tftpd-hpa
# Configuration for TFTP server for PXE boot

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="$TFTP_ROOT"
TFTP_ADDRESS="$PXE_SERVER_IP:69"
TFTP_OPTIONS="--secure --create --verbose"

# PXE Server Configuration
# TFTP_DIRECTORY: Root directory for TFTP files
# TFTP_ADDRESS: IP address and port to bind to
# TFTP_OPTIONS: 
#   --secure: Change root to TFTP_DIRECTORY for security
#   --create: Allow file creation (for some PXE operations)
#   --verbose: Enable verbose logging
EOF
    echo -e "${GREEN}OK${NC}"
    
    # Create basic directory structure
    echo -n "Creating TFTP directory structure... "
    mkdir -p "$TFTP_ROOT/pxelinux.cfg"
    mkdir -p "$TFTP_ROOT/images"
    mkdir -p "$TFTP_ROOT/boot"
    echo -e "${GREEN}OK${NC}"
    
    # Copy PXE boot files
    echo -n "Installing PXE boot files... "
    if [[ -f /usr/lib/PXELINUX/pxelinux.0 ]]; then
        cp /usr/lib/PXELINUX/pxelinux.0 "$TFTP_ROOT/"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: pxelinux.0 not found. Ensure syslinux is installed."
        exit 1
    fi
    
    # Copy syslinux modules
    local syslinux_modules=(
        "menu.c32"
        "vesamenu.c32" 
        "ldlinux.c32"
        "libcom32.c32"
        "libutil.c32"
    )
    
    for module in "${syslinux_modules[@]}"; do
        if [[ -f "/usr/lib/syslinux/modules/bios/$module" ]]; then
            cp "/usr/lib/syslinux/modules/bios/$module" "$TFTP_ROOT/"
        fi
    done
    echo -e "${GREEN}OK${NC}"
    
    # Create test file for verification
    echo -n "Creating test file for verification... "
    echo "PXE TFTP Server Test File - $(date)" > "$TFTP_ROOT/test.txt"
    echo "Server IP: $PXE_SERVER_IP" >> "$TFTP_ROOT/test.txt"
    echo "TFTP Root: $TFTP_ROOT" >> "$TFTP_ROOT/test.txt"
    chmod 644 "$TFTP_ROOT/test.txt"
    echo -e "${GREEN}OK${NC}"
    
    # Set proper permissions
    echo -n "Setting TFTP directory permissions... "
    chown -R tftp:tftp "$TFTP_ROOT" 2>/dev/null || chown -R nobody:nogroup "$TFTP_ROOT"
    find "$TFTP_ROOT" -type d -exec chmod 755 {} \;
    find "$TFTP_ROOT" -type f -exec chmod 644 {} \;
    echo -e "${GREEN}OK${NC}"
}

# Function to create symbolic links to artifacts
create_artifact_links() {
    echo -e "${BLUE}Creating links to artifacts directory...${NC}"
    
    # Link to artifacts TFTP directory
    local artifacts_tftp="$ARTIFACTS_DIR/tftp"
    mkdir -p "$artifacts_tftp"
    
    echo -n "Linking artifacts/tftp to TFTP root... "
    if [[ ! -L "$artifacts_tftp/live" ]]; then
        ln -sf "$TFTP_ROOT" "$artifacts_tftp/live"
    fi
    
    # Copy key configuration files to artifacts for easier management
    if [[ ! -d "$artifacts_tftp/pxelinux.cfg" ]]; then
        cp -r "$TFTP_ROOT/pxelinux.cfg" "$artifacts_tftp/"
    fi
    echo -e "${GREEN}OK${NC}"
}

# Function to start and enable TFTP service
start_tftp_service() {
    echo -e "${BLUE}Starting TFTP service...${NC}"
    
    # Reload systemd configuration
    echo -n "Reloading systemd configuration... "
    systemctl daemon-reload
    echo -e "${GREEN}OK${NC}"
    
    # Enable TFTP service
    echo -n "Enabling TFTP service... "
    systemctl enable tftpd-hpa
    echo -e "${GREEN}OK${NC}"
    
    # Start TFTP service
    echo -n "Starting TFTP service... "
    if systemctl start tftpd-hpa; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: Failed to start TFTP service"
        echo "Check logs with: journalctl -u tftpd-hpa"
        exit 1
    fi
    
    # Check service status
    echo -n "Checking TFTP service status... "
    if systemctl is-active tftpd-hpa >/dev/null 2>&1; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
        echo "Service status:"
        systemctl status tftpd-hpa --no-pager -l
        exit 1
    fi
}

# Function to verify TFTP service
verify_tftp_service() {
    echo -e "${BLUE}Verifying TFTP service...${NC}"
    
    # Check if TFTP port is listening
    echo -n "Checking TFTP port (69/UDP)... "
    if netstat -ulpn 2>/dev/null | grep -q ":69 "; then
        echo -e "${GREEN}Listening${NC}"
    else
        echo -e "${RED}Not listening${NC}"
        echo "TFTP service may not be properly configured"
        exit 1
    fi
    
    # Test TFTP client connection
    echo -n "Testing TFTP client connection... "
    
    # Install tftp client if not available
    if ! command -v tftp >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing TFTP client...${NC}"
        apt update >/dev/null 2>&1
        apt install -y tftp-hpa >/dev/null 2>&1
    fi
    
    # Create a temporary directory for testing
    local test_dir=$(mktemp -d)
    cd "$test_dir"
    
    # Test TFTP get operation
    if timeout 10 tftp "$PXE_SERVER_IP" -c get test.txt 2>/dev/null; then
        if [[ -f "test.txt" ]] && grep -q "PXE TFTP Server Test File" test.txt; then
            echo -e "${GREEN}Success${NC}"
            echo "  Retrieved test file successfully"
        else
            echo -e "${YELLOW}Partial${NC}"
            echo "  File retrieved but content verification failed"
        fi
    else
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not retrieve test file via TFTP"
        echo "Troubleshooting steps:"
        echo "1. Check firewall settings: ufw status"
        echo "2. Check TFTP logs: journalctl -u tftpd-hpa"
        echo "3. Verify network interface: ip addr show $NETWORK_INTERFACE"
        
        # Cleanup and exit
        cd /
        rm -rf "$test_dir"
        exit 1
    fi
    
    # Test file listing (if supported)
    echo -n "Testing TFTP directory listing... "
    if timeout 5 bash -c "echo 'ls' | tftp $PXE_SERVER_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}Supported${NC}"
    else
        echo -e "${YELLOW}Not supported${NC} (this is normal)"
    fi
    
    # Cleanup test directory
    cd /
    rm -rf "$test_dir"
    
    echo
    echo -e "${GREEN}TFTP service verification completed successfully!${NC}"
}

# Function to show configuration summary
show_summary() {
    echo
    echo -e "${GREEN}=== TFTP Configuration Summary ===${NC}"
    echo "TFTP Root Directory: $TFTP_ROOT"
    echo "TFTP Server Address: $PXE_SERVER_IP:69"
    echo "Service Status: $(systemctl is-active tftpd-hpa)"
    echo "Service Enabled: $(systemctl is-enabled tftpd-hpa)"
    echo
    echo "Configuration file: /etc/default/tftpd-hpa"
    echo "Log files: journalctl -u tftpd-hpa"
    echo
    echo "Test TFTP manually:"
    echo "  tftp $PXE_SERVER_IP"
    echo "  get test.txt"
    echo "  quit"
    echo
    echo "Next steps:"
    echo "1. Configure DHCP: sudo ./04-dhcp-setup.sh --local"
    echo "2. Set up NFS: sudo ./05-nfs-setup.sh"
    echo "3. Configure HTTP: sudo ./06-http-setup.sh"
    echo
}

# Function to show firewall configuration help
show_firewall_help() {
    echo -e "${BLUE}Firewall Configuration Help:${NC}"
    echo
    echo "If UFW firewall is enabled, you may need to allow TFTP traffic:"
    echo "  sudo ufw allow 69/udp comment 'TFTP for PXE'"
    echo "  sudo ufw reload"
    echo
    echo "For other firewalls, ensure port 69/UDP is open for incoming connections."
    echo
}

# Main execution
main() {
    echo "Starting TFTP server configuration for PXE setup..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo "Server IP: $PXE_SERVER_IP"
    echo "TFTP Root: $TFTP_ROOT"
    echo

    check_root
    backup_config
    configure_tftp
    create_artifact_links
    start_tftp_service
    verify_tftp_service
    show_summary
    
    # Check if firewall is active and show help
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        show_firewall_help
    fi
}

# Run main function
main "$@"
