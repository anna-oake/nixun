{ buildUBoot, fetchurl }:

let
  rev = "ff2cef41fcdc60ff8c91820e6da5da39fc933e7e";
in
(buildUBoot {
  version = "2026.07";
  src = fetchurl {
    url = "https://gitlab.nura.eco/sm6225-mainline/u-boot/-/archive/${rev}/u-boot-${rev}.tar.gz";
    hash = "sha256-jv7Su1odkcVa2aM1XtdUnQmW5Sz/1Pur7lJ76DHXbpI=";
  };
  # The xun control DTB comes from the Android boot image.
  defconfig = "xiaomi_spes_defconfig";
  filesToInstall = [ "u-boot-nodtb.bin" ];
  extraConfig = ''
    CONFIG_CMD_SYSBOOT=y
    # CONFIG_ENV_IS_IN_FAT is not set
    CONFIG_ENV_IS_NOWHERE=y
  '';
}).overrideAttrs (old: {
  buildFlags = [ "u-boot-nodtb.bin" ];
  postPatch = old.postPatch + ''
    substituteInPlace board/qualcomm/qcom-phone.env \
      --replace-fail 'preboot=scsi scan' 'preboot=' \
      --replace-fail 'bootcmd=run menucmd' 'bootcmd=run boot_nixos; run menucmd' \
      --replace-fail 'bootmenu_0=Boot=bootefi bootmgr; pause' 'bootmenu_0=Boot NixOS=run boot_nixos; pause' \
      --replace-fail 'button_cmd_0_name=Volume Down' 'button_cmd_0_name=Volume Up'
    cat >> board/qualcomm/qcom-phone.env <<'ENV'
boot_nixos=if mmc dev 0 && part number mmc 0 userdata rootpart; then sysboot mmc 0:$rootpart ext2 $scriptaddr /boot/extlinux/extlinux.conf; fi
ENV
  '';
})
