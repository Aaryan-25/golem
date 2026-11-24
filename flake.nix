# Golem: the whole system recipe.
{
  description = "Golem: private, clean, usable";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      golemRev = self.rev or "unknown";                 # which GitHub version this is
      modules = [ ./system/golem.nix ./system/update.nix ./system/truthful.nix ./zones/zones.nix ./realm/desktop.nix ./system/idle.nix ./truth/truth.nix ./panel/panel.nix ./settings/look.nix ./system/selftest.nix ./realm/sand.nix ./editor/editor.nix ./realm/realm.nix ./zones/gate.nix ./zones/browser.nix ./system/optimiser.nix ./echo/echo.nix ./keylight/keylight.nix ./system/nvidia.nix ];
      golem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit golemRev; };
        inherit modules;
      };
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      nixosConfigurations.golem = golem;
      packages.x86_64-linux = {
        system = golem.config.system.build.toplevel;          # checked on every change
        image  = golem.config.system.build.golemImage;        # the pendrive image
        default = self.packages.x86_64-linux.system;
      };
      checks.x86_64-linux.vm = import ./tests/tests.nix { inherit pkgs modules golemRev; };   # the virtual laptop test
    };
}
