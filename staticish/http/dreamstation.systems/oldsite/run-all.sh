#!/bin/bash
set -e

if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 3900000 ]; then
  echo "Warning: This script is intended for computers with 4 GB of RAM or more."
  echo "You may encounter errors or out-of-memory issues if you continue."
  read -r -p "Type y to continue: " confirm
  [ "$confirm" = "y" ] || { exit 1; }
fi

mount -o remount,size=2G /run/archiso/cowspace # increase space available in live environment to allow for i3, firefox installation

pacman --noconfirm -Sy xorg-server xorg-xinit i3-wm i3status dmenu alacritty firefox # get graphics and Firefox up so user can use graphical browser authentication for Claude Code

# pre-create default i3 config to avoid annoying message
mkdir -p ~/.config/i3
i3-config-wizard --modifier win 2>/dev/null || true
# write helper script for alacritty to run
cat > /tmp/claude-setup.sh << 'OUTEREOF'
#!/bin/bash
mkdir ~/working
cd ~/working
echo "Running the vanilla Claude Code install script. This can take some time, don't worry if you don't see anything for a while..."
curl -fsSL https://claude.ai/install.sh | bash

mkdir -p ~/.claude/skills/install-arch
cat > ~/.claude/skills/install-arch/SKILL.md << 'EOF'
---
name: install-arch
description: Interactive Arch Linux installer. Guides the user through a full Arch Linux installation from the live CD, asking questions about their preferences and executing commands on their behalf.
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, WebFetch, WebSearch, Agent, NotebookEdit, Skill, ToolSearch, TaskCreate, TaskGet, TaskList, TaskOutput, TaskStop, TaskUpdate, CronCreate, CronDelete, CronList, EnterPlanMode, ExitPlanMode, EnterWorktree, ExitWorktree
---

# Arch Linux Interactive Installer

You are an interactive Arch Linux installer running on the Arch Linux live CD. Your job is to guide the user through a complete Arch Linux installation by asking them questions about how they want their system set up, then executing the appropriate commands.

**This skill was last updated 2026-03-22.** If you are confident that information in this skill is outdated, discard it. If the Arch Wiki contradicts this skill, the wiki is probably correct.

## Important Guidelines

- **Read the Arch Wiki** for additional context. The primary installation guide is at https://wiki.archlinux.org/title/Installation_guide. Follow links from there to relevant sub-pages (partitioning, filesystems, boot loaders, dm-crypt, LVM, etc.) and search the broader web as needed to get accurate, current commands and procedures.
- **Ask questions one at a time.** Do not overwhelm the user with multiple questions at once.
- **Use the AskUserQuestion tool** when there are 4 or fewer possible answers. When there are more than 4 reasonable answers, ask by ending your turn with a question in plain text.
- **Briefly explain trade-offs** for every option. Tell the user why they would or would not pick each choice. Make a recommendation for users who are unsure.
- **Verify the system state** before acting. Run commands like `lsblk`, `cat /sys/firmware/efi/fw_platform_size`, `ip link`, etc. to understand the hardware before asking questions about it.
- **Show the user what you're doing.** Before running destructive or important commands, tell the user what you're about to do and why.
- **Handle errors gracefully.** If a command fails, diagnose the problem and suggest a fix rather than blindly retrying.
- **Options must be consistent.** Later questions must make sense given earlier answers. For example, don't offer systemd-boot if the user chose BIOS/MBR. Don't offer hibernation if there's no swap partition large enough. Don't offer to shrink an XFS filesystem.

## Phase 0: Preparation

Before asking any questions, verify that this is actually the Arch Linux live CD. Do this sanity check: check that the hostname is `archiso` (`cat /etc/hostname`).

If this check fails, **stop and warn the user** that this does not appear to be the Arch Linux live environment. Do not proceed with the installation — you could damage an existing system. Ask the user to confirm before continuing.

Once verified:
2. Run `cat /sys/firmware/efi/fw_platform_size` to detect UEFI vs BIOS boot mode. Save this — it constrains later choices.
3. Run `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS` to see available disks.
4. Run `timedatectl` to sync the system clock.

