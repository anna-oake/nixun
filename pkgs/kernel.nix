{ pkgs, xun, tapas }:
let
  inherit (pkgs) lib runCommand fetchurl python3;
  version = "7.2.1";
  rev = "f5a976a8334c7563137352eaafe8d49a2a3b8c6a";
  archive = fetchurl {
    url = "https://gitlab.nura.eco/sm6225-mainline/kernels/linux-v.${version}/-/archive/${rev}.tar.gz";
    sha512 = "f8b9677542b1d477401d0cb2c2f3586898fc8490ca084b113172cb44d2a78b9e67192b6b1d92033ad939fcf0c260fb23de011f6aea9684e4e3d95c313f700d1a";
  };
  finalSocPatch = fetchurl {
    url = "https://gitlab.nura.eco/sm6225-mainline/kernels/linux-v.${version}/-/commit/e127de2a6297931b1abce1fb5b13a415163c325e.patch";
    sha256 = "7ffa79ee72b17b11b81ae9f99a5737ecaf88fca075c1e9aaf10a406dd9cde477";
  };
  src = runCommand "linux-xun-${version}-source" { nativeBuildInputs = [ python3 ]; } ''
    mkdir -p "$out" board
    tar -xf ${archive} --strip-components=1 -C "$out"
    patch -d "$out" -p1 < ${finalSocPatch}
    cp ${xun}/build/kernel-dts/*.dts ${xun}/build/kernel-{audio,battery,panel,touch}/*.c board/
    cp -r ${xun}/build/patches board/
    # Reuse the board integration from the port. NixOS supplies the initrd.
    sed '/^# --- initramfs /,$d' ${xun}/pmaports/device/testing/linux-postmarketos-qcom-sm6225/prepare-kernel.sh > prepare-board
    sh prepare-board "$out" "$PWD/board" "$PWD"

    configs="$out/arch/arm64/configs"
    sh "$out/scripts/kconfig/merge_config.sh" -m -O "$configs" \
      ${tapas}/config/base.config ${tapas}/config/tapas.config \
      ${xun}/build/config/xun.config ${./nixos.config}
    mv "$configs/.config" "$configs/xun_defconfig"
  '';
in
pkgs.buildLinux {
  inherit (pkgs.llvmPackages) stdenv;
  inherit src version;
  pname = "linux-xun";
  modDirVersion = "${version}-xun";
  defconfig = "xun_defconfig";
  enableCommonConfig = false;
  autoModules = false;
  structuredExtraConfig = with lib.kernel; {
    MODULES = yes;
    BLK_DEV_INITRD = yes;
    RD_ZSTD = yes;
    DEVTMPFS = yes;
    EXT4_FS = yes;
    MMC_SDHCI_MSM = yes;
    TOUCHSCREEN_FT8203 = yes;
    DRM_PANEL_XIAOMI_M84_35_03_0B = yes;
    DRM_PANEL_XIAOMI_M84_36_02_0A = yes;
    DRM_PANEL_XIAOMI_M84_42_03_0C = yes;
    SH366101 = yes;
    TYPEC_WUSB3801 = yes;
    SND_SOC_FS1815 = yes;
  };
  extraMeta.platforms = [ "aarch64-linux" ];
}
