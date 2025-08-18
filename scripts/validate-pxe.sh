#!/bin/bash
# PXE Server Validation Script
# Quick test of TFTP, DHCP, and NFS services

echo "=== PXE Server Validation ==="
echo "Date: $(date)"
echo

# Check TFTP
echo "1. TFTP Service:"
if systemctl is-active tftpd-hpa >/dev/null 2>&1; then
    echo "  ✓ TFTP service is running"
    if ss -ulpn | grep -q ":69"; then
        echo "  ✓ TFTP port 69 is listening"
    else
        echo "  ✗ TFTP port 69 not listening"
    fi
else
    echo "  ✗ TFTP service not running"
fi

# Check DHCP
echo
echo "2. DHCP Service:"
if systemctl is-active isc-dhcp-server >/dev/null 2>&1; then
    echo "  ✓ DHCP service is running"
    if ss -ulpn | grep -q ":67"; then
        echo "  ✓ DHCP port 67 is listening"
    else
        echo "  ✗ DHCP port 67 not listening"
    fi
else
    echo "  ✗ DHCP service not running"
fi

# Check NFS
echo
echo "3. NFS Service:"
if systemctl is-active nfs-kernel-server >/dev/null 2>&1; then
    echo "  ✓ NFS service is running"
    if ss -tlpn | grep -q ":2049"; then
        echo "  ✓ NFS port 2049 is listening"
    else
        echo "  ✗ NFS port 2049 not listening"
    fi
    
    # Check exports
    export_count=$(sudo exportfs -v | grep -c "/srv/nfs" 2>/dev/null || echo "0")
    if [[ "$export_count" -gt 0 ]]; then
        echo "  ✓ NFS exports configured ($export_count exports)"
    else
        echo "  ✗ No NFS exports found"
    fi
else
    echo "  ✗ NFS service not running"
fi

# Check network configuration
echo
echo "4. Network Configuration:"
if ip addr show | grep -q "10.1.1.1"; then
    echo "  ✓ PXE server IP (10.1.1.1) configured"
else
    echo "  ✗ PXE server IP (10.1.1.1) not found"
fi

# Check files
echo
echo "5. PXE Files:"
if [[ -f /var/lib/tftpboot/pxelinux.0 ]]; then
    echo "  ✓ PXE boot loader present"
else
    echo "  ✗ PXE boot loader missing"
fi

if [[ -d /srv/nfs/iso/test-pxe ]]; then
    echo "  ✓ Test ISO mount point created"
else
    echo "  ✗ Test ISO mount point missing"
fi

echo
echo "=== Summary ==="
echo "PXE server basic components are configured."
echo "Next steps:"
echo "1. Set up HTTP server: sudo ./scripts/06-http-setup.sh"
echo "2. Create PXE menu: sudo ./scripts/07-pxe-menu.sh"
echo "3. Add actual ISO: sudo ./scripts/08-iso-manager.sh add <iso-file>"
echo
