#!/bin/bash
# 00-extract-boot-files.sh
# Extract PXE boot files from Ubuntu ISO or download packages to avoid host build machine dependencies

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
    echo "Please copy config.sh.example to config.sh and configure it."
    exit 1
fi

# Default paths for extracted files
EXTRACTED_FILES_DIR="${ARTIFACTS_DIR}/extracted-boot-files"
SYSLINUX_FILES_DIR="${EXTRACTED_FILES_DIR}/syslinux"
GRUB_FILES_DIR="${EXTRACTED_FILES_DIR}/grub"
MEMTEST_FILES_DIR="${EXTRACTED_FILES_DIR}/memtest"

# Ubuntu package URLs (for 24.04)
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
SYSLINUX_PACKAGE_URL="${UBUNTU_MIRROR}/pool/main/s/syslinux/syslinux-common_6.04~git20190206.bf6db5b4+dfsg1-3ubuntu1_all.deb"
PXELINUX_PACKAGE_URL="${UBUNTU_MIRROR}/pool/main/s/syslinux/pxelinux_6.04~git20190206.bf6db5b4+dfsg1-3ubuntu1_all.deb"
GRUB_EFI_AMD64_SIGNED_URL="${UBUNTU_MIRROR}/pool/main/g/grub2-signed/grub-efi-amd64-signed_1.93+2.02-2ubuntu8_amd64.deb"
MEMTEST86_URL="${UBUNTU_MIRROR}/pool/main/m/memtest86+/memtest86+_7.20-1_amd64.deb"

