# The Gate: the only way from my apps to the internet (gate.py, gate_ask.py).
#   * The firewall stops my user's programs from reaching anything outside this computer directly.
#   * Every app is pointed at the Gate (http_proxy / https_proxy); the Gate asks me the first time an app
#     wants a site (once / always / never), remembers ALWAYS and NEVER, and writes everything down:
#     the truth log, and /var/lib/golem-gate/feed.jsonl for my AI to watch.
#   * golem-gate on | hidden | off | status | rules | forget APP ZONE SITE   (hidden = through Tor)
# System services (updates, the clock, Wi-Fi) are not my apps and are not asked about.
{ pkgs, ... }:
let
  s = import ../settings/settings.nix;
  gatePy = pkgs.python3;
  cli = pkgs.writeShellScriptBin "golem-gate" ''
    exec ${pkgs.python3}/bin/python3 ${./gate_ask.py} "$@"
  '';
  proxy = "http://127.0.0.1:3128";
in {
  users.users.golem-gate = { isSystemUser = true; group = "golem-gate"; extraGroups = [ "tor" ]; };

  # HIDDEN mode: Tor, switched off (no connections at all) until the Gate turns it on.
  services.tor = {
    enable = true;
    client.enable = true;
    controlSocket.enable = true;
    settings.DisableNetwork = true;
  };
  users.groups.golem-gate = { };

  systemd.services.golem-gate = {
    description = "The Gate: the only way from my apps to the internet";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.iproute2 ];
    environment.GOLEM_GATE_OWNER = "1000";
    serviceConfig = {
      ExecStart = "${gatePy}/bin/python3 -u ${./gate.py}";
      User = "golem-gate";
      Group = "golem-gate";
      RuntimeDirectory = "golem-gate";
      RuntimeDirectoryMode = "0755";
      StateDirectory = "golem-gate";
      StateDirectoryMode = "0755";
      # to see which app owns a connection (it reads, never changes, other programs)
      AmbientCapabilities = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      CapabilityBoundingSet = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      Restart = "always";
      RestartSec = 2;
    };
  };

  # My programs reach the outside only through the Gate (this computer itself, 127.0.0.1, is fine).
  networking.firewall.extraCommands = ''
    for t in iptables ip6tables; do
      $t -N golem-out 2>/dev/null || $t -F golem-out
      $t -C OUTPUT -j golem-out 2>/dev/null || $t -A OUTPUT -j golem-out
      $t -A golem-out -o lo -j RETURN
      $t -A golem-out -m owner --uid-owner 1000-59999 -j REJECT
    done
  '';
  networking.firewall.extraStopCommands = ''
    for t in iptables ip6tables; do
      $t -D OUTPUT -j golem-out 2>/dev/null || true
      $t -F golem-out 2>/dev/null || true
      $t -X golem-out 2>/dev/null || true
    done
  '';

  environment.variables = {
    http_proxy = proxy; https_proxy = proxy; HTTP_PROXY = proxy; HTTPS_PROXY = proxy;
    no_proxy = "localhost,127.0.0.1,::1"; NO_PROXY = "localhost,127.0.0.1,::1";
  };
  environment.systemPackages = [ cli ];
}
