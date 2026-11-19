{
  description = "NixOS hardware support for the Redmi Pad SE (xun)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.redmi-pad-se = import ./modules;
      nixosConfigurations.xun = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.redmi-pad-se
          ./examples/xun.nix
        ];
      };
    };
}
