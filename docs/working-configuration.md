# Working PXE Server Configuration

## Overview

This document captures the **verified working configuration** for UEFI PXE boot with Ubuntu Server 24.04.3 that successfully launches the Ubuntu installer interface.

**Status**: ✅ **WORKING** - Successfully boots to Ubuntu Server installer language selection screen  
**Date**: August 20, 2025  
**Tested with**: Generation 2 VM, UEFI PXE boot  

## Key Architecture Insight

The **critical difference** between working and non-working configurations:

- ✅ **WORKING**: Use **mounted ISO files** via NFS (preserves original Ubuntu live system structure)
- ❌ **BROKEN**: Use **extracted ISO contents** (loses casper compatibility)

## Working Configuration Details

### GRUB Configuration
**File**: `/var/lib/tftpboot/grub/grub.cfg`

```bash
# GRUB Config (Original working - mounted ISO approach)
set timeout=15
set default=0
terminal_output console
insmod efinet
insmod pxe
insmod net
insmod tftp
insmod linux

if [ -z "$net_default_ip" ]; then net_bootp; fi
set pxe_server=10.1.1.1
set iso_name=ubuntu-24.04.3-live-server-amd64

menuentry "Ubuntu Server 24.04.3 (Fixed NFS)" {
  net_bootp
  linux (tftp,$pxe_server)/kernels/${iso_name}/vmlinuz boot=casper netboot=nfs nfsroot=10.1.1.1:/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 ip=dhcp
  initrd (tftp,$pxe_server)/initrd/${iso_name}/initrd
}

menuentry "Boot from local disk" {
    set root=(hd0)
    chainloader /EFI/BOOT/BOOTX64.EFI
    boot
}

menuentry "Reboot" {
    reboot
}

menuentry "Shutdown" {
    halt
}
```

### Critical Boot Parameters
- `boot=casper` - Enables Ubuntu live boot system
- `netboot=nfs` - Specifies NFS as the network boot method  
- `nfsroot=10.1.1.1:/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64` - **Points to mounted ISO, not extracted files**
- `ip=dhcp` - Network configuration via DHCP

### ISO Mount Configuration
**Mount point**: `/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64`  
**Source**: `/home/cicorias/g/pxe-server-setup/artifacts/iso/ubuntu-24.04.3-live-server-amd64.iso`  
**Mount command**:
```bash
sudo mount -o loop,ro /home/cicorias/g/pxe-server-setup/artifacts/iso/ubuntu-24.04.3-live-server-amd64.iso /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64
```

### NFS Exports Configuration
**File**: `/etc/exports` (relevant entries)

```bash
/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64 10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)
/srv/nfs/scripts                               10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)  
/srv/nfs/preseed                               10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)
/srv/nfs/kickstart                             10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)
/srv/nfs/iso                                   10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)
/srv/nfs                                       10.1.1.0/24(ro,sync,no_subtree_check,no_root_squash)
```

### TFTP File Structure
```
/var/lib/tftpboot/
├── grub/
│   └── grub.cfg                    # GRUB UEFI configuration
├── kernels/
│   └── ubuntu-24.04.3-live-server-amd64/
│       ├── vmlinuz                 # Standard kernel (15MB)
│       └── hwe-vmlinuz            # Hardware enablement kernel (15.5MB)
└── initrd/
    └── ubuntu-24.04.3-live-server-amd64/
        ├── initrd                  # Standard initrd (74MB)
        └── hwe-initrd             # Hardware enablement initrd (76MB)
```

### Mounted ISO Structure (Read-Only)
```
/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64/
├── casper/
│   ├── filesystem.manifest         # Live system manifest
│   ├── filesystem.size            # Live system size
│   ├── vmlinuz                    # Kernel (matches TFTP)
│   ├── initrd                     # Initrd (matches TFTP)  
│   ├── hwe-vmlinuz               # HWE kernel
│   ├── hwe-initrd                # HWE initrd
│   ├── ubuntu-server-minimal.squashfs                    # Base system (164MB)
│   ├── ubuntu-server-minimal.ubuntu-server.squashfs      # Server components (145MB)
│   └── ubuntu-server-minimal.ubuntu-server.installer.squashfs  # Full installer (694MB)
├── .disk/
│   ├── info                       # Ubuntu release information
│   └── [other metadata]
└── [other ISO contents]
```

