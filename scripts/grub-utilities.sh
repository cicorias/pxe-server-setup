#!/bin/bash
# grub-utilities.sh
# Enhanced GRUB utilities for PXE server management
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
fi

# Function to check GRUB tools availability (prioritizing grub2-* commands)
check_grub_tools() {
    echo -e "${BLUE}Checking GRUB tools availability...${NC}"
    
    local tools=(
        "grub2-mkconfig:grub-mkconfig:Generate GRUB configuration"
        "grub2-install:grub-install:Install GRUB to devices"
        "grub2-script-check:grub-script-check:Validate GRUB scripts"
        "grub2-editenv:grub-editenv:Manage GRUB environment"
        "grub2-set-default:grub-set-default:Set default boot entry"
        "grub2-reboot:grub-reboot:Set one-time boot entry"
        "update-grub::Update GRUB configuration (Debian/Ubuntu)"
        "grub2-mkstandalone:grub-mkstandalone:Create standalone GRUB images"
        "grub2-mknetdir:grub-mknetdir:Create network boot directory"
    )
    
    local available_tools=()
    local missing_tools=()
    
    # Map of preferred command to fallback
    declare -A tool_map
    tool_map["grub-mkconfig"]=""
    tool_map["grub-script-check"]=""
    tool_map["grub-editenv"]=""
    tool_map["grub-set-default"]=""
    tool_map["grub-reboot"]=""
    tool_map["grub-mkstandalone"]=""
    tool_map["grub-mknetdir"]=""
    
    for tool_desc in "${tools[@]}"; do
        IFS=':' read -r preferred fallback desc <<< "$tool_desc"
        echo -n "  Checking $preferred... "
        
        if command -v "$preferred" >/dev/null 2>&1; then
            echo -e "${GREEN}Available${NC} - $desc"
            available_tools+=("$preferred")
            tool_map["${fallback:-$preferred}"]="$preferred"
        elif [[ -n "$fallback" ]] && command -v "$fallback" >/dev/null 2>&1; then
            echo -e "${YELLOW}Using fallback: $fallback${NC} - $desc"
            available_tools+=("$fallback")
            tool_map["$fallback"]="$fallback"
        else
            echo -e "${RED}Missing${NC} - $desc"
            missing_tools+=("$preferred")
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
    
    # Export tool mappings for use by other functions
    export GRUB_MKCONFIG="${tool_map["grub-mkconfig"]:-grub-mkconfig}"
    export GRUB_SCRIPT_CHECK="${tool_map["grub-script-check"]:-grub-script-check}"
    export GRUB_EDITENV="${tool_map["grub-editenv"]:-grub-editenv}"
    export GRUB_SET_DEFAULT="${tool_map["grub-set-default"]:-grub-set-default}"
    export GRUB_REBOOT="${tool_map["grub-reboot"]:-grub-reboot}"
    export GRUB_MKSTANDALONE="${tool_map["grub-mkstandalone"]:-grub-mkstandalone}"
    
    return 0
}

# Function to manage GRUB environment (following PR #11 recommendations)
manage_grubenv() {
    local action="$1"
    local grubenv_file="${2:-$TFTP_ROOT/grub/grubenv}"
    local key="${3:-}"
    local value="${4:-}"
    
    echo -e "${BLUE}Managing GRUB environment...${NC}"
    
    # Ensure grubenv file exists
    if [[ ! -f "$grubenv_file" ]]; then
        echo -n "Creating grubenv file... "
        mkdir -p "$(dirname "$grubenv_file")"
        if command -v "$GRUB_EDITENV" >/dev/null 2>&1; then
            "$GRUB_EDITENV" "$grubenv_file" create
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed - grub-editenv not available${NC}"
            return 1
        fi
    fi
    
    case "$action" in
        "list")
            echo "GRUB environment variables:"
            "$GRUB_EDITENV" "$grubenv_file" list
            ;;
        "set")
            if [[ -z "$key" || -z "$value" ]]; then
                echo -e "${RED}Error: Key and value required for set operation${NC}"
                return 1
            fi
            echo -n "Setting $key=$value... "
            "$GRUB_EDITENV" "$grubenv_file" set "$key=$value"
            echo -e "${GREEN}OK${NC}"
            ;;
        "unset")
            if [[ -z "$key" ]]; then
                echo -e "${RED}Error: Key required for unset operation${NC}"
                return 1
            fi
            echo -n "Unsetting $key... "
            "$GRUB_EDITENV" "$grubenv_file" unset "$key"
            echo -e "${GREEN}OK${NC}"
            ;;
        "get")
            if [[ -z "$key" ]]; then
                echo -e "${RED}Error: Key required for get operation${NC}"
                return 1
            fi
            "$GRUB_EDITENV" "$grubenv_file" list | grep "^$key=" | cut -d'=' -f2-
            ;;
        *)
            echo -e "${RED}Error: Unknown action '$action'${NC}"
            echo "Available actions: list, set, unset, get"
            return 1
            ;;
    esac
}

