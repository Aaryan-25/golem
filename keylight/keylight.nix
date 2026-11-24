# golem-keylight: the keyboard's lights (keylight/keylight.py). The Dell has white light (brightness only); the
# Asus TUF FX506LH has one colour for the whole keyboard (an experiment: patterns are kept per key anyway).
# Echo can use it only through an extension I add: `golem-keylight extension` puts one in place.
# Part of Golem: the keyboard's lights; MAP.md section 5.9.
{ pkgs, ... }:
let
  # This folder's code, as one piece (everything here except this file, which only describes how to build it).
  here = builtins.path { name = "keylight"; path = ./.; filter = path: _: baseNameOf path != "keylight.nix"; };
  keylight = pkgs.writeShellApplication {
    name = "golem-keylight";
    runtimeInputs = with pkgs; [ util-linux coreutils ];
    text = ''
      if [ "''${1:-}" = extension ]; then
        x="$HOME/.local/share/golem-echo/extensions/keylight"
        mkdir -p "$x"
        echo '{"does": "lights the keyboard: give it a colour (red, #ff8800, off) or KEY COLOUR", "needs": ["keyboard light"], "zone": "green"}' > "$x/extension.json"
        # shellcheck disable=SC2016  # these lines are the extension's own script, written as they are
        printf '%s\n' '#!/bin/sh' 'read -r a b' 'if [ -n "$b" ]; then exec golem-keylight key "$a" "$b"; else exec golem-keylight all "$a"; fi' > "$x/keylight"
        chmod +x "$x/keylight"
        echo "Echo can now ask to use the keyboard light (you will be asked the first time)."
        exit 0
      fi
      exec ${pkgs.python3}/bin/python3 ${here}/keylight.py "$@"
    '';
  };
in {
  environment.systemPackages = [ keylight ];
  # My user (in the video group) may change the keyboard light; nothing else about the keyboard.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*kbd_backlight*", RUN+="${pkgs.bash}/bin/sh -c 'cd /sys%p && for f in brightness kbd_rgb_mode multi_intensity; do [ -e $$f ] && ${pkgs.coreutils}/bin/chgrp video $$f && ${pkgs.coreutils}/bin/chmod g+w $$f; done; true'"
  '';
}
