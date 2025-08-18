#!/bin/bash
# 08-iso-manager.sh
# ISO management and PXE menu integration for PXE server setup

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

# Source configuration if it exists
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo -e "${RED}Error: config.sh not found.${NC}"
    echo "Please copy config.sh.example to config.sh and configure your settings:"
    echo "  cp $SCRIPT_DIR/config.sh.example $SCRIPT_DIR/config.sh"
    echo "  nano $SCRIPT_DIR/config.sh"
    echo
    echo "Required network settings must be configured before managing ISOs."
    exit 1
fi

# Validate required configuration
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "TFTP_ROOT" "NFS_ROOT" "HTTP_ROOT")
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

# Define paths
ISO_STORAGE_DIR="$PROJECT_ROOT/artifacts/iso"
NFS_ISO_DIR="$NFS_ROOT/iso"
HTTP_ISO_DIR="$HTTP_ROOT/iso"
TFTP_KERNELS_DIR="$TFTP_ROOT/kernels"
TFTP_INITRD_DIR="$TFTP_ROOT/initrd"
PXE_MENU_FILE="$TFTP_ROOT/pxelinux.cfg/default"
MOUNT_BASE_DIR="/mnt/pxe-iso"

# Usage function
usage() {
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  add <iso-file>      Add ISO file to PXE server"
    echo "  remove <iso-name>   Remove ISO from PXE server"
    echo "  list                List all available ISOs"
    echo "  status              Show ISO and service status"
    echo "  validate            Validate ISO configuration"
    echo "  cleanup             Clean up orphaned files"
    echo
    echo "Examples:"
    echo "  $0 add /path/to/ubuntu-24.04-server.iso"
    echo "  $0 add ubuntu-24.04-server.iso  # if in current directory"
    echo "  $0 remove ubuntu-24.04-server"
    echo "  $0 list"
    echo "  $0 status"
    echo
    echo "Supported ISO types:"
    echo "  - Ubuntu Server/Desktop (20.04+)"
    echo "  - Debian (11+)"
    echo "  - CentOS/RHEL (8+)"
    echo "  - Rocky Linux/AlmaLinux"
    echo "  - Custom Linux distributions"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to create necessary directories
create_directories() {
    local dirs=(
        "$ISO_STORAGE_DIR"
        "$NFS_ISO_DIR"
        "$HTTP_ISO_DIR"
        "$TFTP_KERNELS_DIR"
        "$TFTP_INITRD_DIR"
        "$MOUNT_BASE_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Set proper ownership for service directories
    chown -R tftp:tftp "$TFTP_KERNELS_DIR" "$TFTP_INITRD_DIR"
    chown -R www-data:www-data "$HTTP_ISO_DIR"
}

# Function to detect ISO type and extract distribution info
detect_iso_info() {
    local iso_file="$1"
    local mount_point="$2"
    local iso_info_file="$3"
    
    echo -n "Detecting ISO type and version... "
    
    # Initialize variables
    local distro=""
    local version=""
    local arch=""
    local release_name=""
    local kernel_path=""
    local initrd_path=""
    local boot_params=""
    
    # Mount ISO to analyze
    if ! mount -o loop,ro "$iso_file" "$mount_point" 2>/dev/null; then
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not mount ISO file"
        return 1
    fi
    
    # Ubuntu detection
    if [[ -f "$mount_point/.disk/info" ]]; then
        local disk_info
        disk_info=$(cat "$mount_point/.disk/info")
        
        if [[ $disk_info =~ Ubuntu.*Server ]]; then
            distro="ubuntu-server"
            if [[ $disk_info =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            if [[ $disk_info =~ (amd64|i386|arm64) ]]; then
                arch="${BASH_REMATCH[1]}"
            fi
            release_name="Ubuntu Server $version"
            
            # Ubuntu kernel and initrd paths
            if [[ -f "$mount_point/casper/vmlinuz" ]]; then
                kernel_path="casper/vmlinuz"
                initrd_path="casper/initrd"
                boot_params="boot=casper url=http://$PXE_SERVER_IP/iso/##ISO_NAME##/ ip=dhcp"
            fi
            
        elif [[ $disk_info =~ Ubuntu.*Desktop ]]; then
            distro="ubuntu-desktop"
            if [[ $disk_info =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            if [[ $disk_info =~ (amd64|i386|arm64) ]]; then
                arch="${BASH_REMATCH[1]}"
            fi
            release_name="Ubuntu Desktop $version"
            
            # Ubuntu Desktop kernel and initrd paths
            if [[ -f "$mount_point/casper/vmlinuz" ]]; then
                kernel_path="casper/vmlinuz"
                initrd_path="casper/initrd"
                boot_params="boot=casper url=http://$PXE_SERVER_IP/iso/##ISO_NAME##/ ip=dhcp quiet splash"
            fi
        fi
        
    # Debian detection
    elif [[ -f "$mount_point/.disk/info" ]] && grep -q "Debian" "$mount_point/.disk/info"; then
        distro="debian"
        local disk_info
        disk_info=$(cat "$mount_point/.disk/info")
        if [[ $disk_info =~ ([0-9]+(\.[0-9]+)*) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
        if [[ $disk_info =~ (amd64|i386|arm64) ]]; then
            arch="${BASH_REMATCH[1]}"
        fi
        release_name="Debian $version"
        
        # Debian kernel and initrd paths
        if [[ -f "$mount_point/install/vmlinuz" ]]; then
            kernel_path="install/vmlinuz"
            initrd_path="install/initrd.gz"
            boot_params="url=http://$PXE_SERVER_IP/iso/##ISO_NAME##/ ip=dhcp"
        fi
        
    # CentOS/RHEL detection
    elif [[ -f "$mount_point/.discinfo" ]] || [[ -f "$mount_point/media.repo" ]]; then
        if [[ -f "$mount_point/media.repo" ]]; then
            local media_info
            media_info=$(cat "$mount_point/media.repo")
            
            if [[ $media_info =~ CentOS ]]; then
                distro="centos"
                if [[ $media_info =~ ([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                fi
                release_name="CentOS $version"
            elif [[ $media_info =~ "Red Hat" ]]; then
                distro="rhel"
                if [[ $media_info =~ ([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                fi
                release_name="Red Hat Enterprise Linux $version"
            elif [[ $media_info =~ "Rocky" ]]; then
                distro="rocky"
                if [[ $media_info =~ ([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                fi
                release_name="Rocky Linux $version"
            elif [[ $media_info =~ "AlmaLinux" ]]; then
                distro="alma"
                if [[ $media_info =~ ([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                fi
                release_name="AlmaLinux $version"
            fi
        fi
        
        # Red Hat family kernel and initrd paths
        if [[ -f "$mount_point/images/pxeboot/vmlinuz" ]]; then
            kernel_path="images/pxeboot/vmlinuz"
            initrd_path="images/pxeboot/initrd.img"
            boot_params="inst.repo=http://$PXE_SERVER_IP/iso/##ISO_NAME##/ ip=dhcp"
        fi
        
        # Try to detect architecture from directory structure
        if [[ -d "$mount_point/images/pxeboot" ]]; then
            arch="x86_64"  # Most common for server ISOs
        fi
    fi
    
    # Fallback: try to extract info from filename
    if [[ -z "$distro" ]]; then
        local filename
        filename=$(basename "$iso_file")
        
        if [[ $filename =~ ubuntu.*([0-9]+\.[0-9]+) ]]; then
            distro="ubuntu"
            version="${BASH_REMATCH[1]}"
            release_name="Ubuntu $version"
        elif [[ $filename =~ debian.*([0-9]+(\.[0-9]+)*) ]]; then
            distro="debian"
            version="${BASH_REMATCH[1]}"
            release_name="Debian $version"
        elif [[ $filename =~ centos.*([0-9]+(\.[0-9]+)*) ]]; then
            distro="centos"
            version="${BASH_REMATCH[1]}"
            release_name="CentOS $version"
        else
            distro="unknown"
            version="unknown"
            release_name="Unknown Linux Distribution"
        fi
        
        # Try to detect architecture from filename
        if [[ $filename =~ (amd64|x86_64|i386|i686|arm64|aarch64) ]]; then
            arch="${BASH_REMATCH[1]}"
        fi
    fi
    
    # Normalize architecture names
    case "$arch" in
        "x86_64"|"amd64") arch="x86_64" ;;
        "i386"|"i686") arch="i386" ;;
        "aarch64"|"arm64") arch="arm64" ;;
        *) arch="${arch:-x86_64}" ;;
    esac
    
    # Write ISO information to file
    cat > "$iso_info_file" << EOF
DISTRO="$distro"
VERSION="$version"
ARCH="$arch"
RELEASE_NAME="$release_name"
KERNEL_PATH="$kernel_path"
INITRD_PATH="$initrd_path"
BOOT_PARAMS="$boot_params"
EOF
    
    umount "$mount_point"
    echo -e "${GREEN}$release_name ($arch)${NC}"
    
    return 0
}

# Function to extract kernel and initrd from ISO
extract_boot_files() {
    local iso_file="$1"
    local iso_name="$2"
    local mount_point="$3"
    local iso_info_file="$4"
    
    echo -e "${BLUE}Extracting boot files...${NC}"
    
    # Source ISO information
    source "$iso_info_file"
    
    if [[ -z "$KERNEL_PATH" || -z "$INITRD_PATH" ]]; then
        echo -e "${YELLOW}Warning: Boot file paths not detected, skipping kernel extraction${NC}"
        return 0
    fi
    
    # Mount ISO
    echo -n "Mounting ISO for boot file extraction... "
    if ! mount -o loop,ro "$iso_file" "$mount_point" 2>/dev/null; then
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not mount ISO file"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
    
    # Create ISO-specific directories
    local kernel_dir="$TFTP_KERNELS_DIR/$iso_name"
    local initrd_dir="$TFTP_INITRD_DIR/$iso_name"
    
    mkdir -p "$kernel_dir" "$initrd_dir"
    
    # Extract kernel
    echo -n "Extracting kernel... "
    if [[ -f "$mount_point/$KERNEL_PATH" ]]; then
        cp "$mount_point/$KERNEL_PATH" "$kernel_dir/vmlinuz"
        chown tftp:tftp "$kernel_dir/vmlinuz"
        chmod 644 "$kernel_dir/vmlinuz"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Not found: $KERNEL_PATH${NC}"
        umount "$mount_point"
        return 1
    fi
    
    # Extract initrd
    echo -n "Extracting initrd... "
    if [[ -f "$mount_point/$INITRD_PATH" ]]; then
        cp "$mount_point/$INITRD_PATH" "$initrd_dir/initrd"
        chown tftp:tftp "$initrd_dir/initrd"
        chmod 644 "$initrd_dir/initrd"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Not found: $INITRD_PATH${NC}"
        umount "$mount_point"
        return 1
    fi
    
    umount "$mount_point"
    
    echo "Boot files extracted to:"
    echo "  Kernel: $kernel_dir/vmlinuz"
    echo "  Initrd: $initrd_dir/initrd"
    
    return 0
}

# Function to create NFS and HTTP access to ISO
setup_iso_access() {
    local iso_file="$1"
    local iso_name="$2"
    local mount_point="$3"
    
    echo -e "${BLUE}Setting up ISO access...${NC}"
    
    # Create permanent mount point
    local iso_mount_dir="$NFS_ISO_DIR/$iso_name"
    mkdir -p "$iso_mount_dir"
    
    # Add to /etc/fstab for persistent mounting
    echo -n "Adding to /etc/fstab... "
    local fstab_entry="$iso_file $iso_mount_dir iso9660 loop,ro,auto 0 0"
    
    # Remove existing entry if present
    sed -i "\|$iso_mount_dir|d" /etc/fstab
    
    # Add new entry
    echo "$fstab_entry" >> /etc/fstab
    echo -e "${GREEN}OK${NC}"
    
    # Mount the ISO
    echo -n "Mounting ISO at $iso_mount_dir... "
    if mount "$iso_mount_dir"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not mount ISO"
        return 1
    fi
    
    # Create HTTP symbolic link
    echo -n "Creating HTTP access link... "
    local http_link="$HTTP_ISO_DIR/$iso_name"
    if [[ -L "$http_link" ]]; then
        rm "$http_link"
    fi
    ln -s "$iso_mount_dir" "$http_link"
    chown -h www-data:www-data "$http_link"
    echo -e "${GREEN}OK${NC}"
    
    # Update NFS exports
    echo -n "Updating NFS exports... "
    local export_line="$iso_mount_dir $SUBNET/$NETMASK(ro,sync,no_subtree_check,no_root_squash)"
    
    # Remove existing export if present
    sed -i "\|$iso_mount_dir|d" /etc/exports
    
    # Add new export
    echo "$export_line" >> /etc/exports
    
    # Reload NFS exports
    if exportfs -ra; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Could not reload NFS exports${NC}"
    fi
    
    echo "ISO access configured:"
    echo "  NFS: $iso_mount_dir"
    echo "  HTTP: http://$PXE_SERVER_IP/iso/$iso_name/"
    
    return 0
}

# Function to update PXE menu
update_pxe_menu() {
    local iso_name="$1"
    local iso_info_file="$2"
    
    echo -e "${BLUE}Updating PXE boot menu...${NC}"
    
    # Source ISO information
    source "$iso_info_file"
    
    # Create menu entry
    local menu_label="$iso_name"
    local menu_title="$RELEASE_NAME"
    local kernel_path="/kernels/$iso_name/vmlinuz"
    local initrd_path="/initrd/$iso_name/initrd"
    local boot_params_updated="${BOOT_PARAMS//##ISO_NAME##/$iso_name}"
    
    # Generate PXE menu entry
    local menu_entry="
LABEL $menu_label
    MENU LABEL $menu_title
    KERNEL $kernel_path
    APPEND initrd=$initrd_path $boot_params_updated
    TEXT HELP
    Install $RELEASE_NAME via network installation.
    Architecture: $ARCH
    ISO: $iso_name
    ENDTEXT
"
    
    # Backup current menu
    cp "$PXE_MENU_FILE" "$PXE_MENU_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Find the insertion point (before the final ISO placeholder)
    local temp_file="/tmp/pxe_menu_temp.$$"
    
    # Read the current menu and add the new entry
    echo -n "Adding menu entry for $menu_title... "
    
    # Insert the new entry before the placeholder comment
    if grep -q "# ISO entries will be automatically added here" "$PXE_MENU_FILE"; then
        sed "/# ISO entries will be automatically added here/i\\$menu_entry" "$PXE_MENU_FILE" > "$temp_file"
        mv "$temp_file" "$PXE_MENU_FILE"
    else
        # If no placeholder found, append to end
        echo "$menu_entry" >> "$PXE_MENU_FILE"
    fi
    
    # Set proper ownership
    chown tftp:tftp "$PXE_MENU_FILE"
    chmod 644 "$PXE_MENU_FILE"
    
    echo -e "${GREEN}OK${NC}"
    
    # Restart TFTP service to reload menu
    echo -n "Restarting TFTP service... "
    if systemctl restart tftpd-hpa; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Could not restart TFTP service${NC}"
    fi
    
    echo "PXE menu updated with new entry: $menu_title"
    
    return 0
}

# Function to add ISO
add_iso() {
    local iso_path="$1"
    
    # Validate input
    if [[ -z "$iso_path" ]]; then
        echo -e "${RED}Error: ISO file path required${NC}"
        usage
        exit 1
    fi
    
    # Resolve full path
    if [[ ! "$iso_path" =~ ^/ ]]; then
        iso_path="$(pwd)/$iso_path"
    fi
    
    # Check if file exists
    if [[ ! -f "$iso_path" ]]; then
        echo -e "${RED}Error: ISO file not found: $iso_path${NC}"
        exit 1
    fi
    
    # Check if it's an ISO file
    if ! file "$iso_path" | grep -q "ISO 9660"; then
        echo -e "${RED}Error: File does not appear to be an ISO image${NC}"
        exit 1
    fi
    
    local iso_filename
    iso_filename=$(basename "$iso_path")
    local iso_name="${iso_filename%.iso}"
    
    echo "=== Adding ISO: $iso_filename ==="
    echo "Date: $(date)"
    echo "Source: $iso_path"
    echo "Name: $iso_name"
    echo
    
    # Check if ISO already exists
    if [[ -f "$ISO_STORAGE_DIR/$iso_filename" ]]; then
        echo -e "${YELLOW}Warning: ISO already exists in storage${NC}"
        read -p "Overwrite existing ISO? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            exit 0
        fi
        
        # Remove existing ISO first
        echo "Removing existing ISO..."
        remove_iso "$iso_name" --quiet
    fi
    
    # Create directories
    create_directories
    
    # Copy ISO to storage
    echo -n "Copying ISO to storage directory... "
    if cp "$iso_path" "$ISO_STORAGE_DIR/"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not copy ISO file"
        exit 1
    fi
    
    local stored_iso="$ISO_STORAGE_DIR/$iso_filename"
    local mount_point="$MOUNT_BASE_DIR/$iso_name"
    local iso_info_file="$ISO_STORAGE_DIR/${iso_name}.info"
    
    mkdir -p "$mount_point"
    
    # Detect ISO information
    if ! detect_iso_info "$stored_iso" "$mount_point" "$iso_info_file"; then
        echo "Error: Could not analyze ISO file"
        rm -f "$stored_iso"
        exit 1
    fi
    
    # Extract boot files
    if ! extract_boot_files "$stored_iso" "$iso_name" "$mount_point" "$iso_info_file"; then
        echo "Error: Could not extract boot files"
        rm -f "$stored_iso" "$iso_info_file"
        exit 1
    fi
    
    # Setup NFS and HTTP access
    if ! setup_iso_access "$stored_iso" "$iso_name" "$mount_point" "$iso_info_file"; then
        echo "Error: Could not setup ISO access"
        rm -f "$stored_iso" "$iso_info_file"
        exit 1
    fi
    
    # Update PXE menu
    if ! update_pxe_menu "$iso_name" "$iso_info_file"; then
        echo "Error: Could not update PXE menu"
        exit 1
    fi
    
    echo
    echo -e "${GREEN}=== ISO Successfully Added ===${NC}"
    echo "ISO: $iso_filename"
    echo "Name: $iso_name"
    echo "Storage: $stored_iso"
    echo "NFS Mount: $NFS_ISO_DIR/$iso_name"
    echo "HTTP URL: http://$PXE_SERVER_IP/iso/$iso_name/"
    echo "PXE Menu: Updated with new boot option"
    echo
    echo "The ISO is now available for network installation."
    echo "Test with: tftp $PXE_SERVER_IP -c get pxelinux.cfg/default"
    
    return 0
}

# Function to remove ISO
remove_iso() {
    local iso_name="$1"
    local quiet_mode="$2"
    
    if [[ -z "$iso_name" ]]; then
        echo -e "${RED}Error: ISO name required${NC}"
        usage
        exit 1
    fi
    
    # Remove .iso extension if provided
    iso_name="${iso_name%.iso}"
    
    if [[ "$quiet_mode" != "--quiet" ]]; then
        echo "=== Removing ISO: $iso_name ==="
        echo "Date: $(date)"
        echo
    fi
    
    local iso_file="$ISO_STORAGE_DIR/${iso_name}.iso"
    local iso_info_file="$ISO_STORAGE_DIR/${iso_name}.info"
    local iso_mount_dir="$NFS_ISO_DIR/$iso_name"
    local http_link="$HTTP_ISO_DIR/$iso_name"
    local kernel_dir="$TFTP_KERNELS_DIR/$iso_name"
    local initrd_dir="$TFTP_INITRD_DIR/$iso_name"
    
    # Check if ISO exists
    if [[ ! -f "$iso_file" && ! -d "$iso_mount_dir" ]]; then
        echo -e "${RED}Error: ISO '$iso_name' not found${NC}"
        exit 1
    fi
    
    # Unmount if mounted
    if mountpoint -q "$iso_mount_dir" 2>/dev/null; then
        echo -n "Unmounting ISO... "
        if umount "$iso_mount_dir" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Warning: Could not unmount${NC}"
        fi
    fi
    
    # Remove from /etc/fstab
    echo -n "Removing from /etc/fstab... "
    sed -i "\|$iso_mount_dir|d" /etc/fstab
    echo -e "${GREEN}OK${NC}"
    
    # Remove from NFS exports
    echo -n "Removing from NFS exports... "
    sed -i "\|$iso_mount_dir|d" /etc/exports
    if exportfs -ra 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning${NC}"
    fi
    
    # Remove files and directories
    echo -n "Removing files... "
    rm -f "$iso_file" "$iso_info_file"
    rm -f "$http_link"
    rm -rf "$iso_mount_dir" "$kernel_dir" "$initrd_dir"
    echo -e "${GREEN}OK${NC}"
    
    # Remove from PXE menu
    echo -n "Updating PXE menu... "
    if [[ -f "$PXE_MENU_FILE" ]]; then
        # Create backup
        cp "$PXE_MENU_FILE" "$PXE_MENU_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove the menu entry (from LABEL to next LABEL or end)
        local temp_file="/tmp/pxe_menu_temp.$$"
        awk -v label="LABEL $iso_name" '
            $0 ~ "^LABEL " && $0 != label { print_block=1 }
            $0 == label { print_block=0 }
            print_block { print }
            $0 != label && $0 !~ "^LABEL " && print_block==1 { print }
        ' "$PXE_MENU_FILE" > "$temp_file"
        
        mv "$temp_file" "$PXE_MENU_FILE"
        chown tftp:tftp "$PXE_MENU_FILE"
        chmod 644 "$PXE_MENU_FILE"
        
        # Restart TFTP service
        systemctl restart tftpd-hpa 2>/dev/null
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Menu file not found${NC}"
    fi
    
    if [[ "$quiet_mode" != "--quiet" ]]; then
        echo
        echo -e "${GREEN}ISO '$iso_name' removed successfully${NC}"
    fi
    
    return 0
}

# Function to list ISOs
list_isos() {
    echo "=== Available ISOs ==="
    echo "Date: $(date)"
    echo
    
    if [[ ! -d "$ISO_STORAGE_DIR" ]] || [[ -z "$(ls -A "$ISO_STORAGE_DIR"/*.iso 2>/dev/null)" ]]; then
        echo "No ISOs found."
        echo
        echo "Add ISOs with: sudo $0 add <iso-file>"
        return 0
    fi
    
    local iso_count=0
    
    echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
    echo "│ ISO Name                  │ Distribution          │ Arch   │ Status             │"
    echo "├─────────────────────────────────────────────────────────────────────────────────┤"
    
    for iso_file in "$ISO_STORAGE_DIR"/*.iso; do
        if [[ -f "$iso_file" ]]; then
            local iso_filename
            iso_filename=$(basename "$iso_file")
            local iso_name="${iso_filename%.iso}"
            local iso_info_file="$ISO_STORAGE_DIR/${iso_name}.info"
            
            local distro="Unknown"
            local arch="Unknown"
            local release_name="Unknown"
            local status="Inactive"
            
            # Read ISO info if available
            if [[ -f "$iso_info_file" ]]; then
                source "$iso_info_file"
                distro="$RELEASE_NAME"
                arch="$ARCH"
            fi
            
            # Check if mounted and accessible
            local iso_mount_dir="$NFS_ISO_DIR/$iso_name"
            if mountpoint -q "$iso_mount_dir" 2>/dev/null; then
                status="Active"
            fi
            
            # Truncate long names for display
            local display_name="$iso_name"
            if [[ ${#display_name} -gt 24 ]]; then
                display_name="${display_name:0:21}..."
            fi
            
            local display_distro="$distro"
            if [[ ${#display_distro} -gt 20 ]]; then
                display_distro="${display_distro:0:17}..."
            fi
            
            printf "│ %-24s │ %-20s │ %-6s │ %-18s │\n" \
                "$display_name" "$display_distro" "$arch" "$status"
            
            ((iso_count++))
        fi
    done
    
    echo "└─────────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "Total ISOs: $iso_count"
    echo
    echo "Commands:"
    echo "  View details: sudo $0 status"
    echo "  Add new ISO: sudo $0 add <iso-file>"
    echo "  Remove ISO:  sudo $0 remove <iso-name>"
    
    return 0
}

# Function to show status
show_status() {
    echo "=== PXE Server ISO Status ==="
    echo "Date: $(date)"
    echo "Server: $PXE_SERVER_IP"
    echo
    
    # Service status
    echo -e "${BLUE}Service Status:${NC}"
    local services=("tftpd-hpa" "nfs-kernel-server" "nginx")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo "  ✅ $service: Running"
        else
            echo "  ❌ $service: Stopped"
        fi
    done
    echo
    
    # Directory status
    echo -e "${BLUE}Directory Status:${NC}"
    echo "  ISO Storage: $ISO_STORAGE_DIR"
    echo "  NFS Root: $NFS_ISO_DIR"
    echo "  HTTP Root: $HTTP_ISO_DIR"
    echo "  TFTP Kernels: $TFTP_KERNELS_DIR"
    echo "  TFTP Initrd: $TFTP_INITRD_DIR"
    echo
    
    # Mount status
    echo -e "${BLUE}Mounted ISOs:${NC}"
    local mount_count=0
    if [[ -d "$NFS_ISO_DIR" ]]; then
        for mount_dir in "$NFS_ISO_DIR"/*; do
            if [[ -d "$mount_dir" ]] && mountpoint -q "$mount_dir" 2>/dev/null; then
                local iso_name
                iso_name=$(basename "$mount_dir")
                echo "  📀 $iso_name: Mounted at $mount_dir"
                ((mount_count++))
            fi
        done
    fi
    
    if [[ $mount_count -eq 0 ]]; then
        echo "  No ISOs currently mounted"
    fi
    echo
    
    # NFS exports
    echo -e "${BLUE}NFS Exports:${NC}"
    if command -v exportfs >/dev/null 2>&1; then
        exportfs -v | grep "$NFS_ISO_DIR" || echo "  No ISO exports found"
    else
        echo "  NFS tools not available"
    fi
    echo
    
    # HTTP access
    echo -e "${BLUE}HTTP Access:${NC}"
    echo "  Base URL: http://$PXE_SERVER_IP/iso/"
    if [[ -d "$HTTP_ISO_DIR" ]]; then
        local http_count=0
        for link in "$HTTP_ISO_DIR"/*; do
            if [[ -L "$link" ]]; then
                local link_name
                link_name=$(basename "$link")
                echo "  🔗 http://$PXE_SERVER_IP/iso/$link_name/"
                ((http_count++))
            fi
        done
        
        if [[ $http_count -eq 0 ]]; then
            echo "  No HTTP links found"
        fi
    fi
    echo
    
    # Disk usage
    echo -e "${BLUE}Disk Usage:${NC}"
    if [[ -d "$ISO_STORAGE_DIR" ]]; then
        local storage_size
        storage_size=$(du -sh "$ISO_STORAGE_DIR" 2>/dev/null | cut -f1)
        echo "  ISO Storage: $storage_size ($ISO_STORAGE_DIR)"
    fi
    
    local tftp_size
    tftp_size=$(du -sh "$TFTP_ROOT" 2>/dev/null | cut -f1)
    echo "  TFTP Root: $tftp_size ($TFTP_ROOT)"
    echo
}

# Function to validate configuration
validate_configuration() {
    echo "=== PXE ISO Configuration Validation ==="
    echo "Date: $(date)"
    echo
    
    local errors=0
    local warnings=0
    
    # Check directories
    echo -e "${BLUE}Directory Checks:${NC}"
    local required_dirs=(
        "$ISO_STORAGE_DIR:ISO Storage"
        "$NFS_ISO_DIR:NFS Root"
        "$HTTP_ISO_DIR:HTTP Root"
        "$TFTP_KERNELS_DIR:TFTP Kernels"
        "$TFTP_INITRD_DIR:TFTP Initrd"
    )
    
    for dir_info in "${required_dirs[@]}"; do
        local dir_path="${dir_info%:*}"
        local dir_name="${dir_info#*:}"
        
        if [[ -d "$dir_path" ]]; then
            echo "  ✅ $dir_name: $dir_path"
        else
            echo "  ❌ $dir_name: $dir_path (missing)"
            ((errors++))
        fi
    done
    echo
    
    # Check services
    echo -e "${BLUE}Service Checks:${NC}"
    local required_services=("tftpd-hpa" "nfs-kernel-server" "nginx")
    
    for service in "${required_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo "  ✅ $service: Running"
        else
            echo "  ❌ $service: Not running"
            ((errors++))
        fi
    done
    echo
    
    # Check PXE menu
    echo -e "${BLUE}PXE Menu Checks:${NC}"
    if [[ -f "$PXE_MENU_FILE" ]]; then
        echo "  ✅ PXE Menu: $PXE_MENU_FILE"
        
        # Check if menu has ISO entries
        local iso_entries
        iso_entries=$(grep -c "^LABEL.*" "$PXE_MENU_FILE" 2>/dev/null || echo "0")
        echo "  📋 Menu Entries: $iso_entries"
        
    else
        echo "  ❌ PXE Menu: Not found"
        ((errors++))
    fi
    echo
    
    # Check ISO consistency
    echo -e "${BLUE}ISO Consistency Checks:${NC}"
    if [[ -d "$ISO_STORAGE_DIR" ]]; then
        local iso_files
        iso_files=($(ls "$ISO_STORAGE_DIR"/*.iso 2>/dev/null))
        
        for iso_file in "${iso_files[@]}"; do
            if [[ -f "$iso_file" ]]; then
                local iso_filename
                iso_filename=$(basename "$iso_file")
                local iso_name="${iso_filename%.iso}"
                
                # Check components
                local components_ok=true
                
                # Check mount
                if ! mountpoint -q "$NFS_ISO_DIR/$iso_name" 2>/dev/null; then
                    echo "  ⚠️  $iso_name: Not mounted"
                    components_ok=false
                    ((warnings++))
                fi
                
                # Check HTTP link
                if [[ ! -L "$HTTP_ISO_DIR/$iso_name" ]]; then
                    echo "  ⚠️  $iso_name: HTTP link missing"
                    components_ok=false
                    ((warnings++))
                fi
                
                # Check kernel files
                if [[ ! -f "$TFTP_KERNELS_DIR/$iso_name/vmlinuz" ]]; then
                    echo "  ⚠️  $iso_name: Kernel missing"
                    components_ok=false
                    ((warnings++))
                fi
                
                # Check initrd files
                if [[ ! -f "$TFTP_INITRD_DIR/$iso_name/initrd" ]]; then
                    echo "  ⚠️  $iso_name: Initrd missing"
                    components_ok=false
                    ((warnings++))
                fi
                
                if $components_ok; then
                    echo "  ✅ $iso_name: All components OK"
                fi
            fi
        done
    fi
    echo
    
    # Summary
    echo -e "${BLUE}Validation Summary:${NC}"
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo -e "  ${GREEN}✅ All checks passed${NC}"
    elif [[ $errors -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠️  $warnings warnings found${NC}"
    else
        echo -e "  ${RED}❌ $errors errors, $warnings warnings${NC}"
    fi
    
    return $errors
}

# Function to cleanup orphaned files
cleanup_orphaned() {
    echo "=== Cleanup Orphaned Files ==="
    echo "Date: $(date)"
    echo
    
    local cleaned=0
    
    # Find orphaned mounts
    echo -e "${BLUE}Checking for orphaned mounts:${NC}"
    if [[ -d "$NFS_ISO_DIR" ]]; then
        for mount_dir in "$NFS_ISO_DIR"/*; do
            if [[ -d "$mount_dir" ]]; then
                local iso_name
                iso_name=$(basename "$mount_dir")
                local iso_file="$ISO_STORAGE_DIR/${iso_name}.iso"
                
                if [[ ! -f "$iso_file" ]]; then
                    echo "  🧹 Orphaned mount: $mount_dir"
                    
                    # Unmount if mounted
                    if mountpoint -q "$mount_dir" 2>/dev/null; then
                        umount "$mount_dir" 2>/dev/null
                    fi
                    
                    # Remove directory
                    rmdir "$mount_dir" 2>/dev/null
                    ((cleaned++))
                fi
            fi
        done
    fi
    
    # Find orphaned HTTP links
    echo -e "${BLUE}Checking for orphaned HTTP links:${NC}"
    if [[ -d "$HTTP_ISO_DIR" ]]; then
        for link in "$HTTP_ISO_DIR"/*; do
            if [[ -L "$link" ]]; then
                local link_name
                link_name=$(basename "$link")
                local iso_file="$ISO_STORAGE_DIR/${link_name}.iso"
                
                if [[ ! -f "$iso_file" ]]; then
                    echo "  🧹 Orphaned HTTP link: $link"
                    rm "$link"
                    ((cleaned++))
                fi
            fi
        done
    fi
    
    # Find orphaned kernel/initrd directories
    echo -e "${BLUE}Checking for orphaned boot files:${NC}"
    for boot_dir in "$TFTP_KERNELS_DIR" "$TFTP_INITRD_DIR"; do
        if [[ -d "$boot_dir" ]]; then
            for iso_dir in "$boot_dir"/*; do
                if [[ -d "$iso_dir" ]]; then
                    local iso_name
                    iso_name=$(basename "$iso_dir")
                    local iso_file="$ISO_STORAGE_DIR/${iso_name}.iso"
                    
                    if [[ ! -f "$iso_file" ]]; then
                        echo "  🧹 Orphaned boot files: $iso_dir"
                        rm -rf "$iso_dir"
                        ((cleaned++))
                    fi
                fi
            done
        fi
    done
    
    # Clean /etc/fstab entries
    echo -e "${BLUE}Checking /etc/fstab entries:${NC}"
    local temp_fstab="/tmp/fstab.cleanup.$$"
    local fstab_cleaned=0
    
    while IFS= read -r line; do
        if [[ $line =~ $NFS_ISO_DIR/([^[:space:]]+) ]]; then
            local iso_name="${BASH_REMATCH[1]}"
            local iso_file="$ISO_STORAGE_DIR/${iso_name}.iso"
            
            if [[ ! -f "$iso_file" ]]; then
                echo "  🧹 Orphaned fstab entry: $line"
                ((fstab_cleaned++))
                continue
            fi
        fi
        echo "$line"
    done < /etc/fstab > "$temp_fstab"
    
    if [[ $fstab_cleaned -gt 0 ]]; then
        mv "$temp_fstab" /etc/fstab
        ((cleaned++))
    else
        rm "$temp_fstab"
    fi
    
    # Clean NFS exports
    echo -e "${BLUE}Checking NFS exports:${NC}"
    local temp_exports="/tmp/exports.cleanup.$$"
    local exports_cleaned=0
    
    while IFS= read -r line; do
        if [[ $line =~ $NFS_ISO_DIR/([^[:space:]]+) ]]; then
            local iso_name="${BASH_REMATCH[1]}"
            local iso_file="$ISO_STORAGE_DIR/${iso_name}.iso"
            
            if [[ ! -f "$iso_file" ]]; then
                echo "  🧹 Orphaned export entry: $line"
                ((exports_cleaned++))
                continue
            fi
        fi
        echo "$line"
    done < /etc/exports > "$temp_exports"
    
    if [[ $exports_cleaned -gt 0 ]]; then
        mv "$temp_exports" /etc/exports
        exportfs -ra 2>/dev/null
        ((cleaned++))
    else
        rm "$temp_exports"
    fi
    
    echo
    echo -e "${GREEN}Cleanup completed: $cleaned items cleaned${NC}"
    
    if [[ $cleaned -gt 0 ]]; then
        echo "Restarting services..."
        systemctl restart tftpd-hpa nfs-kernel-server 2>/dev/null
    fi
    
    return 0
}

# Main function
main() {
    case "${1:-}" in
        "add")
            check_root
            add_iso "${2:-}"
            ;;
        "remove")
            check_root
            remove_iso "${2:-}"
            ;;
        "list")
            list_isos
            ;;
        "status")
            show_status
            ;;
        "validate")
            validate_configuration
            ;;
        "cleanup")
            check_root
            cleanup_orphaned
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
