# Golem installed on a laptop's own disk (by golem-install, see install.nix). It is the same Golem as on the
# pendrive; only where it lives differs: the disk's parts are named "golem" and "GOLEM-BOOT" (the pendrive's are
# "nixos" and "ESP"), so a pendrive left plugged in can never be mistaken for the laptop's own disk.
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ lib, ... }:
{
  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-label/golem"; fsType = "ext4";
    options = [ "noatime" ];
  };
  fileSystems."/boot" = lib.mkForce { device = "/dev/disk/by-label/GOLEM-BOOT"; fsType = "vfat"; options = [ "umask=0077" ]; };
  boot.growPartition = lib.mkForce false;       # the disk was made to its full size when installing
  # Which recipe golem-update rebuilds on this laptop (the pendrive's says "golem").
  environment.etc."golem/config-name".text = lib.mkForce "golem-disk";
}
