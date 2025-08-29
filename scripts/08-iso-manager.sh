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
IMG_STORAGE_DIR="$PROJECT_ROOT/artifacts/img"
NFS_ISO_DIR="$NFS_ROOT/iso"
HTTP_ISO_DIR="$HTTP_ROOT/iso"
HTTP_ISO_DIRECT_DIR="$HTTP_ROOT/iso-direct"
HTTP_IMAGES_DIR="$HTTP_ROOT/images"
TFTP_KERNELS_DIR="$TFTP_ROOT/kernels"
TFTP_INITRD_DIR="$TFTP_ROOT/initrd"
GRUB_MENU_FILE="$TFTP_ROOT/grub/grub.cfg"
MOUNT_BASE_DIR="/mnt/pxe-iso"

# Usage function
usage() {
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  add <file>          Add ISO or IMG file to PXE server"
    echo "  remove <name>       Remove ISO/IMG from PXE server"
    echo "  list                List all available ISO/IMG files"
    echo "  status              Show ISO/IMG and service status"
    echo "  validate            Validate ISO/IMG configuration"
    echo "  cleanup             Clean up orphaned files"
    echo "  refresh             Refresh PXE menu entries from existing files"
    echo
    echo "Examples:"
    echo "  $0 add /path/to/ubuntu-24.04-server.iso"
    echo "  $0 add /path/to/ubuntu-24.04-server.img"
    echo "  $0 add ubuntu-24.04-server.iso  # if in current directory"
    echo "  $0 add ubuntu-24.04-server.img  # if in current directory"
    echo "  $0 remove ubuntu-24.04-server"
    echo "  $0 list"
    echo "  $0 status"
    echo "  $0 refresh"
    echo
    echo "Supported file types:"
    echo "  ISO files:"
    echo "    - Ubuntu Server/Desktop (20.04+)"
    echo "    - Debian (11+)"
    echo "    - CentOS/RHEL (8+)"
    echo "    - Rocky Linux/AlmaLinux"
    echo "    - Custom Linux distributions"
    echo "  IMG files:"
    echo "    - Filesystem images (ext4, ext3, ext2, xfs, btrfs)"
    echo "    - Disk images with partitions"
    echo "    - Live system images"
    echo "    - Custom Linux distributions"
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
        "$IMG_STORAGE_DIR"
        "$NFS_ISO_DIR"
        "$HTTP_ISO_DIR"
        "$HTTP_ISO_DIRECT_DIR"
        "$HTTP_IMAGES_DIR"
        "$TFTP_KERNELS_DIR"
        "$TFTP_INITRD_DIR"
        "$MOUNT_BASE_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    # Set proper ownership for service directories
    chown -R tftp:tftp "$TFTP_KERNELS_DIR" "$TFTP_INITRD_DIR"
    chown -R www-data:www-data "$HTTP_ISO_DIR" "$HTTP_ISO_DIRECT_DIR" "$HTTP_IMAGES_DIR"
    chmod -R 755 "$TFTP_KERNELS_DIR" "$TFTP_INITRD_DIR"
    chmod -R 755 "$HTTP_ISO_DIR" "$HTTP_ISO_DIRECT_DIR" "$HTTP_IMAGES_DIR"
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
                # Use working NFS-based approach for Ubuntu Server 20.04+
                if [[ "$version" =~ ^(2[0-9]|[3-9][0-9])\. ]]; then
                    # Modern Ubuntu Server (20.04+) with working mounted ISO approach
                    boot_params="boot=casper netboot=nfs nfsroot=$PXE_SERVER_IP:$NFS_ROOT/iso/##ISO_NAME## ip=dhcp"
                else
                    boot_params="boot=casper netboot=nfs nfsroot=$PXE_SERVER_IP:$NFS_ROOT/iso/##ISO_NAME## ip=dhcp"
                fi
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
                boot_params="boot=casper netboot=nfs nfsroot=$PXE_SERVER_IP:$NFS_ROOT/iso/##ISO_NAME## ip=dhcp quiet splash"
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

# Function to detect IMG file type and filesystem
detect_img_info() {
    local img_file="$1"
    local mount_point="$2"
    local img_info_file="$3"
    
    echo -n "Detecting IMG file type and filesystem... "
    
    # Initialize variables
    local distro=""
    local version=""
    local arch=""
    local release_name=""
    local kernel_path=""
    local initrd_path=""
    local boot_params=""
    local img_type=""
    local fs_type=""
    
    # Detect image type using file command
    local file_info
    file_info=$(file "$img_file" 2>/dev/null || echo "unknown")
    
    # Check if it's a filesystem image or disk image
    if [[ $file_info =~ "filesystem" ]]; then
        img_type="filesystem"
        # Try to detect filesystem type using blkid
        fs_type=$(blkid -o value -s TYPE "$img_file" 2>/dev/null || echo "unknown")
    elif [[ $file_info =~ "DOS/MBR boot sector" ]] || [[ $file_info =~ "partition table" ]]; then
        img_type="disk"
        # For disk images, we'll need to mount the first partition
        fs_type="disk_image"
    else
        # Try to mount directly to see if it's a valid filesystem
        if mount -o loop,ro "$img_file" "$mount_point" 2>/dev/null; then
            img_type="filesystem"
            fs_type=$(mount | grep "$mount_point" | awk '{print $5}' | head -1)
            umount "$mount_point" 2>/dev/null
        else
            echo -e "${RED}Failed${NC}"
            echo "Error: Unable to determine IMG file type or mount filesystem"
            return 1
        fi
    fi
    
    # Try to mount and analyze content
    if ! mount_img_file "$img_file" "$mount_point" "$img_type"; then
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not mount IMG file"
        return 1
    fi
    
    # Try to detect distribution based on mounted content
    # First, try standard Linux distribution detection methods
    if [[ -f "$mount_point/etc/os-release" ]]; then
        # Parse os-release for modern distributions
        local os_info
        os_info=$(cat "$mount_point/etc/os-release")
        
        if [[ $os_info =~ ID=.*ubuntu ]]; then
            distro="ubuntu-img"
            if [[ $os_info =~ VERSION_ID=\"([^\"]+)\" ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            if [[ $os_info =~ VERSION.*Server ]]; then
                release_name="Ubuntu Server $version (IMG)"
            else
                release_name="Ubuntu $version (IMG)"
            fi
            # For IMG files, we'll serve them directly over HTTP
            boot_params="url=http://$PXE_SERVER_IP/images/##IMG_NAME##.img root=/dev/ram0 ip=dhcp"
        elif [[ $os_info =~ ID=.*debian ]]; then
            distro="debian-img"
            if [[ $os_info =~ VERSION_ID=\"([^\"]+)\" ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            release_name="Debian $version (IMG)"
            boot_params="url=http://$PXE_SERVER_IP/images/##IMG_NAME##.img root=/dev/ram0 ip=dhcp"
        elif [[ $os_info =~ ID=.*centos ]] || [[ $os_info =~ ID=.*rhel ]]; then
            distro="rhel-img"
            if [[ $os_info =~ VERSION_ID=\"([^\"]+)\" ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            release_name="RHEL/CentOS $version (IMG)"
            boot_params="url=http://$PXE_SERVER_IP/images/##IMG_NAME##.img root=/dev/ram0 ip=dhcp"
        fi
        
        # Try to detect architecture
        if [[ -f "$mount_point/etc/machine-id" ]] || [[ -d "$mount_point/lib64" ]]; then
            arch="amd64"
        elif [[ -d "$mount_point/lib" ]] && [[ ! -d "$mount_point/lib64" ]]; then
            arch="i386"
        fi
        
    elif [[ -f "$mount_point/boot/vmlinuz" ]] || [[ -f "$mount_point/vmlinuz" ]]; then
        # Generic Linux image with kernel in standard locations
        distro="linux-img"
        version="unknown"
        arch="amd64"
        release_name="Linux System (IMG)"
        boot_params="url=http://$PXE_SERVER_IP/images/##IMG_NAME##.img root=/dev/ram0 ip=dhcp"
        
        # Try to find kernel and initrd
        if [[ -f "$mount_point/boot/vmlinuz" ]]; then
            kernel_path="boot/vmlinuz"
        elif [[ -f "$mount_point/vmlinuz" ]]; then
            kernel_path="vmlinuz"
        fi
        
        if [[ -f "$mount_point/boot/initrd.img" ]]; then
            initrd_path="boot/initrd.img"
        elif [[ -f "$mount_point/initrd.img" ]]; then
            initrd_path="initrd.img"
        elif [[ -f "$mount_point/boot/initramfs" ]]; then
            initrd_path="boot/initramfs"
        fi
    fi
    
    umount "$mount_point" 2>/dev/null || true
    
    # Save IMG information
    cat > "$img_info_file" << EOF
# IMG Information
DISTRO="$distro"
VERSION="$version"
ARCH="$arch"
RELEASE_NAME="$release_name"
KERNEL_PATH="$kernel_path"
INITRD_PATH="$initrd_path"
BOOT_PARAMS="$boot_params"
IMG_TYPE="$img_type"
FS_TYPE="$fs_type"
EOF
    
    echo -e "${GREEN}OK${NC}"
    echo "IMG Details:"
    echo "  Distribution: $release_name"
    echo "  Architecture: $arch"
    echo "  Image type: $img_type"
    echo "  Filesystem: $fs_type"
    echo "  Kernel: $kernel_path"
    echo "  Initrd: $initrd_path"
    
    return 0
}

# Function to mount IMG files with appropriate options
mount_img_file() {
    local img_file="$1"
    local mount_point="$2"
    local img_type="$3"
    
    if [[ "$img_type" == "disk" ]]; then
        # For disk images, try to mount the first partition
        # Use losetup to create a loop device and kpartx to map partitions
        local loop_device
        loop_device=$(losetup -f --show "$img_file")
        if [[ -n "$loop_device" ]]; then
            # Try to map partitions
            if command -v kpartx >/dev/null 2>&1; then
                kpartx -a "$loop_device" 2>/dev/null || true
                # Try to mount the first partition
                local partition="${loop_device}p1"
                if [[ -b "$partition" ]]; then
                    mount -o ro "$partition" "$mount_point" 2>/dev/null || {
                        # Cleanup on failure
                        kpartx -d "$loop_device" 2>/dev/null || true
                        losetup -d "$loop_device" 2>/dev/null || true
                        return 1
                    }
                else
                    # No partitions found, try direct mount
                    mount -o loop,ro "$img_file" "$mount_point" 2>/dev/null || {
                        losetup -d "$loop_device" 2>/dev/null || true
                        return 1
                    }
                fi
            else
                # No kpartx available, try direct mount
                losetup -d "$loop_device" 2>/dev/null || true
                mount -o loop,ro "$img_file" "$mount_point" 2>/dev/null || return 1
            fi
        else
            return 1
        fi
    else
        # For filesystem images, mount directly
        mount -o loop,ro "$img_file" "$mount_point" 2>/dev/null || return 1
    fi
    
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
    chown tftp:tftp "$kernel_dir" "$initrd_dir"
    
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
    
    # Set proper permissions on mounted ISO
    chmod -R 644 "$iso_mount_dir" 2>/dev/null || true
    find "$iso_mount_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Create HTTP symbolic link (for basic HTTP access)
    echo -n "Creating HTTP access link... "
    local http_link="$HTTP_ISO_DIR/$iso_name"
    if [[ -L "$http_link" ]]; then
        rm "$http_link"
    fi
    ln -s "$iso_mount_dir" "$http_link"
    chown -h www-data:www-data "$http_link"
    echo -e "${GREEN}OK${NC}"

    # Update NFS exports for mounted ISO (working approach)
    echo -n "Updating NFS exports... "
    
    # Remove existing exports for this ISO
    sed -i "\|$iso_mount_dir|d" /etc/exports
    
    # Add new export for mounted ISO
    local export_line="$iso_mount_dir $SUBNET/$NETMASK(ro,sync,no_subtree_check,no_root_squash)"
    echo "$export_line" >> /etc/exports
    
    # Reload NFS exports
    if exportfs -ra; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Could not reload NFS exports${NC}"
    fi
    
    echo "ISO access configured:"
    echo "  NFS (mounted ISO): $iso_mount_dir"
    echo "  HTTP: http://$PXE_SERVER_IP/iso/$iso_name/"
    
    return 0
}

# Function to setup HTTP access for IMG files  
setup_img_http_access() {
    local img_file="$1"
    local img_name="$2"
    
    echo -e "${BLUE}Setting up IMG HTTP access...${NC}"
    
    # Create images directory in HTTP root if it doesn't exist
    local http_images_dir="$HTTP_ROOT/images"
    mkdir -p "$http_images_dir"
    chown www-data:www-data "$http_images_dir"
    chmod 755 "$http_images_dir"
    
    # Copy IMG file to HTTP images directory
    echo -n "Copying IMG file to HTTP directory... "
    local http_img_file="$http_images_dir/$img_name.img"
    
    # Remove existing file if present
    if [[ -f "$http_img_file" ]]; then
        rm "$http_img_file"
    fi
    
    # Copy the IMG file
    if cp "$img_file" "$http_img_file"; then
        chown www-data:www-data "$http_img_file"
        chmod 644 "$http_img_file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not copy IMG file to HTTP directory"
        return 1
    fi
    
    echo "IMG access configured:"
    echo "  HTTP: http://$PXE_SERVER_IP/images/$img_name.img"
    echo "  Size: $(du -h "$http_img_file" | cut -f1)"
    
    return 0
}

# Function to update GRUB menu for UEFI boot
update_grub_menu() {
    local iso_name="$1"
    local iso_info_file="$2"
    
    # Source ISO information
    source "$iso_info_file"
    
    local grub_file="$TFTP_ROOT/grub/grub.cfg"
    local grub_backup="${grub_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create GRUB directory if it doesn't exist
    mkdir -p "$(dirname "$grub_file")"
    
    # Backup current GRUB config if it exists
    if [[ -f "$grub_file" ]]; then
        cp "$grub_file" "$grub_backup"
    fi
    
    # Prepare boot parameters using the working mounted ISO approach
    local nfs_path="$NFS_ROOT/iso/$iso_name"
    
    # Base parameters for casper live boot
    local base_params="boot=casper netboot=nfs nfsroot=$PXE_SERVER_IP:$nfs_path ip=dhcp"
    
    # Manual install: Comprehensive offline mode to prevent internet repository access
    # Multiple parameters to ensure no network mirror access during installation
    local manual_boot_params="$base_params apt-setup/use_mirror=false apt-setup/no_mirror=true netcfg/get_hostname=ubuntu-install netcfg/choose_interface=auto netcfg/dhcp_timeout=60 debian-installer/allow_unauthenticated=true"
    
    # Auto install: Include autoinstall for unattended setup + comprehensive offline mode  
    local auto_boot_params="$base_params autoinstall ds=nocloud-net;s=http://$PXE_SERVER_IP/autoinstall/ apt-setup/use_mirror=false apt-setup/no_mirror=true netcfg/get_hostname=ubuntu-install netcfg/choose_interface=auto netcfg/dhcp_timeout=60 debian-installer/allow_unauthenticated=true"
    
    # Always terminate kernel cmdline with '---' delimiter for Ubuntu casper
    manual_boot_params="$manual_boot_params ---"
    auto_boot_params="$auto_boot_params ---"
    
    # Create or update GRUB configuration using the working mounted ISO template
    cat > "$grub_file" << EOF
# GRUB Config (Working mounted ISO approach for proper casper compatibility)
set timeout=15
set default=0
terminal_output console
insmod efinet
insmod pxe
insmod net
insmod tftp
insmod linux

if [ -z "\$net_default_ip" ]; then net_bootp; fi
set pxe_server=$PXE_SERVER_IP
set iso_name=$iso_name

menuentry "$RELEASE_NAME (Manual Install)" {
  net_bootp
  linux (tftp,\$pxe_server)/kernels/\${iso_name}/vmlinuz $manual_boot_params
  initrd (tftp,\$pxe_server)/initrd/\${iso_name}/initrd
}

menuentry "$RELEASE_NAME (Auto Install)" {
  net_bootp
  linux (tftp,\$pxe_server)/kernels/\${iso_name}/vmlinuz $auto_boot_params
  initrd (tftp,\$pxe_server)/initrd/\${iso_name}/initrd
}

menuentry "Boot from local disk" {
    set root=(hd0)
    chainloader /EFI/BOOT/BOOTX64.EFI
    boot
}

menuentry "Memory Test (EFI)" {
    echo "EFI Memory test not available"
    echo "Press any key to return to menu..."
    read
}

menuentry "Reboot" {
    reboot
}

menuentry "Shutdown" {
    halt
}
EOF
    
    # Set proper ownership and permissions
    chown tftp:tftp "$grub_file"
    chmod 644 "$grub_file"
    
    # Rebuild GRUB EFI binary with updated configuration
    echo -n "Rebuilding GRUB EFI binary... "
    if grub-mkstandalone --format=x86_64-efi --output="$TFTP_ROOT/grubnetx64.efi" --modules="efinet tftp net linux" /boot/grub/grub.cfg="$grub_file"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        return 1
    fi
    
    # Set proper ownership and permissions
    chown tftp:tftp "$TFTP_ROOT/grubnetx64.efi"
    chmod 644 "$TFTP_ROOT/grubnetx64.efi"
    
    # Restart services to pick up changes
    echo -n "Restarting TFTP service... "
    if systemctl restart tftpd-hpa; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Could not restart TFTP service${NC}"
    fi
    
    echo "GRUB menu updated:"
    echo "  Config: $grub_file"
    echo "  Binary: $TFTP_ROOT/grubnetx64.efi"
    echo "  Manual boot: $RELEASE_NAME (Manual Install)"
    echo "  Auto boot: $RELEASE_NAME (Auto Install)"
    
    return 0
}

# Function to update GRUB menu (UEFI-only)
update_pxe_menu() {
    local iso_name="$1"
    local iso_info_file="$2"
    
    echo -e "${BLUE}Updating GRUB boot menu (UEFI-only)...${NC}"
    
    # For UEFI-only operation, we only use GRUB
    update_grub_menu "$iso_name" "$iso_info_file"
    
    return 0
}

# Function to add ISO or IMG file
add_image() {
    local file_path="$1"
    
    # Validate input
    if [[ -z "$file_path" ]]; then
        echo -e "${RED}Error: File path required${NC}"
        usage
        exit 1
    fi
    
    # Resolve full path
    if [[ ! "$file_path" =~ ^/ ]]; then
        file_path="$(pwd)/$file_path"
    fi
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}Error: File not found: $file_path${NC}"
        exit 1
    fi
    
    local filename
    filename=$(basename "$file_path")
    local file_ext="${filename##*.}"
    local file_name="${filename%.*}"
    
    # Determine file type and validate
    local is_iso=false
    local is_img=false
    
    if [[ "$file_ext" == "iso" ]]; then
        # Check if it's an ISO file
        if file "$file_path" | grep -q "ISO 9660"; then
            is_iso=true
        else
            echo -e "${RED}Error: File does not appear to be an ISO image${NC}"
            exit 1
        fi
    elif [[ "$file_ext" == "img" ]]; then
        # Check if it's a valid IMG file (filesystem or disk image)
        local file_info
        file_info=$(file "$file_path" 2>/dev/null)
        if [[ $file_info =~ "filesystem" ]] || [[ $file_info =~ "DOS/MBR boot sector" ]] || [[ $file_info =~ "partition table" ]]; then
            is_img=true
        else
            # Try blkid to see if it's a filesystem
            if blkid "$file_path" >/dev/null 2>&1; then
                is_img=true
            else
                echo -e "${RED}Error: File does not appear to be a valid IMG file${NC}"
                echo "Supported: filesystem images, disk images with partitions"
                exit 1
            fi
        fi
    else
        echo -e "${RED}Error: Unsupported file type. Only .iso and .img files are supported${NC}"
        exit 1
    fi
    
    echo "=== Adding $(if $is_iso; then echo "ISO"; else echo "IMG"; fi): $filename ==="
    echo "Date: $(date)"
    echo "Source: $file_path"
    echo "Name: $file_name"
    echo "Type: $(if $is_iso; then echo "ISO 9660"; else echo "IMG file"; fi)"
    echo
    
    # Set storage directory based on file type
    local storage_dir
    if $is_iso; then
        storage_dir="$ISO_STORAGE_DIR"
    else
        storage_dir="$IMG_STORAGE_DIR"
    fi
    
    # Check if file already exists
    if [[ -f "$storage_dir/$filename" ]]; then
        echo -e "${YELLOW}Warning: File already exists in storage${NC}"
        read -p "Overwrite existing file? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            exit 0
        fi
        
        # Remove existing file first
        echo "Removing existing file..."
        if $is_iso; then
            remove_iso "$file_name" --quiet
        else
            remove_img "$file_name" --quiet
        fi
    fi
    
    # Create directories
    create_directories
    
    # Copy file to storage
    echo -n "Copying $(if $is_iso; then echo "ISO"; else echo "IMG"; fi) to storage directory... "
    if cp "$file_path" "$storage_dir/"; then
        echo -e "${GREEN}OK${NC}"
        chmod 644 "$storage_dir/$filename"
    else
        echo -e "${RED}Failed${NC}"
        echo "Error: Could not copy file"
        exit 1
    fi
    
    local stored_file="$storage_dir/$filename"
    local mount_point="$MOUNT_BASE_DIR/$file_name"
    local info_file="$storage_dir/${file_name}.info"
    
    mkdir -p "$mount_point"
    
    if $is_iso; then
        # Process ISO file using existing logic
        # Ensure direct HTTP access to the raw ISO
        local http_iso_target="$HTTP_ISO_DIR/${filename}"
        echo -n "Preparing ISO for direct HTTP access... "
        if [[ -f "$http_iso_target" ]]; then
            rm -f "$http_iso_target"
        fi
        if ln "$file_path" "$http_iso_target" 2>/dev/null; then
            echo -e "${GREEN}hard link${NC}"
        elif cp "$file_path" "$http_iso_target" 2>/dev/null; then
            echo -e "${YELLOW}copied${NC}"
        else
            echo -e "${RED}Failed${NC}"
            echo "Warning: Could not place ISO in HTTP root; iso-url boots may fail (403)." >&2
        fi
        chown www-data:www-data "$http_iso_target" 2>/dev/null || true
        chmod 644 "$http_iso_target" 2>/dev/null || true
        
        # Detect ISO information
        if ! detect_iso_info "$stored_file" "$mount_point" "$info_file"; then
            echo "Error: Could not analyze ISO file"
            rm -f "$stored_file"
            exit 1
        fi
        
        # Extract boot files
        if ! extract_boot_files "$stored_file" "$file_name" "$mount_point" "$info_file"; then
            echo "Error: Could not extract boot files"
            rm -f "$stored_file" "$info_file"
            exit 1
        fi
        
        # Setup NFS and HTTP access
        if ! setup_iso_access "$stored_file" "$file_name" "$mount_point" "$info_file"; then
            echo "Error: Could not setup ISO access"
            rm -f "$stored_file" "$info_file"
            exit 1
        fi
        
        echo
        echo -e "${GREEN}=== ISO Successfully Added ===${NC}"
        echo "ISO: $filename"
        echo "Name: $file_name"
        echo "Storage: $stored_file"
        echo "NFS Mount: $NFS_ISO_DIR/$file_name"
        echo "HTTP URL: http://$PXE_SERVER_IP/iso/$file_name/"
        echo "GRUB Menu: Updated with working NFS boot configuration"
        
    else
        # Process IMG file using new logic
        # Detect IMG information
        if ! detect_img_info "$stored_file" "$mount_point" "$info_file"; then
            echo "Error: Could not analyze IMG file"
            rm -f "$stored_file"
            exit 1
        fi
        
        # Extract boot files if they exist (optional for IMG files)
        if extract_boot_files "$stored_file" "$file_name" "$mount_point" "$info_file" 2>/dev/null; then
            echo "Boot files extracted from IMG"
        else
            echo "No extractable boot files found in IMG (will use HTTP boot)"
        fi
        
        # Setup IMG HTTP access
        if ! setup_img_http_access "$stored_file" "$file_name"; then
            echo "Error: Could not setup IMG HTTP access"
            rm -f "$stored_file" "$info_file"
            exit 1
        fi
        
        echo
        echo -e "${GREEN}=== IMG Successfully Added ===${NC}"
        echo "IMG: $filename"
        echo "Name: $file_name"
        echo "Storage: $stored_file"
        echo "HTTP URL: http://$PXE_SERVER_IP/images/$file_name.img"
        echo "GRUB Menu: Updated with HTTP boot configuration"
    fi
    
    # Update PXE menu
    if ! update_pxe_menu "$file_name" "$info_file"; then
        echo "Error: Could not update PXE menu"
        exit 1
    fi
    
    echo
    echo "The $(if $is_iso; then echo "ISO"; else echo "IMG"; fi) is now available for network installation."
    echo "Boot via UEFI PXE and select the appropriate menu entry."
    
    return 0
}

# Function to add ISO (backward compatibility wrapper)
add_iso() {
    add_image "$@"
}

# Function to remove ISO
remove_iso() {
    local iso_name="$1"
    local quiet_mode="${2:-}"
    
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
    local http_direct_dir="$HTTP_ISO_DIRECT_DIR/$iso_name"
    local kernel_dir="$TFTP_KERNELS_DIR/$iso_name"
    local initrd_dir="$TFTP_INITRD_DIR/$iso_name"
    local http_iso_file="$HTTP_ISO_DIR/${iso_name}.iso"
    
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
    
    # Remove from NFS exports (only mounted ISO now)
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
    
    # Remove HTTP link (should be symlink to mounted ISO)
    if [[ -L "$http_link" ]]; then
        rm -f "$http_link"
    elif [[ -d "$http_link" ]]; then
        rm -rf "$http_link"
    fi
    
    # Remove mount directory and TFTP files
    rm -rf "$iso_mount_dir" "$kernel_dir" "$initrd_dir"
    
    # Remove direct HTTP ISO file if present
    if [[ -f "$http_iso_file" ]]; then
        rm -f "$http_iso_file"
    fi
    echo -e "${GREEN}OK${NC}"
    
    # Remove from PXE menu
    echo -n "Updating PXE menu... "
    if [[ -f "$GRUB_MENU_FILE" ]]; then
        # Create backup
        cp "$GRUB_MENU_FILE" "$GRUB_MENU_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove the menu entry (from LABEL to next LABEL or end)
        local temp_file="/tmp/pxe_menu_temp.$$"
        awk -v label="LABEL $iso_name" '
            $0 ~ "^LABEL " && $0 != label { print_block=1 }
            $0 == label { print_block=0 }
            print_block { print }
            $0 != label && $0 !~ "^LABEL " && print_block==1 { print }
        ' "$GRUB_MENU_FILE" > "$temp_file"
        
        mv "$temp_file" "$GRUB_MENU_FILE"
        chown tftp:tftp "$GRUB_MENU_FILE"
        chmod 644 "$GRUB_MENU_FILE"
        
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

# Function to remove IMG file
remove_img() {
    local img_name="$1"
    local quiet_mode="${2:-}"
    
    if [[ -z "$img_name" ]]; then
        echo -e "${RED}Error: IMG name required${NC}"
        usage
        exit 1
    fi
    
    # Remove .img extension if provided
    img_name="${img_name%.img}"
    
    if [[ "$quiet_mode" != "--quiet" ]]; then
        echo "=== Removing IMG: $img_name ==="
        echo "Date: $(date)"
        echo
    fi
    
    local img_file="$IMG_STORAGE_DIR/${img_name}.img"
    local img_info_file="$IMG_STORAGE_DIR/${img_name}.info"
    local kernel_dir="$TFTP_KERNELS_DIR/$img_name"
    local initrd_dir="$TFTP_INITRD_DIR/$img_name"
    local http_img_file="$HTTP_IMAGES_DIR/${img_name}.img"
    
    # Check if IMG exists
    if [[ ! -f "$img_file" ]]; then
        echo -e "${RED}Error: IMG '$img_name' not found${NC}"
        exit 1
    fi
    
    # Remove files and directories
    echo -n "Removing files... "
    rm -f "$img_file" "$img_info_file"
    
    # Remove TFTP files if they exist
    rm -rf "$kernel_dir" "$initrd_dir"
    
    # Remove HTTP IMG file
    if [[ -f "$http_img_file" ]]; then
        rm -f "$http_img_file"
    fi
    echo -e "${GREEN}OK${NC}"
    
    # Remove from PXE menu
    echo -n "Updating PXE menu... "
    if [[ -f "$GRUB_MENU_FILE" ]]; then
        # Create backup
        cp "$GRUB_MENU_FILE" "$GRUB_MENU_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove the menu entry
        local temp_file="/tmp/pxe_menu_temp.$$"
        awk -v label="LABEL $img_name" '
            $0 ~ "^LABEL " && $0 != label { print_block=1 }
            $0 == label { print_block=0 }
            print_block { print }
            $0 != label && $0 !~ "^LABEL " && print_block==1 { print }
        ' "$GRUB_MENU_FILE" > "$temp_file"
        
        mv "$temp_file" "$GRUB_MENU_FILE"
        chown tftp:tftp "$GRUB_MENU_FILE"
        chmod 644 "$GRUB_MENU_FILE"
        
        # Restart TFTP service
        systemctl restart tftpd-hpa 2>/dev/null
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Menu file not found${NC}"
    fi
    
    if [[ "$quiet_mode" != "--quiet" ]]; then
        echo
        echo -e "${GREEN}IMG '$img_name' removed successfully${NC}"
    fi
    
    return 0
}

# Function to list ISOs and IMGs
list_isos() {
    echo "=== Available Files ==="
    echo "Date: $(date)"
    echo
    
    local iso_count=0
    local img_count=0
    local has_files=false
    
    # Check if we have any files
    if [[ -d "$ISO_STORAGE_DIR" ]] && [[ -n "$(ls -A "$ISO_STORAGE_DIR"/*.iso 2>/dev/null)" ]]; then
        has_files=true
    fi
    if [[ -d "$IMG_STORAGE_DIR" ]] && [[ -n "$(ls -A "$IMG_STORAGE_DIR"/*.img 2>/dev/null)" ]]; then
        has_files=true
    fi
    
    if [[ "$has_files" == "false" ]]; then
        echo "No ISO or IMG files found."
        echo
        echo "Add files with: sudo $0 add <file.iso|file.img>"
        return 0
    fi
    
    echo "┌─────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│ File Name                 │ Type │ Distribution          │ Arch   │ Status         │"
    echo "├─────────────────────────────────────────────────────────────────────────────────────┤"
    
    # List ISO files
    if [[ -d "$ISO_STORAGE_DIR" ]]; then
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
                    status="Active (NFS)"
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
                
                printf "│ %-24s │ %-4s │ %-20s │ %-6s │ %-14s │\n" \
                    "$display_name" "ISO" "$display_distro" "$arch" "$status"
                
                ((iso_count++))
            fi
        done
    fi
    
    # List IMG files
    if [[ -d "$IMG_STORAGE_DIR" ]]; then
        for img_file in "$IMG_STORAGE_DIR"/*.img; do
            if [[ -f "$img_file" ]]; then
                local img_filename
                img_filename=$(basename "$img_file")
                local img_name="${img_filename%.img}"
                local img_info_file="$IMG_STORAGE_DIR/${img_name}.info"
                
                local distro="Unknown"
                local arch="Unknown"
                local release_name="Unknown"
                local status="Inactive"
                
                # Read IMG info if available
                if [[ -f "$img_info_file" ]]; then
                    source "$img_info_file"
                    distro="$RELEASE_NAME"
                    arch="$ARCH"
                fi
                
                # Check if HTTP file exists
                local http_img_file="$HTTP_IMAGES_DIR/${img_name}.img"
                if [[ -f "$http_img_file" ]]; then
                    status="Active (HTTP)"
                fi
                
                # Truncate long names for display
                local display_name="$img_name"
                if [[ ${#display_name} -gt 24 ]]; then
                    display_name="${display_name:0:21}..."
                fi
                
                local display_distro="$distro"
                if [[ ${#display_distro} -gt 20 ]]; then
                    display_distro="${display_distro:0:17}..."
                fi
                
                printf "│ %-24s │ %-4s │ %-20s │ %-6s │ %-14s │\n" \
                    "$display_name" "IMG" "$display_distro" "$arch" "$status"
                
                ((img_count++))
            fi
        done
    fi
    
    echo "└─────────────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "Total: $iso_count ISOs, $img_count IMGs"
    echo
    echo "Commands:"
    echo "  View details: sudo $0 status"
    echo "  Add new file: sudo $0 add <file.iso|file.img>"
    echo "  Remove file:  sudo $0 remove <name>"
    
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

# Function to refresh PXE menu entries from existing ISOs
refresh_pxe_menu() {
    echo "=== Refreshing PXE Menu Entries ==="
    echo "Date: $(date)"
    echo
    
    # Check if we have any ISOs
    if [[ ! -d "$ISO_STORAGE_DIR" ]] || [[ -z "$(ls -A "$ISO_STORAGE_DIR" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No ISOs found in storage directory${NC}"
        return 0
    fi
    
    # Backup current menu
    echo -n "Backing up current PXE menu... "
    cp "$GRUB_MENU_FILE" "$GRUB_MENU_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}OK${NC}"
    
    # Remove all existing ISO entries from menu
    echo -n "Removing existing ISO entries... "
    # Create a temporary file without ISO entries
    awk '
    BEGIN { in_iso_section = 0 }
    /^LABEL .*ubuntu.*|^LABEL .*debian.*|^LABEL .*centos.*|^LABEL .*rocky.*|^LABEL .*alma.*/ {
        in_iso_section = 1
        next
    }
    /^LABEL / && in_iso_section {
        in_iso_section = 0
    }
    /^ENDTEXT/ && in_iso_section {
        in_iso_section = 0
        next
    }
    !in_iso_section { print }
    ' "$GRUB_MENU_FILE" > "$GRUB_MENU_FILE.tmp"
    mv "$GRUB_MENU_FILE.tmp" "$GRUB_MENU_FILE"
    echo -e "${GREEN}OK${NC}"
    
    # Re-add all ISOs
    echo "Re-adding ISO entries..."
    local iso_count=0
    for iso_file in "$ISO_STORAGE_DIR"/*.iso; do
        [[ -f "$iso_file" ]] || continue
        
        local iso_name
        iso_name=$(basename "$iso_file" .iso)
        local iso_info_file="$ISO_STORAGE_DIR/${iso_name}.info"
        
        if [[ -f "$iso_info_file" ]]; then
            echo -n "  Adding $iso_name... "
            if update_pxe_menu "$iso_name" "$iso_info_file"; then
                echo -e "${GREEN}OK${NC}"
                ((iso_count++))
            else
                echo -e "${RED}Failed${NC}"
            fi
        else
            echo -e "${YELLOW}  Skipping $iso_name (no .info file)${NC}"
        fi
    done
    
    # Set proper ownership
    chown tftp:tftp "$GRUB_MENU_FILE"
    chmod 644 "$GRUB_MENU_FILE"
    
    # Restart TFTP service
    echo -n "Restarting TFTP service... "
    if systemctl restart tftpd-hpa; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    echo
    echo -e "${GREEN}PXE menu refresh completed!${NC}"
    echo "Added $iso_count ISO entries to the menu."
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
    if [[ -f "$GRUB_MENU_FILE" ]]; then
        echo "  ✅ PXE Menu: $GRUB_MENU_FILE"
        
        # Check if menu has ISO entries
        local iso_entries
        iso_entries=$(grep -c "^LABEL.*" "$GRUB_MENU_FILE" 2>/dev/null || echo "0")
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
            add_image "${2:-}"
            ;;
        "remove")
            check_root
            # Intelligent remove - check both ISO and IMG storage
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                echo -e "${RED}Error: File name required${NC}"
                usage
                exit 1
            fi
            
            # Remove extensions if provided
            name="${name%.iso}"
            name="${name%.img}"
            
            # Check what type of file exists and remove accordingly
            local found=false
            if [[ -f "$ISO_STORAGE_DIR/${name}.iso" ]]; then
                remove_iso "$name"
                found=true
            fi
            if [[ -f "$IMG_STORAGE_DIR/${name}.img" ]]; then
                remove_img "$name"
                found=true
            fi
            
            if [[ "$found" == "false" ]]; then
                echo -e "${RED}Error: File '$name' not found in ISO or IMG storage${NC}"
                exit 1
            fi
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
        "refresh")
            check_root
            refresh_pxe_menu
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
