#!/bin/bash

# PXE Server Setup - Main Installation Script
# This script orchestrates the complete PXE server setup process

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if config file exists
if [[ ! -f "scripts/config.sh" ]]; then
    print_error "Configuration file scripts/config.sh not found!"
    print_status "Please copy scripts/config.sh.example to scripts/config.sh and edit it"
    exit 1
fi

# Parse command line arguments
ENABLE_UEFI=false
DHCP_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --uefi)
            ENABLE_UEFI=true
            shift
            ;;
        --local-dhcp)
            DHCP_MODE="--local"
            shift
            ;;
        --external-dhcp)
            DHCP_MODE="--external"
            shift
            ;;
        --help|-h)
            echo "PXE Server Installation Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --uefi              Enable UEFI support for Generation 2 VMs"
            echo "  --local-dhcp        Configure local DHCP server"
            echo "  --external-dhcp     Configure for external DHCP server"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo $0                           # Basic setup with prompts"
            echo "  sudo $0 --uefi --local-dhcp      # Full setup with UEFI and local DHCP"
            echo "  sudo $0 --external-dhcp          # Setup for external DHCP"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_status "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_header "PXE Server Setup - Starting Installation"

# Change to scripts directory
cd scripts

# Step 1: Prerequisites
print_header "Step 1: Checking Prerequisites"
./01-prerequisites.sh

# Step 2: Install packages
print_header "Step 2: Installing Packages"
./02-packages.sh

# Step 3: Configure TFTP
print_header "Step 3: Configuring TFTP Server"
./03-tftp-setup.sh

# Step 4: Configure DHCP
print_header "Step 4: Configuring DHCP"
if [[ -n "$DHCP_MODE" ]]; then
    ./04-dhcp-setup.sh $DHCP_MODE
else
    print_status "No DHCP mode specified. You can configure DHCP later with:"
    print_status "  sudo ./scripts/04-dhcp-setup.sh --local    # For local DHCP"
    print_status "  sudo ./scripts/04-dhcp-setup.sh --external # For external DHCP"
    print_warning "Skipping DHCP configuration..."
fi

# Step 5: Configure NFS
print_header "Step 5: Configuring NFS Server"
./05-nfs-setup.sh

# Step 6: Configure HTTP
print_header "Step 6: Configuring HTTP Server"
./06-http-setup.sh

# Step 7: Configure PXE Menu
print_header "Step 7: Configuring PXE Menu"
./07-pxe-menu.sh

# Step 8: UEFI Support (optional)
if [[ "$ENABLE_UEFI" == "true" ]]; then
    print_header "Step 8: Configuring UEFI Support"
    ./09-uefi-pxe-setup.sh
else
    print_status "UEFI support not enabled. You can add it later with:"
    print_status "  sudo ./scripts/09-uefi-pxe-setup.sh"
fi

# Final validation
print_header "Final Validation"
./validate-pxe.sh

print_header "Installation Complete!"
echo ""
print_status "PXE Server setup completed successfully!"
echo ""
print_status "Next steps:"
print_status "1. Add the downloaded Ubuntu ISO:"
print_status "   sudo ./scripts/08-iso-manager.sh add \$HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso"
print_status "2. Add additional ISO files to artifacts/iso/ directory"
print_status "3. Run: sudo ./scripts/08-iso-manager.sh add <iso-file> for other ISOs"
print_status "4. Configure client machines to boot from network"
echo ""

if [[ "$ENABLE_UEFI" == "true" ]]; then
    print_status "UEFI Support Enabled:"
    print_status "  - Generation 1 VMs: Use Legacy BIOS boot"
    print_status "  - Generation 2 VMs: Use UEFI boot"
else
    print_warning "UEFI Support Not Enabled:"
    print_status "  - Only Generation 1 VMs (BIOS) are supported"
    print_status "  - Run 'sudo ./scripts/09-uefi-pxe-setup.sh' to add Generation 2 VM support"
fi

echo ""
print_status "For troubleshooting, see: docs/troubleshooting.md"
print_status "For VM configuration, see VM Support section in README.md"
