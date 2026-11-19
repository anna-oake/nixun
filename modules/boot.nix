{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.redmi-pad-se;
  inherit (pkgs.callPackage ../pkgs/sources.nix { }) tapas;
  packer = pkgs.callPackage ../pkgs/boot-image {
    inherit tapas;
    inherit (cfg) wifiMac bluetoothMac;
  };

  readBootSlot = ''
    case " $(cat /proc/cmdline) " in
      *" androidboot.slot_suffix=_a "*) current=a; currentIndex=0 ;;
      *" androidboot.slot_suffix=_b "*) current=b; currentIndex=1 ;;
      *) echo "The running xun boot image has no slot identity" >&2; exit 1 ;;
    esac
  '';
  lockBootSlots = ''
    exec 9>/run/lock/xun-boot
    flock 9
  '';

  installBootLoader = pkgs.writeShellApplication {
    name = "xun-install-bootloader";
    runtimeInputs = [ packer pkgs.coreutils pkgs.diffutils pkgs.qbootctl pkgs.util-linux ];
    text = ''
      generation=$(realpath "$1")
      booted=$(realpath -e /run/booted-system)
      ${lockBootSlots}
      ${readBootSlot}

      active=$(qbootctl -a)
      if [[ "$generation" == "$booted" ]]; then
        if [[ "$active" != "Active slot: _$current" ]]; then
          qbootctl -s "$currentIndex"
          qbootctl -m "$currentIndex"
        fi
        exit 0
      fi

      if [[ "$active" != "Active slot: _$current" ]]; then
        echo "A different slot is already selected. Reboot before deploying again." >&2
        exit 1
      fi
      if [[ "$(qbootctl -n "$currentIndex")" != "SLOT _$current: is marked successful" ]]; then
        echo "The running boot slot has not been confirmed yet." >&2
        exit 1
      fi

      if [[ "$current" == a ]]; then
        next=b; nextIndex=1
      else
        next=a; nextIndex=0
      fi
      partition="/dev/disk/by-partlabel/boot_$next"
      test -b "$partition"
      test -b "/dev/disk/by-partlabel/boot_$current"
      test ! "$partition" -ef "/dev/disk/by-partlabel/boot_$current"

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      image="$work/boot.img"
      xun-pack-boot "$generation" "$next" "$image"
      bytes=$(stat -c %s "$image")
      test "$bytes" -le "$(blockdev --getsize64 "$partition")"

      roots=/nix/var/nix/gcroots
      ln -sfnT "$booted" "$roots/xun-slot-$current"
      ln -sfnT "$generation" "$roots/xun-slot-$next"
      dd if="$image" of="$partition" bs=4M conv=fsync status=none
      cmp --bytes="$bytes" "$image" "$partition"

      qbootctl -s "$nextIndex"
      test "$(qbootctl -a)" = "Active slot: _$next"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    boot.loader.external = {
      enable = true;
      installHook = lib.getExe installBootLoader;
    };

    system.systemBuilderCommands = ''
      ln -s ${config.system.build.kernel}/dtbs/qcom/sm6225-xiaomi-xun.dtb "$out/xun.dtb"
    '';

    system.build.xunBootImage = pkgs.runCommand "xun-android-boot-image" {
      nativeBuildInputs = [ packer ];
    } ''
      mkdir "$out"
      xun-pack-boot ${config.system.build.toplevel} a "$out/boot.img"
    '';

    systemd.services.xun-boot-success = {
      description = "Confirm the booted xun slot";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig.DefaultDependencies = false;
      restartIfChanged = false;
      stopIfChanged = false;
      path = [ pkgs.coreutils pkgs.qbootctl pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${lockBootSlots}
        ${readBootSlot}
        ln -sfnT "$(realpath -e /run/booted-system)" "/nix/var/nix/gcroots/xun-slot-$current"
        if [ "$(qbootctl -n "$currentIndex")" != "SLOT _$current: is marked successful" ]; then
          qbootctl -m "$currentIndex"
        fi
      '';
    };
  };
}
