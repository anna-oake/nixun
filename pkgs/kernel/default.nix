{ pkgs, xun, tapas }:
let
  inherit (pkgs) fetchurl;
  version = "7.2.1";
  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
    hash = "sha256-QVgJjIoo6o++BoyFXTqmNB4D0GKCrdPLkEnzok5FV7M=";
  };
  socPatches = pkgs.callPackage ./sm6225-patches.nix { };
  boardPatches = map (name: {
    inherit name;
    patch = "${xun}/build/patches/${name}.patch";
  }) [
    "bq2589x-id"
    "bq2589x-quickcharge"
    "hi556-dt"
    "msm-poweroff-scm"
    "qca-no-ibs"
    "qcom-pon-poweroff"
    "wusb3801-typec-psy"
  ];
in
pkgs.buildLinux {
  inherit (pkgs.llvmPackages) stdenv;
  inherit src version;
  pname = "linux-xun";
  kernelPatches = socPatches ++ [
    {
      name = "xun-board-files";
      patch = pkgs.callPackage ./board-files.patch.nix { inherit src xun tapas; };
    }
    {
      name = "xun-board-integration";
      patch = ./board-integration.patch;
    }
  ] ++ boardPatches;
  modDirVersion = "${version}-xun";
  defconfig = "xun_defconfig";
  enableCommonConfig = false;
  autoModules = false;
  extraMeta.platforms = [ "aarch64-linux" ];
}
