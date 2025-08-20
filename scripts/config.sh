#!/bin/bash
# PXE Server Configuration
# Copy this file to config.sh and modify as needed

# Network Configuration
PXE_SERVER_IP="10.1.1.1"               # Static IP of PXE server
NETWORK_INTERFACE="eth0"                # Primary network interface
SUBNET="10.1.1.0"                      # Network subnet
NETMASK="255.255.255.0"                # Subnet mask
BROADCAST="10.1.1.255"                 # Broadcast address
GATEWAY="10.1.1.1"                     # Default gateway
DNS_SERVERS="8.8.8.8,8.8.4.4"         # DNS servers

# DHCP Configuration (for local DHCP mode)
DHCP_RANGE_START="10.1.1.100"          # DHCP range start
DHCP_RANGE_END="10.1.1.200"            # DHCP range end
DHCP_LEASE_TIME="86400"                # Lease time in seconds (24h)

# Directory Paths
TFTP_ROOT="/var/lib/tftpboot"          # TFTP root directory
NFS_ROOT="/srv/nfs"                    # NFS export root
HTTP_ROOT="/var/www/html/pxe"          # HTTP document root
ISO_DIR="$(pwd)/../artifacts/iso"      # ISO storage directory
ARTIFACTS_DIR="$(pwd)/../artifacts"    # Artifacts base directory

# Service Configuration
TFTP_SERVICE="tftpd-hpa"               # TFTP service name
DHCP_SERVICE="isc-dhcp-server"         # DHCP service name
NFS_SERVICE="nfs-kernel-server"        # NFS service name
HTTP_SERVICE="nginx"                   # HTTP service (apache2 or nginx)

# PXE Boot Configuration
PXELINUX_TIMEOUT="30"                  # Boot timeout in seconds
DEFAULT_BOOT_OPTION="local"            # Default boot option (local or first ISO)

# System Requirements
MIN_DISK_SPACE_GB="20"                 # Minimum free disk space in GB
REQUIRED_MEMORY_MB="2048"              # Minimum RAM in MB
