# Golem, step 4: zones. Every app runs in a zone, and gets only what its zone and settings allow.
#
#   zone <app>               the app's saved settings (RED if it has none)
#   zone red|offline|yellow|green <app>   run it in that zone this time
#   zone set <app> <zone>    save the app's zone (with that zone's default settings)
#   zone show <app>          what the app may do
#
# Settings: ~/zones/settings/<app>.conf  (the Control Panel will edit these in step 8)
{ pkgs, ... }:
let
  s = import ./settings.nix;
  L = s.limits;

  zone = pkgs.writeShellApplication {
    name = "zone";
    runtimeInputs = with pkgs; [ systemd coreutils util-linux gnused ];
    text = ''
      SET="$HOME/zones/settings"
      FJ=/run/wrappers/bin/firejail
      is_zone() { case "$1" in red|offline|yellow|green) return 0 ;; esac; return 1; }
      usage() {
        echo "zone <app>                          run with the app's settings (RED if none)"
        echo "zone red|offline|yellow|green <app> run in that zone this time"
        echo "zone set <app> <zone>               save the app's zone"
        echo "zone show <app>                     what the app may do"
        exit 2
      }

      defaults() {   # the starting settings of a zone
        Z=$1; FOLDER=""
        case "$1" in
          red)     RAM=${L.red.memory};     CPU=${L.red.cpu};     NET=never;   CAM=never; USB=never; SND=off ;;
          offline) RAM=${L.offline.memory}; CPU=${L.offline.cpu}; NET=never;   CAM=never; USB=never; SND=on ;;
          yellow)  RAM=${L.yellow.memory};  CPU=${L.yellow.cpu};  NET=allowed; CAM=never; USB=never; SND=on ;;
          green)   RAM=${L.green.memory};   CPU=${L.green.cpu};   NET=never;   CAM=never; USB=never; SND=on ;;
        esac
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
            folder)   FOLDER=$v ;;
          esac
        done < "$f"
      }
      save() {
        mkdir -p "$SET"
        printf '%s\n' "zone=$Z" "ram=$RAM" "cpu=$CPU" "internet=$NET" "camera=$CAM" \
          "usb=$USB" "sound=$SND" "folder=$FOLDER" > "$SET/$1.conf"
      }

      [ $# -ge 1 ] || usage
      case "$1" in
        set)  if [ $# -ne 3 ] || ! is_zone "$3"; then usage; fi
              defaults "$3"; save "$(basename "$2")"
              logger -t zone "SETTINGS $2: zone ''${3^^}"; echo "$2 is now in ''${3^^}"; exit 0 ;;
        show) [ $# -eq 2 ] || usage; load "$(basename "$2")"
              echo "$2: ''${Z^^}  internet:$NET camera:$CAM sound:$SND usb:$USB  RAM<=$RAM CPU<=$CPU  folder:''${FOLDER:-default}"
              exit 0 ;;
      esac

      z=""; if is_zone "$1"; then z=$1; shift; fi
      [ $# -ge 1 ] || usage
      prog=$1; name=$(basename "$prog")
      command -v "$prog" >/dev/null || { echo "zone: '$prog' is not installed" >&2; exit 1; }
      load "$name"
      if [ -n "$z" ] && [ "$z" != "$Z" ]; then defaults "$z"; fi
      # What the zone forbids, no setting can allow.
      if [ "$Z" = red ]; then NET=never; CAM=never; USB=never; SND=off; fi
      if [ "$Z" = offline ]; then NET=never; fi

      dir="$HOME/zones/$name"
      if [ -n "$FOLDER" ]; then
        f=''${FOLDER/#\~/$HOME}
        case "$f" in *..*) echo "zone: bad folder" >&2; exit 1 ;; "$HOME"/?*) dir=$f ;;
          *) echo "zone: the folder must be inside your home" >&2; exit 1 ;; esac
      fi

      export XAUTHORITY="''${XAUTHORITY:-$HOME/.Xauthority}"   # the sandbox needs it to make a RED window key
      opts=(--noprofile --quiet --caps.drop=all --nonewprivs --seccomp --dbus-system=none)
      case "$Z" in
        red)     opts+=(--private --private-tmp --private-dev --nogroups --no3d --dbus-user=none --machine-id)
                 if [ -n "''${DISPLAY:-}" ]; then opts+=(--x11=xorg); fi ;;
        offline) mkdir -p "$dir"; opts+=(--private="$dir" --private-tmp --private-dev --nogroups --dbus-user=none) ;;
        yellow)  mkdir -p "$dir"; opts+=(--private="$dir" --private-tmp --private-dev --nogroups) ;;
        green)   ;;
      esac
      [ "$NET" = allowed ] || opts+=(--net=none)
      [ "$CAM" = allowed ] || opts+=(--novideo)
      [ "$SND" = on ]      || opts+=(--nosound)
      [ "$USB" = allowed ] || opts+=(--blacklist=/run/media --blacklist=/media --blacklist=/mnt)

      desc="''${Z^^} $name | internet:$NET camera:$CAM sound:$SND usb:$USB | RAM<=$RAM CPU<=$CPU"
      logger -t zone "START $desc"
      systemd-run --user --scope --quiet --collect --unit="zone-$Z-$name-$$" --description="$desc" \
        -p MemoryMax="$RAM" -p MemorySwapMax=256M -p CPUQuota="$CPU" -p TasksMax=256 \
        -- "$FJ" "''${opts[@]}" -- "$@" && rc=0 || rc=$?
      logger -t zone "END   ''${Z^^} $name (exit $rc)"
      exit "$rc"
    '';
  };

  # For testing zones: says ONLINE or OFFLINE.
  nettest = pkgs.writeShellScriptBin "golem-net-test" ''
    if timeout 5 bash -c 'echo > /dev/tcp/1.1.1.1/443' 2>/dev/null; then echo ONLINE; else echo OFFLINE; fi
  '';
in {
  programs.firejail.enable = true;
  environment.systemPackages = [ zone nettest pkgs.xauth pkgs.firefox pkgs.alsa-utils ];

  # My folders (DECISIONS.md): documents, projects, media, zones.
  systemd.tmpfiles.rules = map (d: "d /home/${s.user}/${d} 0700 ${s.user} users -")
    [ "documents" "projects" "media" "zones" "zones/settings" ]
    ++ [ "f /home/${s.user}/zones/settings/i3-placements 0600 ${s.user} users -"
         # the RED sandbox looks for xauth here (to give RED windows their own screen key)
         "L+ /usr/bin/xauth - - - - ${pkgs.xauth}/bin/xauth" ];
}
