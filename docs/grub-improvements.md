# GRUB Configuration Improvements for PXE Server

This document describes the enhanced GRUB configuration system that leverages native GRUB tools like `grub-mkconfig` and related utilities for better PXE server management.

## Overview

The PXE server setup has been enhanced with improved GRUB configuration management that:

1. **Uses native GRUB tools** like `grub-mkconfig` instead of manual configuration creation
2. **Automatically updates GRUB configuration** when ISOs are added or removed
3. **Provides better template-based configuration** generation
4. **Validates GRUB syntax** using `grub-script-check`
5. **Supports advanced GRUB features** like standalone images and custom modules

## New Scripts

### 1. grub-pxe-config-generator.sh

A comprehensive GRUB configuration generator that:
- Uses `grub-mkconfig` for standard configuration generation
- Creates dynamic menu entries for available ISOs
- Provides fallback configuration for environments where `grub-mkconfig` is not available
- Automatically scans for available ISOs and creates appropriate menu entries

**Usage:**
```bash
# Generate GRUB configuration to a file
sudo ./scripts/grub-pxe-config-generator.sh generate /tmp/grub.cfg

# Generate and install to TFTP root
sudo ./scripts/grub-pxe-config-generator.sh install

# Create custom GRUB.d script for system integration
sudo ./scripts/grub-pxe-config-generator.sh grub.d
```

### 2. grub-utilities.sh

Advanced GRUB utilities for PXE server management:
- Checks availability of GRUB tools
- Creates advanced configurations using templates
- Validates GRUB configuration syntax
- Creates standalone GRUB images for specialized deployments

**Usage:**
```bash
# Check which GRUB tools are available
./scripts/grub-utilities.sh check-tools

# Create advanced GRUB configuration with templates
sudo ./scripts/grub-utilities.sh create-config

# Validate a GRUB configuration file
./scripts/grub-utilities.sh validate /var/lib/tftpboot/grub/grub.cfg

# Create standalone GRUB EFI image
sudo ./scripts/grub-utilities.sh create-standalone
```

## Integration with Existing Scripts

### UEFI PXE Setup (09-uefi-pxe-setup.sh)

The UEFI setup script has been enhanced to:
- Use the new GRUB configuration generator instead of manual config creation
- Provide fallback to manual configuration if GRUB tools are not available
- Generate more comprehensive and standards-compliant GRUB configurations

### ISO Manager (08-iso-manager.sh)

The ISO manager now:
- Automatically regenerates GRUB configuration when ISOs are added
- Updates GRUB configuration when ISOs are removed
- Maintains consistency between BIOS PXE menu and UEFI GRUB menu

## GRUB Tools Used

The enhanced system leverages these GRUB tools:

1. **grub-mkconfig** - Generate GRUB configuration from templates
2. **grub-script-check** - Validate GRUB script syntax
3. **grub-install** - Install GRUB to devices
4. **grub-mkstandalone** - Create standalone GRUB images
5. **grub-mknetdir** - Create network boot directory
6. **update-grub** - Debian/Ubuntu-specific configuration update

## Configuration Templates

The system now supports GRUB.d-style configuration templates:

- **00_header** - Basic GRUB setup and module loading
- **10_pxe_entries** - Local boot options
- **20_tools** - System tools (memory test, HDT)
- **40_iso_entries** - Dynamic ISO installation entries
- **90_footer** - System control (reboot, shutdown, network info)

## Benefits

### 1. Better Standards Compliance
- Uses GRUB's native configuration system
- Follows GRUB.d conventions for modular configuration
- Provides proper syntax validation

### 2. Dynamic Configuration
- Automatically updates when ISOs change
- No manual editing of configuration files required
- Consistent menu structure across BIOS and UEFI

### 3. Enhanced Error Handling
- Configuration syntax validation
- Fallback to manual configuration if tools fail
- Better error reporting and diagnostics

### 4. Improved Maintainability
- Template-based configuration generation
- Separation of concerns (tools vs. configuration)
- Easier to extend and customize

## Migration from Manual Configuration

Existing PXE servers can be upgraded to use the new system:

1. **Update UEFI setup**: The `09-uefi-pxe-setup.sh` script automatically uses the new system
2. **Regenerate configuration**: Run the GRUB generator to create updated configuration
3. **Test functionality**: Use the validation tools to ensure everything works correctly

## Advanced Features

### Standalone GRUB Images

Create self-contained GRUB EFI images:
```bash
sudo ./scripts/grub-utilities.sh create-standalone /var/lib/tftpboot/grub-pxe.efi
```

### Custom Module Loading

The new system loads comprehensive GRUB modules for PXE boot:
- Network modules (net, efinet, tftp, http)
- Filesystem modules (fat, ext2, part_gpt, part_msdos)
- Boot modules (linux, multiboot, chain)

### Enhanced Network Configuration

Better network initialization and configuration:
- Automatic DHCP configuration
- Support for multiple network interfaces
- Improved network debugging information

## Troubleshooting

### Common Issues

1. **GRUB tools not available**
   - Install: `sudo apt install grub2-common grub-efi-amd64-bin`
   - The system provides fallback manual configuration

2. **Configuration syntax errors**
   - Use: `./scripts/grub-utilities.sh validate <config-file>`
   - Check logs for specific syntax issues

3. **Network boot failures**
   - Verify network configuration in `scripts/config.sh`
   - Check DHCP server configuration
   - Test with network information menu entry

### Debugging

Enable verbose output by setting debug variables:
```bash
export GRUB_DEBUG=1
sudo ./scripts/grub-pxe-config-generator.sh install
```

## Future Enhancements

Potential future improvements:
1. **Automated ISO detection** - Scan for new ISOs automatically
2. **Web-based configuration** - GUI for GRUB menu management
3. **Multi-architecture support** - ARM64, i386 configurations
4. **Advanced boot options** - Kernel parameters, custom boot scripts

## Examples

### Basic Usage

Generate and install GRUB configuration:
```bash
# Configure PXE server
sudo cp scripts/config.sh.example scripts/config.sh
sudo nano scripts/config.sh

# Generate GRUB configuration
sudo ./scripts/grub-pxe-config-generator.sh install

# Add an ISO
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04-server.iso

# Configuration is automatically updated!
```

### Advanced Configuration

Create custom GRUB configuration with templates:
```bash
# Check available tools
./scripts/grub-utilities.sh check-tools

# Create advanced configuration
sudo ./scripts/grub-utilities.sh create-config

# Validate the result
./scripts/grub-utilities.sh validate /var/lib/tftpboot/grub/grub.cfg
```

This enhanced GRUB system provides a much more robust and maintainable approach to PXE server configuration management while maintaining compatibility with existing setups.