## Network Configuration

- **PXE Server IP**: 10.1.1.1
- **Client Network**: 10.1.1.0/24  
- **DHCP Range**: 10.1.1.100-10.1.1.200 (example)
- **NFS Protocol**: NFSv3/NFSv4
- **TFTP Port**: 69
- **NFS Ports**: 2049, 111 (rpcbind)

## Service Status (All Active)

```bash
● tftpd-hpa.service - LSB: HPA's tftp server
● nfs-kernel-server.service - NFS server and services  
● rpcbind.service - RPC bind portmap service
● apache2.service - The Apache HTTP Server (for HTTP access)
```

## Boot Flow (Working)

1. **UEFI PXE Boot**: Client requests bootx64.efi via TFTP
2. **GRUB Load**: GRUB loads and displays menu  
3. **Kernel/Initrd**: Downloads vmlinuz and initrd via TFTP
4. **Network Setup**: Client gets IP via DHCP (10.1.1.105)
5. **NFS Mount**: Casper mounts `/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64` via NFS
6. **Live System**: Ubuntu live system launches with preserved ISO structure
7. **Installer**: Ubuntu Server installer interface appears

## Critical Success Factors

### 1. Mounted ISO vs Extracted Files
- **✅ Use mounted ISO**: Preserves original casper-compatible structure
- **❌ Avoid extracted files**: Breaks casper live system detection

### 2. NFS Path Consistency  
- **nfsroot parameter** must match **actual NFS export path**
- **Path**: `/srv/nfs/iso/ubuntu-24.04.3-live-server-amd64` (not `/var/www/html/pxe/iso-direct/...`)

### 3. Casper Boot Parameters
- **Must include**: `boot=casper netboot=nfs`  
- **Must avoid**: Pure HTTP approaches for Ubuntu Server live systems

### 4. File Permissions
- **ISO mount**: Read-only (ro)
- **NFS export**: `no_root_squash` required for casper access
- **TFTP files**: Owned by `tftp:tftp`

## Failed Approaches (Documented)

### ❌ Extracted ISO with Symlinks
- **Tried**: Extract ISO to `/var/www/html/pxe/iso-direct/` and create filesystem.squashfs symlinks
- **Result**: "Unable to find a live file system on the network"
- **Reason**: Casper cannot detect proper live medium structure

### ❌ HTTP-Only Ubuntu Server Installer  
- **Tried**: `url=http://...` parameters without casper
- **Result**: Still launches casper, same errors
- **Reason**: initrd is hardcoded for live boot

### ❌ Different Kernel/Initrd Combinations
- **Tried**: HWE kernel/initrd, installer-specific files
- **Result**: Same casper errors
- **Reason**: All Ubuntu Server 24.04.3 initrds use casper

## Troubleshooting Commands

### Verify NFS Mounts
```bash
sudo showmount -e 10.1.1.1
sudo exportfs -v
```

### Check ISO Mount
```bash
mount | grep ubuntu-24.04.3
ls -la /srv/nfs/iso/ubuntu-24.04.3-live-server-amd64/casper/
```

### Monitor Boot Process  
```bash
sudo journalctl -u nfs-mountd --no-pager --since "5 minutes ago"
sudo journalctl -u tftpd-hpa --no-pager --since "5 minutes ago"
```

### Verify TFTP Files
```bash
ls -la /var/lib/tftpboot/kernels/ubuntu-24.04.3-live-server-amd64/
ls -la /var/lib/tftpboot/initrd/ubuntu-24.04.3-live-server-amd64/
```

## Implementation Notes

- This configuration works with **Ubuntu Server 24.04.3 LTS**
- Tested on **Generation 2 VMs** with **UEFI PXE boot**
- Requires **mounted ISO approach** (not extracted files)
- Uses **casper live boot system** (standard for Ubuntu)
- **NFS access** is essential for casper functionality

## Next Steps

1. **Update setup scripts** to implement this exact configuration
2. **Add validation** to ensure mounted ISO approach is used  
3. **Document cleanup script** impact and prevention
4. **Create automated testing** to verify working state
