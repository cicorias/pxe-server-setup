#!/bin/bash
# grub-utilities.sh
# Enhanced GRUB utilities for PXE server management

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
fi

# Function to check GRUB tools availability
check_grub_tools() {
    echo -e "${BLUE}Checking GRUB tools availability...${NC}"
    
    local tools=(
        "grub-mkconfig:Generate GRUB configuration"
        "grub-install:Install GRUB to devices"
        "grub-script-check:Validate GRUB scripts"
        "update-grub:Update GRUB configuration (Debian/Ubuntu)"
        "grub-mkstandalone:Create standalone GRUB images"
        "grub-mknetdir:Create network boot directory"
    )
    
    local available_tools=()
    local missing_tools=()
    
    for tool_desc in "${tools[@]}"; do
        IFS=':' read -r tool desc <<< "$tool_desc"
        echo -n "  Checking $tool... "
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "${GREEN}Available${NC} - $desc"
            available_tools+=("$tool")
        else
            echo -e "${RED}Missing${NC} - $desc"
            missing_tools+=("$tool")
        fi
    done
    
    echo
    echo "Summary:"
    echo "  Available tools: ${#available_tools[@]}"
    echo "  Missing tools: ${#missing_tools[@]}"
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Consider installing missing GRUB tools:${NC}"
        echo "  sudo apt update && sudo apt install grub2-common grub-efi-amd64-bin"
    fi
    
    return 0
}

