#!/bin/bash
# 04-dhcp-setup.sh
# DHCP server configuration for PXE server setup

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
    echo "Required network settings must be configured before setting up DHCP."
    exit 1
fi

# Validate required network configuration
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "SUBNET" "NETMASK" "GATEWAY")
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

# Default mode
DHCP_MODE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            DHCP_MODE="local"
            shift
            ;;
        --external)
            DHCP_MODE="external"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--local|--external]"
            echo
            echo "Options:"
            echo "  --local    Configure local DHCP server on this machine"
            echo "  --external Configure for use with existing network DHCP server"
            echo "  --help     Show this help message"
            echo
            echo "Examples:"
            echo "  $0 --local    # Set up ISC DHCP server locally"
            echo "  $0 --external # Configure for existing DHCP server"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no mode specified, ask user
if [[ -z "$DHCP_MODE" ]]; then
    echo -e "${BLUE}DHCP Configuration Mode Selection${NC}"
    echo
    echo "Choose DHCP configuration mode:"
    echo "1) Local DHCP server (install and configure ISC DHCP server on this machine)"
    echo "2) External DHCP server (use existing DHCP server on the network)"
    echo
    read -p "Enter your choice (1 or 2): " choice
    
    case $choice in
        1)
            DHCP_MODE="local"
            ;;
        2)
            DHCP_MODE="external"
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
fi