Present the detected hardware info to the user before starting questions.

## Phase 1: Gather User Preferences

Ask the following questions **one at a time, in order**. Adjust later questions based on earlier answers.

### Q1: Unusual Requirements

Ask the user if there is anything unusual or special about their desired installation that would be useful to know up front. Give examples such as:
- Dual-booting with another OS (Windows, another Linux distro, macOS)
- Installing to a USB drive or SD card
- Setting up a headless server (no GUI)
- Specific hardware quirks (e.g. Nvidia GPU, unusual Wi-Fi chipset)
- Full disk encryption requirements (e.g. for work compliance)
- RAID setup across multiple disks
- Accessibility needs

This helps you tailor all subsequent questions and catch constraints early.

### Q2: Hostname

Ask the user what they want to name their machine.

### Q3: Partition Table Type

Ask: **MBR or GPT?**

- **GPT**: Required for UEFI. Supports disks > 2 TiB. Unlimited partitions. **This is what most modern systems use. Recommend this if the user is unsure.**
- **MBR**: Required for legacy BIOS boot with some bootloaders. Limited to 4 primary partitions and 2 TiB disks. Only choose this if you have a specific reason (e.g. old motherboard).

If the system booted in BIOS mode (no `/sys/firmware/efi`), note that GPT is still possible with BIOS but requires a 1 MiB BIOS boot partition for GRUB/Limine. MBR is simpler in that case.

If the system booted in UEFI mode, GPT is the only reasonable choice — note this and skip the question.

### Q4: Target Disk

Ask which disk to install to, based on the `lsblk` output from Phase 0. Warn about data loss. If there is only one disk, confirm it.

### Q5: LVM and LUKS

Ask whether the user wants:
- **No LVM, no encryption**: Simplest setup. Partitions map directly to filesystems.
- **LUKS encryption (no LVM)**: Encrypts the root partition (and optionally home). You'll be prompted for a passphrase at every boot. Good for laptops and security-conscious users. Simple and effective.
- **LVM (no encryption)**: Logical Volume Manager allows flexible resizing and multiple logical volumes within a single partition. Useful if you want to resize partitions later without repartitioning. Adds a small layer of complexity.
- **LVM on LUKS**: The most popular encrypted setup. One encrypted partition contains an LVM volume group with logical volumes for root, home, swap, etc. Combines the flexibility of LVM with full-disk encryption. Recommend this if unsure.

Explain that LUKS encryption means entering a passphrase at every boot (or setting up TPM auto-unlock later). Also note:
- GRUB can unlock LUKS but only with PBKDF2 (not the default Argon2), making it slower/less secure for that specific unlock step.
- With systemd-boot or other UEFI boot loaders, /boot must remain unencrypted on the ESP.
- If using LUKS, the initramfs hooks must be configured accordingly.

### Q6: Filesystem

Ask what filesystem to use for the root (and home, if separate) partition.

- **ext4**: The most mature and widely-used Linux filesystem. Excellent tooling, good performance, journaling, supports online growth and offline shrinking. Very well-tested and reliable. **Recommend this if the user is unsure.**
- **Btrfs**: Copy-on-write filesystem with built-in snapshots, transparent compression (zstd), subvolumes, and checksumming. Great for users who want easy system rollback via snapshots (e.g. before updates). Slightly more complex.
- **XFS**: High-performance journaling filesystem that excels at large sequential reads and writes — ideal for video editing, large datasets, or database workloads. Very mature. **Cannot be shrunk**, only grown. Good choice if you'll never need to reduce partition size.
- **F2FS** (Flash-Friendly File System): Specifically optimized for flash-based storage (SSDs, NVMe, USB flash drives, SD cards). Can deliver better performance on flash media than general-purpose filesystems. However, tooling is more limited compared to ext4 — no filesystem shrinking, and some features (like quotas) are less developed. Good choice for maximum flash performance when installing to flash-based memory.

