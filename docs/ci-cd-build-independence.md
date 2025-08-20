# CI/CD and Build Machine Independence

This document explains how the PXE server setup has been modified to work in CI/CD environments without relying on packages installed on the build machine.

## Problem

The original PXE server setup scripts relied on files installed by packages on the host build machine:

- **SYSLINUX files** from `/usr/lib/syslinux/` and `/usr/lib/PXELINUX/`
- **GRUB EFI files** from `/usr/lib/grub/x86_64-efi-signed/`
- **Memory test files** from `/boot/` or `/usr/lib/memtest86+/`

This created a dependency on having specific packages installed on the build machine, making it unsuitable for CI/CD workflows or containerized builds.

## Solution

The solution extracts these files from Ubuntu packages directly, without requiring them to be installed on the build machine.

### New Script: `00-extract-boot-files.sh`

This script downloads and extracts the required boot files from Ubuntu 24.04 packages:

```bash
# Extract boot files for CI/CD environments
sudo ./scripts/00-extract-boot-files.sh --download-only

# Extract from Ubuntu ISO and download packages
sudo ./scripts/00-extract-boot-files.sh ubuntu-24.04.3-server.iso

# Extract only from ISO
sudo ./scripts/00-extract-boot-files.sh --iso-only ubuntu.iso
```

### Extracted Files

The script extracts files to `artifacts/extracted-boot-files/`:

```
artifacts/extracted-boot-files/
├── syslinux/
│   └── lib/
│       ├── PXELINUX/
│       │   └── pxelinux.0
│       └── syslinux/modules/bios/
│           ├── menu.c32
│           ├── vesamenu.c32
│           ├── ldlinux.c32
│           ├── libcom32.c32
│           └── libutil.c32
├── grub/
│   └── lib/grub/x86_64-efi-signed/
│       └── grubnetx64.efi.signed
└── memtest/
    └── memtest86+x64.bin
```

### Modified Scripts

All setup scripts now include a fallback mechanism:

1. **First try**: Use extracted files from `artifacts/extracted-boot-files/`
2. **Fallback**: Use files from host system packages (original behavior)

This ensures:
- ✅ **CI/CD compatibility**: Works without installing packages on build machine
- ✅ **Backward compatibility**: Still works with traditional installations
- ✅ **No breaking changes**: Existing workflows continue to work

## Usage in CI/CD

### GitHub Actions Example

```yaml
name: Build PXE Server Setup
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
    - uses: actions/checkout@v4
    
    - name: Extract boot files
      run: sudo ./scripts/00-extract-boot-files.sh --download-only
      
    - name: Setup PXE server
      run: sudo ./install.sh --uefi
```

### Docker Build Example

```dockerfile
FROM ubuntu:24.04

# Copy PXE setup scripts
COPY . /pxe-server-setup
WORKDIR /pxe-server-setup

# Extract boot files and setup PXE server
RUN apt-get update && apt-get install -y wget curl && \
    cp scripts/config.sh.example scripts/config.sh && \
    ./scripts/00-extract-boot-files.sh --download-only && \
    ./install.sh
```

## Integration

The boot file extraction is automatically integrated into the main installation process:

```
Step 1: Prerequisites
Step 2: Extract Boot Files  ← NEW
Step 3: Install Packages
Step 4: Configure TFTP
...
```

## Benefits

1. **CI/CD Ready**: Build PXE server artifacts in GitHub Actions, Jenkins, etc.
2. **Container Friendly**: Works in Docker containers without privileged access
3. **Reproducible**: Same boot files every time, regardless of build environment
4. **Self-Contained**: No external package dependencies during build
5. **Version Controlled**: Boot files can be cached and versioned as artifacts

## Package Sources

Boot files are downloaded from official Ubuntu 24.04 repositories:

- **SYSLINUX**: `syslinux-common` and `pxelinux` packages
- **GRUB EFI**: `grub-efi-amd64-signed` package  
- **Memtest**: `memtest86+` package

All downloads use HTTPS from `archive.ubuntu.com` for security and reliability.

## Migration Guide

### For Existing Users

No changes required! The scripts automatically detect and use extracted files when available, falling back to host packages if not.

### For CI/CD Users

1. Add extraction step before PXE setup:
   ```bash
   sudo ./scripts/00-extract-boot-files.sh --download-only
   ```

2. Run normal PXE setup:
   ```bash
   sudo ./install.sh
   ```

3. Archive the results as build artifacts for deployment.

## Troubleshooting

### Missing Boot Files

If extraction fails, check network connectivity and Ubuntu repository access:

```bash
# Test repository access
curl -I http://archive.ubuntu.com/ubuntu/

# Re-run extraction with verbose output
sudo bash -x ./scripts/00-extract-boot-files.sh --download-only
```

### Fallback Behavior

Scripts automatically fall back to host packages if extracted files aren't available:

```
  Copying pxelinux.0 from extracted files... OK
  Copying menu.c32 from host system... OK
```

This ensures compatibility with all environments.