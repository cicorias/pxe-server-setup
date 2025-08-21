#!/bin/bash
# test-pxe-client-access.sh
# Test script to verify PXE services are accessible from client network

echo "=== PXE Server Network Boot Test ==="
echo "Date: $(date)"
echo "Server IP: 10.1.1.1"
echo

# Test DHCP service
echo "1. Testing DHCP Service:"
if netstat -ulpn | grep -q ":67 "; then
    echo "  ✅ DHCP server listening on port 67"
else
    echo "  ❌ DHCP server not listening"
fi

# Test TFTP service
echo
echo "2. Testing TFTP Service:"
if netstat -ulpn | grep -q ":69 "; then
    echo "  ✅ TFTP server listening on port 69"
    
    # Test TFTP file access
    echo "  Testing TFTP file access..."
    if timeout 5 tftp 10.1.1.1 -c get pxelinux.0 /tmp/pxelinux.test 2>/dev/null; then
        echo "  ✅ TFTP file transfer successful"
        rm -f /tmp/pxelinux.test
    else
        echo "  ⚠️  TFTP connection issue (may be normal from server)"
    fi
else
    echo "  ❌ TFTP server not listening"
fi

# Test HTTP service
echo
echo "3. Testing HTTP Service:"
if netstat -tlpn | grep -q ":80 "; then
    echo "  ✅ HTTP server listening on port 80"
    
    # Test HTTP access
    if curl -s -o /dev/null -w "%{http_code}" http://10.1.1.1/ | grep -q "200"; then
        echo "  ✅ HTTP server responding correctly"
    else
        echo "  ⚠️  HTTP server response issue"
    fi
else
    echo "  ❌ HTTP server not listening"
fi

# Test NFS service
echo
echo "4. Testing NFS Service:"
if netstat -tlpn | grep -q ":2049 "; then
    echo "  ✅ NFS server listening on port 2049"
    
    # Test NFS exports
    if showmount -e 10.1.1.1 >/dev/null 2>&1; then
        echo "  ✅ NFS exports accessible"
        echo "  Available exports:"
        showmount -e 10.1.1.1 | tail -n +2 | sed 's/^/    /'
    else
        echo "  ⚠️  NFS exports not accessible"
    fi
else
    echo "  ❌ NFS server not listening"
fi

# Network connectivity test
echo
echo "5. Network Connectivity:"
echo "  Server network interface (10.1.1.1):"
ip addr show eth0 | grep "inet " | sed 's/^/    /'

echo "  DHCP lease range: 10.1.1.100 - 10.1.1.200"
echo "  Gateway: 10.1.1.1"
echo "  DNS: 8.8.8.8, 8.8.4.4"

echo
echo "6. Available Boot Options:"
if [[ -f /var/lib/tftpboot/pxelinux.cfg/default ]]; then
    echo "  PXE Menu Entries:"
    grep "^LABEL " /var/lib/tftpboot/pxelinux.cfg/default | sed 's/^/    /'
else
    echo "  ❌ PXE menu not found"
fi

echo
echo "=== Client VM Setup Instructions ==="
echo
echo "1. Create VM in Hyper-V Manager:"
echo "   - Memory: 2GB+ recommended"
echo "   - Network: Connect to private virtual switch"
echo "   - Boot order: Network Adapter first, then Hard Drive"
echo
echo "2. VM Settings:"
echo "   - Generation 1: Uses BIOS PXE boot"
echo "   - Generation 2: Requires UEFI network boot (advanced)"
echo "   - Secure Boot: Disabled"
echo
echo "3. Expected Boot Process:"
echo "   - VM gets IP from DHCP (10.1.1.100-200 range)"
echo "   - Downloads pxelinux.0 via TFTP"
echo "   - Displays PXE boot menu"
echo "   - Select Ubuntu Server 24.04.03 or other options"
echo
echo "4. Troubleshooting:"
echo "   - Ensure both VMs on same private virtual switch"
echo "   - Check VM firmware settings (disable secure boot)"
echo "   - Verify network adapter is first in boot order"
echo "   - Monitor server logs: sudo journalctl -f"
echo
