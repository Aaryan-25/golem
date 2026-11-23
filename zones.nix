# Golem, step 4: zones. Every app runs in a zone, and gets only what its zone and settings allow.
#
#   zone <app>               the app's saved settings (RED if it has none)
#   zone red|offline|yellow|green <app>   run it in that zone this time
#   zone set <app> <zone>    a new app's first zone (after that, only the Control Panel changes it)
#   zone show <app>          what the app may do
#
# Settings: /var/lib/golem/apps/<app>.conf. I can read them; only the Control Panel changes them,
# after my password (the Control Panel reigns supreme).
#
# ROOMS (screen and clipboard separation): a RED, OFFLINE or YELLOW app with a window gets its own
# sealed screen, a "room": a window on my desktop (titled ROOM | ZONE | app) with the app inside.
# From inside, the app sees only its room: not my other windows, not my key presses (keys reach it
# only while its room is in front), not my clipboard. Super+C carries my clipboard into the room in
# front; Super+Shift+C carries the room's clipboard out to me. Both are logged.
# GREEN apps stay on my own screen. MEMORIES > PRIVACY > "Separate screens" turns rooms off.
{ pkgs, ... }:
let
  s = import ./settings.nix;
  L = s.limits;

  zone = pkgs.writeShellApplication {
    name = "zone";
    runtimeInputs = with pkgs; [ systemd coreutils util-linux gnused socat xorg.xorgserver i3 ];
    text = ''
      SET=/var/lib/golem/apps
      FJ=/run/wrappers/bin/firejail
      ${s.bigger}
      is_zone() { case "$1" in red|offline|yellow|green) return 0 ;; esac; return 1; }
      usage() {
        echo "zone <app>                          run with the app's settings (RED if none)"
        echo "zone red|offline|yellow|green <app> run in that zone this time"
        echo "zone set <app> <zone>               a new app's first zone (then: Control Panel, Super+Z)"
        echo "zone show <app>                     what the app may do"
        exit 2
      }

      defaults() {   # the starting settings of a zone
        Z=$1; FOLDER=""; GPU=never
        case "$1" in
          red)     RAM=${L.red.memory};     CPU=${L.red.cpu};     NET=never;   CAM=never; USB=never; SND=off ;;
          offline) RAM=${L.offline.memory}; CPU=${L.offline.cpu}; NET=never;   CAM=never; USB=never; SND=on ;;
          yellow)  RAM=${L.yellow.memory};  CPU=${L.yellow.cpu};  NET=allowed; CAM=never; USB=never; SND=on ;;
          green)   RAM=${L.green.memory};   CPU=${L.green.cpu};   NET=never;   CAM=never; USB=never; SND=on ;;
        esac
        RAM=$(bigger "$RAM"); CPU=$(bigger "$CPU")
      }
      load() {       # zone defaults, then the app's own settings
        local f="$SET/$1.conf" k v z=""
        if [ -f "$f" ]; then z=$(sed -n 's/^zone=//p' "$f" | tail -n1); fi
        is_zone "$z" || z=red
        defaults "$z"
        [ -f "$f" ] || return 0
        while IFS='=' read -r k v; do
          case "$k" in
            ram)      if [[ "$v" =~ ^[0-9]+[MG]$ ]]; then RAM=$v; fi ;;
            cpu)      if [[ "$v" =~ ^[0-9]+%$ ]]; then CPU=$v; fi ;;
            # anything that isn't exactly "allowed" / "on" means never / off
            internet) NET=never; if [ "$v" = allowed ]; then NET=allowed; fi ;;
            camera)   CAM=never; if [ "$v" = allowed ]; then CAM=allowed; fi ;;
            usb)      USB=never; if [ "$v" = allowed ]; then USB=allowed; fi ;;
            sound)    SND=off;   if [ "$v" = on ]; then SND=on; fi ;;
            nvidia)   GPU=never; if [ "$v" = allowed ]; then GPU=allowed; fi ;;
            folder)   FOLDER=$v ;;
          esac
        done < "$f"
      }

      [ $# -ge 1 ] || usage
      case "$1" in
        defaults) is_zone "''${2:-}" || usage; defaults "$2"
              printf '%s\n' "zone=$Z" "ram=$RAM" "cpu=$CPU" "internet=$NET" "camera=$CAM" "usb=$USB" "sound=$SND" "nvidia=$GPU" "folder="
              exit 0 ;;
        set)  if [ $# -ne 3 ] || ! is_zone "$3"; then usage; fi
              r=$(printf '{"do":"first-zone","app":"%s","zone":"%s"}\n' "$(basename "$2")" "$3" \
                  | socat -t 10 - UNIX-CONNECT:/run/golem-helper.sock)
              if [ "$r" = OK ]; then echo "$2 is now in ''${3^^}"; exit 0; fi
              echo "zone: ''${r#ERROR }" >&2; exit 1 ;;
        show) [ $# -eq 2 ] || usage; load "$(basename "$2")"
              echo "$2: ''${Z^^}  internet:$NET camera:$CAM sound:$SND usb:$USB nvidia:$GPU  RAM<=$RAM CPU<=$CPU  folder:''${FOLDER:-default}"
              exit 0 ;;
      esac

      z=""; if is_zone "$1"; then z=$1; shift; fi
      [ $# -ge 1 ] || usage
      prog=$1; name=$(basename "$prog")
      command -v "$prog" >/dev/null || { echo "zone: '$prog' is not installed" >&2; exit 1; }
      load "$name"
      if [ -n "$z" ] && [ "$z" != "$Z" ]; then defaults "$z"; fi
      # What the zone forbids, no setting can allow.
      if [ "$Z" = red ]; then NET=never; CAM=never; USB=never; SND=off; GPU=never; fi
      if [ "$Z" = offline ]; then NET=never; fi

      dir="$HOME/zones/$name"
      if [ -n "$FOLDER" ]; then
        f=''${FOLDER/#\~/$HOME}
        case "$f" in *..*) echo "zone: bad folder" >&2; exit 1 ;; "$HOME"/?*) dir=$f ;;
          *) echo "zone: the folder must be inside your home" >&2; exit 1 ;; esac
      fi

      opts=(--noprofile --quiet --caps.drop=all --nonewprivs --seccomp --dbus-system=none)
      case "$Z" in
        red)     opts+=(--private --private-tmp --private-dev --nogroups --no3d --dbus-user=none --machine-id) ;;
        offline) mkdir -p "$dir"; opts+=(--private="$dir" --private-tmp --private-dev --nogroups --dbus-user=none) ;;
        yellow)  mkdir -p "$dir"; opts+=(--private="$dir" --private-tmp --private-dev --nogroups --blacklist=/run/golem-gate) ;;
        green)   ;;
      esac
      [ "$NET" = allowed ] || opts+=(--net=none)
      [ "$CAM" = allowed ] || opts+=(--novideo)
      [ "$SND" = on ]      || opts+=(--nosound)
      [ "$USB" = allowed ] || opts+=(--blacklist=/run/media --blacklist=/media --blacklist=/mnt)
      [ "$GPU" = allowed ] || opts+=("--blacklist=/dev/nvidia*")   # the NVIDIA card: only for apps I mark

      # A room: its own screen (Xephyr), with a tiny window manager inside, shown as one window on mine.
      room=""
      sep=on
      if grep -q '^separate_screens=off' /var/lib/golem/settings.conf 2>/dev/null; then sep=off; fi
      if [ -n "''${DISPLAY:-}" ] && [ "$Z" != green ] && [ "$sep" = on ]; then
        n=20; while [ -e "/tmp/.X11-unix/X$n" ] || [ -e "/tmp/.X$n-lock" ]; do n=$((n + 1)); done
        Xephyr ":$n" -ac -nolisten tcp -nolisten local -resizeable -no-host-grab -screen 1280x720           -title "ROOM | ''${Z^^} | $name | :$n" >/dev/null 2>&1 &
        xp=$!
        for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X$n" ] && break; sleep 0.1; done
        DISPLAY=":$n" i3 -c /etc/golem/room-i3.config >/dev/null 2>&1 &
        wm=$!
        room=":$n"
        # inside: only its own room's screen; never mine, never another room's
        for sock in /tmp/.X11-unix/X*; do
          [ "$sock" = "/tmp/.X11-unix/X$n" ] || opts+=(--blacklist="$sock")
        done
        opts+=(--env=DISPLAY=":$n" --blacklist="$HOME/.Xauthority")
      fi

      gpu_note=""; if [ "$GPU" = allowed ]; then gpu_note=" nvidia:allowed"; fi
      desc="''${Z^^} $name | internet:$NET camera:$CAM sound:$SND usb:$USB$gpu_note | RAM<=$RAM CPU<=$CPU''${room:+ | room $room}"
      logger -t zone "START $desc"
      systemd-run --user --scope --quiet --collect --unit="zone-$Z-$name-$$" --description="$desc" \
        -p MemoryMax="$RAM" -p MemorySwapMax=256M -p CPUQuota="$CPU" -p TasksMax=256 \
        -- "$FJ" "''${opts[@]}" -- "$@" && rc=0 || rc=$?
      logger -t zone "END   ''${Z^^} $name (exit $rc)"
      if [ -n "$room" ]; then kill "$wm" "$xp" 2>/dev/null || true; fi
      exit "$rc"
    '';
  };

  # For testing zones: says ONLINE or OFFLINE.
  nettest = pkgs.writeShellScriptBin "golem-net-test" ''
    # Could this zone get out through the Gate? (a test the Gate allows without asking: it sends nothing)
    if timeout 8 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3128 && printf "CONNECT 1.1.1.1:443 HTTP/1.1\r\nX-Golem-Probe: 1\r\n\r\n" >&3 && read -r l <&3 && [[ $l == *" 200 "* ]]' 2>/dev/null; then
      echo ONLINE; else echo OFFLINE; fi
  '';
  # golem-carry: the clipboard, carried by hand between my screen and the room in front.
  carry = pkgs.writeShellApplication {
    name = "golem-carry";
    runtimeInputs = with pkgs; [ xclip xdotool coreutils util-linux gnused ];
    text = ''
      # golem-carry in   (Super+C)        my clipboard -> the room in front
      # golem-carry out  (Super+Shift+C)  the room in front's clipboard -> mine
      t=$(xdotool getactivewindow getwindowname 2>/dev/null || true)
      case "$t" in "ROOM | "*) ;; *) exit 0 ;; esac
      d=''${t##* | }; who=$(echo "$t" | sed 's/^ROOM | //; s/ | :[0-9]*$//; s/ | / /')
      case "''${1:-}" in
        in)  xclip -selection clipboard -o 2>/dev/null | xclip -display "$d" -selection clipboard -i >/dev/null 2>&1
             logger -t zone "Clipboard carried into the room of $who" ;;
        out) DISPLAY=$d xclip -selection clipboard -o 2>/dev/null | xclip -selection clipboard -i >/dev/null 2>&1
             logger -t zone "Clipboard carried out of the room of $who" ;;
      esac
    '';
  };
in {
  programs.firejail.enable = true;
  # Inside a room: no bars, every window filling the room, nothing else.
  environment.etc."golem/room-i3.config".text = ''
    default_border none
    default_floating_border none
    workspace_layout tabbed
    for_window [all] border none
    bar { mode invisible }
  '';
  # My own screen listens only on its file (the rooms hide that file), not on a hidden name anyone could reach.
  services.xserver.displayManager.xserverArgs = [ "-nolisten" "local" ];
  environment.systemPackages = [ zone nettest carry pkgs.xauth pkgs.alsa-utils pkgs.xclip ];

  # My folders (DECISIONS.md): documents, projects, media, zones.
  systemd.tmpfiles.rules = map (d: "d /home/${s.user}/${d} 0700 ${s.user} users -")
    [ "documents" "projects" "media" "zones" "zones/settings" ]
    ++ map (f: "f /home/${s.user}/zones/settings/${f} 0600 ${s.user} users -") [ "i3-placements" "face.i3" "face.rasi" ];
}
