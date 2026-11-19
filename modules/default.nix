{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.redmi-pad-se;
  inherit (pkgs.callPackage ../pkgs/sources.nix { }) xun tapas audioreach;
  kernel = import ../pkgs/kernel { inherit pkgs xun tapas; };
  topology = pkgs.callPackage ../pkgs/audioreach-firmware { inherit xun audioreach; };
  firmware = pkgs.callPackage ../pkgs/xun-firmware { };
  tqftpserv = pkgs.tqftpserv.overrideAttrs (_: {
    postPatch = ''
      substituteInPlace translate.c --replace-fail '/lib/firmware/' '${firmware}/lib/firmware/'
    '';
  });
  dspDir = "qcom/sm6225/xiaomi/xun";
  earlyFirmware = [
    "qcom/a630_sqe.fw"
    "qcom/a610_zap.mdt"
    "qcom/a610_zap.b00"
    "qcom/a610_zap.b01"
    "qcom/a610_zap.b02"
    "focaltech_ts_fw_huaxing_ft8203.bin"
    "focaltech_ts_fw_boe_ft8203.bin"
    "qca/crbtfw13.tlv"
    "qca/crnv13.bin"
    "${dspDir}/adsp.mdt"
  ] ++ map (n: "${dspDir}/adsp.b${lib.fixedWidthNumber 2 n}") (lib.remove 11 (lib.range 0 35));
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
  options.hardware.redmi-pad-se = {
    enable = lib.mkEnableOption "hardware support for the 11-inch Redmi Pad SE (xun)";
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
    assertions = [{
      assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
      message = "hardware.redmi-pad-se requires aarch64-linux.";
    }];
    boot = {
      kernelPackages = pkgs.linuxPackagesFor kernel;
      kernelParams = [
        "console=tty0"
        "consoleblank=0"
        "clk_ignore_unused"
        "pd_ignore_unused"
        "fw_devlink=off"
        "deferred_probe_timeout=120"
        "video=DSI-1:panel_orientation=upside_down"
      ];
      loader.grub.enable = lib.mkDefault false;
      initrd = {
        includeDefaultModules = lib.mkDefault false;
        extraFirmwarePaths = [ "qcom/sm4250/SM6225-Xun-tplg.bin" ]
          ++ earlyFirmware;
      };
    };

    hardware = {
      firmware = [ firmware topology pkgs.linux-firmware ];
      graphics.enable = lib.mkDefault true;
      bluetooth.enable = lib.mkDefault true;
    };

    environment.sessionVariables.ALSA_CONFIG_UCM2 =
      "${pkgs.alsa-ucm-conf.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          cp -r ${xun}/build/ucm2/. ucm2/
        '';
      })}/share/alsa/ucm2";

    environment.etc."environment.d/70-xun-alsa.conf".text = ''
      ALSA_CONFIG_UCM2=${config.environment.sessionVariables.ALSA_CONFIG_UCM2}
    '';

    systemd.services = {
      xun-tqftpserv = {
        description = "Firmware file service for the Qualcomm modem DSP";
        serviceConfig = {
          ExecStart = "${tqftpserv}/bin/tqftpserv";
          Restart = "on-failure";
        };
      };
      xun-rmtfs = {
        description = "Read-only EFS service for the Qualcomm modem DSP";
        serviceConfig = {
          ExecStart = "${pkgs.rmtfs}/bin/rmtfs -r";
          Restart = "on-failure";
        };
      };
      xun-modem = {
        description = "Start the Qualcomm modem DSP for Wi-Fi";
        wantedBy = [ "multi-user.target" ];
        wants = [ "xun-tqftpserv.service" "xun-rmtfs.service" ];
        after = [ "xun-tqftpserv.service" "xun-rmtfs.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          # Give the QRTR services time to register before starting the modem.
          sleep 2
          modem=
          for attempt in {1..30}; do
            for proc in /sys/class/remoteproc/remoteproc*; do
              [ -r "$proc/firmware" ] || continue
              [ "$(cat "$proc/firmware")" = "${dspDir}/modem.mdt" ] || continue
              modem="$proc"
              break 2
            done
            sleep 1
          done
          if [ -z "$modem" ]; then
            echo "xun modem DSP was not found" >&2
            exit 1
          fi
          if [ "$(cat "$modem/state")" = offline ]; then
            echo start > "$modem/state"
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

    system.build.xunBootImage = pkgs.callPackage ../pkgs/boot-image {
      inherit tapas;
      inherit (cfg) wifiMac bluetoothMac;
      inherit (config.system.build) kernel;
      initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      init = "${config.system.build.toplevel}/init";
      inherit (config.boot) kernelParams;
    };
  };
}
