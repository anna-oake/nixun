{
  config,
  lib,
  pkgs,
  ...
}:

let
  swclock = pkgs.callPackage ../pkgs/swclock-offset { };
  synchronized = "/run/systemd/timesync/synchronized";
  state = {
    StateDirectory = "swclock-offset";
    StateDirectoryMode = "0700";
    UMask = "0077";
  };
in
{
  config = lib.mkIf config.hardware.redmi-pad-se.enable {
    systemd.services.xun-rtc-restore = {
      description = "Restore system time from the RTC offset";
      wantedBy = [ "sysinit.target" ];
      after = [ "local-fs.target" ];
      before = [
        "sysinit.target"
        "time-set.target"
        "systemd-timesyncd.service"
        "shutdown.target"
      ];
      conflicts = [ "shutdown.target" ];
      restartIfChanged = false;
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "!${synchronized}";
      };
      serviceConfig = state // {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${swclock}/bin/swclock-offset-boot";
      };

      # Preserve the last good offset if this boot never synchronized.
      preStop = ''
        if [ -e ${synchronized} ]; then
          ${swclock}/bin/swclock-offset-shutdown
        fi
      '';
    };

    systemd.paths.xun-rtc-save = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathExists = synchronized;
    };

    systemd.services.xun-rtc-save = {
      description = "Save the RTC offset after the first time synchronization";
      after = [ "xun-rtc-restore.service" ];
      restartIfChanged = false;
      unitConfig.ConditionPathExists = synchronized;
      serviceConfig = state // {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${swclock}/bin/swclock-offset-shutdown";
      };
    };
  };
}
