# Golem: the whole system recipe.
{
  description = "Golem: private, clean, usable";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      golemRev = self.rev or "unknown";                 # which GitHub version this is
      # Every part of Golem. The same list makes the pendrive and the installed Golem.
      modules = [ ./system/install.nix ./system/remote.nix ./system/golem.nix ./system/update.nix ./system/truthful.nix ./zones/zones.nix ./realm/desktop.nix ./system/idle.nix ./truth/truth.nix ./panel/panel.nix ./settings/look.nix ./system/selftest.nix ./realm/sand.nix ./editor/editor.nix ./realm/realm.nix ./zones/gate.nix ./zones/browser.nix ./system/optimiser.nix ./echo/echo.nix ./keylight/keylight.nix ./system/nvidia.nix ];
      # Golem installed on a laptop's own disk (system/disk.nix says what differs). golem-install copies it.
      golemDisk = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit golemRev; diskSystem = null; };
        modules = modules ++ [ ./system/disk.nix ];
      };
      # Golem on the pendrive: carries the installed Golem inside it, ready for golem-install.
      golem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit golemRev; diskSystem = golemDisk.config.system.build.toplevel; };
        inherit modules;
      };
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      nixosConfigurations.golem = golem;
      nixosConfigurations.golem-disk = golemDisk;
      packages.x86_64-linux = {
        system = golem.config.system.build.toplevel;          # checked on every change
        image  = golem.config.system.build.golemImage;        # the pendrive image
        default = self.packages.x86_64-linux.system;
      };
      checks.x86_64-linux.vm = import ./tests/tests.nix { inherit pkgs modules golemRev; };   # the virtual laptop test
    };
}
