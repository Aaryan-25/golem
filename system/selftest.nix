# golem-selftest: one command that checks, on the real laptop, everything a machine can check by itself.
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ pkgs, ... }:
let
  selftest = pkgs.writeShellApplication {
    name = "golem-selftest";
    runtimeInputs = with pkgs; [ coreutils gnugrep procps util-linux systemd networkmanager alsa-utils iproute2 i3 ];
    text = builtins.readFile ./selftest.sh;
  };
in {
  environment.systemPackages = [ selftest ];
}