# Function to set default boot entry using native GRUB tools
set_default_entry() {
    local entry_id="$1"
    local grubenv_file="${2:-$TFTP_ROOT/grub/grubenv}"
    
    echo -e "${BLUE}Setting default boot entry...${NC}"
    
    if command -v "$GRUB_SET_DEFAULT" >/dev/null 2>&1; then
        echo -n "Setting default to '$entry_id'... "
        "$GRUB_SET_DEFAULT" "$entry_id"
        echo -e "${GREEN}OK${NC}"
    else
        echo -n "Using grubenv fallback... "
        manage_grubenv "set" "$grubenv_file" "saved_entry" "$entry_id"
    fi
}

# Function to set one-time boot entry
set_reboot_entry() {
    local entry_id="$1"
    local grubenv_file="${2:-$TFTP_ROOT/grub/grubenv}"
    
    echo -e "${BLUE}Setting one-time boot entry...${NC}"
    
    if command -v "$GRUB_REBOOT" >/dev/null 2>&1; then
        echo -n "Setting reboot entry to '$entry_id'... "
        "$GRUB_REBOOT" "$entry_id"
        echo -e "${GREEN}OK${NC}"
    else
        echo -n "Using grubenv fallback... "
        manage_grubenv "set" "$grubenv_file" "next_entry" "$entry_id"
    fi
}

# Function to validate GRUB configuration using native tools
validate_grub_config() {
    local config_file="${1:-$TFTP_ROOT/grub/grub.cfg}"
    
    echo -e "${BLUE}Validating GRUB configuration...${NC}"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Error: Configuration file not found: $config_file${NC}"
        return 1
    fi
    
    # Check syntax with grub-script-check if available
    if command -v "$GRUB_SCRIPT_CHECK" >/dev/null 2>&1; then
        echo -n "Checking GRUB script syntax... "
        if "$GRUB_SCRIPT_CHECK" "$config_file" 2>/dev/null; then
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

# Function to create standalone GRUB image following PR #11 recommendations
create_grub_standalone() {
    local output_file="${1:-$TFTP_ROOT/grub-standalone.efi}"
    local modules="${2:-efinet pxe tftp http linux normal configfile search search_fs_file search_fs_uuid search_label}"
    
    echo -e "${BLUE}Creating standalone GRUB image for PXE...${NC}"
    
    if ! command -v "$GRUB_MKSTANDALONE" >/dev/null 2>&1; then
        echo -e "${RED}Error: grub-mkstandalone not available${NC}"
        return 1
    fi
    
    echo -n "Creating standalone EFI image... "
    
    # Create temporary config for embedding (following PR #11 patterns)
    local temp_config="/tmp/grub-embed-$$.cfg"
    cat > "$temp_config" << EOF
# Embedded GRUB configuration for PXE (follows grub-cli-recommendations.md)
set timeout=5

# Load essential modules
insmod pxe
insmod tftp
insmod net

# Network initialization and server discovery
net_bootp
if [ -z "\$net_default_ip" ]; then
    echo "Network configuration failed"
    sleep 2
fi

# Set PXE server using discovered or configured IP
if [ -n "\$net_default_gateway" ]; then
    set pxe_server=\$net_default_gateway
else
    set pxe_server=${PXE_SERVER_IP:-192.168.1.1}
fi

set root=(tftp,\$pxe_server)
set prefix=\$root/grub

# Load main configuration if available
if [ -f \$prefix/grub.cfg ]; then
    configfile \$prefix/grub.cfg
else
    echo "Main GRUB configuration not found"
    echo "Expected: \$prefix/grub.cfg"
    echo "Press any key to continue..."
    read
fi
EOF
    
    # Create standalone image
    if "$GRUB_MKSTANDALONE" \
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
    echo "  check-tools                    Check availability of GRUB tools"
    echo "  grubenv <action> [file] [key] [value]  Manage GRUB environment"
    echo "    Actions: list, set, unset, get"
    echo "  set-default <entry> [grubenv]  Set default boot entry"
    echo "  set-reboot <entry> [grubenv]   Set one-time boot entry"
    echo "  validate [file]                Validate GRUB configuration"
    echo "  create-standalone [file]       Create standalone GRUB EFI image"
    echo "  help                           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check-tools"
    echo "  $0 grubenv list"
    echo "  $0 grubenv set saved_entry ubuntu-server"
    echo "  $0 set-default local"
    echo "  $0 validate /var/lib/tftpboot/grub/grub.cfg"
    echo "  $0 create-standalone /var/lib/tftpboot/grub-pxe.efi"
}

# Main function
main() {
    local command="${1:-help}"
    
    # Initialize tool mappings
    check_grub_tools >/dev/null 2>&1
    
    case "$command" in
        "check-tools")
            check_grub_tools
            ;;
        "grubenv")
            manage_grubenv "${2:-list}" "${3:-}" "${4:-}" "${5:-}"
            ;;
        "set-default")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: Entry ID required${NC}"
                exit 1
            fi
            set_default_entry "$2" "${3:-}"
            ;;
        "set-reboot")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: Entry ID required${NC}"
                exit 1
            fi
            set_reboot_entry "$2" "${3:-}"
            ;;
        "validate")
            validate_grub_config "${2:-}"
            ;;
        "create-standalone")
            create_grub_standalone "${2:-}" "${3:-}"
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