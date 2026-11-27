{ stockSensors }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  state = "/var/lib/xun-sensors";
  sensorProxy = config.hardware.sensor.iio.package;
  device = "dev-fastrpc\\x2dadsp.device";
  persist = "dev-disk-by\\x2dpartlabel-persist.device";
  firmware = "/dev/disk/by-partlabel/persist";
  hexagonrpc = pkgs.hexagonrpc.overrideAttrs (_: {
    # The sensor DSP needs to update its registry during initialization.
    src = pkgs.fetchFromGitHub {
      owner = "FadyAckad";
      repo = "hexagonrpc";
      rev = "40e50412812adce9dddc2be9a4510ebce05eef89";
      hash = "sha256-+VbVvPfKLgNrg3tliUFWG32Y/HPdNpD6XkaCHsU+DiY=";
    };
  });
in
{
  config = lib.mkIf config.hardware.redmi-pad-se.enable {
    # SSC uses FastRPC, so it can use the proxy without the HID sensor module.
    environment.systemPackages = [ sensorProxy ];
    services.dbus.packages = [ sensorProxy ];
    services.udev.packages = [ sensorProxy ];
    systemd.packages = [ sensorProxy ];

    users.groups.xun-sensors = { };
    users.users.xun-sensors = {
      isSystemUser = true;
      group = "xun-sensors";
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp", GROUP="xun-sensors", MODE="0660", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xun-sensors.service", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel"
    '';

    systemd.services.xun-sensor-registry = {
      description = "Prepare the Redmi Pad SE sensor registry";
      requires = [ persist ];
      after = [ persist ];
      path = [ pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        PrivateMounts = true;
        StateDirectory = "xun-sensors";
      };
      script = ''
        install -d -m 0755 "${state}/sensors" "${state}/socinfo"
        if [ ! -d "${state}/sensors/persist/registry" ]; then
          work=$(mktemp -d "${state}/.registry.XXXXXX")
          trap 'umount "$work/source" 2>/dev/null || true; rm -rf "$work"' EXIT
          mkdir "$work/source" "$work/persist"
          mount -t ext4 -o ro,noload ${firmware} "$work/source"
          cp -R --no-preserve=ownership,mode "$work/source/sensors/registry/." "$work/persist/"
          test -s "$work/persist/registry/sns_reg_config"
          chmod -R u=rwX,go= "$work/persist"
          chown -R xun-sensors:xun-sensors "$work/persist"
          mv -T "$work/persist" "${state}/sensors/persist"
          umount "$work/source"
        fi

        ln -sfn ${stockSensors}/config "${state}/sensors/config"
        ln -sfn ${stockSensors}/sns_reg.conf "${state}/sensors/sns_reg.conf"

        # The firmware expects the Android sysfs attributes. Translate the
        # mainline SMEM values for the IDP platform and subtype zero.
        dbg=/sys/kernel/debug/qcom_socinfo
        test "$(cat "$dbg/hardware_platform")" = 34
        test "$(cat "$dbg/hardware_platform_subtype")" = 0
        printf 'IDP\n' > "${state}/socinfo/hw_platform"
        printf 'Unknown\n' > "${state}/socinfo/platform_subtype"
        cat "$dbg/hardware_platform_subtype" > "${state}/socinfo/platform_subtype_id"
        cat "$dbg/platform_version" > "${state}/socinfo/platform_version"
        for field in soc_id revision; do
          cat "/sys/devices/soc0/$field" > "${state}/socinfo/$field"
        done
      '';
    };

    systemd.services.xun-sensors = {
      description = "Serve the Redmi Pad SE sensor DSP over FastRPC";
      bindsTo = [ device ];
      requires = [ "xun-sensor-registry.service" ];
      after = [
        device
        "xun-sensor-registry.service"
      ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "${lib.getExe hexagonrpc} -f /dev/fastrpc-adsp -d adsp -s -R ${state}";
        User = "xun-sensors";
        Group = "xun-sensors";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "${state}/sensors/persist" ];
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/fastrpc-adsp rw" ];
      };
    };

    systemd.services.iio-sensor-proxy = {
      overrideStrategy = "asDropin";
      wants = [ "xun-sensors.service" ];
      after = [ "xun-sensors.service" ];
    };
  };
}
