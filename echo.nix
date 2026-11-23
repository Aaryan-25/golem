# Echo: my AIs (echo/echo.py). They run offline in the OFFLINE zone; the brain is llama.cpp with Llama 3.2
# (1B on the Dell, 3B on a computer with more memory), and voice notes become text with whisper.cpp.
# The brain is not part of the image (it is large): golem-echo-brain fetches it once, through the Gate.
{ pkgs, ... }:
let
  s = import ./settings.nix;
  py = pkgs.python3.withPackages (p: [ p.tkinter ]);
  echo = pkgs.writeShellApplication {
    name = "golem-echo";
    runtimeInputs = with pkgs; [ llama-cpp whisper-cpp ffmpeg-headless procps util-linux coreutils ];
    text = ''
      export GOLEM_THEMES='${builtins.toJSON { shadow = s.theme; }}'
      exec ${py}/bin/python3 ${./echo}/echo.py "$@"
    '';
  };
  # Run from a terminal, outside any zone, so it goes through the Gate (which asks about each site once).
  brain = pkgs.writeShellApplication {
    name = "golem-echo-brain";
    runtimeInputs = with pkgs; [ curl coreutils gawk util-linux ];
    text = ''
      d="$HOME/zones/golem-echo/echo/brain"
      mkdir -p "$d"
      mem=$(awk '/MemTotal/ {print int($2 / 1048576 + 0.5)}' /proc/meminfo)
      hf=https://huggingface.co
      if [ "''${1:-}" = big ] || [ "$mem" -ge 6 ]; then
        model=Llama-3.2-3B-Instruct-Q4_K_M.gguf; repo=bartowski/Llama-3.2-3B-Instruct-GGUF; ears=ggml-small.bin
      else
        model=Llama-3.2-1B-Instruct-Q4_K_M.gguf; repo=bartowski/Llama-3.2-1B-Instruct-GGUF; ears=ggml-base.bin
      fi
      echo "This computer has about $mem GB of memory, so Echo gets $model."
      echo "The Gate will ask about huggingface.co and the site it sends the file from. Say yes to both."
      get() {   # name url
        if [ -s "$d/$1" ]; then echo "Already here: $1"; return; fi
        curl -fL --retry 3 -C - -o "$d/$1.part" "$2"
        mv "$d/$1.part" "$d/$1"
      }
      get "$model" "$hf/$repo/resolve/main/$model"
      if [ "$(head -c 4 "$d/$model")" != GGUF ]; then
        rm -f "$d/$model"; echo "That download was not a brain. Nothing was kept; try again."; exit 1
      fi
      get "$ears" "$hf/ggerganov/whisper.cpp/resolve/main/$ears"
      for f in "$d"/*.gguf; do [ "$(basename "$f")" = "$model" ] || rm -f "$f"; done   # one brain at a time
      logger -t golem "Echo: got its brain ($model) and its ears ($ears)"
      echo "Done. Open ECHO from the Start panel."
    '';
  };
in {
  environment.systemPackages = [ echo brain ];
  # Its zone: OFFLINE (no internet at all). More memory and both cores, so replies come faster.
  system.activationScripts.golem-echo-zone = {
    deps = [ "golem-settings" ];
    text = ''
      f=/var/lib/golem/apps/golem-echo.conf
      if [ ! -e "$f" ]; then
        if [ "$(${pkgs.gawk}/bin/awk '/MemTotal/ {print int($2 / 1048576 + 0.5)}' /proc/meminfo)" -ge 6 ]; then
          ram=4G; cpu=400%; else ram=2G; cpu=200%; fi
        printf '%s\n' zone=offline ram=$ram cpu=$cpu internet=never camera=never usb=never sound=on folder= > "$f"
      fi
      chmod 644 "$f"
    '';
  };
}
