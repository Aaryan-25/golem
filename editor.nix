# Golem add-on: the text editor (Super+E, or "edit" in Alt+Space). Neovim set up like
# Notepad, inside Cool Retro Term. Built on its own branch; see PLAN.md (Add-ons).
#
#   golem-edit [file]       opens it
#
# The pieces (all in editor/):
#   init.lua               typing, keys, autosave, the truthful SAVED line, start screen, guide
#   panels.lua             files panel, terminal panel, running code, live preview, code pictures, tidying
#   ai.lua                 the AI (Gemini now, your own later)
#   guide.txt              the guide shown with F1
#   extensions.nix / .lua  extensions (Neovim plugins): add names, then golem-rebuild
#   languages.nix          languages it can run: add names, then golem-rebuild
#   bin/                   helpers: golem-open, golem-run, golem-preview, golem-ai, golem-flow, golem-blocks
#   flow.lua / blocks.html the flowchart view (F9) and the block builder (F10)
#
# The look: Cool Retro Term's full CRT glass in Golem's colours (settings.nix), in the current
# face (Shadow / Negative, from the Control Panel) each time it opens. Ctrl+Shift+M inside it
# reaches Cool Retro Term's own settings and screen styles; your choices there are
# kept, and "Golem Shadow" / "Golem Negative" in its profiles list bring Golem's look back.
#
# Its zone: GREEN with internet (for the AI), sound and USB allowed. This is only its starting
# setting; after that the Control Panel decides, like for every app.
{ pkgs, lib, ... }:
let
  s = import ./settings.nix;
  sh = s.theme;
  ng = s.themeNegative;

  # Code colours: blue, teal, ember (cold, to match the void and pale light).
  hues = { shadow = "#8e9bc0 #9fc3c9 #c46a6a"; };

  # Kinds of text the editor opens when asked from elsewhere.
  textTypes = [ "text/plain" "text/markdown" "text/x-python" "text/x-shellscript" "text/x-lua"
    "text/html" "text/css" "text/javascript" "application/json" "text/x-csrc" "text/x-c++src"
    "application/x-shellscript" "text/x-java" ];

  plugins = map (n: pkgs.vimPlugins.${n}) (import ./editor/extensions.nix);
  languages = map (n: pkgs.${n}) (import ./editor/languages.nix);
  langNames = import ./editor/languages.nix;
  has = n: builtins.elem n langNames;

  # Each language brings its tidier (Ctrl+S / Alt+Shift+F).
  tidiers =
    lib.optional (has "python3") pkgs.ruff
    ++ lib.optional (has "bash") pkgs.shfmt
    ++ lib.optional (has "lua") pkgs.stylua
    ++ lib.optional (has "nodejs") pkgs.prettier
    ++ lib.optional (has "gcc") pkgs.clang-tools
    ++ lib.optional (has "go") pkgs.go
    ++ lib.optional (has "rustc") pkgs.rustfmt;

  nvim = pkgs.neovim.override {
    configure = {
      customLuaRC = "dofile('${./editor}/init.lua')";
      packages.golem.start = plugins;
    };
  };

  # The helpers, each with exactly what it needs.
  helper = name: interp: deps: pkgs.writeShellScriptBin name ''
    export PATH=${lib.makeBinPath deps}:$PATH
    exec ${interp} ${./editor/bin}/${name} "$@"
  '';
  golemOpen = helper "golem-open" "${pkgs.bash}/bin/bash"
    [ pkgs.coreutils pkgs.file pkgs.util-linux pkgs.imv pkgs.mpv pkgs.zathura golemOffice ];
  # Word and Excel inside the editor (python-docx, openpyxl): no Firefox, no Google, no internet.
  golemOffice = pkgs.writeShellScriptBin "golem-office" ''
    exec ${pkgs.python3.withPackages (p: [ p.python-docx p.openpyxl ])}/bin/python3 ${./editor/bin}/golem-office "$@"
  '';
  # golem-view: the small window for the live preview and the block builder; pages from this computer only.
  golemView = pkgs.writeShellScriptBin "golem-view" ''
    export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [ pkgs.gtk4 pkgs.webkitgtk_6_0 pkgs.glib.out pkgs.pango.out pkgs.gdk-pixbuf pkgs.graphene pkgs.harfbuzz pkgs.libsoup_3 pkgs.gobject-introspection ]}
    export PATH=${lib.makeBinPath [ pkgs.util-linux ]}:$PATH
    exec ${pkgs.python3.withPackages (p: [ p.pygobject3 ])}/bin/python3 ${./editor/bin}/golem-view "$@"
  '';
  golemRun = helper "golem-run" "${pkgs.bash}/bin/bash" [ pkgs.coreutils pkgs.gnugrep pkgs.bc ];
  golemAi = helper "golem-ai" "${pkgs.bash}/bin/bash" [ pkgs.coreutils pkgs.curl pkgs.jq ];
  golemPreview = pkgs.writeShellScriptBin "golem-preview" ''
    export PATH=${lib.makeBinPath [ golemView ]}:$PATH
    export GOLEM_VOID="${sh.void}" GOLEM_MIST="${sh.mist}" GOLEM_TEXT="${sh.text}" GOLEM_PALE="${sh.pale}"
    exec ${pkgs.python3.withPackages (p: [ p.markdown ])}/bin/python3 ${./editor/bin}/golem-preview "$@"
  '';

  # The gada's soft sounds, made from numbers at build time (no recordings).
  sounds = pkgs.runCommand "golem-edit-sounds" { } "${pkgs.python3}/bin/python3 ${./editor/sounds.py} $out";

  # Blockly (Google's snap-together blocks, Apache-2.0), fetched once when Golem is built;
  # only the parts the block builder uses are kept. Nothing is fetched while you work.
  blockly = pkgs.runCommand "blockly-13.5.0" {
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/blockly/-/blockly-13.5.0.tgz";
      hash = "sha256-nlQcsQ8P3KK54h7MXDJtY+/BKo4rjYpMB3R2Mi67UME=";
    };
  } ''
    mkdir -p $out/msg x
    tar -xzf $src -C x
    cp x/package/{blockly,blocks,python,javascript,lua}_compressed.js $out/
    cp x/package/msg/en.js $out/msg/
    cp -r x/package/media $out/media
    cp x/package/LICENSE $out/
  '';
  golemBlocks = pkgs.writeShellScriptBin "golem-blocks" ''
    export PATH=${lib.makeBinPath [ golemView ]}:$PATH
    export GOLEM_BLOCKLY=${blockly} GOLEM_BLOCKS_PAGE=${./editor/blocks.html}
    exec ${pkgs.python3}/bin/python3 ${./editor/bin}/golem-blocks "$@"
  '';
  golemWires = pkgs.writeShellScriptBin "golem-wires" ''
    export PATH=${lib.makeBinPath [ golemView ]}:$PATH
    export GOLEM_WIRES_PAGE=${./editor/wires.html}
    exec ${pkgs.python3}/bin/python3 ${./editor/bin}/golem-wires "$@"
  '';
  golemFlow = pkgs.writeShellScriptBin "golem-flow" ''
    exec ${pkgs.python3}/bin/python3 ${./editor/bin}/golem-flow "$@"
  '';

  # Neovim with everything the editor uses.
  inner = pkgs.writeShellScriptBin "golem-edit-nvim" ''
    export GOLEM_PALETTE="${sh.void} ${sh.shade} ${sh.mist} ${sh.text} ${sh.pale} ${hues.shadow}"
    export GOLEM_EDIT_EXTENSIONS=${./editor/extensions.lua}
    export GOLEM_EDIT_SOUNDS=${sounds}
    export GOLEM_NEGATIVE_VOID="${ng.void}"
    export PATH=${lib.makeBinPath ([ pkgs.ripgrep pkgs.xclip pkgs.util-linux pkgs.file pkgs.silicon
      pkgs.bash pkgs.alsa-utils golemOpen golemRun golemPreview golemAi golemBlocks golemWires golemFlow ] ++ tidiers)}:$PATH
    exec ${nvim}/bin/nvim "$@"
  '';

  # Cool Retro Term keeps its settings in a small database. The first time, Golem's look is
  # written in; after that your own choices stay. Two styles, "Golem Shadow" and "Golem
  # Negative", are always in its list (right-click > Profiles) to come back to.
  font = "System: DejaVu Sans Mono";
  profile = bg: fg: chroma: builtins.toJSON {
    backgroundColor = bg; fontColor = fg;
    flickering = 0.1; horizontalSync = 0.08; staticNoise = 0.12; chromaColor = chroma;
    saturationColor = 0; screenCurvature = 0.3; glowingLine = 0.2; burnIn = 0.25; bloom = 0.55;
    rasterization = 0; jitter = 0.2; rbgShift = 0; brightness = 0.5; contrast = 0.8;
    ambientLight = 0.2; windowOpacity = 1; fontName = font; fontWidth = 1; margin = 0.5;
    blinkingCursor = false; frameMargin = 0.5;
  };
  firstSettings = builtins.toJSON {
    fps = 20; windowScaling = 1; showTerminalSize = false; fontScaling = 1;
    fontNames = [ font font font ]; showMenubar = false; bloomQuality = 0.5; burnInQuality = 0.5;
    useCustomCommand = false; customCommand = "";
  };

  edit = pkgs.writeShellApplication {
    name = "golem-edit";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.sqlite pkgs.jq pkgs.cool-retro-term inner ];
    text = ''
      shadow='${profile sh.void sh.pale 0.7}'
      negative='${profile ng.void ng.pale 0.25}'
      # the current face, as set in the Control Panel
      if grep -q '^face=negative' /var/lib/golem/settings.conf 2>/dev/null; then want=$negative; else want=$shadow; fi

      dir="''${XDG_DATA_HOME:-$HOME/.local/share}/cool-retro-term/golem-edit/QML/OfflineStorage/Databases"
      db="$dir/27e743fe85b8912a46804fed99e8a9ab"      # Qt's file name for this database
      mkdir -p "$dir"
      [ -f "$db.ini" ] || printf '%s\n' '[General]' 'Description=StorageDatabase' 'Driver=QSQLITE' \
        'EstimatedSize=100000' 'Name=coolretroterm1' 'Version=1.0' > "$db.ini"
      sqlite3 "$db.sqlite" "CREATE TABLE IF NOT EXISTS settings(setting TEXT UNIQUE, value TEXT);"
      get() { sqlite3 "$db.sqlite" "SELECT value FROM settings WHERE setting = '$1';"; }
      put() { v=$(printf '%s' "$2" | sed "s/'/'''/g"); sqlite3 "$db.sqlite" "INSERT OR REPLACE INTO settings VALUES ('$1', '$v');"; }

      # first time: Golem's look
      [ -n "$(get _CURRENT_SETTINGS)" ] || put _CURRENT_SETTINGS '${firstSettings}'
      cur=$(get _CURRENT_PROFILE)
      if [ -z "$cur" ]; then
        put _CURRENT_PROFILE "$want"
      else
        # still in Golem's colours? then follow the face; any other style stays as you chose it
        colours=$(jq -c '[.backgroundColor, .fontColor]' <<<"$cur" 2>/dev/null || echo)
        for p in "$shadow" "$negative"; do
          if [ "$colours" = "$(jq -c '[.backgroundColor, .fontColor]' <<<"$p")" ]; then
            put _CURRENT_PROFILE "$(jq -c --argjson w "$want" '.backgroundColor = $w.backgroundColor
              | .fontColor = $w.fontColor | .chromaColor = $w.chromaColor' <<<"$cur")"
          fi
        done
      fi
      # Golem's two styles in the profiles list
      custom=$(get _CUSTOM_PROFILES); [ -n "$custom" ] || custom='[]'
      custom=$(jq -c --arg s "$shadow" --arg n "$negative" '
        (if type == "array" then . else [] end)
        | map(select(.text != "Golem" and .text != "Golem Shadow" and .text != "Golem Negative"))
        + [{text: "Golem Shadow", obj_string: $s, builtin: false},
           {text: "Golem Negative", obj_string: $n, builtin: false}]' <<<"$custom" 2>/dev/null) \
        || custom='[]'
      put _CUSTOM_PROFILES "$custom"

      # Named golem-edit, so the window, Alt+Tab and remembered workspaces call it golem-edit
      # (and its settings stay apart from any other Cool Retro Term).
      exec -a golem-edit cool-retro-term --workdir "$PWD" -T EDITOR -e golem-edit-nvim "$@"
    '';
  };
