#!/bin/bash
# system-backup.sh
# System backup and restore functionality for PXE server setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/tmp/pxe-backup-$(date +%Y%m%d-%H%M%S)"

# Function to print status messages
print_status() {
    echo -e "${GREEN}[BACKUP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[BACKUP]${NC} $1"
}

print_error() {
    echo -e "${RED}[BACKUP]${NC} $1"
}

# Function to create backup directory
create_backup_dir() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would create backup directory: $BACKUP_DIR"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    print_status "Created backup directory: $BACKUP_DIR"
}

# Function to backup a file
backup_file() {
    local file_path="$1"
    local backup_name="${2:-$(basename "$file_path")}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        if [[ -f "$file_path" ]]; then
            echo "[DRY RUN] Would backup existing file: $file_path -> $BACKUP_DIR/$backup_name"
        else
            echo "[DRY RUN] File does not exist (no backup needed): $file_path"
        fi
        return 0
    fi
    
    if [[ -f "$file_path" ]]; then
        cp "$file_path" "$BACKUP_DIR/$backup_name"
        print_status "Backed up: $file_path"
    else
        echo "# File did not exist before installation" > "$BACKUP_DIR/$backup_name.new"
        print_status "Marked as new file: $file_path"
    fi
}

# Function to backup installed packages
backup_package_state() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would backup current package state"
        return 0
    fi
    
    print_status "Backing up package state..."
    dpkg --get-selections > "$BACKUP_DIR/packages-before.list"
    apt list --installed > "$BACKUP_DIR/apt-installed-before.list" 2>/dev/null
}

# Function to backup service states
backup_service_state() {
    local services=("tftpd-hpa" "isc-dhcp-server" "nfs-kernel-server" "nginx" "apache2")
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would backup service states for: ${services[*]}"
        return 0
    fi
    
    print_status "Backing up service states..."
    for service in "${services[@]}"; do
        if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
            systemctl is-enabled "$service" 2>/dev/null > "$BACKUP_DIR/service-$service-enabled.state" || echo "disabled" > "$BACKUP_DIR/service-$service-enabled.state"
            systemctl is-active "$service" 2>/dev/null > "$BACKUP_DIR/service-$service-active.state" || echo "inactive" > "$BACKUP_DIR/service-$service-active.state"
        else
            echo "not-installed" > "$BACKUP_DIR/service-$service-enabled.state"
            echo "not-installed" > "$BACKUP_DIR/service-$service-active.state"
        fi
    done
}

# Function to create installation manifest
create_manifest() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would create installation manifest"
        return 0
    fi
    
    cat > "$BACKUP_DIR/manifest.txt" << EOF
# PXE Server Installation Manifest
# Created: $(date)
# Backup Location: $BACKUP_DIR

## System Information
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
Kernel: $(uname -r)
Hostname: $(hostname)
User: $(whoami)

## Backup Contents
- Configuration files backed up before modification
- Package state before installation
- Service states before modification
- This manifest file

## To Restore
Run: sudo $SCRIPT_DIR/system-restore.sh "$BACKUP_DIR"

## Files that will be modified:
/etc/default/tftpd-hpa
/etc/dhcp/dhcpd.conf
/etc/default/isc-dhcp-server
/etc/nginx/sites-available/pxe
/etc/exports
/etc/fstab (for ISO mounts)

## Services that will be installed/configured:
- tftpd-hpa (TFTP server)
- isc-dhcp-server (DHCP server)
- nfs-kernel-server (NFS server)
- nginx (HTTP server)

## Directories that will be created:
/var/lib/tftpboot
/srv/nfs
/var/www/html/pxe
$SCRIPT_DIR/../artifacts/
EOF

    print_status "Created installation manifest: $BACKUP_DIR/manifest.txt"
    echo ""
    print_status "BACKUP LOCATION: $BACKUP_DIR"
    echo ""
}

# Function to perform full system backup
full_backup() {
    create_backup_dir
    
    # Backup configuration files that will be modified
    backup_file "/etc/default/tftpd-hpa" "tftpd-hpa.conf"
    backup_file "/etc/dhcp/dhcpd.conf" "dhcpd.conf"
    backup_file "/etc/default/isc-dhcp-server" "isc-dhcp-server.conf"
    backup_file "/etc/nginx/sites-available/pxe" "nginx-pxe.conf"
    backup_file "/etc/nginx/sites-enabled/pxe" "nginx-pxe-enabled"
    backup_file "/etc/exports" "exports"
    backup_file "/etc/fstab" "fstab"
    
    # Backup system state
    backup_package_state
    backup_service_state
    
    # Create manifest
    create_manifest
    
    # Output backup location for other scripts to use
    echo "$BACKUP_DIR" > "/tmp/pxe-current-backup.location"
}

# Main execution
case "${1:-backup}" in
    "backup")
        full_backup
        ;;
    "file")
        if [[ $# -lt 2 ]]; then
            print_error "Usage: $0 file <file_path> [backup_name]"
            exit 1
        fi
        backup_file "$2" "${3:-}"
        ;;
    *)
        print_error "Unknown command: $1"
        print_status "Available commands: backup, file"
        exit 1
        ;;
esac