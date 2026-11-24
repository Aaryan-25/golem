# Golem, step 1: the smallest system that boots from the pendrive.
# Login, tiling windows (no bars), a terminal, Wi-Fi. Nothing else yet.
{ config, lib, pkgs, modulesPath, ... }:
let
  s = import ../settings/settings.nix;

  # golem-why: what went wrong, in short (golem-why = this start, golem-why last = the start before).
  why = pkgs.writeShellApplication {
    name = "golem-why";
    runtimeInputs = with pkgs; [ systemd coreutils gnugrep ];
    text = ''
      b=0; when="this start"
      if [ "''${1:-}" = last ]; then b=-1; when="the start before this one"; fi
      echo; echo "== Problems on $when =="
      journalctl -b "$b" -p warning -q --no-pager -o short-monotonic | tail -n 25 || echo "(none written down)"
      echo; echo "== Golem's own notes on $when =="
      journalctl -b "$b" -t golem -q --no-pager -o cat | tail -n 12 || true
      for f in ~/.local/share/xorg/Xorg.0.log ~/.local/share/xorg/Xorg.0.log.old; do
        if [ -f "$f" ] && grep -q '(EE)' "$f"; then echo; echo "== The picture's errors ($(basename "$f")) =="; grep '(EE)' "$f" | tail -n 8; fi
      done
      echo
    '';
  };

in
{
  system.stateVersion = "26.05";
  networking.hostName = "golem";
  time.timeZone = s.timeZone;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  documentation.enable = false;                       # no manuals: smaller and cleaner
  services.speechd.enable = false;                    # no text-to-speech (650 MB of voices)
  networking.modemmanager.enable = false;             # no mobile-modem support (no SIM in this laptop)
  networking.networkmanager.plugins = lib.mkForce [ ];   # no VPN plugins for now
  fonts.enableDefaultPackages = false;                # only the fonts Golem uses
  fonts.packages = [ pkgs.dejavu_fonts ];

  # ---- Starting from the pendrive ----
  # The boot loader lives only on the pendrive and never writes to the laptop's firmware.
  boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true; efiInstallAsRemovable = true; };
  boot.loader.efi.canTouchEfiVariables = false;
  # Lets GitHub's boot test read the screen (start-up menu and messages also go to a serial line).
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty1" ];
  boot.loader.grub.extraConfig = "serial --unit=0 --speed=115200; terminal_input serial console; terminal_output serial console";
  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "nvme" "usb_storage" "uas" "sd_mod" "sdhci_pci" "virtio_pci" "virtio_blk" ];
  # Only the firmware my two laptops need (Wi-Fi, Bluetooth, graphics, wired network), not the 1 GB+ full set.
  # Dell Latitude 3180: Intel 7265 Wi-Fi, Apollo Lake graphics. Asus TUF FX506LH: Comet Lake graphics, and either
  # a Realtek or an Intel AX201 Wi-Fi card (both kinds are sold), Realtek wired network.
  hardware.firmware = [
    (pkgs.runCommand "golem-firmware" { } ''
      f=${pkgs.linux-firmware}/lib/firmware
      o=$out/lib/firmware
      mkdir -p $o/intel $o/i915 $o/rtl_nic
      cp -aL $f/iwlwifi-7265* $f/iwlwifi-Qu-* $f/iwlwifi-QuZ-* $o/
      cp -aL $f/intel/ibt-* $o/intel/ 2>/dev/null || true
      cp -aL $f/i915/bxt_* $f/i915/kbl_* $f/i915/cml_* $o/i915/
      cp -aL $f/rtw88 $f/rtl_bt $o/
      cp -aL $f/rtl_nic/rtl8168* $o/rtl_nic/
      # If a name changes upstream, stop here rather than make an image with no Wi-Fi.
      ls $o/iwlwifi-7265D-* $o/iwlwifi-QuZ-a0-hr-b0-* $o/rtw88/rtw8822c_fw.bin* $o/rtw88/rtw8821c_fw.bin* >/dev/null
    '')
    pkgs.wireless-regdb
    pkgs.sof-firmware          # sound on this processor family (Apollo Lake) may need it
  ];
  hardware.cpu.intel.updateMicrocode = true;

  # (The Asus's NVIDIA card: nvidia.nix.)
  services.udev.extraRules = ''
    # Stop charging at 80% where the laptop allows it (the Asus does), so the battery lasts more years.
    ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]", TEST=="charge_control_end_threshold", ATTR{charge_control_end_threshold}="80"
  '';

  # On the first start Golem grows to fill the whole pendrive.
  boot.growPartition = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos"; fsType = "ext4"; autoResize = true;
    options = [ "noatime" "commit=60" ];              # fewer writes = longer pendrive life
  };
  fileSystems."/boot" = { device = "/dev/disk/by-label/ESP"; fsType = "vfat"; options = [ "umask=0077" ]; };

  # ---- You ----
  users.users.${s.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "systemd-journal" ];   # journal: to read the truth log
    initialPassword = "arise";
  };

  # ---- Wi-Fi and sound ----
  networking.networkmanager.enable = true;
  services.pipewire = { enable = true; pulse.enable = true; };

  # ---- The desktop: log in on the text screen, then the windows start ----
  services.xserver = {
    enable = true;
    xkb.layout = s.keyboardLayout;
    windowManager.i3.enable = true;               # its keys and look are in desktop.nix
    displayManager.startx = { enable = true; generateScript = true; };
  };
  services.libinput.enable = true;                    # touchpad
  environment.loginShellInit = ''
    # The picture starts after login on the first screen. If it doesn't come up (graphics still waking up),
    # try again a few times, then stay on this text screen and say how to find out why.
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${DISPLAY:-}" ]; then
      if [ -e /etc/golem/text-only ]; then
        echo "GOLEM, TEXT ONLY: the picture is not started."
        golem-why last
      else
        for golem_try in 1 2 3 4; do
          startx >/dev/null 2>&1 && exit 0
          logger -t golem "The picture did not start (try $golem_try)"
          sleep 3
        done
        echo "The picture did not start. Type  golem-why  to see why, and send Claude a photo."
      fi
    fi
  '';
  # A second line in the start menu: the same Golem, but only the text screen.
  specialisation.text-only.configuration = {
    boot.loader.grub.configurationName = "text only";
    environment.etc."golem/text-only".text = "The picture is not started on this start.\n";
  };
  environment.systemPackages = with pkgs; [ xterm xsetroot git why ];
  # Only what we chose. NixOS would also add perl, rsync and strace by itself; nano stays, to fix a file if something breaks.
  environment.defaultPackages = [ ];
  programs.nano.enable = true;

  # ---- The pendrive image (built by GitHub) ----
  system.build.golemImage = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit config lib pkgs;
    partitionTableType = "efi";
    format = "raw";
    diskSize = "auto";
    additionalSpace = "512M";
    label = "nixos";
    copyChannel = false;
  };
}
