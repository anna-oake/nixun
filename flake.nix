{
  description = "NixOS hardware support for the Redmi Pad SE (xun)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    {
      packages = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        system: {
          xun-firmware = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/xun-firmware { };
        }
      );
      nixosModules.redmi-pad-se = import ./modules;
      nixosConfigurations.xun = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.redmi-pad-se
          ./examples/xun.nix
        ];
      };
    };
}
