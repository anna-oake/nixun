{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.redmi-pad-se;
  inherit (pkgs.callPackage ../pkgs/sources.nix { }) xun tapas audioreach ath10k;
  kernel = import ../pkgs/kernel { inherit pkgs xun tapas; };
  topology = pkgs.callPackage ../pkgs/audioreach-firmware { inherit xun audioreach; };
  firmware = pkgs.callPackage ../pkgs/xun-firmware { inherit ath10k; };
  dspDir = "qcom/sm6225/xiaomi/xun";
  macType = lib.types.strMatching "[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}";
  # Use distinct, locally administered addresses if factory values are unavailable.
  defaultMac = suffix:
    let
      hash = builtins.hashString "sha256" "xun:${config.networking.hostName}:${suffix}";
      octets = map (offset: builtins.substring offset 2 hash) [ 0 2 4 6 8 ];
    in
    lib.concatStringsSep ":" ([ "02" ] ++ octets);
in
{
  imports = [ ./boot.nix ];

  options.hardware.redmi-pad-se = {
    enable = lib.mkEnableOption "hardware support for the 11-inch Redmi Pad SE (xun)";
    useFirmwareFramebuffer = lib.mkEnableOption "the firmware framebuffer in place of native display modesetting";
    panelVariant = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "m84-35-03-0b"
        "m84-36-02-0a"
        "m84-42-03-0c"
      ]);
      default = null;
      description = "Override the panel variant selected by the board device tree.";
    };
    wifiMac = lib.mkOption {
      type = macType;
      default = defaultMac "wifi";
      defaultText = lib.literalExpression "a locally administered address derived from networking.hostName";
      description = "Tablet's Wi-Fi MAC address in conventional byte order.";
    };
    bluetoothMac = lib.mkOption {
      type = macType;
      default = defaultMac "bluetooth";
      defaultText = lib.literalExpression "a locally administered address derived from networking.hostName";
      description = "Tablet's Bluetooth address in conventional byte order.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelPackages = pkgs.linuxPackagesFor kernel;
      kernelParams = [
        "console=tty0"
        "consoleblank=0"
        "clk_ignore_unused"
        "pd_ignore_unused"
        "fw_devlink=off"
        "deferred_probe_timeout=120"
      ];
      loader.grub.enable = lib.mkDefault false;
      initrd = {
        includeDefaultModules = lib.mkDefault false;
        systemd.tpm2.enable = lib.mkDefault false;
        extraFirmwarePaths = firmware.initrdFirmwarePaths ++ [
          "qcom/sm4250/SM6225-Xun-tplg.bin"
        ];
      };
    };

    hardware = {
      firmware = [ firmware topology ];
      wirelessRegulatoryDatabase = lib.mkDefault true;
      graphics.enable = lib.mkDefault true;
      bluetooth.enable = lib.mkDefault true;
    };

    environment.sessionVariables.ALSA_CONFIG_UCM2 =
      "${pkgs.alsa-ucm-conf.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          cp -r ${xun}/build/ucm2/. ucm2/
        '';
      })}/share/alsa/ucm2";

    services.udev.extraRules = ''
      SUBSYSTEM=="remoteproc", ATTR{firmware}=="${dspDir}/modem.mdt", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xun-modem@.service"
    '';

    systemd.packages = [ pkgs.tqftpserv ];
    systemd.services = {
      xun-rmtfs = {
        description = "Read-only EFS service for the Qualcomm modem DSP";
        serviceConfig = {
          ExecStart = "${pkgs.rmtfs}/bin/rmtfs -r -P";
          Restart = "on-failure";
        };
      };
      "xun-modem@" = {
        description = "Start the Qualcomm modem DSP for Wi-Fi";
        bindsTo = [ "%i.device" ];
        scriptArgs = "%f";
        wants = [ "tqftpserv.service" "xun-rmtfs.service" ];
        after = [ "%i.device" "tqftpserv.service" "xun-rmtfs.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Give the QRTR services time to register before starting the modem.
          sleep 2
          if [ "$(cat "$1/state")" = offline ]; then
            echo start > "$1/state"
          fi

          # As in the upstream bring-up, reprobe ath10k after WLAN QMI starts.
          sleep 5
          driver=/sys/bus/platform/drivers/ath10k_snoc
          wifi=c800000.wifi
          if [ -d "$driver" ]; then
            if [ -e "$driver/$wifi" ]; then
              echo "$wifi" > "$driver/unbind"
            fi
            echo "$wifi" > "$driver/bind"
          fi
        '';
      };
    };
  };
}
