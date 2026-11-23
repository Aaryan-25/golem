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
  # Echo's hands: outside the zone, asks me before any extension runs (echo/hands.py). Started with i3.
  hands = pkgs.writeShellApplication {
    name = "golem-echo-hands";
    runtimeInputs = with pkgs; [ util-linux coreutils ];
    text = "exec ${pkgs.python3}/bin/python3 ${./echo}/hands.py";
  };
  # The trainer (echo/train.py), on the NVIDIA card. Its tools (PyTorch and friends, about 4 GB) and the brains in
  # training form (about 3 GB) are not in the image: golem-echo-trainer fetches them once, through the Gate.
  trainEnv = ''
    export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ]}:/run/opengl-driver/lib
    export GOLEM_LLAMA_SRC=${pkgs.llama-cpp.src}
    export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 PYTHONUNBUFFERED=1
  '';
  train = pkgs.writeShellApplication {        # runs in its zone: OFFLINE, its folder is Echo's, NVIDIA allowed
    name = "golem-echo-train";
    runtimeInputs = with pkgs; [ util-linux coreutils ];
    text = ''
      ${trainEnv}
      h="$HOME"; [ -d "$HOME/zones/golem-echo/echo" ] && h="$HOME/zones/golem-echo"
      py="$h/echo/trainer/venv/bin/python3"
      [ -x "$py" ] || py=${pkgs.python3}/bin/python3
      exec "$py" ${./echo}/train.py "$h/echo" "$1"
    '';
  };
  trainer = pkgs.writeShellApplication {
    name = "golem-echo-trainer";
    runtimeInputs = with pkgs; [ coreutils curl util-linux ];
    text = ''
      ${trainEnv}
      export HF_HUB_OFFLINE=0 TRANSFORMERS_OFFLINE=0
      d="$HOME/zones/golem-echo/echo/trainer"
      if [ "''${1:-}" = check ]; then
        if [ -x "$d/venv/bin/python3" ] && [ -d "$d/base-3B" ]; then echo "The trainer is ready."; exit 0; fi
        echo "The trainer isn't set up yet."; exit 1
      fi
      if ! [ -e /proc/driver/nvidia/version ]; then
        echo "This computer has no NVIDIA card that Golem can use, so Echo can't train here."; exit 1
      fi
      echo "This fetches about 7 GB, once: PyTorch (for the NVIDIA card) and Echo's brain in training form."
      echo "The Gate will ask about a few sites (pypi.org, files.pythonhosted.org, download.pytorch.org,"
      echo "huggingface.co and where it sends files from). Say yes to them."
      mkdir -p "$d"
      [ -x "$d/venv/bin/python3" ] || ${pkgs.python3}/bin/python3 -m venv "$d/venv"
      pip() { "$d/venv/bin/python3" -m pip install --disable-pip-version-check -q "$@"; }
      pip torch --index-url https://download.pytorch.org/whl/cu126
      pip transformers peft bitsandbytes accelerate safetensors sentencepiece numpy huggingface_hub
      get() {   # a brain in training form, from Hugging Face
        [ -s "$d/base-$1/config.json" ] && [ -n "$(ls "$d/base-$1"/*.safetensors 2>/dev/null)" ] && return 0
        "$d/venv/bin/python3" -c "import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1], local_dir=sys.argv[2], allow_patterns=['*.json', '*.safetensors'])" "$2" "$d/base-$1"
      }
      get 3B unsloth/Llama-3.2-3B-Instruct-bnb-4bit
      get 1B unsloth/Llama-3.2-1B-Instruct-bnb-4bit
      # If the 3B doesn't fit on the card, the Echo talks with the 1B brain and its voice, so fetch that too.
      b="$HOME/zones/golem-echo/echo/brain"; mkdir -p "$b"
      if ! [ -s "$b/Llama-3.2-1B-Instruct-Q4_K_M.gguf" ]; then
        curl -fL --retry 3 -C - -o "$b/Llama-3.2-1B-Instruct-Q4_K_M.gguf.part" \
          https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf
        mv "$b/Llama-3.2-1B-Instruct-Q4_K_M.gguf.part" "$b/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
      fi
      "$d/venv/bin/python3" -c "import torch; print('PyTorch sees the NVIDIA card:', torch.cuda.is_available())"
      logger -t golem "Echo: the trainer is ready"
      echo "Done. In ECHO > FEEDING, press Ctrl+T to train an Echo."
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
      for f in "$d"/*.gguf; do   # one brain at a time (and the 1B the trainer may need)
        case "$(basename "$f")" in "$model") ;; Llama-3.2-1B-*) [ -d "$d/../trainer" ] || rm -f "$f" ;; *) rm -f "$f" ;; esac
      done
      logger -t golem "Echo: got its brain ($model) and its ears ($ears)"
      echo "Done. Open ECHO from the Start panel."
    '';
  };
in {
  environment.systemPackages = [ echo brain hands train trainer ];
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
      # The trainer: OFFLINE, Echo's folder, the NVIDIA card allowed, most of the memory and processor.
      f=/var/lib/golem/apps/golem-echo-train.conf
      [ -e "$f" ] || printf '%s\n' zone=offline ram=6G cpu=800% internet=never camera=never usb=never sound=off \
        nvidia=allowed folder=~/zones/golem-echo > "$f"
      chmod 644 "$f"
    '';
  };
}
