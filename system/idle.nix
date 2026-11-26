# Idle and the lid. There is no lock screen for now (decided 22 Nov 2026): Golem starts straight in.
#   idle    dim after a few minutes (POWER page), then the idle screen, then sleep
#   lid     closing it sleeps
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ pkgs, ... }:
let
  s = import ../settings/settings.nix;

  # Runs when nothing has been touched for the idle time (xss-lock starts it), and ends on the first touch.
  idle = pkgs.writeShellApplication {
    name = "golem-idle";
    runtimeInputs = with pkgs; [ xprintidle xset gnused coreutils util-linux systemd procps ];
    text = ''
      # Going to sleep (lid): nothing to hold the sleep back for.
      if [ -n "''${XSS_SLEEP_LOCK_FD:-}" ]; then exec {XSS_SLEEP_LOCK_FD}<&-; fi
      logger -t golem "IDLE"
      if [ -e /var/lib/golem/remote-on ]; then
        # Staying on day and night (guard.nix): the screen goes fully off, nothing moves. Any touch brings it back.
        xset +dpms; xset dpms force off
      elif command -v golem-realm >/dev/null; then golem-realm idle || true; fi
      get() { if [ -f /var/lib/golem/settings.conf ]; then sed -n "s/^$1=//p" /var/lib/golem/settings.conf | tail -n1; fi; }
      sl=$(get idle_sleep); sl=''${sl:-30}
      while [ "$(xprintidle)" -gt 1500 ]; do
        if [ "$sl" != never ] && [ $(( $(xprintidle) / 1000 )) -ge $(( sl * 60 )) ]; then
          logger -t golem "Untouched for $sl minutes: sleeping"; systemctl suspend; sleep 5
        fi
        sleep 1
      done
      if [ -e /var/lib/golem/remote-on ]; then xset dpms force on; xset -dpms; fi
      logger -t golem "AWAKE"
    '';
  };

  # Dims the screen a little before the idle time; brightness comes back on any key.
  dim = pkgs.writeShellScript "golem-dim" ''
    if grep -q '^idle_dim=never' /var/lib/golem/settings.conf 2>/dev/null; then sleep infinity & wait; exit 0; fi
    ${pkgs.brightnessctl}/bin/brightnessctl -q -s set 10%
    trap '${pkgs.brightnessctl}/bin/brightnessctl -q -r; exit 0' TERM INT
    sleep infinity & wait
  '';
in {
  environment.etc."golem/dim".source = dim;
  environment.systemPackages = [ idle pkgs.xss-lock ];

  # Straight in: log in by itself on the first screen, every time.
  services.getty.autologinUser = s.user;

  services.logind.settings.Login.HandleLidSwitch = "suspend";
}
