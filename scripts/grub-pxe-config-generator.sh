#!/bin/bash
# grub-pxe-config-generator.sh
# GRUB configuration generator for PXE boot entries
# Follows GRUB2 native CLI best practices from grub-cli-recommendations.md

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
    echo -e "${RED}Error: config.sh not found.${NC}" >&2
    exit 1
fi

# Source GRUB utilities
if [[ -f "$SCRIPT_DIR/grub-utilities.sh" ]]; then
    source "$SCRIPT_DIR/grub-utilities.sh"
fi

# Function to generate GRUB configuration using native tools and PR #11 patterns
generate_grub_config() {
    local output_file="${1:-}"
    local use_grub_mkconfig="${2:-true}"
    
    if [[ -z "$output_file" ]]; then
        echo -e "${RED}Error: Output file required${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Generating GRUB configuration for PXE boot...${NC}"
    
    # Initialize tool availability
    check_grub_tools >/dev/null 2>&1
    
    if [[ "$use_grub_mkconfig" == "true" ]] && command -v "$GRUB_MKCONFIG" >/dev/null 2>&1; then
        generate_with_grub_mkconfig "$output_file"
    else
        generate_manual_config "$output_file"
    fi
    
    # Add PXE-specific enhancements following PR #11 recommendations
    enhance_pxe_config "$output_file"
    
    return 0
}

# Function to generate configuration using grub-mkconfig (preferred method)
generate_with_grub_mkconfig() {
    local output_file="$1"
    
    echo -n "Using $GRUB_MKCONFIG for configuration generation... "
    
    # Create temporary GRUB environment for PXE
    local temp_grub_dir="/tmp/grub-pxe-$$"
    local temp_default="$temp_grub_dir/grub-defaults"
    local temp_grub_d="$temp_grub_dir/grub.d"
    
    # Cleanup function
    cleanup() {
        [[ -n "${temp_grub_dir:-}" ]] && rm -rf "$temp_grub_dir" 2>/dev/null || true
    }
    trap cleanup EXIT
    
    # Create temporary GRUB environment
    mkdir -p "$temp_grub_dir" "$temp_grub_d"
    
    # Create PXE-specific GRUB defaults following PR #11 patterns
    cat > "$temp_default" << EOF
# GRUB defaults for PXE boot generation (grub-cli-recommendations.md compliant)
GRUB_DEFAULT=saved
GRUB_TIMEOUT=30
GRUB_DISTRIBUTOR="PXE Server"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_INPUT=console
GRUB_TERMINAL_OUTPUT=console
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_SUBMENU=y
GRUB_SAVEDEFAULT=true

# PXE-specific variables
GRUB_PXE_SERVER_IP="$PXE_SERVER_IP"
GRUB_TFTP_ROOT="$TFTP_ROOT"
GRUB_HTTP_ROOT="$HTTP_ROOT"
GRUB_NFS_ROOT="$NFS_ROOT"
EOF
    
    # Create GRUB.d templates for PXE
    create_grub_d_templates "$temp_grub_d"
    
    # Generate configuration using grub-mkconfig with custom environment
    if GRUB_CONFIG_FILE="$temp_default" "$GRUB_MKCONFIG" > "$output_file" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Failed, using manual method${NC}"
        generate_manual_config "$output_file"
    fi
}

