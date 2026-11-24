# Golem, step 3: the system does nothing I didn't ask for.
# Wi-Fi off at every start, no internet clock, silent start, the boot menu says Golem.
{ pkgs, lib, ... }:
let
  # Super+N: Wi-Fi on or off.
  wifi = pkgs.writeShellApplication {
    name = "golem-wifi";
    runtimeInputs = [ pkgs.networkmanager pkgs.util-linux ];
    text = ''
      if [ "$(nmcli radio wifi)" = enabled ]; then nmcli radio wifi off; echo "Wi-Fi is now OFF"; logger -t golem "Wi-Fi turned OFF"
      else nmcli radio wifi on; echo "Wi-Fi is now ON"; logger -t golem "Wi-Fi turned ON"; fi
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

  # ---- Start: visible for now (22 Nov 2026) ----
  # The menu shows for 3 seconds: Golem, "Golem - text only" (no picture; shows what went wrong last time),
  # and older versions. Start messages are shown, so a stuck start is never just a black screen.
  boot.loader.timeout = 3;
  boot.loader.grub.timeoutStyle = "menu";
  boot.kernelParams = [ "loglevel=4" ];
  services.getty = { greetingLine = ""; helpLine = ""; };

  # ---- The name ----
  system.nixos.distroName = "Golem";            # boot menu and system name say Golem
}
