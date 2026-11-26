{ buildUBoot, fetchurl, xxd }:

let
  rev = "ff2cef41fcdc60ff8c91820e6da5da39fc933e7e";
in
(buildUBoot {
  version = "2026.07";
  src = fetchurl {
    url = "https://gitlab.nura.eco/sm6225-mainline/u-boot/-/archive/${rev}/u-boot-${rev}.tar.gz";
    hash = "sha256-jv7Su1odkcVa2aM1XtdUnQmW5Sz/1Pur7lJ76DHXbpI=";
  };

  # The shim supplies the xun control DTB at entry.
  defconfig = "xiaomi_spes_defconfig";
  buildFlags = [ "u-boot-nodtb.bin" ];
  filesToInstall = [ "u-boot-nodtb.bin" ];
  extraPatches = [
    ./extlinux-buttons.patch
    ./xun-abl-memory.patch
  ];
  extraConfig = ''
    CONFIG_CMD_SYSBOOT=y
    CONFIG_SYS_CBSIZE=2048
    CONFIG_BOOTDELAY=-2
    # CONFIG_AUTOBOOT_MENU_SHOW is not set
    # CONFIG_BOOT_RETRY is not set
    # CONFIG_ENV_IS_IN_FAT is not set
    CONFIG_ENV_IS_NOWHERE=y
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="${./xun.env}"
  '';
}).overrideAttrs (old: {
  nativeBuildInputs = old.nativeBuildInputs ++ [ xxd ];
})
