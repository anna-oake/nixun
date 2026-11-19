{
  lib,
  runCommand,
  dtc,
  cpio,
  python3,
  llvmPackages,
  tapas,
  kernel,
  initrd,
  init,
  kernelParams,
  wifiMac,
  bluetoothMac,
}:
let
  macBytes = mac: lib.splitString ":" mac;
  wifiBytes = lib.concatStringsSep " " (macBytes wifiMac);
  bluetoothBytes = lib.concatStringsSep " " (lib.reverseList (macBytes bluetoothMac));
  bootargs = lib.escapeShellArg (toString ([ "init=${init}" ] ++ kernelParams));
in
runCommand "xun-android-boot-image" {
  nativeBuildInputs = [
    dtc
    cpio
    python3
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];
} ''
  dtb=xun.dtb
  cp ${kernel}/dtbs/qcom/sm6225-xiaomi-xun.dtb "$dtb"
  chmod u+w "$dtb"
  fdtput -t s "$dtb" /chosen bootargs ${bootargs}
  fdtput -t x "$dtb" /chosen linux,initrd-start 0 13716a5e
  fdtput -t x "$dtb" /chosen linux,initrd-end 0 29d53b78
  fdtput -t bx "$dtb" "$(fdtget -t s "$dtb" /__symbols__ wifi)" local-mac-address ${wifiBytes}
  fdtput -t bx "$dtb" "$(fdtget -t s "$dtb" /__symbols__ uart3)/bluetooth" local-bd-address ${bluetoothBytes}

  cp -r ${tapas}/shim ./shim
  chmod -R u+w shim
  patch -p1 < ${./shim-initrd.patch}
  clang --target=aarch64-linux-gnu -c shim/start.S -o shim.o
  ld.lld -T shim/shim.ld shim.o -o shim.elf
  llvm-objcopy -O binary shim.elf shim.bin
  python3 ${tapas}/scripts/pack-shim.py shim.bin "$dtb" ${kernel}/Image payload
  python3 ${./pack-initrd.py} payload ${initrd}

  # ABL ignores this ramdisk. The shim hands the NixOS initrd to Linux.
  mkdir empty
  (cd empty && find . | cpio -o -H newc -R 0:0 --quiet | gzip -9n) > empty.cpio.gz
  mkdir "$out"
  python3 ${tapas}/scripts/mkbootimg.py --header_version 4 \
    --kernel payload --ramdisk empty.cpio.gz \
    --os_version 13.0.0 --os_patch_level 2026-10 \
    --cmdline "" --output "$out/boot.img"
''
