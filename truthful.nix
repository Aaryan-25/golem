# Golem, step 3: the system does nothing I didn't ask for.
# Wi-Fi off at every start, no internet clock, silent start, the boot menu says Golem.
{ pkgs, ... }:
let
  # Super+N: Wi-Fi on or off.
  wifi = pkgs.writeShellApplication {
    name = "golem-wifi";
    runtimeInputs = [ pkgs.networkmanager ];
    text = ''
      if [ "$(nmcli radio wifi)" = enabled ]; then nmcli radio wifi off; echo "Wi-Fi is now OFF"
      else nmcli radio wifi on; echo "Wi-Fi is now ON"; fi
    '';
  };
in {
  # ---- Wi-Fi off at every start ----
  # Written before NetworkManager starts, so Wi-Fi never comes up even for a moment.
  systemd.services.golem-wifi-off = {
    description = "Golem: Wi-Fi stays off until I turn it on";
    wantedBy = [ "NetworkManager.service" ];
    before = [ "NetworkManager.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/lib/NetworkManager
      printf '[main]\nNetworkingEnabled=true\nWirelessEnabled=false\nWWANEnabled=false\n' \
        > /var/lib/NetworkManager/NetworkManager.state
    '';
  };
  environment.systemPackages = [ wifi ];

  # ---- No clock over the internet ----
  # The laptop's own clock keeps time. To set it:  sudo timedatectl set-time "2026-11-21 22:30"
  services.timesyncd.enable = false;
  networking.timeServers = [ ];

  # ---- Nothing comes in from outside ----
  networking.firewall = { enable = true; allowPing = false; };

  # ---- Silent start ----
  # No menu and no text. Hold Shift (or press Esc) at power-on for the menu of older versions.
  boot.loader.timeout = 1;
  boot.loader.grub.timeoutStyle = "hidden";
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet" "loglevel=3" "systemd.show_status=false" "rd.systemd.show_status=false"
    "udev.log_level=3" "rd.udev.log_level=3"
  ];
  services.getty = { greetingLine = ""; helpLine = ""; };

  # ---- The name ----
  system.nixos.distroName = "Golem";            # boot menu and system name say Golem
}
