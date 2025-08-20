#!/bin/bash
# 99-cleanup.sh
# Complete cleanup script to remove all PXE server configurations and files
# This script returns the system to a clean state before PXE setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== PXE Server Complete Cleanup ==="
echo "This script will completely remove all PXE server configurations and files."
echo "WARNING: This action cannot be undone!"
echo

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo -e "${YELLOW}This will remove:${NC}"
    echo "  • All TFTP server files and configuration"
    echo "  • All DHCP server configuration"
    echo "  • All NFS exports and mounts (including iso-direct)"
    echo "  • All HTTP/nginx PXE configuration"
    echo "  • All GRUB UEFI boot files"
    echo "  • All ISO files and extracted content"
    echo "  • All service configurations"
    echo "  • All artifacts and generated files"
    echo
    echo -e "${RED}Are you sure you want to proceed? This cannot be undone.${NC}"
    read -p "Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
}

# Function to stop and disable services
stop_services() {
    echo -e "${BLUE}Stopping and disabling PXE services...${NC}"
    
    local services=("tftpd-hpa" "isc-dhcp-server" "nfs-kernel-server" "nginx" "apache2")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -n "  Stopping $service... "
            if systemctl stop "$service" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}Warning${NC}"
            fi
        fi
        
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            echo -n "  Disabling $service... "
            if systemctl disable "$service" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}Warning${NC}"
            fi
        fi
    done
}

