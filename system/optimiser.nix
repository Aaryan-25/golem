# The optimiser: Golem working less behind the curtain, without ever getting in my way.
# Almost everything here is a kernel feature that costs nothing while nothing happens:
#   * compressed memory (zram): the 4 GB act more like 6; swapping to the pendrive almost never happens
#   * a guard against freezes (earlyoom): when memory is nearly gone it closes the biggest background app,
#     never the desktop, the realm or the window manager; and says so in the truth log
#   * the window I work in first (golem-tune): only when I switch windows, that app's zone gets more CPU and
#     disk time and the one I left goes back to normal. No polling: it sleeps until a window changes.
#   * power by charger (POWER > Processor > by charger): saver on battery, balanced when plugged in
#   * small, steady disk use: the journal is capped, old Golem versions are cleaned weekly
# And golem-report (the reports to my private repo golem-reports), so nobody has to photograph the screen.
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ pkgs, ... }:
let
  s = import ../settings/settings.nix;
  tune = pkgs.writeShellApplication {
    name = "golem-tune";
    runtimeInputs = with pkgs; [ i3 jq xorg.xprop systemd coreutils gnused ];
    text = ''
      # Gives the zone of the window I'm in more CPU and disk time; the one I left goes back to normal.
      prev=""
      i3-msg -t subscribe -m '[ "window" ]' | while read -r ev; do
        [ "$(jq -r .change <<<"$ev")" = focus ] || continue
        wid=$(jq -r '.container.window // empty' <<<"$ev")
        [ -n "$wid" ] || continue
        pid=$(xprop -id "$wid" _NET_WM_PID 2>/dev/null | sed -n 's/.*= //p')
        [ -n "$pid" ] || continue
        unit=$(sed -n 's|.*/\(zone-[^/]*\.scope\)$|\1|p' "/proc/$pid/cgroup" 2>/dev/null | head -n1)
        [ "$unit" = "$prev" ] && continue
        if [ -n "$prev" ]; then systemctl --user set-property --runtime "$prev" CPUWeight=100 IOWeight=100 2>/dev/null || true; fi
        if [ -n "$unit" ]; then systemctl --user set-property --runtime "$unit" CPUWeight=400 IOWeight=400 2>/dev/null || true; fi
        prev=$unit
      done
    '';
  };

  report = pkgs.writeShellApplication {
    name = "golem-report";
    runtimeInputs = with pkgs; [ git coreutils gnused util-linux procps pciutils usbutils iproute2 systemd imagemagick ];
    text = ''
      # golem-report setup             once: the key that may write only to my private repo golem-reports
      # golem-report [--screen] [note]  sends a report: self-test, errors, version, hardware, truth log
      #                                 (--screen adds a picture of the screen)
      repo="https://github.com/${builtins.head (builtins.split "/" s.githubRepo)}/golem-reports.git"
      conf=~/.config/golem-report
      dir=~/.cache/golem-reports
      if [ "''${1:-}" = setup ]; then
        mkdir -p "$conf"; chmod 700 "$conf"
        echo "Paste the key for golem-reports (it isn't shown), then Enter:"
        read -rs key
        printf '%s\n' "$key" > "$conf/token"; chmod 600 "$conf/token"
        echo "Saved. Now: golem-report   (the Gate will ask about git and github.com: ALWAYS)"
        exit 0
      fi
      [ -s "$conf/token" ] || { echo "First: golem-report setup"; exit 1; }
      token=$(cat "$conf/token")
      screen=no
      if [ "''${1:-}" = --screen ]; then screen=yes; shift; fi
      if [ "''${1:-}" = --quiet ]; then shift; exec >/dev/null 2>&1; fi
      note="$*"
      auth="https://x-access-token:$token@''${repo#https://}"
      if [ ! -d "$dir/.git" ]; then
        rm -rf "$dir"; git clone -q "$auth" "$dir" 2>/dev/null || { mkdir -p "$dir"; git -C "$dir" init -q -b main; }
      fi
      git -C "$dir" pull -q "$auth" main 2>/dev/null || true
      when=$(date +%Y-%m-%d_%H%M)
      out="$dir/$when"
      mkdir -p "$out"
      {
        echo "Golem report $when   version $(cat /etc/golem/version 2>/dev/null)"
        [ -n "$note" ] && echo "Note: $note"
        echo; uptime; echo; free -h; echo; df -h / /home 2>/dev/null
      } > "$out/README.txt"
      golem-selftest > "$out/selftest.txt" 2>&1 || true
      { golem-why; echo; golem-why last; } > "$out/errors.txt" 2>&1 || true
      { lscpu; echo; lspci; echo; lsusb; echo; ip -br link; echo; uname -a; } > "$out/hardware.txt" 2>&1 || true
      golem-truth --text 2>/dev/null | tail -n 400 > "$out/truth-log.txt" || true
      golem-gate rules > "$out/gate-rules.txt" 2>&1 || true
      tail -n 50 ~/golem-updates.txt > "$out/updates.txt" 2>/dev/null || true
      if [ "$screen" = yes ] && [ -n "''${DISPLAY:-}" ]; then import -window root "$out/screen.png" 2>/dev/null || true; fi
      git -C "$dir" add -A
      git -C "$dir" -c user.name=golem -c user.email=golem@localhost commit -q -m "Report $when''${note:+: $note}" || true
      if git -C "$dir" push -q "$auth" HEAD:main 2>/dev/null; then
        logger -t golem "Report sent to golem-reports ($when)"
        echo "Report sent: $when"
      else
        echo "Couldn't send the report (is Wi-Fi on, and did the Gate allow git?)"; exit 1
      fi
    '';
  };
in {
  zramSwap = { enable = true; algorithm = "zstd"; memoryPercent = 60; };
  boot.kernel.sysctl = { "vm.swappiness" = 150; "vm.page-cluster" = 0; };   # tuned for compressed memory

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 4;
    freeSwapThreshold = 8;
    enableNotifications = false;
    extraArgs = [ "--avoid" "^(Xorg|X|i3|golem-realm|python3|systemd|dbus-daemon|pipewire|wireplumber)$" "--prefer" "^(firefox|WebKit.*|golem-browser|xterm)$" ];
  };

  services.journald.extraConfig = "SystemMaxUse=200M";
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 21d"; };

  # power by charger: plugging in or out re-applies the processor setting
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart golem-settings.service"
  '';

  environment.systemPackages = [ tune report ];
}
