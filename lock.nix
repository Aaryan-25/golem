# Golem, step 6: the lock screen and the lid.
# Login = lock screen: Golem starts straight into a locked screen with no username and no box.
# You just type your password and press Enter. Wrong tries are written to the system log.
#
#   Super+L          lock now (always)
#   lid closed       sleep; on waking it's locked, unless Caps Lock was ON
#   idle             dim at 4 min, lock at 5 (unless Caps Lock is ON), sleep at 30
{ pkgs, ... }:
let
  s = import ./settings.nix;
  c = s.theme;

  lock = pkgs.writeShellApplication {
    name = "golem-lock";
    runtimeInputs = with pkgs; [ i3lock xset gnugrep gnused coreutils util-linux systemd i3 procps ];
    text = ''
      # golem-lock          lock now
      # golem-lock --auto   lid or idle: skipped while Caps Lock is ON
      # golem-lock --start  the first lock after starting; if the lock ever fails, log out instead
      mode=''${1:-}
      if [ "$mode" = --auto ] && xset q | grep -q "Caps Lock: *on"; then
        logger -t golem "LOCK skipped: Caps Lock is ON"; exit 0
      fi
      pgrep -u "$(id -u)" -x i3lock >/dev/null && exit 0      # already locked
      logger -t golem "LOCK"
      # Sleep after the rest of the idle time (Control Panel > POWER), if still locked by then.
      get() { sed -n "s/^$1=//p" /var/lib/golem/settings.conf 2>/dev/null | tail -n1; }
      sl=$(get idle_sleep); lk=$(get idle_lock); sl=''${sl:-30}; lk=''${lk:-5}
      wait_s=1500
      if [ "$sl" = never ]; then wait_s=0
      elif [ "$lk" != never ] && [ "$sl" -gt "$lk" ]; then wait_s=$(( (sl - lk) * 60 )); fi
      ( if [ "$wait_s" -gt 0 ]; then sleep "$wait_s"; if pgrep -u "$(id -u)" -x i3lock >/dev/null; then systemctl suspend; fi; fi ) &
      timer=$!
      colour='${builtins.substring 1 6 c.void}'
      if grep -q '^face=negative' /var/lib/golem/settings.conf 2>/dev/null; then colour='${builtins.substring 1 6 s.themeNegative.void}'; fi
      if [ -n "''${XSS_SLEEP_LOCK_FD:-}" ] && [ -e "/dev/fd/$XSS_SLEEP_LOCK_FD" ]; then
        # Going to sleep: let the laptop sleep only once the lock is really on the screen,
        # so nothing shows for a moment on waking.
        i3lock -u -e -c "$colour" {XSS_SLEEP_LOCK_FD}<&- || { logger -t golem "LOCK failed"; kill "$timer"; exit 1; }
        exec {XSS_SLEEP_LOCK_FD}<&-
        while pgrep -u "$(id -u)" -x i3lock >/dev/null; do sleep 0.5; done
        logger -t golem "UNLOCK"
      elif i3lock -n -u -e -c "$colour"; then
        logger -t golem "UNLOCK"
      else
        logger -t golem "LOCK failed"
        if [ "$mode" = --start ]; then i3-msg -q exit; fi      # never leave a start unlocked
      fi
      kill "$timer" 2>/dev/null || true
    '';
  };

  # Dims the screen after 4 idle minutes; brightness comes back on any key.
  dim = pkgs.writeShellScript "golem-dim" ''
    if grep -q '^idle_dim=never' /var/lib/golem/settings.conf 2>/dev/null; then sleep infinity & wait; exit 0; fi
    ${pkgs.brightnessctl}/bin/brightnessctl -q -s set 10%
    trap '${pkgs.brightnessctl}/bin/brightnessctl -q -r; exit 0' TERM INT
    sleep infinity & wait
  '';
in {
  programs.i3lock.enable = true;
  environment.etc."golem/dim".source = dim;
  environment.systemPackages = [ lock pkgs.xss-lock ];

  # Login = lock screen: log in by itself on the first screen, once per start, then lock at once.
  services.getty = { autologinUser = s.user; autologinOnce = true; };

  # Lid closed: sleep (the lock happens just before, through xss-lock below).
  services.logind.settings.Login.HandleLidSwitch = "suspend";

}