# Function to create advanced GRUB configuration using grub-mkconfig
create_advanced_grub_config() {
    local output_file="${1:-$TFTP_ROOT/grub/grub.cfg}"
    local use_templates="${2:-true}"
    
    echo -e "${BLUE}Creating advanced GRUB configuration...${NC}"
    
    # Check if grub-mkconfig is available
    if ! command -v grub-mkconfig >/dev/null 2>&1; then
        echo -e "${RED}Error: grub-mkconfig not available${NC}"
        return 1
    fi
    
    # Create temporary environment for PXE GRUB generation
    local temp_dir="/tmp/grub-pxe-env-$$"
    local temp_grub_defaults="$temp_dir/grub-defaults"
    local temp_grub_d="$temp_dir/grub.d"
    
    # Cleanup function
    cleanup() {
        [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir" 2>/dev/null || true
    }
    trap cleanup EXIT
    
    # Create temporary environment
    mkdir -p "$temp_dir" "$temp_grub_d"
    
    # Create PXE-specific GRUB defaults
    cat > "$temp_grub_defaults" << EOF
# GRUB defaults for PXE boot generation
GRUB_DEFAULT=0
GRUB_TIMEOUT=30
GRUB_DISTRIBUTOR="PXE Server"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_INPUT=console
GRUB_TERMINAL_OUTPUT=console
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_SUBMENU=y

# PXE-specific variables
GRUB_PXE_SERVER_IP="$PXE_SERVER_IP"
GRUB_TFTP_ROOT="$TFTP_ROOT"
GRUB_HTTP_ROOT="$HTTP_ROOT"
GRUB_NFS_ROOT="$NFS_ROOT"
EOF
    
    if [[ "$use_templates" == "true" ]]; then
        create_grub_templates "$temp_grub_d"
    fi
    
    # Generate configuration using grub-mkconfig
    echo -n "Running grub-mkconfig with PXE environment... "
    
    # Set environment and run grub-mkconfig
    export GRUB_CONFIG_FILE="$temp_grub_defaults"
    
    if [[ "$use_templates" == "true" ]]; then
        # Use custom grub.d directory
        if GRUB_CONFIG_GENERATOR_PATH="$temp_grub_d" grub-mkconfig > "$output_file" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Failed with templates, trying basic generation${NC}"
            use_templates="false"
        fi
    fi
    
    if [[ "$use_templates" == "false" ]]; then
        # Basic generation without custom templates
        if grub-mkconfig > "$output_file" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed${NC}"
            return 1
        fi
    fi
    
    # Post-process the generated configuration for PXE
    postprocess_grub_config "$output_file"
    
    # Set proper ownership
    if [[ -n "$TFTP_ROOT" ]] && [[ -f "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        chown tftp:tftp "$output_file"
        chmod 644 "$output_file"
    fi
    
    echo -e "${GREEN}Advanced GRUB configuration created: $output_file${NC}"
    return 0
}

# Function to create GRUB templates for PXE
create_grub_templates() {
    local grub_d_dir="$1"
    
    echo -n "Creating GRUB templates... "
    
    # 00_header template
    cat > "$grub_d_dir/00_header" << 'EOF'
#!/bin/bash
# PXE GRUB Header

cat << EOM
# GRUB Configuration for UEFI PXE Boot
# Generated using grub-mkconfig with PXE templates
# Server: ${GRUB_PXE_SERVER_IP:-unknown}

set timeout=${GRUB_TIMEOUT:-30}
set default=${GRUB_DEFAULT:-0}

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

# Set network configuration
set net_default_server=${GRUB_PXE_SERVER_IP:-192.168.1.1}
set root=(tftp,\$net_default_server)

# Network initialization
net_add_addr \$net_default_mac ipv4 dhcp

EOM
EOF

    # 10_pxe_entries template
    cat > "$grub_d_dir/10_pxe_entries" << 'EOF'
#!/bin/bash
# PXE Boot Entries

cat << EOM

# === Local Boot Options ===

menuentry 'Boot from local disk' --class os --id=local {
    search --no-floppy --set=root --label /
    if [ -f /EFI/BOOT/BOOTX64.EFI ]; then
        chainloader /EFI/BOOT/BOOTX64.EFI
    elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    else
        # Try alternative boot methods
        set root=(hd0,gpt1)
        chainloader /EFI/Boot/bootx64.efi
        if [ \$? != 0 ]; then
            set root=(hd0,msdos1)
            chainloader +1
        fi
    fi
    boot
}

menuentry 'Boot from second disk' --class os --id=local2 {
    set root=(hd1)
    chainloader +1
    boot
}

EOM
EOF

    # 20_tools template
    cat > "$grub_d_dir/20_tools" << 'EOF'
#!/bin/bash
# System Tools

cat << EOM

# === System Tools ===

menuentry 'Memory Test (EFI)' --class memtest --id=memtest {
    if [ -f /tools/memtest86.efi ]; then
        chainloader /tools/memtest86.efi
    elif [ -f /boot/memtest86+.efi ]; then
        chainloader /boot/memtest86+.efi
    else
        echo "Memory test not available"
        echo "Install memtest86+ or place memtest86.efi in /tools/"
        echo "Press any key to return to menu..."
        read
    fi
    boot
}

menuentry 'Hardware Detection Tool' --class hdt --id=hdt {
    if [ -f /tools/hdt.c32 ]; then
        linux16 /tools/hdt.c32
    else
        echo "HDT not available"
        echo "Press any key to return to menu..."
        read
    fi
}

EOM
EOF

    # 40_iso_entries template
    cat > "$grub_d_dir/40_iso_entries" << 'EOF'
#!/bin/bash
# Dynamic ISO Entries

if [ -n "$GRUB_TFTP_ROOT" ] && [ -d "$GRUB_TFTP_ROOT/kernels" ]; then
    echo ""
    echo "# === Available Installations ==="
    echo ""
    
    for iso_dir in "$GRUB_TFTP_ROOT/kernels"/*; do
        if [ -d "$iso_dir" ] && [ -f "$iso_dir/vmlinuz" ]; then
            iso_name=$(basename "$iso_dir")
            
            # Try to get ISO information
            if [ -f "$GRUB_TFTP_ROOT/../artifacts/iso/$iso_name.info" ]; then
                . "$GRUB_TFTP_ROOT/../artifacts/iso/$iso_name.info"
                title="${RELEASE_NAME:-$iso_name}"
                boot_params="${BOOT_PARAMS:-}"
            else
                title="$iso_name"
                boot_params="boot=live"
            fi
            
            echo "menuentry '$title' --class linux --id=$iso_name {"
            echo "    echo 'Loading $title...'"
            echo "    linux /kernels/$iso_name/vmlinuz $boot_params"
            echo "    initrd /initrd/$iso_name/initrd"
            echo "    boot"
            echo "}"
            echo ""
        fi
    done
fi
EOF

    # 90_footer template
    cat > "$grub_d_dir/90_footer" << 'EOF'
#!/bin/bash
# Footer entries

cat << EOM

# === System Control ===

menuentry 'Network Information' --class info --id=netinfo {
    echo "=== Network Configuration ==="
    echo "PXE Server: ${GRUB_PXE_SERVER_IP:-unknown}"
    echo "Client MAC: \$net_default_mac"
    echo "Client IP: (assigned by DHCP)"
    echo ""
    echo "TFTP Root: ${GRUB_TFTP_ROOT:-/var/lib/tftpboot}"
    echo "HTTP Root: ${GRUB_HTTP_ROOT:-/var/www/html/pxe}"
    echo "NFS Root: ${GRUB_NFS_ROOT:-/srv/nfs}"
    echo ""
    echo "Press any key to return to menu..."
    read
}

menuentry 'BIOS PXE Menu (Legacy)' --class legacy --id=legacy {
    echo 'To access BIOS PXE menu:'
    echo '1. Restart your system'
    echo '2. Enable Legacy/BIOS boot mode'
    echo '3. Boot from network again'
    echo ""
    echo 'Press any key to continue...'
    read
}

menuentry 'Reboot' --class restart --id=reboot {
    echo "Rebooting system..."
    reboot
}

menuentry 'Shutdown' --class shutdown --id=shutdown {
    echo "Shutting down system..."
    halt
}

EOM
EOF

    # Make templates executable
    chmod +x "$grub_d_dir"/*
    
    echo -e "${GREEN}OK${NC}"
}

# Function to post-process GRUB configuration
postprocess_grub_config() {
    local config_file="$1"
    
    echo -n "Post-processing GRUB configuration... "
    
    # Add PXE-specific enhancements
    local temp_file="/tmp/grub-postprocess-$$"
    
    # Process the configuration file
    {
        echo "# Post-processed for PXE boot optimization"
        echo "# Generated: $(date)"
        echo ""
        cat "$config_file"
        echo ""
        echo "# === PXE Boot Enhancements ==="
        echo "# End of configuration"
    } > "$temp_file"
    
    mv "$temp_file" "$config_file"
    
    echo -e "${GREEN}OK${NC}"
}

# Function to validate GRUB configuration
validate_grub_config() {
    local config_file="${1:-$TFTP_ROOT/grub/grub.cfg}"
    
    echo -e "${BLUE}Validating GRUB configuration...${NC}"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Error: Configuration file not found: $config_file${NC}"
        return 1
    fi
    
    # Check syntax with grub-script-check if available
    if command -v grub-script-check >/dev/null 2>&1; then
        echo -n "Checking GRUB script syntax... "
        if grub-script-check "$config_file" 2>/dev/null; then
            echo -e "${GREEN}Valid${NC}"
        else
            echo -e "${RED}Invalid${NC}"
            echo "Syntax errors found in GRUB configuration"
            return 1
        fi
    else
        echo -e "${YELLOW}grub-script-check not available, skipping syntax validation${NC}"
    fi
    
    # Basic structure validation
    echo -n "Checking configuration structure... "
    local issues=0
    
    if ! grep -q "set timeout" "$config_file"; then
        echo -e "${YELLOW}Warning: No timeout setting found${NC}"
        ((issues++))
    fi
    
    if ! grep -q "menuentry" "$config_file"; then
        echo -e "${RED}Error: No menu entries found${NC}"
        ((issues++))
    fi
    
    local entry_count
    entry_count=$(grep -c "^menuentry" "$config_file" || echo 0)
    
    if [[ $entry_count -eq 0 ]]; then
        echo -e "${RED}Error: No valid menu entries${NC}"
        ((issues++))
    else
        echo -e "${GREEN}$entry_count menu entries found${NC}"
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}Configuration structure is valid${NC}"
    else
        echo -e "${YELLOW}$issues issues found in configuration${NC}"
    fi
    
    return 0
}

# Function to create standalone GRUB image for PXE
create_grub_standalone() {
    local output_file="${1:-$TFTP_ROOT/grub-standalone.efi}"
    local modules="${2:-net efinet tftp http linux}"
    
    echo -e "${BLUE}Creating standalone GRUB image for PXE...${NC}"
    
    if ! command -v grub-mkstandalone >/dev/null 2>&1; then
        echo -e "${RED}Error: grub-mkstandalone not available${NC}"
        return 1
    fi
    
    echo -n "Creating standalone EFI image... "
    
    # Create temporary config for embedding
    local temp_config="/tmp/grub-embed-$$.cfg"
    cat > "$temp_config" << EOF
# Embedded GRUB configuration for PXE
set net_default_server=$PXE_SERVER_IP
set root=(tftp,\$net_default_server)
configfile /grub/grub.cfg
EOF
    
    # Create standalone image
    if grub-mkstandalone \
        --format=x86_64-efi \
        --output="$output_file" \
        --modules="$modules" \
        "boot/grub/grub.cfg=$temp_config" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        chown tftp:tftp "$output_file"
        chmod 644 "$output_file"
    else
        echo -e "${RED}Failed${NC}"
        rm -f "$temp_config"
        return 1
    fi
    
    rm -f "$temp_config"
    echo "Standalone GRUB image created: $output_file"
    return 0
}

# Function to show usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  check-tools              Check availability of GRUB tools"
    echo "  create-config [file]     Create advanced GRUB config using grub-mkconfig"
    echo "  create-simple [file]     Create simple GRUB config (no templates)"
    echo "  validate [file]          Validate GRUB configuration"
    echo "  create-standalone [file] Create standalone GRUB EFI image"
    echo "  help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check-tools"
    echo "  $0 create-config /tmp/grub.cfg"
    echo "  $0 validate /var/lib/tftpboot/grub/grub.cfg"
    echo "  $0 create-standalone /var/lib/tftpboot/grub-pxe.efi"
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "check-tools")
            check_grub_tools
            ;;
        "create-config")
            create_advanced_grub_config "${2:-}" true
            ;;
        "create-simple")
            create_advanced_grub_config "${2:-}" false
            ;;
        "validate")
            validate_grub_config "${2:-}"
            ;;
        "create-standalone")
            create_grub_standalone "${2:-}"
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
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