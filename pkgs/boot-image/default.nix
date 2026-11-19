{
  lib,
  runCommand,
  writeShellApplication,
  coreutils,
  dtc,
  cpio,
  gzip,
  python3,
  llvmPackages,
  tapas,
  wifiMac,
  bluetoothMac,
}:
let
  macBytes = mac: lib.splitString ":" mac;
  wifiBytes = lib.concatStringsSep " " (macBytes wifiMac);
  bluetoothBytes = lib.concatStringsSep " " (lib.reverseList (macBytes bluetoothMac));
  shim = runCommand "xun-boot-shim" {
    nativeBuildInputs = [ llvmPackages.clang llvmPackages.lld llvmPackages.llvm ];
  } ''
    cp -r ${tapas}/shim ./shim
    chmod -R u+w shim
    patch -p1 < ${./shim-initrd.patch}
    clang --target=aarch64-linux-gnu -c shim/start.S -o shim.o
    ld.lld -T shim/shim.ld shim.o -o shim.elf
    llvm-objcopy -O binary shim.elf "$out"
  '';
in
writeShellApplication {
  name = "xun-pack-boot";
  runtimeInputs = [ coreutils dtc cpio gzip python3 ];
  text = ''
    generation=$(realpath "$1")
    slot=$2
    image=$(realpath -m "$3")
    case "$slot" in
      a|b) ;;
      *) echo "Invalid boot slot: $slot" >&2; exit 1 ;;
    esac

    params=$(cat "$generation/kernel-params")
    case "$params" in
      *androidboot.slot_suffix=*)
        echo "androidboot.slot_suffix is set by the xun boot image" >&2
        exit 1
        ;;
    esac

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cd "$work"
    cp "$generation/xun.dtb" xun.dtb
    chmod u+w xun.dtb
    fdtput -t s xun.dtb /chosen bootargs "androidboot.slot_suffix=_$slot init=$generation/init $params"
    fdtput -t x xun.dtb /chosen linux,initrd-start 0 13716a5e
    fdtput -t x xun.dtb /chosen linux,initrd-end 0 29d53b78
    fdtput -t bx xun.dtb "$(fdtget -t s xun.dtb /__symbols__ wifi)" local-mac-address ${wifiBytes}
    fdtput -t bx xun.dtb "$(fdtget -t s xun.dtb /__symbols__ uart3)/bluetooth" local-bd-address ${bluetoothBytes}

    python3 ${tapas}/scripts/pack-shim.py ${shim} xun.dtb "$generation/kernel" payload
    python3 ${./pack-initrd.py} payload "$generation/initrd"

    # ABL ignores the Android ramdisk. The shim supplies the NixOS initrd.
    mkdir empty
    (cd empty && printf '.\n' | cpio -o -H newc -R 0:0 --quiet | gzip -9n) > empty.cpio.gz
    python3 ${tapas}/scripts/mkbootimg.py --header_version 4       --kernel payload --ramdisk empty.cpio.gz       --os_version 13.0.0 --os_patch_level 2026-10       --cmdline "" --output "$image"
  '';
}
