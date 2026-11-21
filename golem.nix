# Golem, step 1: the smallest system that boots from the pendrive.
# Login, tiling windows (no bars), a terminal, Wi-Fi. Nothing else yet.
{ config, lib, pkgs, modulesPath, ... }:
let
  s = import ./settings.nix;

  # Colours: a dark void with pale, cold light.
  c = { void = "#050506"; mist = "#6f7484"; text = "#c8ccd8"; pale = "#e6e9f2"; };

  term = "xterm -bg '${c.void}' -fg '${c.text}' -cr '${c.pale}' -fa 'DejaVu Sans Mono' -fs 11 -b 12";

  i3config = pkgs.writeText "golem-i3" ''
    # No bar, no titles, no gaps. Only a thin line around the focused window.
    font pango:DejaVu Sans Mono 10
    default_border pixel 1
    default_floating_border pixel 1
    hide_edge_borders smart
    focus_follows_mouse no
    focus_on_window_activation none
    focus_wrapping yes
    client.focused          ${c.pale} ${c.void} ${c.text} ${c.pale} ${c.pale}
    client.focused_inactive ${c.void} ${c.void} ${c.mist} ${c.void} ${c.void}
    client.unfocused        ${c.void} ${c.void} ${c.mist} ${c.void} ${c.void}
    client.background       ${c.void}
    exec --no-startup-id xsetroot -solid "${c.void}"

    # Keys (Super = the Windows key)
    bindsym Mod1+Return exec ${term}
    bindsym Mod4+w      exec ${term} -e nmtui
    bindsym Mod1+Tab    focus right
    bindsym Mod1+Shift+Tab focus left
    bindsym Mod1+f      fullscreen toggle
    bindsym Mod1+q      kill
    bindsym Mod4+1 workspace 1
    bindsym Mod4+2 workspace 2
    bindsym Mod4+3 workspace 3
    bindsym Mod4+4 workspace 4
    bindsym Mod4+Shift+1 move container to workspace 1
    bindsym Mod4+Shift+2 move container to workspace 2
    bindsym Mod4+Shift+3 move container to workspace 3
    bindsym Mod4+Shift+4 move container to workspace 4
    bindsym Mod4+Shift+e exit
  '';
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
  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "usb_storage" "uas" "sd_mod" "sdhci_pci" "virtio_pci" "virtio_blk" ];
  # Only the firmware this laptop needs (Wi-Fi, Bluetooth, graphics), not the 1 GB+ full set.
  hardware.firmware = [
    (pkgs.runCommand "golem-firmware" { } ''
      f=${pkgs.linux-firmware}/lib/firmware
      mkdir -p $out/lib/firmware/intel $out/lib/firmware/i915
      cp -aL $f/iwlwifi-7265* $out/lib/firmware/
      cp -aL $f/intel/ibt-hw-37.8* $out/lib/firmware/intel/ 2>/dev/null || true
      cp -aL $f/i915/bxt_* $out/lib/firmware/i915/
    '')
    pkgs.wireless-regdb
  ];
  hardware.cpu.intel.updateMicrocode = true;

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
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "golem";
  };

  # ---- Wi-Fi and sound ----
  networking.networkmanager.enable = true;
  services.pipewire = { enable = true; pulse.enable = true; };

  # ---- The desktop: log in on the text screen, then the windows start ----
  services.xserver = {
    enable = true;
    xkb.layout = s.keyboardLayout;
    windowManager.i3 = { enable = true; configFile = i3config; };
    displayManager.startx = { enable = true; generateScript = true; };
  };
  services.libinput.enable = true;                    # touchpad
  environment.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${DISPLAY:-}" ]; then exec startx >/dev/null 2>&1; fi
  '';
  environment.systemPackages = with pkgs; [ xterm xsetroot git ];

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
