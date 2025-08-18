#!/bin/bash
# 01-prerequisites.sh
# System prerequisites validation for PXE server setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo "Required network settings must be configured:"
    echo "  - NETWORK_INTERFACE"
    echo "  - PXE_SERVER_IP" 
    echo "  - SUBNET"
    echo "  - NETMASK"
    echo "  - GATEWAY"
    exit 1
fi

# Validate required network configuration
echo -n "Validating required network configuration... "
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "SUBNET" "NETMASK" "GATEWAY")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo -e "${RED}FAILED${NC}"
    echo "Error: Missing required network configuration variables in config.sh:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo
    echo "Please edit $SCRIPT_DIR/config.sh and set all required network variables."
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi

echo "=== PXE Server Prerequisites Check ==="

# Function to check if running as root
check_root() {
    echo -n "Checking root privileges... "
    if [[ $EUID -eq 0 ]]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: This script must be run as root or with sudo"
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    echo -n "Checking Ubuntu version... "
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            echo -e "${GREEN}OK (Ubuntu $VERSION_ID)${NC}"
        else
            echo -e "${YELLOW}WARNING${NC}"
            echo "Warning: This script is designed for Ubuntu 24.04. Current: $PRETTY_NAME"
            echo "Continue at your own risk."
            read -p "Do you want to continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: Cannot determine OS version"
        exit 1
    fi
}

# Function to check available disk space
check_disk_space() {
    echo -n "Checking available disk space... "
    local available_space=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [[ $available_space -ge $MIN_DISK_SPACE_GB ]]; then
        echo -e "${GREEN}OK (${available_space}GB available)${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: Insufficient disk space. Required: ${MIN_DISK_SPACE_GB}GB, Available: ${available_space}GB"
        exit 1
    fi
}

# Function to check available memory
check_memory() {
    echo -n "Checking available memory... "
    local available_memory=$(free -m | awk 'NR==2 {print $2}')
    
    if [[ $available_memory -ge $REQUIRED_MEMORY_MB ]]; then
        echo -e "${GREEN}OK (${available_memory}MB available)${NC}"
    else
        echo -e "${YELLOW}WARNING${NC}"
        echo "Warning: Low memory. Recommended: ${REQUIRED_MEMORY_MB}MB, Available: ${available_memory}MB"
        echo "PXE server may work but performance could be affected."
    fi
}

# Function to check network connectivity
check_network() {
    echo -n "Checking network connectivity... "
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: No internet connectivity. Required for package installation."
        exit 1
    fi
}

# Function to check network interface
check_network_interface() {
    echo -n "Checking network interface ($NETWORK_INTERFACE)... "
    if ip link show "$NETWORK_INTERFACE" &> /dev/null; then
        echo -e "${GREEN}OK${NC}"
        
        # Check if interface has an IP address
        local interface_ip=$(ip addr show "$NETWORK_INTERFACE" | grep -oP 'inet \K[\d.]+' | head -1)
        if [[ -n "$interface_ip" ]]; then
            echo "  Current IP: $interface_ip"
            if [[ "$interface_ip" != "$PXE_SERVER_IP" ]]; then
                echo -e "  ${YELLOW}Note: Current IP differs from configured PXE_SERVER_IP ($PXE_SERVER_IP)${NC}"
            fi
        else
            echo -e "  ${YELLOW}Warning: Interface has no IP address assigned${NC}"
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: Network interface '$NETWORK_INTERFACE' not found"
        echo "Available interfaces:"
        ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://' | grep -v lo
        exit 1
    fi
}

# Function to check if required ports are available
check_ports() {
    echo "Checking port availability..."
    local ports=("69:tftp" "80:http" "111:nfs" "2049:nfs")
    local failed_ports=()
    
    for port_info in "${ports[@]}"; do
        local port=$(echo "$port_info" | cut -d: -f1)
        local service=$(echo "$port_info" | cut -d: -f2)
        
        echo -n "  Port $port ($service)... "
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${YELLOW}IN USE${NC}"
            local process=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            echo "    Process: $process"
            failed_ports+=("$port:$service")
        else
            echo -e "${GREEN}AVAILABLE${NC}"
        fi
    done
    
    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Some ports are already in use.${NC}"
        echo "This may indicate existing services that could conflict."
        echo "The installation scripts will attempt to configure services properly."
    fi
}

# Function to check firewall status
check_firewall() {
    echo -n "Checking firewall status... "
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            echo -e "${YELLOW}ACTIVE${NC}"
            echo "  UFW firewall is active. You may need to configure rules for PXE services."
            echo "  Required ports: 69/udp (TFTP), 80/tcp (HTTP), 111/tcp+udp, 2049/tcp+udp (NFS)"
        else
            echo -e "${GREEN}INACTIVE${NC}"
        fi
    else
        echo -e "${GREEN}UFW NOT INSTALLED${NC}"
    fi
}

# Function to create required directories
create_directories() {
    echo "Creating required directories..."
    local base_dir="$(dirname "$SCRIPT_DIR")"
    local dirs=("$base_dir/artifacts" "$base_dir/artifacts/iso" "$base_dir/artifacts/tftp" "$base_dir/artifacts/http")
    
    for dir in "${dirs[@]}"; do
        echo -n "  Creating $dir... "
        if mkdir -p "$dir" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            echo "Error: Cannot create directory $dir"
            exit 1
        fi
    done
}

# Function to check package manager
check_package_manager() {
    echo -n "Checking package manager... "
    if command -v apt >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        
        # Check if apt is locked
        echo -n "Checking apt lock status... "
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            echo -e "${RED}LOCKED${NC}"
            echo "Error: Another package manager is running. Please wait and try again."
            exit 1
        else
            echo -e "${GREEN}AVAILABLE${NC}"
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error: apt package manager not found"
        exit 1
    fi
}

# Main execution
main() {
    echo "Starting prerequisites check for PXE server setup..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo

    check_root
    check_ubuntu_version
    check_disk_space
    check_memory
    check_network
    check_network_interface
    check_ports
    check_firewall
    check_package_manager
    create_directories

    echo
    echo -e "${GREEN}=== Prerequisites check completed successfully! ===${NC}"
    echo
    echo "Next steps:"
    echo "1. Review and configure scripts/config.sh"
    echo "2. Run: sudo ./02-packages.sh"
    echo
}

# Run main function
main "$@"