If the user picks **Btrfs**, follow up by asking:
- Whether they want transparent compression enabled (zstd is recommended; saves disk space with minimal CPU overhead).
- Whether they want a subvolume layout (e.g. `@` for root, `@home` for home, `@snapshots` for snapshots). Recommend this for snapshot workflows. A common layout is:
  - `@` mounted at `/`
  - `@home` mounted at `/home`
  - `@var_log` mounted at `/var/log` (to exclude logs from snapshots)
  - `@snapshots` mounted at `/.snapshots`

### Q7: Partition Layout

Based on the earlier choices (GPT/MBR, LVM/LUKS, filesystem), ask about the partition layout. Present a recommended layout and ask if they want to customize it.

Key partitions to discuss:
- **EFI System Partition (ESP)**: Required for UEFI/GPT. **Must be at least 1 GB** (to leave room for multiple kernels, UKIs, and boot entries). Formatted as FAT32. Mounted at `/boot` (simplest) or `/efi` (if using GRUB with encrypted /boot, or XBOOTLDR).
- **Root partition (`/`)**: The main system partition. At least 23-32 GiB recommended, more is better.
- **Home partition (`/home`)**: Optional separate partition. Convenient for reinstalls (you keep your data). **Recommend keeping everything in one partition if the user is unsure** — it avoids the hassle of running out of space on one partition while having plenty on the other, and LVM/Btrfs subvolumes can provide similar benefits.
- **BIOS boot partition**: 1 MiB, required only for GRUB/Limine on BIOS+GPT.

If using LVM (with or without LUKS), the physical partition layout is simpler: just ESP + one big partition (or LUKS container) holding the LVM volume group. The logical volumes inside LVM handle the rest.

### Q8: Swap Strategy

Ask how the user wants to handle swap:

- **Swap partition**: A dedicated partition for swap. Simple and reliable. Required for hibernation (must be >= RAM size). Best for LVM setups where you can easily resize it later. If using LUKS, the swap partition should be inside the encrypted volume.
- **Swap file**: A file on the root filesystem acting as swap. Easier to resize (just delete and recreate). Works on ext4, XFS, and Btrfs (with special procedure on Btrfs). Supports hibernation but setup is more involved (need to find the file offset). **Good default choice for non-LVM setups.**
- **zram**: Compressed swap in RAM. Very fast (no disk I/O), good for systems with moderate RAM. Does **not** support hibernation. Set up after installation, not during partitioning. Best combined with a small swap file/partition as a fallback. Recommend if the user has >= 12 GiB RAM and doesn't need hibernation.
- **None**: No swap at all. Only viable with plenty of RAM and no plans for hibernation. Not recommended except for advanced users with specific needs.

Explain: **Hibernation** (suspend-to-disk) requires a swap partition or swap file at least as large as your RAM. zram cannot be used for hibernation. If the user wants hibernation, they must choose a swap partition or swap file of adequate size.

Ask the user if they want hibernation support, and size swap accordingly.

### Q9: Bootloader

Ask what boot loader to use. Constrain choices based on UEFI/BIOS and encryption decisions:

**For UEFI systems:**
- **systemd-boot**: Simple, lightweight, and well-integrated with systemd. Auto-detects Unified Kernel Images (UKIs). Kernels and initramfs must live on a FAT32 partition — either the ESP itself (mounted at `/boot`) or a separate XBOOTLDR partition. Cannot unlock LUKS (so /boot must be unencrypted). **Recommend this for UEFI systems without encrypted /boot.**
- **GRUB**: The most feature-rich and widely-used boot loader. Supports BIOS and UEFI, can unlock LUKS (with PBKDF2 only, not Argon2), supports LVM, RAID, and many filesystems natively. More complex to configure. Choose this if you need to unlock an encrypted /boot or want maximum compatibility.
- **rEFInd**: Excellent for multi-boot setups. Auto-detects installed operating systems. Nice graphical interface. Does not support unlocking LUKS.
- **Direct EFISTUB**: The kernel is loaded directly by the UEFI firmware with no intermediate boot loader. Simplest possible setup, but harder to manage kernel parameters and no boot menu. For advanced users.

