# Golem, step 5: my keys and my windows.
# Tiling (i3 underneath), no bars, no titles, no gaps, a 1 px line on the focused window.
# Focus moves by keys only; new windows don't take focus. Each app remembers its workspace.
# Apps opened from the launcher always go through `zone`.
{ pkgs, lib, ... }:
let
  s = import ./settings.nix;
  c = s.theme;
  term = "xterm -bg '${c.void}' -fg '${c.text}' -cr '${c.pale}' -fa 'DejaVu Sans Mono' -fs 11 -b 12";

  rasi = pkgs.writeText "golem.rasi" ''
    * { background-color: transparent; text-color: ${c.text}; font: "DejaVu Sans 12"; }
    window { background-color: ${c.void}; border: 1px; border-color: ${c.shade}; padding: 16px 18px;
             width: 440px; location: south west; anchor: south west; x-offset: 22px; y-offset: -22px; }
    mainbox  { children: [ inputbar, message, listview ]; spacing: 12px; }
    inputbar { children: [ prompt, entry ]; spacing: 14px; }
    prompt   { text-color: ${c.mist}; }
    entry    { text-color: ${c.pale}; placeholder: ""; }
    textbox  { text-color: ${c.mist}; }
    listview { lines: 8; fixed-height: false; scrollbar: false; spacing: 2px; }
    element  { padding: 5px 8px; text-color: ${c.mist}; }
    element selected { background-color: ${c.shade}; text-color: ${c.pale}; }
    element-text { text-color: inherit; highlight: bold; }
    element-icon { size: 0; }
  '';
  centre = "window { location: center; anchor: center; x-offset: 0; y-offset: 0; width: 360px; }";
  rofi = "rofi -theme ${rasi}";

  # ---- small helpers ----
  ask = pkgs.writeShellScriptBin "golem-ask" ''
    # golem-ask "QUESTION" choice1 choice2 ...   prints the chosen line (centred, keyboard only)
    q=$1; shift
    printf '%s\n' "$@" | ${pkgs.rofi}/bin/${rofi} -dmenu -i -no-custom -p "$q" \
      -theme-str '${centre} listview { lines: '"$#"'; }'
  '';

  launch = pkgs.writeShellApplication {
    name = "golem-launch";
    runtimeInputs = [ pkgs.rofi ask ];
    text = ''
      # Alt+Space: find an app by name (typos are fine). It always opens through its zone.
      if [ $# -eq 0 ]; then
        exec ${rofi} -show drun -matching fuzzy -drun-display-format '{name}' -p OPEN \
          -run-command 'golem-launch {cmd}'
      fi
      app=$(basename "$1")
      if [ ! -f "/var/lib/golem/apps/$app.conf" ]; then
        z=$(golem-ask "ZONE FOR $app (asked once)" red offline yellow green) || exit 0
        zone set "$app" "$z" >/dev/null
      fi
      exec zone "$@"
    '';
  };

  win = pkgs.writeShellApplication {
    name = "golem-win";
    runtimeInputs = with pkgs; [ i3 rofi xdotool xprop gnused gawk gnugrep coreutils util-linux ask ];
    text = ''
      PLACES="$HOME/zones/settings/placements.txt"      # app -> workspace
      INCL="$HOME/zones/settings/i3-placements"
      cls() { xprop -id "$(xdotool getactivewindow)" WM_CLASS 2>/dev/null | sed -n 's/.*", "\(.*\)"/\1/p'; }
      case "''${1:-}" in
        close)
          n=$(cls); n=''${n:-this window}
          if [ "$(golem-ask "CLOSE $n?" no yes)" = yes ]; then i3-msg -q kill; logger -t golem "WINDOW closed: $n"; fi ;;
        send)   # send the window to a workspace; its app opens there from now on
          n=$(cls); i3-msg -q "move container to workspace number $2"
          if [ -n "$n" ]; then
            mkdir -p "$(dirname "$PLACES")"; touch "$PLACES"
            { grep -v "^$n " "$PLACES" || true; echo "$n $2"; } > "$PLACES.tmp"; mv "$PLACES.tmp" "$PLACES"
            awk '{ printf "assign [class=\"^%s$\"] workspace number %s\n", $1, $2 }' "$PLACES" > "$INCL"
            i3-msg -q reload; logger -t golem "WINDOW $n now opens on workspace $2"
          fi ;;
        switch) exec ${rofi} -show window -window-format '{c}  {t}' -p SWITCH -theme-str '${centre}' ;;
        power)
          case "$(golem-ask POWER lock sleep restart "shut down" "log out" cancel)" in
            lock) golem-lock ;;
            sleep) systemctl suspend ;;
            restart) systemctl reboot ;;
            "shut down") systemctl poweroff ;;
            "log out") i3-msg -q exit ;;
          esac ;;
        logout) if [ "$(golem-ask "LOG OUT?" no yes)" = yes ]; then i3-msg -q exit; fi ;;
        keys) column -t -s '|' /var/lib/golem/keys.txt | ${rofi} -dmenu -i -p KEYS -no-custom \
                -theme-str 'window { location: center; anchor: center; x-offset: 0; y-offset: 0; width: 760px; } listview { lines: 20; }' >/dev/null || true ;;
      esac
    '';
  };

  sound = pkgs.writeShellApplication {
    name = "golem-sound";
    runtimeInputs = [ pkgs.wireplumber ];
    text = ''
      case "''${1:-}" in
        up)   wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
        down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        mic)  wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
      esac
    '';
  };

  # ---- my keys (the starting list): key | what it does | i3 command ----
  # My own list lives in /var/lib/golem/keys.conf and is changed in the Control Panel.
  keys = [
    [ "Alt+space"         "Open an app (asks its zone the first time)" "exec golem-launch" ]
    [ "Alt+Return"        "Terminal"                                   "exec ${term}" ]
    [ "Alt+Tab"           "Switch window (list of names)"              "exec golem-win switch" ]
    [ "Alt+q"             "Close window (asks first)"                  "exec golem-win close" ]
    [ "Alt+f"             "Fullscreen on/off"                          "fullscreen toggle" ]
    [ "Super+z"           "Control Panel"                              "exec golem-panel-start" ]
    [ "Super+h"           "Show this key list"                         "exec golem-win keys" ]
    [ "Super+Left"        "Focus left"                                 "focus left" ]
    [ "Super+Right"       "Focus right"                                "focus right" ]
    [ "Super+Up"          "Focus up"                                   "focus up" ]
    [ "Super+Down"        "Focus down"                                 "focus down" ]
    [ "Super+Shift+Left"  "Move window left"                           "move left" ]
    [ "Super+Shift+Right" "Move window right"                          "move right" ]
    [ "Super+Shift+Up"    "Move window up"                             "move up" ]
    [ "Super+Shift+Down"  "Move window down"                           "move down" ]
    [ "Super+equal"       "Make the window bigger"                     "resize grow width 10 px or 10 ppt; resize grow height 10 px or 10 ppt" ]
    [ "Super+minus"       "Make the window smaller"                    "resize shrink width 10 px or 10 ppt; resize shrink height 10 px or 10 ppt" ]
    [ "Super+F1"          "Next window opens beside"                   "split horizontal" ]
    [ "Super+F2"          "Next window opens below"                    "split vertical" ]
    [ "Super+F3"          "Turn the split around"                      "layout toggle split" ]
    [ "Super+1"           "Workspace 1"                                "workspace number 1" ]
    [ "Super+2"           "Workspace 2"                                "workspace number 2" ]
    [ "Super+3"           "Workspace 3"                                "workspace number 3" ]
    [ "Super+4"           "Workspace 4"                                "workspace number 4" ]
    [ "Super+Shift+1"     "Send window to 1 (its app opens there from now on)" "exec golem-win send 1" ]
    [ "Super+Shift+2"     "Send window to 2 (remembered)"              "exec golem-win send 2" ]
    [ "Super+Shift+3"     "Send window to 3 (remembered)"              "exec golem-win send 3" ]
    [ "Super+Shift+4"     "Send window to 4 (remembered)"              "exec golem-win send 4" ]
    [ "Super+l"           "Lock the screen"                            "exec golem-lock" ]
    [ "Super+Escape"      "Power: lock, sleep, restart, shut down, log out" "exec golem-win power" ]
    [ "Super+Shift+q"     "Log out (asks first)"                       "exec golem-win logout" ]
    [ "Super+t"           "Truth log: what the system did"             "exec ${term} -e golem-truth" ]
    [ "Super+n"           "Wi-Fi on/off"                               "exec golem-wifi" ]
    [ "Super+w"           "Choose a Wi-Fi network"                     "exec ${term} -e nmtui" ]
    [ "Super+r"           "Reload keys and windows"                    "restart" ]
    [ "XF86AudioRaiseVolume"  "Volume up"                              "exec golem-sound up" ]
    [ "XF86AudioLowerVolume"  "Volume down"                            "exec golem-sound down" ]
    [ "XF86AudioMute"         "Sound on/off"                           "exec golem-sound mute" ]
    [ "XF86AudioMicMute"      "Microphone on/off"                      "exec golem-sound mic" ]
    [ "XF86MonBrightnessUp"   "Brighter"                               "exec brightnessctl set +10%" ]
    [ "XF86MonBrightnessDown" "Dimmer"                                 "exec brightnessctl set 10%-" ]
  ];
  keyList = lib.concatMapStrings (k: "${builtins.elemAt k 0} | ${builtins.elemAt k 1} | ${builtins.elemAt k 2}\n") keys;

  i3config = pkgs.writeText "golem-i3" ''
    font pango:DejaVu Sans Mono 10
    default_border pixel 1
    default_floating_border pixel 1
    hide_edge_borders smart
    focus_follows_mouse no
    mouse_warping none
    focus_on_window_activation none
    focus_wrapping yes
    no_focus [all]
    client.focused          ${c.pale} ${c.void} ${c.text} ${c.pale} ${c.pale}
    client.focused_inactive ${c.void} ${c.void} ${c.mist} ${c.void} ${c.void}
    client.unfocused        ${c.void} ${c.void} ${c.mist} ${c.void} ${c.void}
    client.background       ${c.void}
    exec --no-startup-id xsetroot -solid "${c.void}"
    include ~/zones/settings/i3-placements
    # Login = lock screen; idle: dim at 4 min, lock at 5; lid: lock before sleep (lock.nix)
    exec --no-startup-id golem-lock --start
    exec --no-startup-id xset s 240 60
    exec --no-startup-id xss-lock -n /etc/golem/dim --transfer-sleep-lock -- golem-lock --auto
    include /var/lib/golem/keys.i3
    # Golem's own panel is the one window that takes focus when it opens (DECISIONS: panels do)
    for_window [class="(?i)^golem-panel$"] fullscreen enable, focus
  '';
in {
  services.xserver.windowManager.i3.configFile = lib.mkForce i3config;
  environment.etc."golem/keys.default".text = keyList;
  environment.systemPackages = [ ask launch win sound pkgs.rofi pkgs.brightnessctl pkgs.xdotool pkgs.xprop ];
  services.udev.packages = [ pkgs.brightnessctl ];   # brightness without admin rights
}
