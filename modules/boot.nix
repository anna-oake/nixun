{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.redmi-pad-se;
  dt = config.hardware.deviceTree;
  inherit (pkgs.callPackage ../pkgs/sources.nix { }) tapas;
  macBytes = mac: lib.splitString ":" mac;
  wifiBytes = lib.concatStringsSep " " (macBytes cfg.wifiMac);
  bluetoothBytes = lib.concatStringsSep " " (lib.reverseList (macBytes cfg.bluetoothMac));
in
{
  config = lib.mkIf cfg.enable {
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.timeout = lib.mkDefault 5;

    hardware.deviceTree = {
      enable = true;
      name = "qcom/sm6225-xiaomi-xun.dtb";
      filter = "sm6225-xiaomi-xun.dtb";
      overlays = [
        {
          name = "xun-radio-addresses";
          dtsText = ''
            /dts-v1/;
            /plugin/;

            &wifi {
              local-mac-address = [${wifiBytes}];
            };

            &uart3 {
              bluetooth {
                local-bd-address = [${bluetoothBytes}];
              };
            };
          '';
        }
      ];
    };

    system.build.xunBootImage = pkgs.callPackage ../pkgs/boot-image {
      inherit tapas;
      uboot = pkgs.callPackage ../pkgs/uboot { };
      deviceTree = "${dt.package}/${dt.name}";
    };
  };
}
