#!/bin/bash
# system-restore.sh
# System restore functionality for PXE server setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[RESTORE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[RESTORE]${NC} $1"
}

print_error() {
    echo -e "${RED}[RESTORE]${NC} $1"
}

print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}===================================${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check arguments
if [[ $# -lt 1 ]]; then
    print_error "Usage: $0 <backup_directory> [--dry-run]"
    print_status "Available backups:"
    ls -1 /tmp/pxe-backup-* 2>/dev/null || echo "  No backups found"
    exit 1
fi

BACKUP_DIR="$1"
DRY_RUN=false

if [[ "${2:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Validate backup directory
if [[ ! -d "$BACKUP_DIR" ]]; then
    print_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

if [[ ! -f "$BACKUP_DIR/manifest.txt" ]]; then
    print_error "Invalid backup directory (missing manifest): $BACKUP_DIR"
    exit 1
fi

# Function to restore a file
restore_file() {
    local backup_file="$1"
    local target_path="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$backup_file" ]]; then
            echo "[DRY RUN] Would restore: $backup_file -> $target_path"
        else
            echo "[DRY RUN] Would remove (was new): $target_path"
        fi
        return 0
    fi
    
    if [[ -f "$backup_file.new" ]]; then
        # File was created during installation, remove it
        if [[ -f "$target_path" ]]; then
            rm "$target_path"
            print_status "Removed new file: $target_path"
        fi
    elif [[ -f "$backup_file" ]]; then
        # Restore original file
        cp "$backup_file" "$target_path"
        print_status "Restored: $target_path"
    else
        print_warning "No backup found for: $target_path"
    fi
}

# Function to restore services
restore_services() {
    local services=("tftpd-hpa" "isc-dhcp-server" "nfs-kernel-server" "nginx" "apache2")
    
    print_status "Restoring service states..."
    
    for service in "${services[@]}"; do
        local enabled_file="$BACKUP_DIR/service-$service-enabled.state"
        local active_file="$BACKUP_DIR/service-$service-active.state"
        
        if [[ -f "$enabled_file" && -f "$active_file" ]]; then
            local was_enabled=$(cat "$enabled_file")
            local was_active=$(cat "$active_file")
            
            if [[ "$was_enabled" == "not-installed" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would note that $service was not originally installed"
                else
                    print_status "$service was not originally installed"
                fi
                continue
            fi
            
            # Stop service if it's running
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[DRY RUN] Would stop service: $service"
            else
                systemctl stop "$service" 2>/dev/null || true
            fi
            
            # Restore enabled state
            if [[ "$was_enabled" == "enabled" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would enable service: $service"
                else
                    systemctl enable "$service" 2>/dev/null || true
                fi
            else
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would disable service: $service"
                else
                    systemctl disable "$service" 2>/dev/null || true
                fi
            fi
            
            # Restore active state
            if [[ "$was_active" == "active" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would start service: $service"
                else
                    systemctl start "$service" 2>/dev/null || true
                    print_status "Restored service state: $service"
                fi
            fi
        fi
    done
}

# Function to remove installed packages (careful approach)
remove_packages() {
    print_warning "Package removal requires manual review"
    print_status "Original package state saved in: $BACKUP_DIR/packages-before.list"
    print_status "Current package state can be checked with: dpkg --get-selections"
    print_status ""
    print_status "To manually remove PXE-related packages, you can run:"
    print_status "  sudo apt remove tftpd-hpa isc-dhcp-server nfs-kernel-server nginx"
    print_status "  sudo apt autoremove"
    print_status ""
    print_status "WARNING: Only do this if you're sure these packages weren't needed before!"
}

# Function to clean up directories
cleanup_directories() {
    local dirs=(
        "/var/lib/tftpboot"
        "/srv/nfs"
        "/var/www/html/pxe"
    )
    
    print_status "Cleaning up created directories..."
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[DRY RUN] Would remove directory: $dir"
            else
                rm -rf "$dir"
                print_status "Removed directory: $dir"
            fi
        fi
    done
}

# Main restore process
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header "PXE Server Restore - DRY RUN MODE"
        print_warning "This is a dry run - no changes will be made to the system"
    else
        print_header "PXE Server Restore - Starting Restore"
        print_warning "This will restore your system to its previous state"
        echo ""
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Restore cancelled"
            exit 0
        fi
    fi
    
    echo ""
    print_status "Restoring from backup: $BACKUP_DIR"
    echo ""
    
    # Show manifest
    print_status "Backup manifest:"
    echo "----------------"
    cat "$BACKUP_DIR/manifest.txt"
    echo "----------------"
    echo ""
    
    # Stop services first
    print_status "Stopping PXE services..."
    if [[ "$DRY_RUN" != "true" ]]; then
        systemctl stop tftpd-hpa 2>/dev/null || true
        systemctl stop isc-dhcp-server 2>/dev/null || true
        systemctl stop nfs-kernel-server 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
    fi
    
    # Restore configuration files
    print_status "Restoring configuration files..."
    restore_file "$BACKUP_DIR/tftpd-hpa.conf" "/etc/default/tftpd-hpa"
    restore_file "$BACKUP_DIR/dhcpd.conf" "/etc/dhcp/dhcpd.conf"
    restore_file "$BACKUP_DIR/isc-dhcp-server.conf" "/etc/default/isc-dhcp-server"
    restore_file "$BACKUP_DIR/nginx-pxe.conf" "/etc/nginx/sites-available/pxe"
    restore_file "$BACKUP_DIR/nginx-pxe-enabled" "/etc/nginx/sites-enabled/pxe"
    restore_file "$BACKUP_DIR/exports" "/etc/exports"
    restore_file "$BACKUP_DIR/fstab" "/etc/fstab"
    
    # Restore services
    restore_services
    
    # Clean up directories
    cleanup_directories
    
    # Package information
    remove_packages
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header "Dry Run Complete!"
        print_status "The above steps show what would be done during restore."
        print_status "To perform the actual restore, run:"
        print_status "  sudo $0 $BACKUP_DIR"
    else
        print_header "Restore Complete!"
        print_status "System has been restored to its previous state."
        print_status "Backup files are still available at: $BACKUP_DIR"
        print_status ""
        print_status "You may need to:"
        print_status "1. Reboot the system to ensure all changes take effect"
        print_status "2. Manually remove any packages that were installed (see above)"
        print_status "3. Check that your original services are working correctly"
    fi
}

# Run main function
main