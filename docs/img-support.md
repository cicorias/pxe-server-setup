# IMG File Support for PXE Server

This document describes the IMG file support added to the PXE server setup, providing an alternative to traditional ISO files for network deployments.

## Overview

IMG files are now supported alongside ISO files, offering:
- **HTTP-based delivery**: Direct download of filesystem/disk images
- **Faster deployment**: Optimized for network transfers with caching and range requests  
- **Custom filesystems**: Support for ext4, xfs, btrfs and other filesystem images
- **Disk images**: Support for full disk images with partition tables
- **Backward compatibility**: All existing ISO functionality is preserved

## Supported IMG Types

### Filesystem Images
- **ext4, ext3, ext2**: Linux native filesystems
- **xfs**: High-performance filesystem  
- **btrfs**: Next-generation filesystem
- **Raw filesystems**: Direct filesystem dumps

### Disk Images
- **MBR/GPT**: Disk images with partition tables
- **Hybrid images**: Images with both filesystems and boot sectors

## Usage Examples

### Adding IMG Files
```bash
# Add a filesystem image
sudo ./scripts/08-iso-manager.sh add /path/to/custom-rootfs.img

# Add a disk image
sudo ./scripts/08-iso-manager.sh add /path/to/system-disk.img

# Add from current directory
sudo ./scripts/08-iso-manager.sh add ubuntu-custom.img
```

### Listing Files
```bash
# Shows both ISO and IMG files with type indicators
sudo ./scripts/08-iso-manager.sh list
```

### Removing Files
```bash
# Intelligent removal - detects ISO or IMG automatically
sudo ./scripts/08-iso-manager.sh remove custom-rootfs
```

## Boot Methods

The system supports multiple boot strategies for IMG files:

### Method 1: Extracted Kernel + HTTP Root (Recommended)
- Kernel and initrd extracted to TFTP
- IMG file served via HTTP
- Boot parameters: `url=http://server/images/file.img root=/dev/ram0 ip=dhcp`
- **Best for**: Custom Linux distributions with extractable kernels

### Method 2: Pure HTTP Boot (Experimental)
- Entire boot process via HTTP
- Requires OS support for HTTP IMG loading
- **Best for**: Specialized deployments with HTTP-aware bootloaders

### Method 3: HTTP-Only Menu Entry
- IMG files without extractable kernels
- Informational menu entries
- **Best for**: Documentation and manual deployment processes

## Directory Structure

```
artifacts/
├── iso/              # ISO files and metadata
│   ├── ubuntu.iso
│   └── ubuntu.info
└── img/              # IMG files and metadata  
    ├── custom.img
    └── custom.info

/var/www/html/pxe/
├── iso/              # Symlinks to mounted ISOs
├── images/           # Copied IMG files for HTTP access
│   ├── custom.img
│   └── system.img
└── index.html        # Updated with IMG section

/var/lib/tftpboot/
├── kernels/          # Extracted kernels (ISO + IMG)
│   ├── ubuntu/
│   └── custom/
├── initrd/           # Extracted initramfs (ISO + IMG)  
│   ├── ubuntu/
│   └── custom/
└── grub/grub.cfg     # Dynamic menu with both types
```

## HTTP Configuration

### nginx Location Block
```nginx
location /images/ {
    autoindex on;
    autoindex_exact_size on;
    autoindex_localtime on;
    
    # Large file optimization
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # Support for partial downloads (Range headers)
    add_header Accept-Ranges bytes;
    
    # Caching for IMG files
    expires 1d;
    add_header Cache-Control "public, immutable";
    
    # MIME type for IMG files
    location ~* \.img$ {
        add_header Content-Type application/octet-stream;
    }
}
```

### Access URLs
- IMG file listing: `http://server/images/`
- Direct IMG access: `http://server/images/filename.img`
- Main page with IMG section: `http://server/`

## GRUB Menu Integration

The GRUB configuration automatically detects IMG files and creates appropriate menu entries:

```grub
menuentry 'Custom Linux (IMG)' --id=custom {
    echo 'Loading Custom Linux from IMG...'
    linux /kernels/custom/vmlinuz url=http://10.1.1.1/images/custom.img root=/dev/ram0 ip=dhcp
    initrd /initrd/custom/initrd
    boot
}
```

## Configuration Options

### config.sh Settings
```bash
# IMG-specific directories
IMG_DIR="$PROJECT_ROOT/artifacts/img"
HTTP_IMAGES_DIR="$HTTP_ROOT/images"
IMG_STORAGE_DIR="$IMG_DIR"
```

### Detection and Mounting
The system automatically detects IMG file types and uses appropriate mounting strategies:
- **kpartx**: For disk images with partitions
- **loop devices**: For filesystem images  
- **blkid**: For filesystem type detection
- **file command**: For initial image type identification

## IMG vs ISO Guidelines

### Use IMG files for:
- **Custom deployments**: Pre-configured system images
- **Filesystem images**: Direct filesystem deployment
- **Network optimization**: Faster HTTP-based downloads
- **Specialized distributions**: Custom Linux builds
- **Development environments**: Rapid prototyping and testing

### Use ISO files for:
- **Ubuntu Server**: Live installations with casper support
- **Traditional OS installs**: Standard distribution ISOs
- **Legacy compatibility**: Systems expecting ISO 9660 format
- **Live systems**: Operating systems requiring mounted ISO structure

### Hybrid Environments
Both file types can coexist on the same PXE server:
- ISO files use NFS mounting for casper compatibility
- IMG files use HTTP delivery for optimization
- GRUB menu shows both types with clear indicators
- Unified management through the same command interface

## Troubleshooting

### Common Issues

1. **IMG file not detected**
   - Verify file extension is `.img`
   - Check filesystem type with `blkid filename.img`
   - Ensure file is readable

2. **Boot fails with IMG file**
   - Check if kernel/initrd were extracted
   - Verify HTTP access to images directory
   - Review GRUB menu entry parameters

3. **Large IMG files slow to transfer**
   - Verify nginx range header support
   - Check client HTTP/1.1 support
   - Monitor network bandwidth

### Log Locations
- **nginx access**: `/var/log/nginx/pxe-access.log`
- **nginx errors**: `/var/log/nginx/pxe-error.log`
- **TFTP service**: `journalctl -u tftpd-hpa`
- **IMG processing**: Console output during add operations

## Migration from ISO-Only

To migrate an existing ISO-only PXE server:

1. **Update configuration**:
   ```bash
   cp scripts/config.sh.example scripts/config.sh
   # Edit with IMG-specific paths
   ```

2. **Update HTTP server**:
   ```bash
   sudo ./scripts/06-http-setup.sh
   ```

3. **Regenerate GRUB config**:
   ```bash
   sudo ./scripts/09-uefi-pxe-setup.sh
   ```

4. **Add IMG files**:
   ```bash
   sudo ./scripts/08-iso-manager.sh add your-image.img
   ```

## Security Considerations

- **File validation**: Only .iso and .img extensions accepted
- **Directory permissions**: Proper www-data ownership for HTTP files
- **Access control**: Standard nginx security headers applied
- **File integrity**: Recommend checksums for deployed IMG files

## Performance Optimization

- **HTTP caching**: 1-day cache for IMG files
- **Range requests**: Support for partial downloads
- **Sendfile**: Zero-copy file transfer in nginx
- **Compression**: Consider gzip for smaller IMG files (optional)

---

*For more information, see the main [README.md](../README.md) and [troubleshooting guide](troubleshooting.md).*