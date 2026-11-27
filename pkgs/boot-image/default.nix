{
  runCommand,
  dtc,
  cpio,
  python3,
  llvmPackages,
  tapas,
  uboot,
  deviceTree,
}:

runCommand "xun-uboot-android-image" {
  nativeBuildInputs = [
    dtc
    cpio
    python3
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];
} ''
  cp ${deviceTree} xun.dtb
  chmod u+w xun.dtb
  mmc=$(fdtget -t s xun.dtb /__symbols__ sdhc_1)
  fdtput -t s xun.dtb /aliases mmc0 "$mmc"
  # The U-Boot Qualcomm SDHCI driver lacks the DLL tuning and enhanced strobe
  # support needed for these modes. Keep them in Linux's separate DTB.
  fdtput -d xun.dtb "$mmc" mmc-hs200-1_8v mmc-hs400-1_8v mmc-hs400-enhanced-strobe
  fb=$(fdtget -t s xun.dtb /__symbols__ framebuffer0)
  fdtput -t i xun.dtb "$fb" rot 2

  # Clear exactly the visible scanout in the shim, before U-Boot starts.
  read -r fb_base_high fb_base fb_size_high fb_size <<< "$(fdtget -t x xun.dtb "$fb" reg)"
  fb_width=$(fdtget -t u xun.dtb "$fb" width)
  fb_height=$(fdtget -t u xun.dtb "$fb" height)
  fb_stride=$(fdtget -t u xun.dtb "$fb" stride)
  fb_scanout=$((fb_stride * fb_height))
  test "$fb_base_high:$fb_size_high:$(fdtget -t s xun.dtb "$fb" format)" = "0:0:a8r8g8b8"
  (( fb_width >= 1051 && fb_height >= 480 && fb_stride >= fb_width * 4 &&
     fb_scanout <= 0x$fb_size && fb_scanout % 16 == 0 && 0x$fb_base % 16 == 0 ))

  patch -o shim.S ${tapas}/shim/start.S < ${./keep-abl-fdt.patch}
  patch shim.S < ${./clear-abl-splash.patch}
  clang --target=aarch64-linux-gnu -DFB_BASE="0x$fb_base" -DFB_WIDTH="$fb_width" \
    -DFB_STRIDE="$fb_stride" -DFB_SIZE="$fb_scanout" -c shim.S -o shim.o
  ld.lld -T ${tapas}/shim/shim.ld shim.o -o shim.elf
  llvm-objcopy -O binary shim.elf shim.bin
  python3 ${tapas}/scripts/pack-shim.py shim.bin xun.dtb ${uboot}/u-boot-nodtb.bin payload

  printf '.\n' | cpio -o -H newc -R 0:0 --quiet | gzip -9n > empty.cpio.gz
  mkdir "$out"
  python3 ${tapas}/scripts/mkbootimg.py --header_version 4 \
    --kernel payload --ramdisk empty.cpio.gz \
    --os_version 13.0.0 --os_patch_level 2026-10 \
    --cmdline "" --output "$out/boot.img"
''
