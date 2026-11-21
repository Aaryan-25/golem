# Golem, step 8: the Control Panel (Super+Z) and the guard in front of the settings.
# The Control Panel reigns supreme: app settings and keys live in /var/lib/golem, which I can read
# but only the guard (golem-helper) can change, and only after my password. Every change is logged.
{ config, pkgs, lib, ... }:
let
  s = import ./settings.nix;
  uid = toString config.users.users.${s.user}.uid;
  pyw = name: deps: file: pkgs.writers.writePython3Bin name { libraries = deps; flakeIgnore = [ "E501" "W503" "W504" ]; }
    (builtins.readFile file);
  helper = pyw "golem-helper" [ pkgs.python3Packages.python-pam ] ./helper.py;
  keysgen = pyw "golem-keys-gen" [ ] ./keysgen.py;
  panelPy = (pkgs.python3.withPackages (ps: [ ps.tkinter ]));
  panel = pkgs.writeShellApplication {
    name = "golem-panel";
    runtimeInputs = with pkgs; [ systemd networkmanager wireplumber brightnessctl procps util-linux i3 pciutils bluez coreutils gawk gnugrep nix ];
    text = ''
      export GOLEM_THEMES='${builtins.toJSON { shadow = s.theme; negative = s.themeNegative; }}'
      exec ${panelPy}/bin/python3 ${./panel.py} "$@"
    '';
  };
  # Super+Z: the panel runs in the GREEN zone. If it can't open, say so and write down why.
  start = pkgs.writeShellApplication {
    name = "golem-panel-start";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      if ! out=$(zone green golem-panel 2>&1); then
        logger -t golem "The Control Panel could not open: $(echo "$out" | tail -n 3 | tr '\n' ' ')"
        golem-alert "The Control Panel could not open. The reason is in the truth log (Super+T)." || true
      fi
    '';
  };
in {
  environment.systemPackages = [ panel start keysgen ];
  users.users.${s.user}.uid = 1000;

  # The guard: a socket only my user may use; each request starts it once, as root.
  security.pam.services.golem-panel = { };
  systemd.sockets.golem-helper = {
    wantedBy = [ "sockets.target" ];
    socketConfig = { ListenStream = "/run/golem-helper.sock"; Accept = true; SocketMode = "0666"; };
  };
  systemd.services."golem-helper@" = {
    description = "Golem: the guard in front of the settings";
    path = with pkgs; [ networkmanager keysgen chrony util-linux coreutils bluez gnutar nix systemd ] ++ [ "/run/current-system/sw" ];
    environment = { GOLEM_USER = s.user; GOLEM_UID = uid; };
    serviceConfig = { ExecStart = "${helper}/bin/golem-helper"; StandardInput = "socket"; StandardOutput = "journal"; };
  };

  # At every start and update: make sure the settings folder exists, bring in settings from the
  # old place (~/zones/settings) once, and rebuild the key lines (new Golem keys get added).
  system.activationScripts.golem-settings = {
    deps = [ "etc" "users" ];
    text = ''
      mkdir -p /var/lib/golem/apps
      chmod 755 /var/lib/golem /var/lib/golem/apps
      old=/home/${s.user}/zones/settings
      if [ -d "$old" ] && [ ! -e /var/lib/golem/.moved ]; then
        for f in "$old"/*.conf; do
          [ -e "$f" ] || continue
          n=$(basename "$f")
          [ -e "/var/lib/golem/apps/$n" ] || install -m 644 -o root "$f" "/var/lib/golem/apps/$n"
        done
        touch /var/lib/golem/.moved
      fi
      ${keysgen}/bin/golem-keys-gen
    '';
  };
}
