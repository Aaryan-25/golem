# Reaching this laptop from my phone (golem-remote). OFF until I turn it on, and it stays as I left it.
#
#   golem-remote setup     once: joins Tailscale (shows a link to log in on the phone) and sets the screen password
#   (on, off and setup ask for my password: they change the system)
#   golem-remote on        the phone can reach this laptop; it stays awake, even with the lid closed
#   golem-remote off       nothing can reach it any more (Tailscale is stopped too); it sleeps as usual
#   golem-remote status    on or off, this laptop's address, who is connected
#
# How it works, piece by piece:
#   * Tailscale makes a private link between my own devices (this laptop, my phone), encrypted from end to end,
#     wherever they are. Only devices logged in to my Tailscale account can use it. Tailscale the company helps
#     the devices find each other, but can't see what goes between them. (Later: my own server instead.)
#   * The screen: x11vnc shares this laptop's real screen (what I would see if I sat at it). On the phone,
#     a VNC app (address: this laptop's Tailscale address, port 5900), or the phone's browser:
#     http://<address>:6080/vnc.html (noVNC: the same screen in a web page, nothing to install).
#   * Both listen only on the Tailscale link (the firewall allows ports 5900 and 6080 on tailscale0 only),
#     and ask for the screen password. Every connection goes to the truth log ("Remote: ...").
#   * While it's on, a small service holds the laptop awake (systemd-inhibit), so sleep and the lid don't cut me off.
# Where things are: /var/lib/golem/remote-on (exists = on), ~/.config/golem-remote/passwd (the screen password).
# Part of Golem: the system (start, hardware, power, updates); MAP.md section 5.10.
{ pkgs, lib, ... }:
let
  flag = "/var/lib/golem/remote-on";
  # The screen sharing, inside my session (started by i3, see desktop.nix): runs only while remote is on.
  screen = pkgs.writeShellApplication {
    name = "golem-remote-screen";
    runtimeInputs = with pkgs; [ x11vnc novnc util-linux coreutils procps ];
    text = ''
      pw="$HOME/.config/golem-remote/passwd"
      while true; do
        if [ -e ${flag} ] && [ -s "$pw" ]; then
          if ! pgrep -u "$(id -u)" -x x11vnc >/dev/null; then
            # shellcheck disable=SC2016  # $RFB_CLIENT_IP is filled in by x11vnc when someone connects
            x11vnc -display "$DISPLAY" -rfbauth "$pw" -forever -shared -rfbport 5900 -quiet -noxdamage \
              -afteraccept 'logger -t golem "Remote: the screen was opened from $RFB_CLIENT_IP"' \
              -gone 'logger -t golem "Remote: the screen was closed from $RFB_CLIENT_IP"' >/dev/null 2>&1 &
            novnc --listen 6080 --vnc localhost:5900 >/dev/null 2>&1 &
          fi
        else
          pkill -u "$(id -u)" -x x11vnc 2>/dev/null || true
          pkill -u "$(id -u)" -f 'novnc|websockify' 2>/dev/null || true
        fi
        sleep 5
      done
    '';
  };
  remote = pkgs.writeShellApplication {
    name = "golem-remote";
    runtimeInputs = with pkgs; [ tailscale x11vnc systemd util-linux coreutils ];
    text = ''
      pw="$HOME/.config/golem-remote/passwd"
      case "''${1:-status}" in
        setup)
          echo "1) Install the Tailscale app on your phone and log in there (Google or any account)."
          echo "2) This laptop joins the same account: a link appears below; open it on the phone and approve."
          sudo systemctl start tailscaled
          sudo tailscale up --operator="$USER"
          echo; echo "3) A password for the screen (up to 8 letters; asked when the phone opens the screen)."
          mkdir -p "$(dirname "$pw")"; chmod 700 "$(dirname "$pw")"
          x11vnc -storepasswd "$pw"
          logger -t golem "Remote: set up (Tailscale joined, screen password set)"
          echo; echo "Done. Turn it on with: golem-remote on" ;;
        on)
          [ -s "$pw" ] || { echo "First: golem-remote setup"; exit 1; }
          sudo touch ${flag}
          sudo systemctl start tailscaled golem-remote-awake
          logger -t golem "Remote: ON (reachable from my phone; staying awake)"
          echo "On. From the phone: a VNC app to $(tailscale ip -4 2>/dev/null | head -n 1):5900,"
          echo "or the browser: http://$(tailscale ip -4 2>/dev/null | head -n 1):6080/vnc.html" ;;
        off)
          sudo rm -f ${flag}
          sudo systemctl stop golem-remote-awake tailscaled
          logger -t golem "Remote: OFF (nothing can reach this laptop)"
          echo "Off. Nothing can reach this laptop." ;;
        status)
          if [ -e ${flag} ]; then echo "Remote: ON"; else echo "Remote: OFF"; fi
          tailscale ip -4 2>/dev/null | sed 's/^/Address: /' || true
          tailscale status 2>/dev/null || true ;;
        *) echo "golem-remote setup | on | off | status"; exit 2 ;;
      esac
    '';
  };
  # While remote is on, the battery stops at 60% (kinder to a battery that is always on the charger).
  battery60 = pkgs.writeShellScript "golem-battery-60" ''
    for p in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
      if [ -w "$p" ]; then echo 60 > "$p"; fi
    done
    ${pkgs.util-linux}/bin/logger -t golem "Remote: the battery stops at 60% while remote is on"
  '';
in
{
  environment.systemPackages = [ remote screen pkgs.tailscale ];
  services.tailscale = { enable = true; openFirewall = true; };
  # Tailscale does not start by itself: only when remote is on (or during setup).
  systemd.services.tailscaled.wantedBy = lib.mkForce [ ];
  systemd.services.golem-remote-start = {
    description = "Golem: if remote was on when I shut down, turn it on again";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = flag;
    serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.systemd}/bin/systemctl start --no-block tailscaled golem-remote-awake"; };
  };
  # Holds the laptop awake while remote is on: no sleep, and closing the lid does nothing.
  # (The staying-on guard, guard.nix: while this runs, the battery stops at 60%; my own setting comes back after.)
  systemd.services.golem-remote-awake = {
    description = "Golem: stay awake for remote";
    serviceConfig.ExecStartPre = "${battery60}";
    serviceConfig.ExecStopPost = "${pkgs.systemd}/bin/systemctl start --no-block golem-settings";
    serviceConfig.ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=sleep:idle:handle-lid-switch --who=golem-remote --why=reachable-from-my-phone --mode=block ${pkgs.coreutils}/bin/sleep infinity";
  };
  # The phone may reach the screen only through the Tailscale link, and my programs may answer only there.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5900 6080 ];
  networking.firewall.extraCommands = lib.mkAfter ''
    for t in iptables ip6tables; do
      $t -I golem-out 1 -o tailscale0 -m conntrack --ctstate ESTABLISHED -j RETURN
    done
  '';
}
