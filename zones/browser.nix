# golem-browser: Golem's only browser (browser.py). It starts in YELLOW, reaches the internet only
# through the Gate (which asks about each new site), keeps nothing after closing, runs no JavaScript
# unless I turn it on for a site (Ctrl+J), and opens no pop-ups. Super+B, or a link from the editor.
{ pkgs, lib, ... }:
let
  s = import ../settings/settings.nix;
  browser = pkgs.writeShellScriptBin "golem-browser" ''
    export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [ pkgs.gtk4 pkgs.webkitgtk_6_0 pkgs.glib.out pkgs.pango.out pkgs.gdk-pixbuf pkgs.graphene pkgs.harfbuzz pkgs.libsoup_3 pkgs.gobject-introspection ]}
    export PATH=${lib.makeBinPath [ pkgs.util-linux ]}:$PATH
    # The zone (firejail) is the browser's sandbox; WebKit's own sandbox can't start inside it.
    export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
    exec ${pkgs.python3.withPackages (p: [ p.pygobject3 ])}/bin/python3 ${./browser.py} "$@"
  '';
in {
  environment.systemPackages = [ browser ];
  # Its starting zone (only if it has none yet; after that the Control Panel decides).
  system.activationScripts.golem-browser-zone = {
    deps = [ "golem-settings" ];
    text = ''
      f=/var/lib/golem/apps/golem-browser.conf
      ${s.bigger}
      [ -e "$f" ] || printf '%s\n' zone=yellow ram=$(bigger ${s.limits.yellow.memory}) cpu=$(bigger ${s.limits.yellow.cpu}) \
        internet=allowed camera=never usb=never sound=on folder= > "$f"
      chmod 644 "$f"
    '';
  };
}
