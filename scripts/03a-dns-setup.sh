#!/bin/bash
# 03a-dns-setup.sh
# DNS server configuration for PXE server setup

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
    echo "Required network settings must be configured before setting up DNS."
    exit 1
fi

# Validate required network configuration
required_vars=("NETWORK_INTERFACE" "PXE_SERVER_IP" "PXE_SERVER_HOSTNAME" "DOMAIN_NAME" "SUBNET" "NETMASK")
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

echo "=== DNS Server Configuration ==="

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
        exit 1
    fi
}

# Function to check if DNS is enabled
check_dns_enabled() {
    if [[ "${LOCAL_DNS_ENABLED:-false}" != "true" ]]; then
        echo -e "${YELLOW}DNS server is disabled in configuration (LOCAL_DNS_ENABLED=false)${NC}"
        echo "To enable DNS server, set LOCAL_DNS_ENABLED=true in config.sh"
        echo "Skipping DNS configuration..."
        exit 0
    fi
}

# Function to backup existing DNS configuration
backup_dns_config() {
    echo -e "${BLUE}Backing up existing DNS configuration...${NC}"
    
    local backup_dir="/etc/bind/backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -f /etc/bind/named.conf.local ]]; then
        echo -n "Backing up named.conf.local... "
        cp /etc/bind/named.conf.local "$backup_dir/"
        echo -e "${GREEN}OK${NC}"
    fi
    
    if [[ -f /etc/bind/named.conf.options ]]; then
        echo -n "Backing up named.conf.options... "
        cp /etc/bind/named.conf.options "$backup_dir/"
        echo -e "${GREEN}OK${NC}"
    fi
    
    echo "Backup created at: $backup_dir"
}

