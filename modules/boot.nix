{ config, lib, modulesPath, pkgs, ... }:

let
  cfg = config.hardware.redmi-pad-se;
  dt = config.hardware.deviceTree;
  xunLinuxDtbs = pkgs.runCommand "xun-linux-dtbs" { nativeBuildInputs = [ pkgs.dtc ]; } ''
    install -Dm644 "${dt.kernelPackage}/dtbs/${dt.name}" "$out/${dt.name}"
    rtc=$(fdtget -t s "$out/${dt.name}" /__symbols__ pm6125_rtc)
    # The PMIC arbiter grants Linux read access to the RTC registers.
    fdtput -d "$out/${dt.name}" "$rtc" allow-set-time
    fdtput -r "$out/${dt.name}" /vibrator
  '';
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
        # Keep firmware-enabled regulator supplies on during boot.
        [ "regulator_ignore_unused" ]
        ++ (
          if cfg.useFirmwareFramebuffer then
            [ "fbcon=rotate:2" ]
          else
            [ "video=DSI-1:panel_orientation=upside_down" ]
        );
    };

    hardware.deviceTree = {
      enable = true;
      name = "qcom/sm6225-xiaomi-xun.dtb";
      filter = "sm6225-xiaomi-xun.dtb";
      dtbSource = lib.mkDefault xunLinuxDtbs;
      overlays = [
        {
          name = if cfg.useFirmwareFramebuffer then "xun-firmware-display" else "xun-native-display";
          dtsText = ''
            /dts-v1/;
            /plugin/;

            / {
              compatible = "xiaomi,xun";
            };

            ${if cfg.useFirmwareFramebuffer then ''
              &mdss {
                status = "disabled";
              };

              &dispcc {
                status = "disabled";
              };
            '' else ''
              &framebuffer0 {
                status = "disabled";
              };
            ''}
          '';
        }
      ] ++ (lib.optional (cfg.panelVariant != null) {
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
      }) ++ (lib.optional (cfg.touchscreenVariant == "novatek-nt36532") {
        name = "xun-novatek-touchscreen";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "xiaomi,xun";
          };

          &{/soc@0/geniqup@4ac0000/spi@4a80000/touchscreen@0} {
            compatible = "novatek,nt36532-xun";
            firmware-name = "novatek/nt36532-xun.bin";
            interrupts = <80 1>; /* IRQ_TYPE_EDGE_RISING */
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
