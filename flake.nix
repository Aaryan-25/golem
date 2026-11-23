# Golem: the whole system recipe.
{
  description = "Golem: private, clean, usable";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      golemRev = self.rev or "unknown";                 # which GitHub version this is
      modules = [ ./golem.nix ./update.nix ./truthful.nix ./zones.nix ./desktop.nix ./idle.nix ./truth.nix ./panel.nix ./look.nix ./selftest.nix ./sand.nix ./editor.nix ./realm.nix ./gate.nix ./browser.nix ./optimiser.nix ./echo.nix ./keylight.nix ];
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
      checks.x86_64-linux.vm = import ./tests.nix { inherit pkgs modules golemRev; };   # the virtual laptop test
    };
}
