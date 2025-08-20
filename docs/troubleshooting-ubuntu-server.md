# Ubuntu Server PXE Boot Troubleshooting Guide

## Common Error: "Unable to find a live file system on the network"

### Symptoms
- Client boots successfully via UEFI PXE
- Kernel and initrd load correctly  
- Network configuration works (gets DHCP lease)
- Casper runs but fails with: `Unable to find a live file system on the network`
- Falls back to: `Attempt interactive netboot from a URL?`

### Root Cause Analysis

This error occurs when **casper cannot detect a valid Ubuntu live system structure**. The Ubuntu casper boot process expects specific files and directory layouts that are preserved in the original ISO but lost when extracting ISO contents to directories.

### Solution: Use Mounted ISO Approach

#### ✅ Correct Approach (Working)
```bash
# Mount ISO directly
sudo mount -o loop,ro /path/to/ubuntu-24.04.3-live-server-amd64.iso /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64

# Export mounted ISO via NFS  
echo "/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)" >> /etc/exports
sudo exportfs -ra

# GRUB configuration points to mounted ISO
nfsroot=10.1.1.1:/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
```

#### ❌ Incorrect Approach (Broken)
```bash
# Extract ISO contents (BREAKS casper compatibility)
sudo mount -o loop ubuntu.iso /mnt/temp
sudo cp -r /mnt/temp/* /var/www/html/pxe/iso-direct/ubuntu/
sudo umount /mnt/temp

# Export extracted directory (casper cannot detect live system)
echo "/var/www/html/pxe/iso-direct/ubuntu 10.1.1.0/24(...)" >> /etc/exports
```

### Why Mounted ISO Works

1. **Preserves Original Structure**: ISO maintains exact directory layout expected by casper
2. **Read-Only Integrity**: Mounted ISO is immutable, preventing corruption
3. **Metadata Preservation**: `.disk/` directory and metadata files remain intact
4. **Squashfs Accessibility**: All squashfs files remain in original locations

### Verification Steps

1. **Check ISO Mount**:
   ```bash
   mount | grep ubuntu-24.04.3
   # Should show: /path/to/iso on /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 type iso9660
   ```

2. **Verify NFS Export**:
   ```bash
   sudo showmount -e localhost
   # Should list: /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
   ```

3. **Test NFS Access**:
   ```bash
   sudo mount -t nfs 10.1.1.1:/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 /mnt/test
   ls /mnt/test/casper/
   # Should show: filesystem.manifest, ubuntu-server-minimal.squashfs, etc.
   sudo umount /mnt/test
   ```

4. **Check GRUB Configuration**:
   ```bash
   grep "nfsroot" /var/lib/tftpboot/grub/grub.cfg
   # Should show: nfsroot=10.1.1.1:/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
   ```

## Other Common Issues

### Issue: Client Gets IP But No TFTP Response

**Symptoms**: Client gets DHCP lease but fails to download boot files

**Solutions**:
1. Check TFTP service: `sudo systemctl status tftpd-hpa`
2. Verify TFTP directory: `ls -la /var/lib/tftpboot/`
3. Check firewall: `sudo ufw status` (allow port 69)
4. Test TFTP manually: `tftp 10.1.1.1` then `get bootx64.efi`

### Issue: NFS Mount Fails

**Symptoms**: Casper reports NFS mount failures

**Solutions**:
1. Check NFS service: `sudo systemctl status nfs-kernel-server`
2. Verify exports: `sudo exportfs -v`
3. Check NFS firewall ports: 2049, 111
4. Test manual mount: `sudo mount -t nfs server:/path /mnt/test`

### Issue: Wrong Kernel/Initrd Used

**Symptoms**: Boot fails early or wrong hardware detection

**Solutions**:
1. Use standard kernel/initrd (not HWE) for most systems:
   ```bash
   linux (tftp,$pxe_server)/kernels/${iso_name}/vmlinuz
   initrd (tftp,$pxe_server)/initrd/${iso_name}/initrd
   ```
2. For newer hardware, try HWE versions:
   ```bash
   linux (tftp,$pxe_server)/kernels/${iso_name}/hwe-vmlinuz  
   initrd (tftp,$pxe_server)/initrd/${iso_name}/hwe-initrd
   ```

### Issue: GRUB Menu Doesn't Appear

**Symptoms**: Client boots but hangs at blank screen

**Solutions**:
1. Check GRUB file exists: `ls -la /var/lib/tftpboot/grub/grub.cfg`
2. Verify GRUB syntax: Check for missing quotes, braces
3. Test GRUB modules: Ensure `insmod` commands are correct
4. Check TFTP permissions: Files owned by `tftp:tftp`

## Debug Commands

### Monitor Live Boot Process
```bash
# Watch NFS access logs
sudo journalctl -u nfs-mountd -f

# Watch TFTP access logs  
sudo journalctl -u tftpd-hpa -f

# Check current mounts
mount | grep -E "(nfs|iso)"

# Monitor network traffic
sudo tcpdump -i eth0 port 69    # TFTP
sudo tcpdump -i eth0 port 2049  # NFS
```

### Validate Configuration Files
```bash
# Check GRUB syntax
sudo grub-script-check /var/lib/tftpboot/grub/grub.cfg

# Verify NFS exports
sudo exportfs -v

# Test NFS access
sudo showmount -e localhost
```

### Emergency Recovery

If configuration is broken and you need to restore working state:

1. **Mount ISO**:
   ```bash
   sudo mkdir -p /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
   sudo mount -o loop,ro /path/to/ubuntu-24.04.3-live-server-amd64.iso /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
   ```

2. **Add NFS Export**:
   ```bash
   echo "/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
   sudo exportfs -ra
   ```

3. **Restore GRUB Config**:
   ```bash
   sudo cp /var/lib/tftpboot/grub/grub.cfg.backup /var/lib/tftpboot/grub/grub.cfg
   # Or use the working configuration from docs/working-configuration.md
   ```

## Prevention

1. **Always backup working configurations** before making changes
2. **Use mounted ISO approach** instead of extracted files
3. **Test changes** on single client before deploying broadly  
4. **Document successful configurations** for future reference
5. **Avoid running cleanup scripts** unless necessary

## Key Takeaway

**The fundamental issue is architectural**: Ubuntu Server casper boot system requires the original ISO structure to be preserved. Extracting ISO contents to directories breaks this compatibility, while mounting the ISO maintains the required structure for successful live system detection.
