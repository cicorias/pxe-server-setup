# PXE Server Configuration
# Test configuration for GRUB improvements

# Network Configuration
PXE_SERVER_IP="10.1.1.1"
NETWORK_INTERFACE="eth0"
SUBNET="10.1.1.0"
NETMASK="255.255.255.0"
BROADCAST="10.1.1.255"
GATEWAY="10.1.1.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"

# DHCP Configuration
DHCP_RANGE_START="10.1.1.100"
DHCP_RANGE_END="10.1.1.200"
DHCP_LEASE_TIME="86400"

# Directory Paths
TFTP_ROOT="/var/lib/tftpboot"
NFS_ROOT="/srv/nfs"
HTTP_ROOT="/var/www/html/pxe"
ISO_DIR="$(pwd)/../artifacts/iso"
ARTIFACTS_DIR="$(pwd)/../artifacts"

# Service Configuration
TFTP_SERVICE="tftpd-hpa"
DHCP_SERVICE="isc-dhcp-server"
NFS_SERVICE="nfs-kernel-server"
HTTP_SERVICE="nginx"

# PXE Boot Configuration
PXELINUX_TIMEOUT="30"
DEFAULT_BOOT_OPTION="local"

# System Requirements
MIN_DISK_SPACE_GB="20"
REQUIRED_MEMORY_MB="2048"