# golem-update: bring changes from GitHub onto the laptop without reinstalling.
# It always shows what changed and asks first. Every update is written to ~/golem-updates.txt.
# Part of Golem: the system (start, hardware, power, updates); MAP.md sections 4, 5.8, 5.9.
{ pkgs, golemRev, ... }:
let
  s = import ../settings/settings.nix;

  update = pkgs.writeShellApplication {
    name = "golem-update";
    runtimeInputs = with pkgs; [ git coreutils less util-linux ];
    text = ''
      repo="$HOME/golem"
      log="$HOME/golem-updates.txt"
      url="https://github.com/${s.githubRepo}.git"
      now=$(cat /etc/golem/version)
      say() { printf '\n%s\n' "$*"; }

      say "GOLEM UPDATE"
      echo "This Golem was built from version ''${now:0:7}"

      if [ ! -d "$repo/.git" ]; then
        say "Getting the recipe from GitHub into ~/golem ..."
        git clone -q "$url" "$repo" || { say "Could not reach GitHub. Is Wi-Fi on? (Super+W)"; exit 1; }
      else
        git -C "$repo" fetch -q origin main || { say "Could not reach GitHub. Is Wi-Fi on? (Super+W)"; exit 1; }
      fi

      if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        say "You changed these files in ~/golem:"
        git -C "$repo" status --short
        say "Golem will not overwrite your changes. Move them aside, then run golem-update again."
        exit 1
      fi

      new=$(git -C "$repo" rev-parse origin/main)
      if [ "$now" = "$new" ]; then say "Already up to date. Nothing to do."; exit 0; fi

      say "WHAT CHANGED (newest first):"
      if git -C "$repo" cat-file -e "$now^{commit}" 2>/dev/null; then
        changes=$(git -C "$repo" log --format='  * %s  (%ar)' "$now..$new")
        echo "$changes"
        say "FILES CHANGED:"
        git -C "$repo" diff --stat "$now" "$new" | sed 's/^/  /'
        from=$now
      else
        changes=$(git -C "$repo" log --format='  * %s  (%ar)' -n 15 "$new")
        echo "$changes"
        from="$new~1"
      fi

      while true; do
        echo
        read -rp "Apply? y = yes, d = show every changed line, n = no: " a
        case "$a" in
          y|Y) break ;;
          d|D) git -C "$repo" diff --color=always "$from" "$new" | less -R ;;
          *) say "Stopped. Nothing changed."; exit 0 ;;
        esac
      done

      git -C "$repo" merge -q --ff-only origin/main
      say "Building the new version. This can take a while. Nothing changes until it finishes."
      if nixos-rebuild switch --flake "$repo#$(cat /etc/golem/config-name)" --sudo; then
        { echo "$(date '+%F %R')  ''${now:0:7} -> ''${new:0:7}"; echo "$changes"; echo; } >> "$log"
        logger -t golem "Golem updated from version ''${now:0:7} to ''${new:0:7}"
        say "Done. Golem is now version ''${new:0:7}."
        if [ -s ~/.config/golem-report/token ]; then (golem-report --quiet "after the update to ''${new:0:7}" &); fi
        echo "The old version stays in the boot menu, in case you need it."
        echo "Every update is listed in ~/golem-updates.txt"
        echo "Some changes (like a new kernel) show only after a restart."
      else
        say "The update failed. You are still on the old version."
        exit 1
      fi
    '';
  };
in {
  environment.etc."golem/version".text = golemRev;
  environment.systemPackages = [ update ];
  boot.loader.grub.configurationLimit = 5;    # save slots: the last 5 versions stay in the boot menu
}