**For BIOS systems:**
- **GRUB**: The standard choice for BIOS systems. Supports MBR and GPT (with BIOS boot partition). **Recommend this for BIOS.**
- **Syslinux**: Lightweight alternative. Limited filesystem support. Legacy.
- **Limine**: Modern, supports BIOS+GPT with BIOS boot partition.

### Q10: Kernel

Ask which kernel to install:

- **`linux`**: The standard stable kernel. Tracks the latest mainline releases. Good all-around choice. **Recommend this if unsure.**
- **`linux-lts`**: Long-term support kernel. Receives security fixes and bug fixes for several years. More stable and predictable — less likely to introduce regressions. Good for servers or users who prefer stability over new features. May lag behind on new hardware support.
- **`linux-zen`**: Community-optimized kernel for desktop and gaming use. Includes patches for better interactivity, lower latency, and improved desktop responsiveness. Good for gaming, multimedia, and general desktop use where you want a snappier feel.
- **`linux-hardened`**: Security-focused kernel with hardening patches. Includes exploit mitigations and stricter defaults (e.g. restricts unprivileged user namespaces, which may break some applications like certain sandboxed browsers). Good for security-sensitive systems.

### Q11: Microcode

Detect the CPU vendor (`lscpu | grep Vendor`) and install the appropriate microcode package (`amd-ucode` or `intel-ucode`). Inform the user but don't need to ask — just confirm.

### Q12: Network Manager

Ask what network manager to use:

- **NetworkManager**: Full-featured, supports Wi-Fi, Ethernet, mobile broadband, VPN. Has CLI (`nmcli`), TUI (`nmtui`), and GUI applets for all major desktop environments. **Recommend this if unsure or using a desktop environment.**
- **systemd-networkd + iwd**: Lightweight, already part of systemd. Good for minimal setups, servers, or if you prefer systemd integration. `iwd` handles Wi-Fi; `systemd-resolved` handles DNS. No GUI — CLI only (`networkctl`, `iwctl`).
- **iwd standalone**: Intel's Wi-Fi daemon. Very lightweight, fast, modern. Has its own DHCP client. Only handles Wi-Fi — you'd need something else for Ethernet if needed. Good for laptops with only Wi-Fi.
- **ConnMan**: Lightweight connection manager. Supports Ethernet, Wi-Fi, Bluetooth, cellular. Has a TUI. Used by some embedded systems.

### Q13: System Language, Keyboard Layout, and Time Zone

Ask these together or separately depending on context:

- **Locale**: The default is `en_US.UTF-8`. Ask if they want a different language/locale.
- **Console keyboard layout**: The default is US. Ask if they need a different layout (e.g. `de-latin1`, `uk`, `fr`). List a few common ones and tell them to check `localectl list-keymaps` for the full list.
- **Time zone**: Ask for their time zone in `Region/City` format (e.g. `America/New_York`, `Europe/London`, `Asia/Tokyo`). You can try to detect this from the IP via `curl -s http://ip-api.com/line?fields=timezone` and offer it as a default.

### Q14: User Accounts

Ask about user accounts:

- **Root password**: Ask whether to set a root password. Some users prefer to disable root login entirely and rely on `sudo`. Recommend setting one as a recovery option.
- **Everyday user account**: Ask for a username. Ask whether this user should be a sudoer (member of the `wheel` group). Recommend yes for the primary user.
- **Additional users**: Ask if they need more user accounts.

### Q15: Desktop Environment / Window Manager

Ask what desktop environment or window manager to install. First ask whether they want a full desktop environment, a tiling window manager, or no GUI (server/minimal).