in {
  environment.systemPackages = [ edit golemOpen golemRun golemPreview golemOffice golemView golemWires ] ++ languages ++ [
    # so Alt+Space finds it as "Text editor" (or "edit")
    (pkgs.makeDesktopItem { name = "golem-edit"; desktopName = "Text editor (edit)"; exec = "golem-edit"; })
    # so text files opened from anywhere (a link, another app) open in it, through its zone
    (pkgs.makeDesktopItem {
      name = "golem-edit-open"; desktopName = "Text editor"; exec = "golem-launch golem-edit %f";
      noDisplay = true; mimeTypes = textTypes;
    })
  ];

  xdg.mime.defaultApplications = lib.genAttrs textTypes (_: "golem-edit-open.desktop");

  # A small font that joins Devanagari letters properly (for F6's preview of Hindi / Sanskrit text).
  fonts.packages = [ pkgs.lohit-fonts.devanagari ];

  # Its starting zone (only if it has none yet; after that the Control Panel decides).
  system.activationScripts.golem-edit-zone = {
    deps = [ "golem-settings" ];
    text = ''
      f=/var/lib/golem/apps/golem-edit.conf
      [ -e "$f" ] || printf '%s\n' zone=green ram=${s.limits.green.memory} cpu=${s.limits.green.cpu} \
        internet=allowed camera=never usb=allowed sound=on folder= > "$f"
      chmod 644 "$f"
    '';
  };
}
