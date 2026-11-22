# golem-sand: the sand test (drift, yin-yang, picture to picture), drawn by the graphics chip.
# It checks whether this laptop can carry Golem's look, before the look is built on it.
{ pkgs, ... }:
let
  py = pkgs.python3.withPackages (p: [ p.moderngl p.glfw p.numpy p.pillow ]);
  sand = pkgs.writeShellApplication {
    name = "golem-sand";
    runtimeInputs = [ pkgs.util-linux ];   # logger, for the truth log
    text = ''exec ${py}/bin/python3 ${./sand.py} "$@"'';
  };
in {
  environment.systemPackages = [ sand ];
  hardware.graphics.enable = true;         # the Intel chip's drawing driver (Mesa)
}
