# The shadow realm: Golem's own rune letters, and the sand that draws everything outside apps
# (the Start panel, the idle screen). See realm.py and runes.py.
{ pkgs, ... }:
let
  # Golem Runes: made here from runes.py (straight cuts on a grid). Nothing is downloaded.
  runes = pkgs.runCommand "golem-runes" { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ]; } ''
    mkdir -p $out/share/fonts/truetype
    python3 ${./runes.py} $out/share/fonts/truetype/GolemRunes.ttf
  '';
  py = pkgs.python3.withPackages (p: [ p.moderngl p.glfw p.numpy p.pillow p.i3ipc ]);
  realm = pkgs.writeShellApplication {
    name = "golem-realm";
    runtimeInputs = with pkgs; [ util-linux i3 ];
    text = ''
      export GOLEM_RUNES=${runes}/share/fonts/truetype/GolemRunes.ttf
      exec ${py}/bin/python3 ${./realm.py} "$@"
    '';
  };
in {
  fonts.packages = [ runes ];
  environment.systemPackages = [ realm ];
  hardware.graphics.enable = true;
}
