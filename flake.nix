{
  description = "NixOS hardware support for the Redmi Pad SE (xun)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    xun = {
      url = "github:xushengfeng/redmi_pad_se_xun_linux/f25fba528aa352b3706bba363c5b05444e03ebe8";
      flake = false;
    };
    tapas = {
      url = "github:Sype0/pmos-tapas/5dee84cc5d7939a1042cf9daf2a21e67ab5c3579";
      flake = false;
    };
    audioreach = {
      url = "github:linux-msm/audioreach-topology/d6bb205aca5f4b8fa6b2f44cf8b5f6a081cbf037";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    {
      packages = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        system: {
          xun-firmware = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/xun-firmware.nix { };
        }
      );
      nixosModules.redmi-pad-se = import ./modules { inherit inputs; };
      nixosConfigurations.xun = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.redmi-pad-se
          ./examples/xun.nix
        ];
      };
    };
}
