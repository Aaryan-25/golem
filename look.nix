# The look and the settings that take effect: Shadow / Negative faces, the red alert, and the pieces that
# turn the Control Panel's settings into reality (system side at start and after Apply, my side at login).
{ pkgs, lib, ... }:
let
  s = import ./settings.nix;
  themes = builtins.toJSON { shadow = s.theme; negative = s.themeNegative; };
  pyw = name: deps: file: pkgs.writers.writePython3Bin name { libraries = deps; flakeIgnore = [ "E501" "W503" "W504" ]; }
    (builtins.readFile file);
  tkpy = pkgs.python3.withPackages (ps: [ ps.tkinter ]);

  settingsApply = pyw "golem-settings-apply" [ ] ./settings_apply.py;

  sessionApply = pkgs.writeShellApplication {
    name = "golem-session-apply";
    runtimeInputs = with pkgs; [ xset xinput sct xsetroot i3 python3 ];
    text = ''
      export GOLEM_THEMES='${themes}'
      exec python3 ${./session_apply.py} "$@"
    '';
  };

  alert = pkgs.writeShellApplication {
    name = "golem-alert";
    runtimeInputs = with pkgs; [ util-linux ];
    text = ''exec ${tkpy}/bin/python3 ${./alert.py} "$@"'';
  };

  # The terminal, in the colours of the current face.
  term = pkgs.writeShellApplication {
    name = "golem-term";
    runtimeInputs = [ pkgs.xterm pkgs.gnugrep ];
    text = ''
      if grep -q '^face=negative' /var/lib/golem/settings.conf 2>/dev/null; then
        bg='${s.themeNegative.void}'; fg='${s.themeNegative.text}'; cr='${s.themeNegative.pale}'
      else
        bg='${s.theme.void}'; fg='${s.theme.text}'; cr='${s.theme.pale}'
      fi
      exec xterm -bg "$bg" -fg "$fg" -cr "$cr" -fa 'DejaVu Sans Mono' -fs 11 -b 12 "$@"
    '';
  };

  # Super+I: Shadow <-> Negative, anywhere.
  face = pkgs.writeShellApplication {
    name = "golem-face";
    runtimeInputs = with pkgs; [ gnugrep socat sessionApply ];
    text = ''
      new=negative
      if grep -q '^face=negative' /var/lib/golem/settings.conf 2>/dev/null; then new=shadow; fi
      printf '{"do":"look","settings":{"face":"%s"}}\n' "$new" | socat -t 10 - UNIX-CONNECT:/run/golem-helper.sock >/dev/null
      golem-session-apply
    '';
  };
in {
  environment.systemPackages = [ settingsApply sessionApply alert term face pkgs.sct pkgs.xinput pkgs.pciutils pkgs.alsa-utils ];
  environment.etc."golem/settings-schema.json".source = ./settings-schema.json;
  environment.variables.GOLEM_THEMES = themes;

  # System side of the settings, at every start (drivers, microphone, processor, charge limit, block list).
  systemd.services.golem-settings = {
    description = "Golem: apply the Control Panel's system settings";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "local-fs.target" ];
    before = [ "systemd-udev-trigger.service" "NetworkManager.service" ];
    unitConfig.DefaultDependencies = false;
    path = with pkgs; [ kmod alsa-utils util-linux procps ];
    environment = {
      GOLEM_FALSE = "${pkgs.coreutils}/bin/false";
      GOLEM_BLOCKLIST = "${./blocklist/hosts}";
    };
    serviceConfig = { Type = "oneshot"; ExecStart = "${settingsApply}/bin/golem-settings-apply"; };
  };

  # Trackers and ads: the local DNS answers "nowhere" for every site on the list (when it's ON).
  environment.etc."NetworkManager/dnsmasq.d/golem-block.conf".text = "addn-hosts=/var/lib/golem/blocklist.hosts\n";

  # Networks see a new random address and no PC name.
  networking.networkmanager = {
    wifi.macAddress = "random";
    ethernet.macAddress = "random";
    settings.connection."ipv4.dhcp-send-hostname" = false;
    settings.connection."ipv6.dhcp-send-hostname" = false;
  };

  # Bluetooth exists but stays off until switched on (and its driver can be switched off in DRIVERS).
  hardware.bluetooth = { enable = true; powerOnBoot = false; };

  # Crash reports stay on the laptop for 7 days and are never sent anywhere.
  systemd.tmpfiles.rules = [ "e /var/lib/systemd/coredump - - - 7d" ];
}
