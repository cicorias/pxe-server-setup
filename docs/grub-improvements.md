# GRUB Configuration Improvements for PXE Server

This document describes the enhanced GRUB configuration system that leverages native GRUB CLI tools and follows the best practices outlined in `grub-cli-recommendations.md`. This implementation addresses the requirements from PR #5 while incorporating the architectural improvements recommended in PR #11.

## Overview

The PXE server setup has been enhanced with improved GRUB configuration management that:

1. **Uses native GRUB2 CLI tools** like `grub2-mkconfig`, `grub2-editenv`, and `grub2-script-check`
2. **Implements grubenv for persistent settings** following grub-cli-recommendations.md
3. **Uses GRUB's internal scripting** with `search` commands for device discovery
4. **Automatically updates GRUB configuration** when ISOs are added or removed
5. **Maintains compatibility** with the working mounted ISO approach
6. **Provides better template-based configuration** generation
7. **Validates GRUB syntax** using native validation tools

## Architecture Changes

### From Manual Configuration to Native Tools

**Before (Manual approach):**
- Static GRUB configuration files created with heredocs
- No use of GRUB's native configuration system
- No persistent settings management
- Hard-coded device paths

**After (Native CLI approach):**
- Uses `grub2-mkconfig` for standards-compliant configuration generation
- Implements `grubenv` for persistent settings via `grub2-editenv`
- Uses GRUB's `search` commands for device discovery
- Leverages GRUB's internal scripting capabilities

## New Scripts

### 1. grub-utilities.sh

A comprehensive GRUB utilities script that provides:

- **Tool Detection**: Automatically detects `grub2-*` commands with fallback to `grub-*`
- **grubenv Management**: Complete grubenv manipulation (`list`, `set`, `unset`, `get`)
- **Persistent Settings**: `grub2-set-default` and `grub2-reboot` integration
- **Configuration Validation**: Native `grub2-script-check` validation
- **Standalone Images**: `grub2-mkstandalone` support for custom EFI images

**Usage Examples:**
```bash
# Check available GRUB tools
./scripts/grub-utilities.sh check-tools

# Manage grubenv settings
./scripts/grub-utilities.sh grubenv list
./scripts/grub-utilities.sh grubenv set saved_entry ubuntu-server

# Set default and one-time boot entries
./scripts/grub-utilities.sh set-default local
./scripts/grub-utilities.sh set-reboot ubuntu-server

# Validate configuration
./scripts/grub-utilities.sh validate /var/lib/tftpboot/grub/grub.cfg

# Create standalone GRUB EFI image
sudo ./scripts/grub-utilities.sh create-standalone
```

### 2. grub-pxe-config-generator.sh

A sophisticated GRUB configuration generator that:

- **Uses grub2-mkconfig**: Leverages the official configuration generation system
- **Creates GRUB.d templates**: Modular configuration following GRUB.d conventions
- **Implements PR #11 patterns**: Search commands, network auto-discovery, grubenv support
- **Maintains ISO compatibility**: Works with the existing mounted ISO approach
- **Provides fallback support**: Manual configuration if native tools fail

**Usage Examples:**
```bash
# Generate configuration to a file
sudo ./scripts/grub-pxe-config-generator.sh generate /tmp/grub.cfg

# Generate and install to TFTP root
sudo ./scripts/grub-pxe-config-generator.sh install

# Update configuration after ISO changes
sudo ./scripts/grub-pxe-config-generator.sh add-iso ubuntu-server
```

## Enhanced Integration

### UEFI PXE Setup (09-uefi-pxe-setup.sh)

The UEFI setup script now:
- **Uses GRUB configuration generator** instead of manual config creation
- **Sets up grubenv** for persistent settings management
- **Provides enhanced fallback** with PR #11 best practices
- **Implements device discovery** using `search` commands

### ISO Manager (08-iso-manager.sh)

The ISO manager now:
- **Automatically regenerates GRUB configuration** when ISOs are added
- **Updates GRUB configuration** when ISOs are removed  
- **Uses native GRUB tools** for configuration updates
- **Maintains backward compatibility** with legacy update methods

## GRUB Tools Integration

The enhanced system leverages these GRUB tools with automatic fallback:

1. **grub2-mkconfig** → **grub-mkconfig** - Generate GRUB configuration from templates
2. **grub2-script-check** → **grub-script-check** - Validate GRUB script syntax
3. **grub2-editenv** → **grub-editenv** - Manage GRUB environment variables
4. **grub2-set-default** → **grub-set-default** - Set default boot entry
5. **grub2-reboot** → **grub-reboot** - Set one-time boot entry
6. **grub2-mkstandalone** → **grub-mkstandalone** - Create standalone GRUB images
7. **update-grub** - Debian/Ubuntu-specific configuration update

## Configuration Templates

The system now supports GRUB.d-style configuration templates:

- **00_header** - Basic GRUB setup, module loading, and network initialization
- **10_local_boot** - Enhanced local boot options with device discovery
- **20_system_tools** - System tools (memory test, HDT) with search functionality
- **40_iso_entries** - Dynamic ISO installation entries with casper compatibility
- **90_footer** - System control (reboot, shutdown, network info)

## Key Features Following PR #11 Recommendations

### 1. grubenv for Persistent Settings

Instead of editing `grub.cfg` directly:

```bash
# Set default entry persistently
./scripts/grub-utilities.sh set-default ubuntu-server

# Set one-time boot entry
./scripts/grub-utilities.sh set-reboot local

# Manage environment variables directly
./scripts/grub-utilities.sh grubenv set custom_option value
```

### 2. GRUB Internal Scripting

Enhanced configuration with native GRUB scripting:

```grub
# Load grubenv for persistent settings
load_env

# Use saved_entry from grubenv
if [ -z "$default" ]; then
    set default="${saved_entry}"
fi

# Network auto-discovery
net_bootp
if [ -n "$net_default_gateway" ]; then
    set pxe_server=$net_default_gateway
else
    set pxe_server=192.168.1.1
fi
```

### 3. Device Discovery with Search Commands

Following PR #11 recommendations for robust device handling:

```grub
menuentry 'Boot from local disk' {
    # Use search command for device discovery
    search --no-floppy --set=root --label /
    if [ -z "$root" ]; then
        search --no-floppy --fs-uuid --set=root $(probe -u (hd0,gpt1)) 2>/dev/null
    fi
    
    if [ -n "$root" ]; then
        # Multiple boot path attempts
        if [ -f /EFI/BOOT/BOOTX64.EFI ]; then
            chainloader /EFI/BOOT/BOOTX64.EFI
        elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        fi
    fi
    boot
}
```

## Benefits

### 1. Standards Compliance
- Uses GRUB's native configuration system
- Follows GRUB.d conventions for modular configuration
- Provides proper syntax validation with native tools

### 2. Enhanced Reliability
- Automatic fallback to manual configuration if tools fail
- Device discovery instead of hard-coded paths
- Proper error handling and validation

### 3. Better Maintainability
- Template-based configuration generation
- Separation of concerns (utilities vs. configuration)
- Clear integration points with existing scripts

### 4. Persistent Settings Management
- Uses grubenv for atomic configuration updates
- No direct grub.cfg editing required for settings changes
- Persistent default entry management

### 5. Improved User Experience
- Interactive GRUB CLI debugging support
- Enhanced network information display
- Better error messages and fallback options

## Migration and Compatibility

### Existing PXE Servers
The enhanced system maintains full backward compatibility:

1. **Automatic detection** - Uses new tools if available, falls back to manual methods
2. **Configuration preservation** - Respects existing grub.cfg files
3. **ISO compatibility** - Works with the existing mounted ISO approach
4. **Service integration** - No changes to TFTP/NFS/HTTP services required

### Working Configuration Integration
The system is fully compatible with the documented working configuration:

- **Mounted ISO approach** - Maintains casper compatibility
- **NFS exports** - Uses correct nfsroot parameters
- **Boot parameters** - Preserves working casper boot settings

## Testing and Validation

### Syntax Validation
```bash
# Validate GRUB configuration syntax
./scripts/grub-utilities.sh validate /var/lib/tftpboot/grub/grub.cfg

# Check tool availability
./scripts/grub-utilities.sh check-tools
```

### Functional Testing
```bash
# Test new ISO addition
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04.3-live-server-amd64.iso

# Verify GRUB configuration was updated
cat /var/lib/tftpboot/grub/grub.cfg

# Test grubenv functionality
./scripts/grub-utilities.sh grubenv list
```

## Troubleshooting

### Common Issues

1. **GRUB tools not available**
   ```bash
   sudo apt update && sudo apt install grub2-common grub-efi-amd64-bin
   ```

2. **Configuration syntax errors**
   ```bash
   ./scripts/grub-utilities.sh validate /var/lib/tftpboot/grub/grub.cfg
   ```

3. **Network boot failures**
   - Verify network configuration in `scripts/config.sh`
   - Check DHCP server configuration
   - Use network information menu entry for debugging

### Debug Mode

Enable verbose output:
```bash
export GRUB_DEBUG=1
sudo ./scripts/grub-pxe-config-generator.sh install
```

## Future Enhancements

Potential future improvements:
1. **Automated ISO detection** - Scan for new ISOs automatically
2. **Web-based GRUB management** - GUI for menu configuration
3. **Multi-architecture support** - ARM64, i386 configurations
4. **Advanced boot options** - Kernel parameters, custom boot scripts
5. **Integration testing** - Automated PXE boot testing

## Examples

### Complete Setup Workflow

```bash
# 1. Configure PXE server
sudo cp scripts/config.sh.example scripts/config.sh
sudo nano scripts/config.sh

# 2. Set up UEFI PXE with enhanced GRUB
sudo ./scripts/09-uefi-pxe-setup.sh

# 3. Add an ISO (GRUB config automatically updated)
sudo ./scripts/08-iso-manager.sh add ubuntu-24.04-server.iso

# 4. Set persistent default entry
./scripts/grub-utilities.sh set-default ubuntu-server

# 5. Validate configuration
./scripts/grub-utilities.sh validate
```

### Advanced GRUB Management

```bash
# Create custom standalone GRUB image
sudo ./scripts/grub-utilities.sh create-standalone /var/lib/tftpboot/custom-grub.efi

# Set one-time boot entry for testing
./scripts/grub-utilities.sh set-reboot local

# Manage custom environment variables
./scripts/grub-utilities.sh grubenv set debug_mode on
./scripts/grub-utilities.sh grubenv set custom_timeout 60
```

This enhanced GRUB system provides a robust, maintainable, and standards-compliant foundation for PXE server GRUB configuration management while maintaining full compatibility with existing workflows and the documented working configuration.