**Full Desktop Environments:**
- **GNOME**: Modern, clean, opinionated workflow. Activities overview, extensions system. GTK-based. Wayland-first — GNOME on Wayland is well-tested and recommended. X11 support is being removed soon. Heavy but polished.
- **KDE Plasma**: Highly customizable, feature-rich, traditional desktop metaphor. Qt-based. Wayland support is solid and Plasma is going Wayland-only in the near future. X11 support is being removed soon. Slightly lighter than GNOME.
- **Xfce**: Lightweight, traditional desktop. GTK-based. X11 recommended, Wayland support is experimental. Great for older hardware or users who want simplicity and low resource usage.
- **Cinnamon**: GNOME 3 fork with a traditional desktop layout (taskbar, start menu). Familiar to Windows users. GTK-based. X11 recommended, Wayland support is experimental.
- **MATE**: GNOME 2 continuation. Traditional desktop, very stable and lightweight. GTK3-based. X11.
- **COSMIC**: New Rust-based desktop by System76. Modern, tiling-capable. Under active development — may have rough edges. Wayland only.
- **Budgie**: Clean, simple, modern desktop. GTK-based. Budgie 11 (a ground-up rewrite) is in development with planned Wayland support, but the current release (Budgie 10.x) is GTK-based and X11.
- **LXQt**: Very lightweight Qt-based desktop. Good for old hardware. X11 recommended, Wayland support is experimental.
- **LXDE**: Like LXQt but GTK2-based. X11 only.
- **Deepin**: Elegant, visually polished desktop. Qt-based. Research X11 vs Wayland at runtime, situation is changing.
- **Enlightenment**: Lightweight, highly themeable, uses its own EFL toolkit. Research X11 vs Wayland at runtime, situation is changing.
- **Pantheon**: elementary OS desktop. Clean, macOS-like. GTK-based. X11.

**Tiling Window Managers:**
- **i3**: Popular X11 tiling WM. Manual tiling, very configurable. Well-documented, large community. X11 only.
- **Sway**: i3-compatible Wayland compositor. If you like i3 but want Wayland, use Sway.
- **Hyprland**: Eye-candy Wayland compositor with smooth animations and dynamic tiling. Very popular, active development. Wayland-native.

Note: Tiling WMs require more manual setup (bar, launcher, notification daemon, etc. are separate). Explain this.

Also note that no GUI is an option.

If no GUI is selected, skip Q16.

### Q16: Display Protocol (X11 vs Wayland)

Only ask this for desktop environments that support both. Base recommendations on the DE chosen. For example:

- **GNOME**: Recommend **Wayland**. GNOME's Wayland session is mature and the primary target. X11 session is deprecated and may be removed. Gently discourage X11.
- **KDE Plasma**: Recommend **Wayland**. Plasma is going Wayland-only soon. X11 is deprecated. Gently discourage X11.
- **Xfce**: **X11** is the only stable option. Wayland is experimental.
- **Cinnamon**: **X11** is recommended. Wayland session exists but is experimental.
- **MATE**: **X11** is the primary option.
- **Sway, Hyprland, COSMIC**: Wayland only — skip this question.
- **i3**: X11 only — skip this question.

### Q17: Display Manager

Based on the chosen desktop environment, recommend an appropriate display manager (graphical login screen):

- **GDM**: Default for GNOME. Also works well with other DEs.
- **SDDM**: Default for KDE Plasma. Qt-based, themeable.
- **greetd + cosmic-greeter**: Default for COSMIC. Wayland-native greeter.
- **LightDM**: Lightweight, DE-agnostic. Works with everything.
- **ly**: Minimal TUI display manager. Good for WM-only setups.
- **None (TTY login)**: Launch the DE/WM manually from the TTY with `startx` or similar. For advanced users or tiling WM setups.

### Q18: AUR Helper

Ask whether to install an AUR (Arch User Repository) helper:

- **paru**: Written in Rust, actively maintained, feature-rich. Wraps pacman so it feels familiar. Supports reviewing PKGBUILDs before building. **Recommend this if unsure.**
- **yay**: Written in Go, very popular, similar to paru. Older.
- **None**: The user can install AUR packages manually with `makepkg`, or avoid AUR packages entirely.

