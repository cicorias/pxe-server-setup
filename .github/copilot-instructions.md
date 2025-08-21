# Copilot Instructions for PXE Server Setup

## Project Overview
This repository automates the setup of a PXE (Preboot Execution Environment) server on Ubuntu 24.04 LTS. It uses native Ubuntu packages and shell scripts to configure TFTP, NFS, HTTP, and optionally DHCP services for network booting and OS installation.

## Key Architecture & Workflow
- **Scripts Directory**: All setup logic is in `scripts/`. Each script configures a specific service or step:
  - `01-prerequisites.sh`: Validates system requirements
  - `02-packages.sh`: Installs required packages
  - `03-tftp-setup.sh`: Configures TFTP server
  - `04-dhcp-setup.sh`: Configures DHCP (local or external)
  - `05-nfs-setup.sh`: Sets up NFS
  - `06-http-setup.sh`: Sets up HTTP
  - `07-pxe-menu.sh`: Configures PXE boot menu
  - `08-iso-manager.sh`: Manages ISO files
  - `09-uefi-pxe-setup.sh`: Configures UEFI PXE boot
  - `config.sh`: Central configuration variables
- **Artifacts Directory**: Stores generated files and boot assets:
  - `iso/`: Uploaded ISO files
  - `tftp/`: TFTP root and PXE menu
  - `http/`: HTTP root for installation files
- **Main Entry Point**: Run `sudo ./install.sh` for full setup, or execute scripts in order for granular control.

## Developer Workflows
- **Configuration**: Copy and edit `scripts/config.sh.example` to `scripts/config.sh` before running scripts.
- **Adding ISOs**: Place ISO files in `artifacts/iso/` and run `sudo ./scripts/08-iso-manager.sh add <iso>`.
- **PXE Menu**: Edit `artifacts/tftp/pxelinux.cfg/default` to customize boot options. Restart TFTP after changes.
- **Service Logs**: Use `journalctl` for TFTP/DHCP and `tail` for HTTP logs. See README for exact commands.
- **Troubleshooting**: Refer to `docs/troubleshooting.md` for common issues and solutions.

## Project-Specific Patterns
- **Idempotent Scripts**: All setup scripts are designed to be safely re-run.
- **DHCP Modes**: Choose between local DHCP (`--local`) or external DHCP (`--external`) via script flags.
- **ISO Management**: Use `08-iso-manager.sh` for add/list/remove operations. Supports batch ISO addition.
- **Artifacts Exclusion**: `artifacts/` is excluded from git; treat as ephemeral build/output directory.

## Integration Points
- **Services**: Integrates TFTP (tftpd-hpa), NFS, HTTP (apache2/nginx), DHCP (isc-dhcp-server), and Syslinux.
- **Network**: Requires static IP and open ports (see README for details).
- **External DHCP**: If using network DHCP, ensure PXE options are set on the external server.

## Conventions
- **Scripts**: Bash scripts, named and ordered by setup step. Always run as root/sudo.
- **Configuration**: All environment and network settings in `scripts/config.sh`.
- **Documentation**: Key usage and troubleshooting in `README.md` and `docs/troubleshooting.md`.

## Example Commands
- `sudo ./install.sh` — Full automated setup
- `sudo ./scripts/08-iso-manager.sh add ubuntu-24.04.3-server.iso` — Add ISO
- `sudo ./scripts/08-iso-manager.sh list` — List bootable ISOs
- `sudo nano artifacts/tftp/pxelinux.cfg/default` — Edit PXE menu

## References
- See `README.md` for architecture, workflow, and troubleshooting
- See `docs/troubleshooting.md` for service-specific issues
- Scripts in `scripts/` directory are the main automation entry points
- use [GRUB Guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/system_administrators_guide/ch-working_with_the_grub_2_boot_loader)

## Tool Instructions
- ensure following instructions in [patching-tool.md](./patching-tool.md)


## Directives
- Never suggest iPXE
- UEFI Boot is the priority
- BIOS Boot is deprecated
- avoid symlinks and use copy instead
- use native GRUB2 cli tools as needed
---
_Last updated: August 2025_
