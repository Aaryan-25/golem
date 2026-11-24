# The shadow realm: Golem's own rune letters, and the sand that draws everything outside apps
# (the Start panel, the idle screen). See realm.py and runes.py.
# Part of Golem: the shadow realm and the desktop; MAP.md section 5.5.
{ pkgs, ... }:
let
  # Golem Runes: Cambria's letter shapes (through Caladea, its free twin, Apache 2.0), carved as ancient stone
  # by runes.py at build time: chipped, cracked, pitted, every curve cut into facets. Nothing is downloaded.
  runes = pkgs.runCommand "golem-runes" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools p.pillow p.numpy ])) pkgs.potrace ];
  } ''
    mkdir -p $out/share/fonts/truetype
    python3 ${./runes.py} ${pkgs.caladea}/share/fonts/truetype/Caladea-Bold.ttf $out/share/fonts/truetype/GolemRunes.ttf
  '';
  py = pkgs.python3.withPackages (p: [ p.moderngl p.glfw p.numpy p.pillow p.i3ipc ]);
  realm = pkgs.writeShellApplication {
    name = "golem-realm";
    runtimeInputs = with pkgs; [ util-linux i3 ];
    text = ''
      export GOLEM_RUNES=${runes}/share/fonts/truetype/GolemRunes.ttf
      if [ "''${1:-}" = --daemon ]; then
        # If the realm ever stops, say why in the truth log (the desktop keeps working without it).
        err="''${XDG_RUNTIME_DIR:-/tmp}/golem-realm.err"
        if ! ${py}/bin/python3 ${./realm.py} --daemon 2>"$err"; then
          logger -t golem "The realm stopped: $(tail -n 4 "$err" | tr '\n' ' ')"
        fi
        exit 0
      fi
      exec ${py}/bin/python3 ${./realm.py} "$@"
    '';
  };
in {
  fonts.packages = [ runes ];
  environment.variables.GOLEM_RUNES = "${runes}/share/fonts/truetype/GolemRunes.ttf";   # for the Control Panel's sand
  environment.systemPackages = [ realm ];
  hardware.graphics.enable = true;
}