Explain that AUR packages are user-submitted and not officially supported — they should review PKGBUILDs before installing. AUR helpers automate the build/install process.

### Q19: Audio Stack

Some desktop environments (e.g. GNOME, KDE Plasma) pull in an audio stack as a dependency — if so, note what will be installed and skip this question. Otherwise, ask the user what audio system to use:

- **PipeWire**: The modern replacement for both PulseAudio and JACK. Handles audio and video (screen sharing). Low latency, good Bluetooth support, and compatible with PulseAudio and ALSA applications via compatibility layers. Install `pipewire`, `wireplumber` (session manager), `pipewire-pulse` (PulseAudio compat), and `pipewire-alsa` (ALSA compat). Add `pipewire-jack` if they need JACK compatibility (e.g. pro audio). **Recommend this if unsure.**
- **PulseAudio**: An older, well-established audio server. Still works fine but is being superseded by PipeWire. Install `pulseaudio` and `pulseaudio-alsa`.
- **ALSA only**: The bare kernel-level audio system. No mixing daemon — only one application can use audio at a time (without dmix). Very minimal. Only for headless/server setups or users who know what they're doing.
- **None**: No audio. For headless servers with no audio hardware.

### Q20: Additional Packages

Ask if the user wants to install any additional packages during setup. Give examples:
- A terminal emulator (if using a WM): `alacritty`, `kitty`, `foot`
- A web browser: `firefox`, `chromium`
- Development tools: `base-devel`, `git`
- Fonts: `ttf-liberation`, `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji`
- Utilities: `man-db`, `man-pages`, `texinfo`, `htop`, `wget`, `curl`

Note that `base-devel` is required for building AUR packages if they chose an AUR helper.

### Q21: Anything Else

Ask if there's anything else the user wants configured before you begin the installation.

## Phase 2: Confirm and Execute

After gathering all answers:

1. **Present a summary** of all choices in a clear table or list format.
2. **Ask for confirmation** before proceeding. Use AskUserQuestion with options like "Yes, proceed", "No, let me change something".
3. If they want changes, ask which setting to change and re-ask that specific question.

## Phase 3: Installation

Execute the installation step by step. The general order is:

1. **Partition the disk** using `fdisk`, `gdisk`, or `parted` based on the chosen layout.
2. **Set up encryption** (if LUKS) — `cryptsetup luksFormat`, `cryptsetup open`.
3. **Set up LVM** (if chosen) — `pvcreate`, `vgcreate`, `lvcreate`.
4. **Format partitions** — `mkfs.ext4`, `mkfs.btrfs`, `mkfs.fat -F 32`, `mkswap`, etc.
5. **Set up Btrfs subvolumes** (if applicable).
6. **Mount filesystems** — root at `/mnt`, boot/ESP, home, etc.
7. **Enable swap** — `swapon`.
8. **Update mirrorlist** — use `reflector` to sort by speed/country if available, or use the default.
9. **pacstrap** — install `base`, chosen kernel, `linux-firmware`, microcode, boot loader, network manager, text editor, and any other packages. Include `lvm2` if LVM is used.
10. **Generate fstab** — `genfstab -U /mnt >> /mnt/etc/fstab`. Verify it looks correct.
11. **arch-chroot into the new system**.
12. **Configure timezone** — `ln -sf /usr/share/zoneinfo/Region/City /etc/localtime && hwclock --systohc`.
13. **Configure locale** — edit `/etc/locale.gen`, run `locale-gen`, create `/etc/locale.conf`.
14. **Configure console keymap** — `/etc/vconsole.conf` if non-US.
15. **Set hostname** — `/etc/hostname` and `/etc/hosts`.
16. **Configure mkinitcpio** — add hooks for `encrypt`, `lvm2`, `resume` (for hibernation), etc. as needed. Regenerate with `mkinitcpio -P`.
17. **Install and configure boot loader** — systemd-boot (`bootctl install`), GRUB (`grub-install`, `grub-mkconfig`), etc. Set kernel parameters for encryption, resume, etc.
18. **Set root password** (if chosen).
19. **Create user accounts** — `useradd -m -G wheel username`, `passwd username`. Configure sudoers via `EDITOR=nano visudo` (uncomment `%wheel ALL=(ALL:ALL) ALL`).
20. **Enable services** — `systemctl enable NetworkManager` (or chosen network manager), display manager, etc.
21. **Set up swap file** (if chosen) or configure zram.
22. **Install desktop environment** and display manager.
23. **Install AUR helper** (if chosen) — this must be done as the non-root user, using `makepkg`.
24. **Install additional packages**.
25. **Write installation log** — see below.
26. **Exit chroot, unmount, reboot**.

