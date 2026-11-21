# Golem: the whole system recipe.
{
  description = "Golem: private, clean, usable";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }:
    let
      golem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./golem.nix ];
      };
    in {
      nixosConfigurations.golem = golem;
      packages.x86_64-linux = {
        system = golem.config.system.build.toplevel;          # checked on every change
        image  = golem.config.system.build.golemImage;        # the pendrive image
        default = self.packages.x86_64-linux.system;
      };
    };
}
