# golem-install: puts Golem on a laptop's own disk, from the pendrive. Everything on that disk is erased.
#
#   sudo golem-install          shows the disks, I pick one, I type ERASE, and it installs (no internet needed:
#                               the installed Golem is already on the pendrive, see "diskSystem" below)
#   golem-install --list        only shows the disks it could install on
#   sudo golem-install --disk nvme0n1 --erase [--copy-files yes|no]
#                               the same, without questions (the visual installer, golem-install-ui, uses this;
#                               --erase stands for typing ERASE, and the window asks for that first)
# Everything it prints also goes to /var/log/golem-install.log (golem-report sends that file too).
#
# What it does, step by step (each step is printed as it happens, and written to the truth log):
#   1. refuses to run unless Golem was started from the pendrive
#   2. lists the laptop's disks (never the pendrive Golem is running from)
#   3. shows what is on the chosen disk, and asks me to type ERASE
#   4. makes two parts on it: GOLEM-BOOT (the start menu, 512 MB) and golem (everything else)
#   5. copies the installed Golem (disk.nix) onto it, with its start menu
#   6. asks whether to copy my files from the pendrive too
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ pkgs, lib, diskSystem, ... }:   # diskSystem: the installed Golem (flake.nix); null when this IS installed
let
  s = import ../settings/settings.nix;
  install = pkgs.writeShellApplication {
    name = "golem-install";
    runtimeInputs = with pkgs; [ util-linux parted dosfstools e2fsprogs coreutils gnugrep gawk rsync ];      # nixos-install comes with every NixOS
    text = ''
      say() { printf '\n%s\n' "$*"; }
      note() { logger -t golem "Install: $*"; }
      if [ "$(cat /etc/golem/config-name 2>/dev/null)" != golem ]; then
        echo "golem-install works only when Golem was started from the pendrive."; exit 1
      fi
      # The disk Golem is running from (the pendrive): never offered.
      root=$(findmnt -no SOURCE /)
      here=$(lsblk -no PKNAME "$root" | head -n 1)
      [ -n "$here" ] || here=$(basename "$root")           # Golem's root is a whole disk, not a part of one
      mapfile -t disks < <(lsblk -dn -o NAME,TYPE | awk -v h="$here" '$2 == "disk" && $1 != h && $1 !~ /^(zram|loop|sr)/ {print $1}')
      if [ "''${#disks[@]}" -eq 0 ]; then echo "No disk found to install on (only the pendrive)."; exit 1; fi
      say "Disks Golem can be installed on (the pendrive, $here, is not listed):"
      i=1
      for d in "''${disks[@]}"; do
        printf '  %s)  /dev/%-8s %8s  %s\n' "$i" "$d" "$(lsblk -dn -o SIZE "/dev/$d")" "$(lsblk -dn -o MODEL "/dev/$d" | xargs)"
        i=$((i + 1))
      done
      if [ "''${1:-}" = --list ]; then exit 0; fi
      if [ "$(id -u)" -ne 0 ]; then echo; echo "To install, run it with sudo:  sudo golem-install"; exit 1; fi
      # Without questions (from the visual installer): --disk NAME --erase [--copy-files yes|no]
      want="" erase="" copy=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --disk) want="''${2:-}"; shift 2 ;;
          --erase) erase=yes; shift ;;
          --copy-files) copy="''${2:-}"; shift 2 ;;
          *) echo "Unknown: $1"; exit 2 ;;
        esac
      done
      exec > >(tee -a /var/log/golem-install.log) 2>&1     # everything shown is also kept, for a report
      chmod 644 /var/log/golem-install.log
      if [ -n "$want" ]; then
        ok=""; for d in "''${disks[@]}"; do [ "$d" = "''${want#/dev/}" ] && ok=yes; done
        [ -n "$ok" ] || { echo "$want is not a disk Golem may install on. Nothing was changed."; exit 1; }
        [ "$erase" = yes ] || { echo "Without --erase nothing is changed."; exit 1; }
        disk="/dev/''${want#/dev/}"
      else
        printf '\nWhich disk? Type its number (or press Enter to stop): '
        read -r n
        case "$n" in ""|*[!0-9]*) echo "Stopped. Nothing was changed."; exit 0 ;; esac
        [ "$n" -ge 1 ] && [ "$n" -le "''${#disks[@]}" ] || { echo "No disk $n. Nothing was changed."; exit 1; }
        disk="/dev/''${disks[$((n - 1))]}"
        say "This is on $disk now:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL "$disk"
        say "EVERYTHING on $disk will be erased (Windows, files, everything), and Golem put there instead."
        printf 'To go ahead, type ERASE (anything else stops): '
        read -r yes
        [ "$yes" = ERASE ] || { echo "Stopped. Nothing was changed."; exit 0; }
      fi
      note "erasing $disk ($(lsblk -dn -o SIZE,MODEL "$disk" | xargs)) to install Golem"

      say "1/4  Making the two parts: GOLEM-BOOT (start menu) and golem (everything else) ..."
      umount -R /mnt 2>/dev/null || true
      wipefs -a "$disk" >/dev/null
      parted -s "$disk" mklabel gpt mkpart GOLEM-BOOT fat32 1MiB 513MiB set 1 esp on mkpart golem ext4 513MiB 100%
      udevadm settle
      p=""; case "$disk" in *[0-9]) p=p ;; esac          # nvme0n1 -> nvme0n1p1; sda -> sda1
      mkfs.fat -F 32 -n GOLEM-BOOT "''${disk}''${p}1" >/dev/null
      mkfs.ext4 -q -F -L golem "''${disk}''${p}2"
      udevadm settle

      say "2/4  Getting the parts ready ..."
      mount /dev/disk/by-label/golem /mnt
      mkdir -p /mnt/boot
      mount -o umask=0077 /dev/disk/by-label/GOLEM-BOOT /mnt/boot

      say "3/4  Copying Golem onto the disk (from the pendrive, no internet; this can take a while) ..."
      nixos-install --system ${if diskSystem == null then "/run/current-system" else diskSystem} \
        --root /mnt --no-root-passwd --no-channel-copy

      say "4/4  Your files"
      if [ -z "$copy" ]; then
        printf 'Copy your files from the pendrive (home folder: Echo, zones, editor) onto the disk too? [y/N] '
        read -r copy
      fi
      if [ "$copy" = y ] || [ "$copy" = Y ] || [ "$copy" = yes ]; then
        mkdir -p "/mnt/home/${s.user}"
        rsync -a --info=progress2 "/home/${s.user}/" "/mnt/home/${s.user}/"
        note "copied my home folder from the pendrive"
      fi
      sync
      umount -R /mnt
      note "Golem is installed on $disk"
      say "DONE. Golem is on $disk."
      echo "Shut down (SLUMBER), unplug the pendrive, and start the laptop: Golem starts from its own disk."
      echo "The password is the same: arise."
    '';
  };
  # The visual installer (install_ui.py): the same steps, in a small window in Golem's look.
  ui = pkgs.writeShellApplication {
    name = "golem-install-ui";
    text = ''
      export GOLEM_THEMES='${builtins.toJSON { shadow = s.theme; }}'
      exec ${pkgs.python3.withPackages (p: [ p.tkinter ])}/bin/python3 ${./install_ui.py} "$@"
    '';
  };
in
{
  # Only the pendrive carries the installer (and the installed Golem, ready to copy).
  config = lib.mkIf (diskSystem != null) {
    environment.systemPackages = [ install ui ];     # (desktop.nix opens its window floating, in front)
  };
}