echo "=== Extracting PXE Boot Files ==="
echo "This script extracts boot files needed for PXE server setup"
echo "without relying on packages installed on the build machine."
echo

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to create directories
create_directories() {
    echo -e "${BLUE}Creating extraction directories...${NC}"
    
    local dirs=(
        "$EXTRACTED_FILES_DIR"
        "$SYSLINUX_FILES_DIR"
        "$GRUB_FILES_DIR"
        "$MEMTEST_FILES_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        echo -n "  Creating $dir... "
        if mkdir -p "$dir"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed${NC}"
            exit 1
        fi
    done
}

# Function to extract files from Ubuntu ISO
extract_from_ubuntu_iso() {
    local iso_path="$1"
    
    echo -e "${BLUE}Extracting boot files from Ubuntu ISO: $iso_path${NC}"
    
    if [[ ! -f "$iso_path" ]]; then
        echo -e "${RED}Error: ISO file not found: $iso_path${NC}"
        return 1
    fi
    
    local mount_point="/tmp/ubuntu_iso_mount"
    mkdir -p "$mount_point"
    
    echo -n "Mounting Ubuntu ISO... "
    if mount -o loop,ro "$iso_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        return 1
    fi
    
    # Extract syslinux files from the ISO
    echo -n "Extracting syslinux files from ISO... "
    if [[ -d "$mount_point/isolinux" ]]; then
        # Copy available syslinux files from isolinux directory
        for file in "$mount_point/isolinux"/*.c32; do
            if [[ -f "$file" ]]; then
                cp "$file" "$SYSLINUX_FILES_DIR/"
            fi
        done
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}No isolinux directory found${NC}"
    fi
    
    # Extract kernel and initrd (for reference)
    echo -n "Extracting kernel files for reference... "
    if [[ -d "$mount_point/casper" ]]; then
        cp "$mount_point/casper/vmlinuz" "$EXTRACTED_FILES_DIR/" 2>/dev/null || true
        cp "$mount_point/casper/initrd" "$EXTRACTED_FILES_DIR/" 2>/dev/null || true
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}No casper directory found${NC}"
    fi
    
    echo -n "Unmounting ISO... "
    umount "$mount_point"
    rmdir "$mount_point"
    echo -e "${GREEN}OK${NC}"
}

# Function to download and extract .deb package
download_and_extract_deb() {
    local package_url="$1"
    local destination_dir="$2"
    local package_name
    
    package_name=$(basename "$package_url")
    
    echo -n "Downloading $package_name... "
    
    local temp_dir="/tmp/deb_extract_$$"
    mkdir -p "$temp_dir"
    
    if wget -q -O "$temp_dir/$package_name" "$package_url"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -n "Extracting $package_name... "
    cd "$temp_dir"
    if ar x "$package_name" && tar -xf data.tar.* 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Copy relevant files to destination
    if [[ -d "usr" ]]; then
        cp -r usr/* "$destination_dir/" 2>/dev/null || true
    fi
    if [[ -d "boot" ]]; then
        cp -r boot/* "$destination_dir/" 2>/dev/null || true
    fi
    
    cd - >/dev/null
    rm -rf "$temp_dir"
}

# Function to download syslinux packages
download_syslinux_packages() {
    echo -e "${BLUE}Downloading SYSLINUX packages...${NC}"
    
    # Create syslinux directory structure
    mkdir -p "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios"
    mkdir -p "$SYSLINUX_FILES_DIR/lib/PXELINUX"
    
    # Download and extract syslinux-common package
    if download_and_extract_deb "$SYSLINUX_PACKAGE_URL" "$SYSLINUX_FILES_DIR"; then
        echo "SYSLINUX common files extracted"
    else
        echo -e "${YELLOW}Warning: Could not download syslinux-common package${NC}"
    fi
    
    # Download and extract pxelinux package
    if download_and_extract_deb "$PXELINUX_PACKAGE_URL" "$SYSLINUX_FILES_DIR"; then
        echo "PXELINUX files extracted"
    else
        echo -e "${YELLOW}Warning: Could not download pxelinux package${NC}"
    fi
}

# Function to download GRUB packages
download_grub_packages() {
    echo -e "${BLUE}Downloading GRUB EFI packages...${NC}"
    
    mkdir -p "$GRUB_FILES_DIR/lib/grub/x86_64-efi-signed"
    mkdir -p "$GRUB_FILES_DIR/lib/grub/x86_64-efi/monolithic"
    
    if download_and_extract_deb "$GRUB_EFI_AMD64_SIGNED_URL" "$GRUB_FILES_DIR"; then
        echo "GRUB EFI files extracted"
    else
        echo -e "${YELLOW}Warning: Could not download grub-efi-amd64-signed package${NC}"
    fi
}

# Function to download memtest package
download_memtest_package() {
    echo -e "${BLUE}Downloading memtest86+ package...${NC}"
    
    mkdir -p "$MEMTEST_FILES_DIR/lib/memtest86+"
    mkdir -p "$MEMTEST_FILES_DIR/boot"
    
    if download_and_extract_deb "$MEMTEST86_URL" "$MEMTEST_FILES_DIR"; then
        echo "Memtest86+ files extracted"
    else
        echo -e "${YELLOW}Warning: Could not download memtest86+ package${NC}"
    fi
}

# Function to verify extracted files
verify_extracted_files() {
    echo -e "${BLUE}Verifying extracted files...${NC}"
    
    local files_to_check=(
        "$SYSLINUX_FILES_DIR/lib/PXELINUX/pxelinux.0:PXELINUX bootloader"
        "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios/menu.c32:Menu module"
        "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios/vesamenu.c32:VESA menu module"
        "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios/ldlinux.c32:Linux loader"
        "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios/libcom32.c32:COM32 library"
        "$SYSLINUX_FILES_DIR/lib/syslinux/modules/bios/libutil.c32:Utility library"
        "$GRUB_FILES_DIR/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed:GRUB EFI signed"
        "$MEMTEST_FILES_DIR/lib/memtest86+/memtest86+.bin:Memtest86+"
    )
    
    local missing_files=0
    local required_missing=0
    
    for file_info in "${files_to_check[@]}"; do
        local file_path="${file_info%%:*}"
        local file_desc="${file_info##*:}"
        
        echo -n "  Checking $file_desc... "
        if [[ -f "$file_path" ]]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Missing${NC}"
            ((missing_files++))
            
            # Only consider SYSLINUX files as required
            if [[ "$file_path" == *"/syslinux/"* || "$file_path" == *"/PXELINUX/"* ]]; then
                ((required_missing++))
            fi
        fi
    done
    
    if [[ $required_missing -eq 0 ]]; then
        echo -e "${GREEN}All required SYSLINUX files extracted successfully!${NC}"
        if [[ $missing_files -gt 0 ]]; then
            echo -e "${YELLOW}Note: $missing_files optional files are missing (GRUB/memtest)${NC}"
        fi
        return 0
    else
        echo -e "${RED}Error: $required_missing required SYSLINUX files are missing${NC}"
        return 1
    fi
}

# Function to show extraction summary
show_summary() {
    echo
    echo -e "${GREEN}=== Boot Files Extraction Summary ===${NC}"
    echo "Extracted files location: $EXTRACTED_FILES_DIR"
    echo
    echo "SYSLINUX files: $SYSLINUX_FILES_DIR"
    echo "GRUB files: $GRUB_FILES_DIR"
    echo "Memtest files: $MEMTEST_FILES_DIR"
    echo
    echo "These files can now be used by the PXE setup scripts"
    echo "without relying on packages installed on the build machine."
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [UBUNTU_ISO_PATH]"
    echo
    echo "Options:"
    echo "  --iso-only          Extract only from provided Ubuntu ISO"
    echo "  --download-only     Download packages only (no ISO extraction)"
    echo "  --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0                           # Download packages from Ubuntu repository"
    echo "  $0 ubuntu-24.04.3-server.iso # Extract from ISO and download packages"
    echo "  $0 --iso-only ubuntu.iso     # Extract only from ISO"
    echo "  $0 --download-only           # Download packages only"
}

# Main execution
main() {
    local iso_path=""
    local iso_only=false
    local download_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --iso-only)
                iso_only=true
                shift
                ;;
            --download-only)
                download_only=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                if [[ -z "$iso_path" ]]; then
                    iso_path="$1"
                else
                    echo -e "${RED}Error: Too many arguments${NC}"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    echo "Starting boot files extraction..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo
    
    check_root
    create_directories
    
    # Extract from ISO if provided and not download-only
    if [[ -n "$iso_path" && "$download_only" == false ]]; then
        extract_from_ubuntu_iso "$iso_path"
    fi
    
    # Download packages if not iso-only
    if [[ "$iso_only" == false ]]; then
        download_syslinux_packages
        download_grub_packages
        download_memtest_package
    fi
    
    verify_extracted_files
    show_summary
    
    echo "Next steps:"
    echo "1. Run the PXE setup scripts - they will use the extracted files"
    echo "2. The setup scripts have been modified to use extracted files instead of host packages"
}

# Run main function
main "$@"