# Function to configure DNS server options
configure_dns_options() {
    echo -e "${BLUE}Configuring DNS server options...${NC}"
    
    # Calculate network address for reverse zone
    IFS='.' read -ra IP_PARTS <<< "$PXE_SERVER_IP"
    local reverse_zone="${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}.in-addr.arpa"
    
    echo -n "Creating named.conf.options... "
    cat > /etc/bind/named.conf.options << EOF
options {
    directory "/var/cache/bind";
    
    // Listen on all interfaces
    listen-on { any; };
    listen-on-v6 { any; };
    
    // Allow queries from local network
    allow-query { localhost; ${SUBNET}/${NETMASK#*.*.*.}; };
    allow-recursion { localhost; ${SUBNET}/${NETMASK#*.*.*.}; };
    
    // Forward unresolved queries to external DNS
    forwarders {
$(echo "$DNS_SERVERS" | tr ',' '\n' | sed 's/^/        /; s/$/;/')
    };
    
    // Security settings
    dnssec-validation auto;
    auth-nxdomain no;
    
    // Disable IPv6 if not needed
    filter-aaaa-on-v4 yes;
};
EOF
    echo -e "${GREEN}OK${NC}"
}

# Function to create local zone configuration
configure_local_zones() {
    echo -e "${BLUE}Configuring local DNS zones...${NC}"
    
    # Calculate reverse zone
    IFS='.' read -ra IP_PARTS <<< "$PXE_SERVER_IP"
    local reverse_zone="${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}.in-addr.arpa"
    
    echo -n "Creating local zone configuration... "
    cat > /etc/bind/named.conf.local << EOF
//
// PXE Server Local DNS Zones
//

// Forward zone for $DOMAIN_NAME
zone "$DOMAIN_NAME" {
    type master;
    file "/etc/bind/db.$DOMAIN_NAME";
};

// Reverse zone for $SUBNET
zone "$reverse_zone" {
    type master;
    file "/etc/bind/db.${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}";
};
EOF
    echo -e "${GREEN}OK${NC}"
}

# Function to create forward zone file
create_forward_zone() {
    echo -e "${BLUE}Creating forward DNS zone file...${NC}"
    
    echo -n "Creating forward zone for $DOMAIN_NAME... "
    cat > "/etc/bind/db.$DOMAIN_NAME" << EOF
;
; BIND data file for $DOMAIN_NAME
;
\$TTL    604800
@       IN      SOA     $PXE_SERVER_HOSTNAME.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
                        $(date +%Y%m%d%H)     ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.
@       IN      A       $PXE_SERVER_IP

; PXE Server records
$PXE_SERVER_HOSTNAME    IN      A       $PXE_SERVER_IP
pxe                     IN      CNAME   $PXE_SERVER_HOSTNAME
tftp                    IN      CNAME   $PXE_SERVER_HOSTNAME
nfs                     IN      CNAME   $PXE_SERVER_HOSTNAME
http                    IN      CNAME   $PXE_SERVER_HOSTNAME
dhcp                    IN      CNAME   $PXE_SERVER_HOSTNAME

; Service records
_tftp._udp              IN      SRV     0 5 69 $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.
_nfs._tcp               IN      SRV     0 5 2049 $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.
_http._tcp              IN      SRV     0 5 80 $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.
EOF
    echo -e "${GREEN}OK${NC}"
}

# Function to create reverse zone file
create_reverse_zone() {
    echo -e "${BLUE}Creating reverse DNS zone file...${NC}"
    
    IFS='.' read -ra IP_PARTS <<< "$PXE_SERVER_IP"
    local reverse_zone="${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}"
    
    echo -n "Creating reverse zone for $SUBNET... "
    cat > "/etc/bind/db.$reverse_zone" << EOF
;
; BIND reverse data file for $SUBNET
;
\$TTL    604800
@       IN      SOA     $PXE_SERVER_HOSTNAME.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
                        $(date +%Y%m%d%H)     ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.

; PTR records
${IP_PARTS[3]}    IN      PTR     $PXE_SERVER_HOSTNAME.$DOMAIN_NAME.
EOF
    echo -e "${GREEN}OK${NC}"
}

# Function to set permissions and validate configuration
configure_dns_permissions() {
    echo -e "${BLUE}Setting DNS file permissions and validating configuration...${NC}"
    
    echo -n "Setting file ownership... "
    chown root:bind /etc/bind/db.*
    chmod 644 /etc/bind/db.*
    echo -e "${GREEN}OK${NC}"
    
    echo -n "Validating DNS configuration... "
    if named-checkconf; then
        echo -e "${GREEN}Valid${NC}"
    else
        echo -e "${RED}Invalid${NC}"
        echo "Please check the DNS configuration for errors"
        exit 1
    fi
    
    echo -n "Validating zone files... "
    local zones_valid=true
    
    if ! named-checkzone "$DOMAIN_NAME" "/etc/bind/db.$DOMAIN_NAME" >/dev/null 2>&1; then
        echo -e "${RED}Forward zone invalid${NC}"
        zones_valid=false
    fi
    
    IFS='.' read -ra IP_PARTS <<< "$PXE_SERVER_IP"
    local reverse_zone="${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}"
    if ! named-checkzone "${reverse_zone}.in-addr.arpa" "/etc/bind/db.$reverse_zone" >/dev/null 2>&1; then
        echo -e "${RED}Reverse zone invalid${NC}"
        zones_valid=false
    fi
    
    if [[ "$zones_valid" == "true" ]]; then
        echo -e "${GREEN}Valid${NC}"
    else
        echo "Please check the zone files for errors"
        exit 1
    fi
}

# Function to start and enable DNS service
start_dns_service() {
    echo -e "${BLUE}Starting and enabling DNS service...${NC}"
    
    echo -n "Enabling bind9 service... "
    if systemctl enable bind9; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        exit 1
    fi
    
    echo -n "Starting bind9 service... "
    if systemctl start bind9; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        echo "Check service status with: systemctl status bind9"
        exit 1
    fi
    
    echo -n "Checking service status... "
    if systemctl is-active bind9 >/dev/null 2>&1; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
        exit 1
    fi
}

# Function to test DNS resolution
test_dns_resolution() {
    echo -e "${BLUE}Testing DNS resolution...${NC}"
    
    # Wait a moment for service to fully start
    sleep 2
    
    echo -n "Testing forward resolution... "
    if nslookup "$PXE_SERVER_HOSTNAME.$DOMAIN_NAME" localhost >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Forward resolution test failed${NC}"
    fi
    
    echo -n "Testing reverse resolution... "
    if nslookup "$PXE_SERVER_IP" localhost >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: Reverse resolution test failed${NC}"
    fi
    
    echo -n "Testing external resolution... "
    if nslookup google.com localhost >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Warning: External resolution test failed${NC}"
    fi
}

# Function to show DNS configuration summary
show_dns_summary() {
    echo -e "${GREEN}DNS server configuration completed successfully!${NC}"
    echo
    echo -e "${BLUE}DNS Server Summary:${NC}"
    echo "  Service: bind9"
    echo "  Domain: $DOMAIN_NAME"
    echo "  PXE Server: $PXE_SERVER_HOSTNAME.$DOMAIN_NAME -> $PXE_SERVER_IP"
    echo "  Listen Port: 53 (UDP/TCP)"
    echo
    echo -e "${BLUE}Available Hostnames:${NC}"
    echo "  $PXE_SERVER_HOSTNAME.$DOMAIN_NAME"
    echo "  pxe.$DOMAIN_NAME"
    echo "  tftp.$DOMAIN_NAME"
    echo "  nfs.$DOMAIN_NAME"
    echo "  http.$DOMAIN_NAME"
    echo "  dhcp.$DOMAIN_NAME"
    echo
    echo -e "${BLUE}Testing Commands:${NC}"
    echo "  nslookup $PXE_SERVER_HOSTNAME.$DOMAIN_NAME"
    echo "  dig @localhost $PXE_SERVER_HOSTNAME.$DOMAIN_NAME"
    echo "  systemctl status bind9"
    echo
    echo "Next steps:"
    echo "1. Configure TFTP server: sudo ./03-tftp-setup.sh"
    echo "2. Update DHCP to use DNS: sudo ./04-dhcp-setup.sh"
    echo "3. Configure remaining services with hostname support"
    echo
}

# Main execution
main() {
    echo "Starting DNS server configuration for PXE setup..."
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo

    check_root
    check_dns_enabled
    backup_dns_config
    configure_dns_options
    configure_local_zones
    create_forward_zone
    create_reverse_zone
    configure_dns_permissions
    start_dns_service
    test_dns_resolution
    show_dns_summary
}

# Run main function
main "$@"