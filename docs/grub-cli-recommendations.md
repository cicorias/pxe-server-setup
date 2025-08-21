# GRUB 2 Native CLI Recommendations

This document outlines best practices for using GRUB 2's native CLI and companion user‑land tools instead of ad‑hoc scripts that directly edit or regenerate `grub.cfg`. By leveraging GRUB's built‑in scripting, environment store, device probing, and official helper utilities, your PXE‑boot configuration becomes more robust, maintainable, and easier to iterate on.

## 1. Drive persistent settings via `grubenv`

Avoid sed‑ing or appending menu entries in your shipped `grub.cfg`. Instead, use GRUB's environment block for atomic updates:

```bash
# Set the default entry (zero‑based index) persistently
grub2-set-default 2

# Reboot into entry 0 just once
grub2-reboot 0

# Operate directly on the environment file
grub2-editenv /var/lib/tftpboot/grub/grubenv list
grub2-editenv /var/lib/tftpboot/grub/grubenv set myflag=yes
```

These commands let GRUB read/write a small state file (`grubenv`) without you touching `grub.cfg` at all.

## 2. Use GRUB's internal scripting in `grub.cfg`

Rather than generating multiple static `grub.cfg` variants, embed logic directly into a single master file:

```cfg
set timeout=5
set default=0

if [ "${grub_platform}" = "efi" ]; then
  set arch=x86_64-efi
else
  set arch=i386-pc
fi

echo "Loading ${arch} config..."
configfile (tftp,${pxe_server_ip})/grub/${arch}/grub.cfg
```

And within each sub‑config (`grub/x86_64-efi/grub.cfg`):

```cfg
menuentry "Ubuntu Live Installer (${arch})" {
  linux (tftp,${pxe_server_ip})/live/${iso_name}/vmlinuz \
        boot=casper netboot=nfs nfsroot=${pxe_server_ip}:/srv/nfs/iso/${iso_name} ip=dhcp ---
  initrd (tftp,${pxe_server_ip})/live/${iso_name}/initrd
}
```

This approach centralizes your menu logic in GRUB itself, eliminating external text munging.

## 3. Probe and mount devices within GRUB

Hard‑coding device names in scripts is fragile. Use GRUB's `search` command to auto‑discover partitions by UUID or label:

```cfg
search --no-floppy --fs-uuid --set=root abcd-1234-ef56-7890
# or by filesystem label
search --no-floppy --label --set=root LIVE-UBUNTU

linux /vmlinuz root=/dev/ram0 ramdisk_size=150000 ip=dhcp ---
initrd /initrd.img
boot
```

For network boot, load modules and probe DHCP/TFTP servers on the fly:

```cfg
insmod pxe
insmod tftp
net_bootp
set prefix=(tftp,${net_default_gateway})/grub
configfile ${prefix}/grub.cfg
```

## 4. Leverage `grub2-mkconfig` and `grub2-mkstandalone`

Your scripts need not handcraft `grub.cfg`. Use the official tools:

```bash
# Generate a menu from /etc/default/grub and /etc/grub.d/*
grub2-mkconfig -o /var/lib/tftpboot/grub/grub.cfg

# Build a self‑contained EFI executable with desired modules
grub2-mkstandalone \
  --format=x86_64-efi \
  --output=/var/lib/tftpboot/grubnetx64.efi \
  --modules="tftp pxe http linux normal" \
  /boot/grub2/grub.cfg=/var/lib/tftpboot/grub/grub.cfg
```

This delegates validity checks and complex syntax handling to GRUB’s own code.

## 5. Test interactively with the GRUB CLI

Before committing any PXE script changes, drop to the GRUB prompt (press `c`) and experiment:

```text
grub> set debug=all
grub> search --fs-uuid --set=root abcd-1234
grub> linux /vmlinuz boot=casper netboot=nfs nfsroot=10.0.0.1:/srv/nfs/iso/ubuntu ip=dhcp ---
grub> initrd /initrd.img
grub> boot
```

Iterating live in the GRUB shell drastically cuts down trial‑and‑error in your shell scripts.

## 6. Summary of key benefits

| Pain Point                          | GRUB CLI Alternative                                    | Benefit                           |
|-------------------------------------|---------------------------------------------------------|-----------------------------------|
| Scripted grub.cfg munging           | `grub2-editenv`, `grub2-set-default`, `grub2-reboot`     | Atomic state updates; no file hacks |
| Multiple static configs             | `if`/`for`/`configfile` inside one `grub.cfg`            | Single source of truth            |
| Hard‑coded devices                  | `search --fs-uuid` / `--label`                           | Auto‑discovery; more robust        |
| Manual EFI binary builds            | `grub2-mkconfig` / `grub2-mkstandalone`                  | Official toolchain; fewer errors  |
| Edit‑reload‑test loop               | GRUB interactive CLI                                     | Instant feedback; faster debugging |

---

**Bottom‑line:** Whenever you find yourself writing shell snippets to open, edit, or regenerate `grub.cfg`, pause and ask “Can GRUB itself do this with its built‑in CLI or helper tools?” Leveraging native GRUB mechanisms will yield a more reliable, maintainable PXE‑boot infrastructure.