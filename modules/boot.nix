{ config, lib, modulesPath, pkgs, ... }:

let
  cfg = config.hardware.redmi-pad-se;
  dt = config.hardware.deviceTree;
  rootImage = pkgs.callPackage "${modulesPath}/../lib/make-disk-image.nix" {
    inherit config pkgs;
    partitionTableType = "none";
    label = "NIXOS_XUN";
    baseName = "userdata";
    copyChannel = false;
  };
  inherit (pkgs.callPackage ../pkgs/sources.nix { }) tapas;
  macBytes = mac: lib.splitString ":" mac;
  wifiBytes = lib.concatStringsSep " " (macBytes cfg.wifiMac);
  bluetoothBytes = lib.concatStringsSep " " (lib.reverseList (macBytes cfg.bluetoothMac));
in
{
  config = lib.mkIf cfg.enable {
    boot = {
      loader.generic-extlinux-compatible.enable = true;
      kernelParams =
        if cfg.useFirmwareFramebuffer then
          [
            "regulator_ignore_unused"
            "fbcon=rotate:2"
          ]
        else
          [ "video=DSI-1:panel_orientation=upside_down" ];
    };

    hardware.deviceTree = {
      enable = true;
      name = "qcom/sm6225-xiaomi-xun.dtb";
      filter = "sm6225-xiaomi-xun.dtb";
      overlays = (lib.optional cfg.useFirmwareFramebuffer {
        name = "xun-firmware-display";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "xiaomi,xun";
          };

          &mdss {
            status = "disabled";
          };

          &dispcc {
            status = "disabled";
          };
        '';
      }) ++ (lib.optional (cfg.panelVariant != null) {
        name = "xun-panel-variant";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "xiaomi,xun";
          };

          &panel {
            compatible = "xiaomi,${cfg.panelVariant}";
          };
        '';
      }) ++ [
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
      deviceTree = "${dt.dtbSource}/${dt.name}";
    };

    system.build.xunSparseRootImage = pkgs.runCommand "xun-userdata-sparse" {
      nativeBuildInputs = [ pkgs.android-tools ];
    } ''
      mkdir -p "$out"
      img2simg ${rootImage}/userdata.img "$out/userdata.img"
    '';
  };
}
