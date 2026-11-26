# The staying-on guard: keeps a laptop healthy when it stays on day and night (the Asus, reachable from the phone).
#
# Always (on every laptop):
#   * Heat watch (golem-heat): every 30 seconds it reads the processor's temperature.
#       85 °C or more for a minute  -> the truth log says so, and the processor is held to 60% of its top speed
#       back under 70 °C            -> full speed again, and the truth log says so
#       95 °C or more for a minute  -> the truth log says why, and the laptop shuts down safely
#   * Disk health (golem-disk-health): once a week it asks each disk how healthy it is, and writes the answer
#     to the truth log. (Pendrives usually can't tell; it says so.)
# Only while remote is on (remote.nix), the rest is done there and in idle.nix:
#   * the battery stops charging at 60% (back to my own setting when remote is turned off)
#   * when nothing is touched, the screen turns fully off instead of showing the moving sand
# Part of Golem: the system (start, hardware, power, updates); MAP.md section 5.11.
{ pkgs, ... }:
let
  heat = pkgs.writeShellApplication {
    name = "golem-heat";
    runtimeInputs = with pkgs; [ coreutils util-linux systemd gnugrep ];
    text = ''
      # The processor's temperature in °C: the processor's own sensor if there is one, else the hottest zone.
      temp() {
        local best=0 t z
        for z in /sys/class/thermal/thermal_zone*; do
          [ -r "$z/temp" ] || continue
          t=$(( $(cat "$z/temp" 2>/dev/null || echo 0) / 1000 ))
          if grep -qs x86_pkg_temp "$z/type"; then echo "$t"; return; fi
          [ "$t" -gt "$best" ] && best=$t
        done
        echo "$best"
      }
      # Hold the processor to a share of its top speed (100 = no limit).
      cap() {
        local p max
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
          [ -r "$p/cpuinfo_max_freq" ] || continue
          max=$(cat "$p/cpuinfo_max_freq")
          echo $(( max * $1 / 100 )) > "$p/scaling_max_freq" 2>/dev/null || true
        done
      }
      hot=0 burning=0 held=0
      while true; do
        t=$(temp)
        if [ "$t" -ge 95 ]; then burning=$((burning + 1)); else burning=0; fi
        if [ "$t" -ge 85 ]; then hot=$((hot + 1)); else hot=0; fi
        if [ "$burning" -ge 2 ]; then
          logger -t golem "Too hot: $t °C for a minute. Shutting down safely to protect the laptop."
          systemctl poweroff
        elif [ "$hot" -ge 2 ] && [ "$held" = 0 ]; then
          cap 60; held=1
          logger -t golem "Hot: $t °C. The processor is held to 60% of its speed until it cools down."
        elif [ "$held" = 1 ] && [ "$t" -lt 70 ]; then
          cap 100; held=0
          logger -t golem "Cooled down to $t °C: full speed again."
        fi
        sleep 30
      done
    '';
  };
  diskHealth = pkgs.writeShellApplication {
    name = "golem-disk-health";
    runtimeInputs = with pkgs; [ smartmontools util-linux coreutils gnugrep ];
    text = ''
      for d in $(lsblk -dn -o NAME,TYPE | grep ' disk$' | cut -d' ' -f1 | grep -v '^zram'); do
        model=$(lsblk -dn -o MODEL "/dev/$d" | xargs)
        if out=$(smartctl -H "/dev/$d" 2>&1) && echo "$out" | grep -q PASSED; then
          logger -t golem "Disk health: /dev/$d ($model) is healthy."
        elif echo "$out" | grep -qi 'FAILED'; then
          logger -t golem "Disk health: /dev/$d ($model) says it is FAILING. Copy your files somewhere else soon."
        else
          logger -t golem "Disk health: /dev/$d ($model) can't tell (pendrives usually can't)."
        fi
      done
    '';
  };
in
{
  environment.systemPackages = [ heat diskHealth pkgs.smartmontools ];
  systemd.services.golem-heat = {
    description = "Golem: heat watch";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { ExecStart = "${heat}/bin/golem-heat"; Restart = "always"; RestartSec = 10; Nice = 10; };
  };
  systemd.services.golem-disk-health = {
    description = "Golem: weekly disk health check";
    serviceConfig = { Type = "oneshot"; ExecStart = "${diskHealth}/bin/golem-disk-health"; };
  };
  systemd.timers.golem-disk-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "weekly"; Persistent = true; RandomizedDelaySec = "1h"; };
  };
}