# Function to create GRUB.d templates following PR #11 recommendations
create_grub_d_templates() {
    local grub_d_dir="$1"
    
    # 00_header - Enhanced with PR #11 patterns
    cat > "$grub_d_dir/00_header" << 'EOF'
#!/bin/bash
cat << EOM
# GRUB Configuration for UEFI PXE Boot
# Generated using grub-mkconfig with native CLI tools
# Follows grub-cli-recommendations.md best practices

# Load grubenv for persistent settings
load_env

# Set defaults (can be overridden by grubenv)
if [ -z "\$timeout" ]; then
    set timeout=${GRUB_TIMEOUT:-30}
fi
if [ -z "\$default" ]; then
    set default="\${saved_entry}"
fi

# Load essential modules for PXE boot
insmod part_gpt
insmod part_msdos
insmod fat
insmod ext2
insmod net
insmod efinet
insmod tftp
insmod http
insmod chain
insmod linux
insmod multiboot
insmod multiboot2
insmod configfile
insmod normal
insmod test
insmod search
insmod search_fs_file
insmod search_fs_uuid
insmod search_label
insmod gzio
insmod echo
insmod probe

# Network initialization following grub-cli-recommendations.md
if [ "\${grub_platform}" = "efi" ]; then
    insmod efi_gop
    insmod efi_uga
fi

# Network configuration with auto-discovery
net_bootp
if [ -z "\$net_default_ip" ]; then
    echo "Warning: Network configuration may have failed"
fi

# Set PXE server (prefer discovered gateway, fallback to configured)
if [ -n "\$net_default_gateway" ]; then
    set pxe_server=\$net_default_gateway
else
    set pxe_server=${GRUB_PXE_SERVER_IP:-192.168.1.1}
fi

set root=(tftp,\$pxe_server)

EOM
EOF

    # 10_local_boot - Enhanced with search commands per PR #11
    cat > "$grub_d_dir/10_local_boot" << 'EOF'
#!/bin/bash
cat << EOM

# === Local Boot Options ===

menuentry 'Boot from local disk' --class os --id=local {
    # Use search command for device discovery (grub-cli-recommendations.md)
    search --no-floppy --set=root --label / 2>/dev/null
    if [ -z "\$root" ]; then
        # Try searching by filesystem UUID if label search fails
        search --no-floppy --fs-uuid --set=root \$(probe -u (hd0,gpt1)) 2>/dev/null
    fi
    
    if [ -n "\$root" ]; then
        if [ -f /EFI/BOOT/BOOTX64.EFI ]; then
            chainloader /EFI/BOOT/BOOTX64.EFI
        elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        else
            # Fallback to legacy boot
            set root=(hd0)
            chainloader +1
        fi
    else
        # Last resort fallback
        echo "No bootable disk found, trying first hard drive..."
        set root=(hd0)
        chainloader +1
    fi
    boot
}

submenu 'Advanced Local Boot Options' --id=advanced-local {
    menuentry 'Boot from second disk' --id=local2 {
        search --no-floppy --set=root --label / --hint=(hd1,gpt1) 2>/dev/null
        if [ -z "\$root" ]; then
            set root=(hd1)
        fi
        chainloader +1
        boot
    }
    
    menuentry 'Boot from USB' --id=usb {
        search --no-floppy --set=root --label / --hint=(usb0) 2>/dev/null
        if [ -z "\$root" ]; then
            set root=(usb0)
        fi
        chainloader +1
        boot
    }
}

EOM
EOF

    # 20_system_tools
    cat > "$grub_d_dir/20_system_tools" << 'EOF'
#!/bin/bash
cat << EOM

# === System Tools ===

menuentry 'Memory Test (EFI)' --class memtest --id=memtest {
    # Search for memory test tools in multiple locations
    search --no-floppy --set=root --file /tools/memtest86.efi 2>/dev/null
    if [ -n "\$root" ] && [ -f /tools/memtest86.efi ]; then
        chainloader /tools/memtest86.efi
        boot
    fi
    
    search --no-floppy --set=root --file /boot/memtest86+.efi 2>/dev/null
    if [ -n "\$root" ] && [ -f /boot/memtest86+.efi ]; then
        chainloader /boot/memtest86+.efi
        boot
    fi
    
    echo "Memory test not available"
    echo "Install memtest86+ or place memtest86.efi in /tools/"
    echo "Press any key to return to menu..."
    read
}

EOM
EOF

    # 40_iso_entries - Dynamic ISO detection
    cat > "$grub_d_dir/40_iso_entries" << 'EOF'
#!/bin/bash
# Dynamic ISO entries based on available ISOs

if [ -n "$GRUB_TFTP_ROOT" ] && [ -d "$GRUB_TFTP_ROOT/kernels" ]; then
    echo ""
    echo "# === Available ISO Installations ==="
    echo ""
    
    iso_count=0
    for iso_dir in "$GRUB_TFTP_ROOT/kernels"/*; do
        if [ -d "$iso_dir" ] && [ -f "$iso_dir/vmlinuz" ]; then
            iso_name=$(basename "$iso_dir")
            
            # Try to get ISO information
            iso_info=""
            if [ -f "${GRUB_TFTP_ROOT%/*}/artifacts/iso/$iso_name.info" ]; then
                . "${GRUB_TFTP_ROOT%/*}/artifacts/iso/$iso_name.info" 2>/dev/null
                title="${RELEASE_NAME:-$iso_name}"
                boot_params="${BOOT_PARAMS:-boot=live}"
            else
                title="$iso_name"
                boot_params="boot=live"
            fi
            
            # Use nfsroot for casper compatibility (working-configuration.md)
            if [[ "$boot_params" == *"casper"* ]]; then
                boot_params="${boot_params//##ISO_NAME##/$iso_name}"
                boot_params="${boot_params//##PXE_SERVER_IP##/$GRUB_PXE_SERVER_IP}"
                boot_params="${boot_params//##NFS_ROOT##/$GRUB_NFS_ROOT}"
            fi
            
            echo "menuentry '$title' --class linux --id=$iso_name {"
            echo "    echo 'Loading $title...'"
            echo "    linux /kernels/$iso_name/vmlinuz $boot_params"
            echo "    initrd /initrd/$iso_name/initrd"
            echo "    boot"
            echo "}"
            echo ""
            
            iso_count=$((iso_count + 1))
        fi
    done
    
    if [ $iso_count -eq 0 ]; then
        echo "# No ISOs available yet"
        echo "# Run: sudo ./scripts/08-iso-manager.sh add <iso-file>"
        echo ""
    fi
fi
EOF

    # 90_footer - System control and utilities
    cat > "$grub_d_dir/90_footer" << 'EOF'
#!/bin/bash
cat << EOM

# === System Information & Control ===

menuentry 'Network Information' --class info --id=netinfo {
    echo "=== Network Configuration ==="
    echo "PXE Server: \$pxe_server"
    echo "Client MAC: \$net_default_mac"
    echo "Client IP: \$net_default_ip"
    echo "Gateway: \$net_default_gateway"
    echo ""
    echo "TFTP Root: ${GRUB_TFTP_ROOT:-/var/lib/tftpboot}"
    echo "HTTP Root: ${GRUB_HTTP_ROOT:-/var/www/html/pxe}"
    echo "NFS Root: ${GRUB_NFS_ROOT:-/srv/nfs}"
    echo ""
    echo "Press any key to return to menu..."
    read
}

menuentry 'GRUB Command Line' --class terminal --id=cmdline {
    echo "Entering GRUB command line..."
    echo "Type 'normal' to return to menu"
    echo ""
}

submenu 'System Control' --id=control {
    menuentry 'Reboot' --class restart --id=reboot {
        echo "Rebooting system..."
        reboot
    }
    
    menuentry 'Shutdown' --class shutdown --id=shutdown {
        echo "Shutting down system..."
        halt
    }
    
    menuentry 'Return to BIOS/UEFI Setup' --id=setup {
        echo "Rebooting to firmware setup..."
        fwsetup
    }
}

EOM
EOF

    # Make all templates executable
    chmod +x "$grub_d_dir"/*
}

# Function to generate manual configuration (fallback)
generate_manual_config() {
    local output_file="$1"
    
    echo -n "Generating manual GRUB configuration... "
    
    cat > "$output_file" << EOF
# GRUB Configuration for UEFI PXE Boot
# Generated manually following grub-cli-recommendations.md best practices
# Server: $PXE_SERVER_IP

# Load grubenv for persistent settings management
load_env

# Set defaults (overrideable by grubenv)
if [ -z "\$timeout" ]; then
    set timeout=30
fi
if [ -z "\$default" ]; then
    set default="\${saved_entry}"
fi

# Load essential modules for PXE boot
insmod part_gpt
insmod part_msdos
insmod fat
insmod ext2
insmod net
insmod efinet
insmod tftp
insmod http
insmod chain
insmod linux
insmod multiboot
insmod multiboot2
insmod configfile
insmod normal
insmod test
insmod search
insmod search_fs_file
insmod search_fs_uuid
insmod search_label

# Network initialization with auto-discovery
net_bootp

# Set PXE server (prefer discovered, fallback to configured)
if [ -n "\$net_default_gateway" ]; then
    set pxe_server=\$net_default_gateway
else
    set pxe_server=$PXE_SERVER_IP
fi

set root=(tftp,\$pxe_server)

EOF

    echo -e "${GREEN}OK${NC}"
}

# Function to enhance PXE configuration with dynamic content
enhance_pxe_config() {
    local config_file="$1"
    
    echo -n "Adding dynamic PXE enhancements... "
    
    # Add dynamic ISO entries if not already added by grub-mkconfig
    if ! grep -q "Available ISO Installations" "$config_file"; then
        add_iso_entries "$config_file"
    fi
    
    # Add footer if not already present
    if ! grep -q "System Information" "$config_file"; then
        add_config_footer "$config_file"
    fi
    
    echo -e "${GREEN}OK${NC}"
}

# Function to add ISO entries to GRUB configuration
add_iso_entries() {
    local config_file="$1"
    local iso_storage_dir="$(dirname "$SCRIPT_DIR")/artifacts/iso"
    
    if [[ ! -d "$iso_storage_dir" ]]; then
        return 0
    fi
    
    cat >> "$config_file" << EOF

# === Available ISO Installations ===

EOF
    
    local iso_count=0
    
    # Process each ISO file
    for iso_info in "$iso_storage_dir"/*.info; do
        if [[ -f "$iso_info" ]]; then
            local iso_name
            iso_name=$(basename "$iso_info" .info)
            
            # Source ISO information
            local DISTRO="" VERSION="" ARCH="" RELEASE_NAME="" KERNEL_PATH="" INITRD_PATH="" BOOT_PARAMS=""
            source "$iso_info" 2>/dev/null || continue
            
            if [[ -n "$RELEASE_NAME" && -f "$TFTP_ROOT/kernels/$iso_name/vmlinuz" ]]; then
                add_single_iso_entry "$config_file" "$iso_name" "$RELEASE_NAME" "$BOOT_PARAMS"
                ((iso_count++))
            fi
        fi
    done
    
    if [[ $iso_count -eq 0 ]]; then
        cat >> "$config_file" << EOF
# No ISOs available yet
# Run: sudo ./scripts/08-iso-manager.sh add <iso-file>

EOF
    fi
}

# Function to add a single ISO entry following working configuration patterns
add_single_iso_entry() {
    local config_file="$1"
    local iso_name="$2"
    local release_name="$3"
    local boot_params="$4"
    
    # Replace placeholders in boot parameters (working-configuration.md compatible)
    local boot_params_updated="${boot_params//##ISO_NAME##/$iso_name}"
    boot_params_updated="${boot_params_updated//##PXE_SERVER_IP##/$PXE_SERVER_IP}"
    boot_params_updated="${boot_params_updated//##NFS_ROOT##/$NFS_ROOT}"
    
    cat >> "$config_file" << EOF
menuentry '$release_name' --class linux --id=$iso_name {
    echo 'Loading $release_name...'
    linux /kernels/$iso_name/vmlinuz $boot_params_updated
    initrd /initrd/$iso_name/initrd
    boot
}

EOF
}

# Function to add configuration footer
add_config_footer() {
    local config_file="$1"
    
    cat >> "$config_file" << EOF

# === Local Boot Options ===

menuentry 'Boot from local disk' --class os --id=local {
    search --no-floppy --set=root --label /
    if [ -z "\$root" ]; then
        search --no-floppy --fs-uuid --set=root \$(probe -u (hd0,gpt1)) 2>/dev/null
    fi
    
    if [ -n "\$root" ]; then
        if [ -f /EFI/BOOT/BOOTX64.EFI ]; then
            chainloader /EFI/BOOT/BOOTX64.EFI
        elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        else
            set root=(hd0)
            chainloader +1
        fi
    else
        set root=(hd0)
        chainloader +1
    fi
    boot
}

# === System Information & Control ===

menuentry 'Network Information' --class info --id=netinfo {
    echo "=== Network Configuration ==="
    echo "PXE Server: \$pxe_server"
    echo "Client MAC: \$net_default_mac"
    echo "Client IP: \$net_default_ip"
    echo ""
    echo "Press any key to return to menu..."
    read
}

menuentry 'Reboot' --class restart --id=reboot {
    reboot
}

menuentry 'Shutdown' --class shutdown --id=shutdown {
    halt
}

EOF
}

# Function to install GRUB configuration with proper validation
install_grub_config() {
    local source_config="$1"
    local target_config="${2:-$TFTP_ROOT/grub/grub.cfg}"
    local grubenv_file="${3:-$TFTP_ROOT/grub/grubenv}"
    
    echo -e "${BLUE}Installing GRUB configuration...${NC}"
    
    # Ensure target directory exists
    mkdir -p "$(dirname "$target_config")"
    mkdir -p "$(dirname "$grubenv_file")"
    
    # Validate configuration before installing
    if command -v "$GRUB_SCRIPT_CHECK" >/dev/null 2>&1; then
        echo -n "Validating configuration syntax... "
        if "$GRUB_SCRIPT_CHECK" "$source_config" 2>/dev/null; then
            echo -e "${GREEN}Valid${NC}"
        else
            echo -e "${RED}Invalid syntax, aborting installation${NC}"
            return 1
        fi
    fi
    
    # Install configuration
    echo -n "Installing configuration to $target_config... "
    cp "$source_config" "$target_config"
    
    # Set proper ownership and permissions
    chown tftp:tftp "$target_config"
    chmod 644 "$target_config"
    echo -e "${GREEN}OK${NC}"
    
    # Create/update grubenv file
    echo -n "Setting up grubenv... "
    if command -v "$GRUB_EDITENV" >/dev/null 2>&1; then
        if [[ ! -f "$grubenv_file" ]]; then
            "$GRUB_EDITENV" "$grubenv_file" create
        fi
        # Set default entry to local boot
        "$GRUB_EDITENV" "$grubenv_file" set saved_entry=local
        chown tftp:tftp "$grubenv_file"
        chmod 644 "$grubenv_file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Skipped (grub-editenv not available)${NC}"
    fi
    
    echo -e "${GREEN}GRUB configuration installed successfully${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  generate <file> [use_mkconfig]  Generate GRUB config to file"
    echo "  install [target_file]           Generate and install to TFTP root"
    echo "  add-iso <iso_name>              Add ISO entry to existing config"
    echo "  remove-iso <iso_name>           Remove ISO entry from config"
    echo "  help                            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 generate /tmp/grub.cfg"
    echo "  $0 install"
    echo "  $0 add-iso ubuntu-24.04-server"
    echo "  $0 remove-iso ubuntu-24.04-server"
}

# Main function
main() {
    local action="${1:-generate}"
    
    case "$action" in
        "generate")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: Output file required for generate command${NC}"
                exit 1
            fi
            generate_grub_config "$2" "${3:-true}"
            echo "GRUB configuration generated: $2"
            ;;
        "install")
            local temp_config="/tmp/grub-pxe-generated-$$.cfg"
            generate_grub_config "$temp_config" "true"
            install_grub_config "$temp_config" "${2:-}"
            rm -f "$temp_config"
            ;;
        "add-iso"|"remove-iso")
            # These will be implemented as configuration regeneration
            local temp_config="/tmp/grub-pxe-updated-$$.cfg"
            generate_grub_config "$temp_config" "true"
            install_grub_config "$temp_config"
            rm -f "$temp_config"
            echo "GRUB configuration updated for ISO changes"
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$action'${NC}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi