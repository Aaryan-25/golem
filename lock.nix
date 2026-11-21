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
    runtimeInputs = with pkgs; [ i3lock xset gnugrep coreutils util-linux systemd i3 ];
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
      # After 25 minutes locked, sleep (30 minutes idle in all).
      ( sleep 1500; if pgrep -u "$(id -u)" -x i3lock >/dev/null; then systemctl suspend; fi ) &
      timer=$!
      if i3lock -n -u -e -c '${builtins.substring 1 6 c.void}'; then
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