echo "=== DHCP Configuration ($DHCP_MODE mode) ==="

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to validate DHCP configuration for local mode
validate_dhcp_config() {
    if [[ "$DHCP_MODE" == "local" ]]; then
        local dhcp_vars=("DHCP_RANGE_START" "DHCP_RANGE_END" "DHCP_LEASE_TIME")
        local missing_dhcp_vars=()
        
        echo -n "Validating DHCP configuration... "
        
        for var in "${dhcp_vars[@]}"; do
            if [[ -z "${!var}" ]]; then
                missing_dhcp_vars+=("$var")
            fi
        done
        
        if [[ ${#missing_dhcp_vars[@]} -gt 0 ]]; then
            echo -e "${RED}FAILED${NC}"
            echo "Error: Missing required DHCP configuration variables in config.sh:"
            for var in "${missing_dhcp_vars[@]}"; do
                echo "  - $var"
            done
            echo
            echo "Please edit $SCRIPT_DIR/config.sh and set all required DHCP variables."
            exit 1
        else
            echo -e "${GREEN}OK${NC}"
        fi
    fi
}

# Function to backup existing DHCP configuration
backup_dhcp_config() {
    if [[ "$DHCP_MODE" == "local" ]]; then
        echo -n "Backing up existing DHCP configuration... "
        local backup_dir="/root/pxe-backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        if [[ -f /etc/dhcp/dhcpd.conf ]]; then
            cp /etc/dhcp/dhcpd.conf "$backup_dir/"
        fi
        
        if [[ -f /etc/default/isc-dhcp-server ]]; then
            cp /etc/default/isc-dhcp-server "$backup_dir/"
        fi
        
        echo -e "${GREEN}OK${NC}"
        echo "  Backup location: $backup_dir"
    fi
}

# Function to configure local DHCP server
configure_local_dhcp() {
    echo -e "${BLUE}Configuring local DHCP server...${NC}"
    
    # Stop DHCP service if running
    echo -n "Stopping DHCP service... "
    systemctl stop isc-dhcp-server 2>/dev/null || true
    echo -e "${GREEN}OK${NC}"
    
    # Configure DHCP daemon interface
    echo -n "Configuring DHCP daemon interface... "
    cat > /etc/default/isc-dhcp-server << EOF
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)

# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
DHCPDv4_CONF=/etc/dhcp/dhcpd.conf

# Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
DHCPDv4_PID=/var/run/dhcpd.pid

# Additional options to start dhcpd with.
OPTIONS=""

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
INTERFACESv4="$NETWORK_INTERFACE"

# IPv6 options
INTERFACESv6=""
EOF
    echo -e "${GREEN}OK${NC}"
    
    # Create DHCP configuration
    echo -n "Creating DHCP configuration file... "
    cat > /etc/dhcp/dhcpd.conf << EOF
# DHCP Server Configuration for PXE Boot
# Generated by PXE Server Setup Script

# Global DHCP Configuration
default-lease-time $DHCP_LEASE_TIME;
max-lease-time $(($DHCP_LEASE_TIME * 2));
authoritative;

# Logging
log-facility local7;

# PXE Boot Options
option architecture-type code 93 = unsigned integer 16;

# Subnet Configuration
subnet $SUBNET netmask $NETMASK {
    # DHCP Range
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    
    # Network Options
    option routers $GATEWAY;
    option domain-name-servers $DNS_SERVERS;
    option subnet-mask $NETMASK;
    option broadcast-address $BROADCAST;
    
    # PXE Boot Configuration
    next-server $PXE_SERVER_IP;
    
    # Boot file selection based on client architecture
    if option architecture-type = 00:07 or option architecture-type = 00:09 {
        # UEFI x64 clients
        filename "bootx64.efi";
    } elsif option architecture-type = 00:0b {
        # UEFI ARM64 clients  
        filename "bootaa64.efi";
    } elsif option architecture-type = 00:06 {
        # EFI IA32 clients
        filename "bootia32.efi";
    } else {
        # Legacy BIOS clients
        filename "pxelinux.0";
    }
    
    # Additional PXE options
    option tftp-server-name "$PXE_SERVER_IP";
}

# Host-specific configurations can be added here
# Example:
# host workstation1 {
#     hardware ethernet aa:bb:cc:dd:ee:ff;
#     fixed-address 10.1.1.50;
# }

# Class definitions for different client types
class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server $PXE_SERVER_IP;
    
    if option architecture-type = 00:07 or option architecture-type = 00:09 {
        filename "bootx64.efi";
    } elsif option architecture-type = 00:06 {
        filename "bootia32.efi";
    } else {
        filename "pxelinux.0";
    }
}
EOF
    echo -e "${GREEN}OK${NC}"
    
    # Validate DHCP configuration
    echo -n "Validating DHCP configuration syntax... "
    if dhcpd -t -cf /etc/dhcp/dhcpd.conf 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: DHCP configuration has syntax errors"
        echo "Check with: dhcpd -t -cf /etc/dhcp/dhcpd.conf"
        exit 1
    fi
}

# Function to start and enable local DHCP service
start_local_dhcp() {
    echo -e "${BLUE}Starting local DHCP service...${NC}"
    
    # Enable DHCP service
    echo -n "Enabling DHCP service... "
    systemctl enable isc-dhcp-server
    echo -e "${GREEN}OK${NC}"
    
    # Start DHCP service
    echo -n "Starting DHCP service... "
    if systemctl start isc-dhcp-server; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: Failed to start DHCP service"
        echo "Check logs with: journalctl -u isc-dhcp-server"
        echo "Check configuration with: dhcpd -t -cf /etc/dhcp/dhcpd.conf"
        exit 1
    fi
    
    # Check service status
    echo -n "Checking DHCP service status... "
    if systemctl is-active isc-dhcp-server >/dev/null 2>&1; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
        echo "Service status:"
        systemctl status isc-dhcp-server --no-pager -l
        exit 1
    fi
}

# Function to verify local DHCP service
verify_local_dhcp() {
    echo -e "${BLUE}Verifying local DHCP service...${NC}"
    
    # Check if DHCP port is listening
    echo -n "Checking DHCP port (67/UDP)... "
    # Use systemctl to check if DHCP is actually running and serving
    if systemctl is-active isc-dhcp-server >/dev/null 2>&1; then
        # Wait a moment for service to fully bind to port
        sleep 2
        # Double-check with port listening
        if ss -ulpn 2>/dev/null | grep -q ":67" || netstat -ulpn 2>/dev/null | grep -q ":67"; then
            echo -e "${GREEN}Listening${NC}"
        else
            echo -e "${YELLOW}Service active but port check unclear${NC}"
            echo "  (Service is running but port 67 not detected in socket list)"
        fi
    else
        echo -e "${RED}Not listening${NC}"
        echo "DHCP service may not be properly configured"
        exit 1
    fi
    
    # Check DHCP lease file
    echo -n "Checking DHCP lease file... "
    if [[ -f /var/lib/dhcp/dhcpd.leases ]]; then
        echo -e "${GREEN}Present${NC}"
    else
        echo -e "${YELLOW}Not found${NC} (will be created when first lease is issued)"
    fi
    
    # Check for DHCP conflicts
    echo -n "Checking for DHCP conflicts... "
    if command -v nmap >/dev/null 2>&1; then
        # Use nmap if available to check for other DHCP servers
        local dhcp_check=$(timeout 10 nmap --script broadcast-dhcp-discover 2>/dev/null | grep -c "DHCP Message Type: Offer" || echo "0")
        # Remove any newlines and whitespace from the result
        dhcp_check=$(echo "$dhcp_check" | tr -d '\n\r' | awk '{print $1}')
        # Ensure we have a valid number
        [[ "$dhcp_check" =~ ^[0-9]+$ ]] || dhcp_check=0
        
        if [[ "$dhcp_check" -eq 1 ]]; then
            echo -e "${GREEN}None detected${NC}"
        elif [[ "$dhcp_check" -gt 1 ]]; then
            echo -e "${YELLOW}Warning: Multiple DHCP servers detected${NC}"
        else
            echo -e "${GREEN}OK${NC}"
        fi
    else
        echo -e "${YELLOW}Skipped (nmap not available)${NC}"
    fi
    
    echo
    echo -e "${GREEN}Local DHCP service verification completed!${NC}"
}

# Function to show external DHCP configuration
configure_external_dhcp() {
    echo -e "${BLUE}External DHCP Server Configuration${NC}"
    echo
    echo "Since you're using an existing DHCP server on your network, you need to"
    echo "configure it to support PXE booting. The exact steps depend on your DHCP"
    echo "server type, but here are the general requirements:"
    echo
    
    echo -e "${YELLOW}Required DHCP Options:${NC}"
    echo "  Option 66 (TFTP Server Name): $PXE_SERVER_IP"
    echo "  Option 67 (Boot Filename): pxelinux.0 (for BIOS) or bootx64.efi (for UEFI)"
    echo "  Next Server: $PXE_SERVER_IP"
    echo
    
    echo -e "${YELLOW}Network Information:${NC}"
    echo "  PXE Server IP: $PXE_SERVER_IP"
    echo "  Network Interface: $NETWORK_INTERFACE"
    echo "  Subnet: $SUBNET"
    echo "  Netmask: $NETMASK"
    echo "  Gateway: $GATEWAY"
    echo
    
    echo -e "${BLUE}Configuration Examples:${NC}"
    echo
    
    echo -e "${YELLOW}1. ISC DHCP Server (dhcpd.conf):${NC}"
    cat << 'EOF'
subnet 10.1.1.0 netmask 255.255.255.0 {
    range 10.1.1.100 10.1.1.200;
    option routers 10.1.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    
    # PXE Configuration
    next-server 10.1.1.1;
    option tftp-server-name "10.1.1.1";
    
    # Architecture-specific boot files
    if option architecture-type = 00:07 or option architecture-type = 00:09 {
        filename "bootx64.efi";  # UEFI x64
    } else {
        filename "pxelinux.0";   # Legacy BIOS
    }
}
EOF
    echo
    
    echo -e "${YELLOW}2. Windows DHCP Server:${NC}"
    echo "  1. Open DHCP Management Console"
    echo "  2. Right-click on Scope Options → Configure Options"
    echo "  3. Enable Option 066 (Boot Server Host Name): $PXE_SERVER_IP"
    echo "  4. Enable Option 067 (Bootfile Name): pxelinux.0"
    echo "  5. Restart DHCP service"
    echo
    
    echo -e "${YELLOW}3. pfSense DHCP Server:${NC}"
    echo "  1. Go to Services → DHCP Server"
    echo "  2. Under 'Network booting':"
    echo "     - Enable network booting"
    echo "     - Next Server: $PXE_SERVER_IP"
    echo "     - Default BIOS file name: pxelinux.0"
    echo "     - UEFI 32 bit file name: bootia32.efi"
    echo "     - UEFI 64 bit file name: bootx64.efi"
    echo "  3. Save configuration"
    echo
    
    echo -e "${YELLOW}4. Ubiquiti UniFi (via SSH):${NC}"
    echo "  1. SSH to UniFi controller"
    echo "  2. Edit DHCP configuration:"
    echo "     configure"
    echo "     set service dhcp-server shared-network-name LAN subnet $SUBNET bootfile-server $PXE_SERVER_IP"
    echo "     set service dhcp-server shared-network-name LAN subnet $SUBNET bootfile-name pxelinux.0"
    echo "     commit; save"
    echo
    
    echo -e "${YELLOW}5. RouterOS (MikroTik):${NC}"
    echo "  /ip dhcp-server option"
    echo "  add code=66 name=tftp-server value=\"$PXE_SERVER_IP\""
    echo "  add code=67 name=bootfile value=\"pxelinux.0\""
    echo "  /ip dhcp-server network"
    echo "  set [find address=$SUBNET/$NETMASK] dhcp-option=tftp-server,bootfile"
    echo
    
    echo -e "${BLUE}Verification Steps:${NC}"
    echo "After configuring your DHCP server:"
    echo
    echo "1. Test DHCP lease renewal:"
    echo "   sudo dhclient -r $NETWORK_INTERFACE"
    echo "   sudo dhclient $NETWORK_INTERFACE"
    echo
    echo "2. Check DHCP options (if dhcping is available):"
    echo "   sudo dhcping -c $PXE_SERVER_IP -s $PXE_SERVER_IP"
    echo
    echo "3. Monitor DHCP requests:"
    echo "   sudo tcpdump -i $NETWORK_INTERFACE port 67 or port 68"
    echo
    echo "4. Test PXE boot with a client machine"
    echo
    
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "- Ensure DHCP server can reach the PXE server ($PXE_SERVER_IP)"
    echo "- Verify TFTP service is running: systemctl status tftpd-hpa"
    echo "- Check firewall allows DHCP (ports 67/68) and TFTP (port 69)"
    echo "- Verify boot files exist in TFTP root: ls -la /var/lib/tftpboot/"
    echo
    
    # Create a validation script for external DHCP
    echo -e "${BLUE}Creating DHCP validation script...${NC}"
    cat > /usr/local/bin/pxe-dhcp-check << 'EOF'
#!/bin/bash
# PXE DHCP Configuration Checker

echo "=== PXE DHCP Configuration Check ==="
echo

# Check TFTP service
echo -n "TFTP Service: "
if systemctl is-active tftpd-hpa >/dev/null 2>&1; then
    echo "Running"
else
    echo "Not running - start with: sudo systemctl start tftpd-hpa"
fi

# Check TFTP port
echo -n "TFTP Port 69: "
if netstat -ulpn 2>/dev/null | grep -q ":69 "; then
    echo "Listening"
else
    echo "Not listening"
fi

# Check boot files
echo -n "PXE Boot Files: "
if [[ -f /var/lib/tftpboot/pxelinux.0 ]]; then
    echo "Present"
else
    echo "Missing - run TFTP setup script"
fi

# Test TFTP
echo -n "TFTP Test: "
if timeout 5 tftp localhost -c get test.txt >/dev/null 2>&1; then
    echo "Success"
else
    echo "Failed - check TFTP configuration"
fi

echo
echo "To test DHCP options from a client, use:"
echo "  sudo dhclient -r && sudo dhclient -v"
echo
echo "Monitor for PXE requests with:"
echo "  sudo tcpdump -i any port 67 or port 68 or port 69"
EOF
    
    chmod +x /usr/local/bin/pxe-dhcp-check
    echo "  Created validation script: /usr/local/bin/pxe-dhcp-check"
    echo
}

# Function to show configuration summary
show_summary() {
    echo
    echo -e "${GREEN}=== DHCP Configuration Summary ===${NC}"
    echo "Mode: $DHCP_MODE"
    echo "PXE Server IP: $PXE_SERVER_IP"
    echo "Network Interface: $NETWORK_INTERFACE"
    echo "Subnet: $SUBNET/$NETMASK"
    echo
    
    if [[ "$DHCP_MODE" == "local" ]]; then
        echo "Local DHCP Server:"
        echo "  Service: $(systemctl is-active isc-dhcp-server 2>/dev/null || echo 'inactive')"
        echo "  Enabled: $(systemctl is-enabled isc-dhcp-server 2>/dev/null || echo 'disabled')"
        echo "  Range: $DHCP_RANGE_START - $DHCP_RANGE_END"
        echo "  Lease Time: $DHCP_LEASE_TIME seconds"
        echo
        echo "Configuration files:"
        echo "  - /etc/dhcp/dhcpd.conf"
        echo "  - /etc/default/isc-dhcp-server"
        echo
        echo "Monitor DHCP with:"
        echo "  sudo journalctl -u isc-dhcp-server -f"
        echo "  sudo tail -f /var/lib/dhcp/dhcpd.leases"
    else
        echo "External DHCP Server Configuration:"
        echo "  Configure your DHCP server with:"
        echo "  - Option 66 (TFTP Server): $PXE_SERVER_IP"
        echo "  - Option 67 (Boot File): pxelinux.0"
        echo "  - Next Server: $PXE_SERVER_IP"
        echo
        echo "Validation script: /usr/local/bin/pxe-dhcp-check"
    fi
    
    echo
    echo "Next steps:"
    echo "1. Configure NFS: sudo ./05-nfs-setup.sh"
    echo "2. Set up HTTP server: sudo ./06-http-setup.sh"
    echo "3. Create PXE menu: sudo ./07-pxe-menu.sh"
    echo
}

# Function to show firewall configuration help
show_firewall_help() {
    echo -e "${BLUE}Firewall Configuration Help:${NC}"
    echo
    if [[ "$DHCP_MODE" == "local" ]]; then
        echo "For local DHCP server, ensure these ports are open:"
        echo "  sudo ufw allow 67:68/udp comment 'DHCP'"
        echo "  sudo ufw allow 69/udp comment 'TFTP for PXE'"
    else
        echo "For external DHCP, ensure TFTP port is open:"
        echo "  sudo ufw allow 69/udp comment 'TFTP for PXE'"
    fi
    echo "  sudo ufw reload"
    echo
}

# Main execution
main() {
    echo "Starting DHCP configuration for PXE setup..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo "Mode: $DHCP_MODE"
    echo

    check_root
    validate_dhcp_config
    
    if [[ "$DHCP_MODE" == "local" ]]; then
        backup_dhcp_config
        configure_local_dhcp
        start_local_dhcp
        verify_local_dhcp
    else
        configure_external_dhcp
    fi
    
    show_summary
    
    # Check if firewall is active and show help
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        show_firewall_help
    fi
}

# Run main function
main "$@"