# Function to clean TFTP configuration
cleanup_tftp() {
    echo -e "${BLUE}Cleaning TFTP configuration...${NC}"
    
    # Remove TFTP root directory
    if [[ -d "/var/lib/tftpboot" ]]; then
        echo -n "  Removing TFTP root directory... "
        rm -rf /var/lib/tftpboot/*
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Reset TFTP configuration
    if [[ -f "/etc/default/tftpd-hpa" ]]; then
        echo -n "  Resetting TFTP configuration... "
        cat > /etc/default/tftpd-hpa << 'EOF'
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
EOF
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Remove any TFTP systemd overrides
    if [[ -d "/etc/systemd/system/tftpd-hpa.service.d" ]]; then
        echo -n "  Removing TFTP systemd overrides... "
        rm -rf /etc/systemd/system/tftpd-hpa.service.d
        echo -e "${GREEN}OK${NC}"
    fi
}

# Function to clean DHCP configuration
cleanup_dhcp() {
    echo -e "${BLUE}Cleaning DHCP configuration...${NC}"
    
    # Remove DHCP configuration
    if [[ -f "/etc/dhcp/dhcpd.conf" ]]; then
        echo -n "  Removing DHCP configuration... "
        rm -f /etc/dhcp/dhcpd.conf
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Reset DHCP defaults
    if [[ -f "/etc/default/isc-dhcp-server" ]]; then
        echo -n "  Resetting DHCP defaults... "
        cat > /etc/default/isc-dhcp-server << 'EOF'
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)

# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
#DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
#DHCPDv6_CONF=/etc/dhcp/dhcpd6.conf

# Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
#DHCPDv4_PID=/var/run/dhcpd.pid
#DHCPDv6_PID=/var/run/dhcpd6.pid

# Additional options to start dhcpd with.
#	Don't use options -cf or -pf here; use DHCPD_CONF/ DHCPD_PID instead
#OPTIONS=""

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
#	Separate multiple interfaces with spaces, e.g. "eth0 eth1".
INTERFACESv4=""
INTERFACESv6=""
EOF
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Remove DHCP leases
    if [[ -f "/var/lib/dhcp/dhcpd.leases" ]]; then
        echo -n "  Removing DHCP leases... "
        rm -f /var/lib/dhcp/dhcpd.leases*
        echo -e "${GREEN}OK${NC}"
    fi
}

# Function to clean NFS configuration
cleanup_nfs() {
    echo -e "${BLUE}Cleaning NFS configuration...${NC}"
    
    # Unmount any mounted ISOs
    echo -n "  Unmounting ISO files... "
    local unmount_count=0
    while IFS= read -r mount_point; do
        if umount "$mount_point" 2>/dev/null; then
            ((unmount_count++))
        fi
    done < <(mount | grep "/srv/nfs/iso" | awk '{print $3}')
    echo -e "${GREEN}$unmount_count unmounted${NC}"
    
    # Remove NFS exports
    if [[ -f "/etc/exports" ]]; then
        echo -n "  Cleaning NFS exports... "
        # Remove PXE-related exports
        sed -i '/\/srv\/nfs/d' /etc/exports
        sed -i '/\/var\/www\/html\/pxe\/iso-direct/d' /etc/exports
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Remove NFS directories
    if [[ -d "/srv/nfs" ]]; then
        echo -n "  Removing NFS directories... "
        rm -rf /srv/nfs
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Remove from fstab
    if [[ -f "/etc/fstab" ]]; then
        echo -n "  Cleaning /etc/fstab... "
        sed -i '/\/srv\/nfs/d' /etc/fstab
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Reload NFS exports
    if command -v exportfs >/dev/null 2>&1; then
        echo -n "  Reloading NFS exports... "
        exportfs -ra 2>/dev/null || true
        echo -e "${GREEN}OK${NC}"
    fi
}

# Function to clean HTTP configuration
cleanup_http() {
    echo -e "${BLUE}Cleaning HTTP configuration...${NC}"
    
    # Remove nginx PXE configuration
    local nginx_configs=(
        "/etc/nginx/sites-available/pxe-server"
        "/etc/nginx/sites-enabled/pxe-server"
    )
    
    for config in "${nginx_configs[@]}"; do
        if [[ -f "$config" ]]; then
            echo -n "  Removing $(basename "$config")... "
            rm -f "$config"
            echo -e "${GREEN}OK${NC}"
        fi
    done
    
    # Remove Apache PXE configuration
    local apache_configs=(
        "/etc/apache2/sites-available/pxe-server.conf"
        "/etc/apache2/sites-enabled/pxe-server.conf"
    )
    
    for config in "${apache_configs[@]}"; do
        if [[ -f "$config" ]]; then
            echo -n "  Removing $(basename "$config")... "
            rm -f "$config"
            echo -e "${GREEN}OK${NC}"
        fi
    done
    
    # Remove PXE web directories
    local web_dirs=(
        "/var/www/html/pxe"
        "/var/www/pxe"
    )
    
    for dir in "${web_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo -n "  Removing $(basename "$dir") web directory... "
            rm -rf "$dir"
            echo -e "${GREEN}OK${NC}"
        fi
    done
    
    # Remove any lingering iso-direct mounts
    echo -n "  Unmounting iso-direct files... "
    local unmount_count=0
    while IFS= read -r mount_point; do
        if umount "$mount_point" 2>/dev/null; then
            ((unmount_count++))
        fi
    done < <(mount | grep "/var/www/html/pxe/iso-direct" | awk '{print $3}')
    if [[ $unmount_count -gt 0 ]]; then
        echo -e "${GREEN}$unmount_count unmounted${NC}"
    else
        echo -e "${GREEN}none found${NC}"
    fi
}

# Function to clean GRUB/UEFI configuration
cleanup_grub() {
    echo -e "${BLUE}Cleaning GRUB/UEFI configuration...${NC}"
    
    # Remove GRUB network boot files
    local grub_files=(
        "/var/lib/tftpboot/bootx64.efi"
        "/var/lib/tftpboot/grub"
        "/var/lib/tftpboot/efi64"
    )
    
    for item in "${grub_files[@]}"; do
        if [[ -e "$item" ]]; then
            echo -n "  Removing $(basename "$item")... "
            rm -rf "$item"
            echo -e "${GREEN}OK${NC}"
        fi
    done
}

# Function to clean artifacts and generated files
cleanup_artifacts() {
    echo -e "${BLUE}Cleaning artifacts and generated files...${NC}"
    
    # Remove project artifacts
    if [[ -d "$PROJECT_ROOT/artifacts" ]]; then
        echo -n "  Removing project artifacts... "
        rm -rf "$PROJECT_ROOT/artifacts"
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Remove backup directories
    local backup_dirs=(
        "/root/pxe-backups"
        "/tmp/pxe-*"
    )
    
    for pattern in "${backup_dirs[@]}"; do
        for dir in $pattern; do
            if [[ -d "$dir" ]]; then
                echo -n "  Removing backup $(basename "$dir")... "
                rm -rf "$dir"
                echo -e "${GREEN}OK${NC}"
            fi
        done
    done
    
    # Remove any lingering temp files
    echo -n "  Cleaning temporary files... "
    rm -f /tmp/pxe_* /tmp/grub_* /tmp/*pxe* 2>/dev/null || true
    echo -e "${GREEN}OK${NC}"
}

# Function to clean network configuration
cleanup_network() {
    echo -e "${BLUE}Cleaning network configuration...${NC}"
    
    # Note: We don't automatically remove static IP configuration
    # as it might be needed for other purposes
    echo -e "${YELLOW}  Note: Static IP configuration not removed${NC}"
    echo "  You may need to manually reconfigure network if desired:"
    echo "    sudo nano /etc/netplan/01-netcfg.yaml"
    echo "    sudo netplan apply"
}

# Function to reload systemd and clean up
final_cleanup() {
    echo -e "${BLUE}Final cleanup...${NC}"
    
    # Reload systemd daemon
    echo -n "  Reloading systemd daemon... "
    systemctl daemon-reload
    echo -e "${GREEN}OK${NC}"
    
    # Reset any failed services
    echo -n "  Resetting failed services... "
    systemctl reset-failed 2>/dev/null || true
    echo -e "${GREEN}OK${NC}"
}

# Function to display cleanup summary
show_summary() {
    echo
    echo -e "${GREEN}=== Cleanup Complete ===${NC}"
    echo "All PXE server configurations and files have been removed."
    echo
    echo -e "${BLUE}Services Status:${NC}"
    local services=("tftpd-hpa" "isc-dhcp-server" "nfs-kernel-server" "nginx")
    for service in "${services[@]}"; do
        local status
        if systemctl is-active "$service" >/dev/null 2>&1; then
            status="${RED}running${NC}"
        else
            status="${GREEN}stopped${NC}"
        fi
        echo "  $service: $status"
    done
    
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Run: sudo ./scripts/01-prerequisites.sh"
    echo "2. Configure: cp scripts/config.sh.example scripts/config.sh"
    echo "3. Edit: nano scripts/config.sh"
    echo "4. Install: sudo ./install.sh"
    echo
    echo -e "${YELLOW}Note: Network configuration was preserved.${NC}"
    echo "Review and adjust network settings if needed."
}

# Main execution
main() {
    check_root
    confirm_cleanup
    
    echo
    echo "Starting cleanup process..."
    echo "Date: $(date)"
    echo
    
    stop_services
    cleanup_tftp
    cleanup_dhcp
    cleanup_nfs
    cleanup_http
    cleanup_grub
    cleanup_artifacts
    cleanup_network
    final_cleanup
    
    show_summary
}

# Run main function
main "$@"