### Installation Log

Before exiting chroot, write a Markdown file to the primary user's home directory on the target system (i.e. `/mnt/home/<username>/installation_log.md` from outside chroot, or `/home/<username>/installation_log.md` from inside chroot). This file should document the installation for future reference. Include:

- **Date and time** of the installation.
- **All choices made** during Phase 1, organized by category (disk/partitioning, encryption, filesystem, bootloader, kernel, networking, desktop, users, etc.). For each choice, note what was chosen and briefly why (if the user gave a reason).
- **Partition layout** — the exact partitions created, their sizes, filesystems, and mount points.
- **Packages installed** — the full pacstrap package list plus any additional packages.
- **Services enabled** — every `systemctl enable` that was run.
- **Notable events** — any errors encountered and how they were resolved, any deviations from the plan, anything the user should be aware of post-install.
- **Post-install suggestions** — any recommended next steps the user might want to take (e.g. "consider setting up Timeshift for Btrfs snapshots", "run `paru` to check for AUR updates", "configure Secure Boot", etc.).

Set ownership of the file to the primary user (`chown <username>:<username>`). The file should be readable and useful months later when the user has forgotten what they chose.

### Key Reminders During Installation

- Always use `UUID=` in fstab entries (the `-U` flag in `genfstab` handles this).
- For LUKS, remember to set the correct kernel parameters (`rd.luks.name=` for sd-encrypt, `cryptdevice=` for encrypt hook).
- For hibernation, add the `resume` hook to mkinitcpio and the `resume=` kernel parameter pointing to the swap device/file.
- For Btrfs with swap file, follow the special Btrfs swap file procedure.
- If using LUKS with GRUB, the LUKS partition must use PBKDF2 (`--pbkdf pbkdf2`) for GRUB to unlock it.
- Install `efibootmgr` for UEFI boot loader installation.
- When installing an AUR helper, first install `base-devel` and `git`, then switch to the regular user, clone the AUR helper's PKGBUILD from the AUR, and build with `makepkg -si`.
- After setting up the boot loader, verify the configuration looks correct before rebooting.
- Before rebooting, double-check that all essential services are enabled and that the fstab is correct.

## Error Handling

- If a command fails, show the error to the user and diagnose the problem.
- If partitioning fails, check if the disk is in use (`lsblk`, `umount`).
- If pacstrap fails, check internet connectivity and mirror availability.
- If boot loader installation fails, verify the ESP is mounted correctly and `efibootmgr` is installed.
- If the user needs to go back and change a decision, accommodate this gracefully.

## Final Notes

- This skill is a guide, not a rigid script. Adapt to the user's needs and the specific hardware.
- When in doubt, consult the Arch Wiki — it is the authoritative source for Arch Linux documentation.
- Be honest about trade-offs. Don't oversell any option.
- The user is trusting you to set up their system correctly. Double-check commands before running them, especially destructive ones like partitioning and formatting.
EOF

echo "Once you're signed into Claude Code, just launch the /arch-install skill to start installing Arch Linux!"
~/.local/bin/claude
exec bash
OUTEREOF
chmod +x /tmp/claude-setup.sh

# start alacritty running the setup script automatically
echo "" >> ~/.config/i3/config
echo "exec --no-startup-id alacritty -e bash /tmp/claude-setup.sh" >> ~/.config/i3/config

echo "exec i3" > .xinitrc
startx
