{
  runCommand,
  src,
  xun,
  tapas,
}:

runCommand "xun-board-files.patch" { } ''
  add_file() {
    diff -u --label /dev/null --label "b/$2" /dev/null "$1" || test "$?" -eq 1
  }

  tar -xOf ${src} linux-7.2.1/scripts/kconfig/merge_config.sh > merge_config.sh
  sh merge_config.sh -m ${tapas}/config/base.config ${tapas}/config/tapas.config     ${xun}/build/config/xun.config ${./nixos.config}

  {
    add_file .config arch/arm64/configs/xun_defconfig
    add_file ${xun}/build/kernel-dts/sm6225-xiaomi-xun.dts arch/arm64/boot/dts/qcom/sm6225-xiaomi-xun.dts
    for panel in ${xun}/build/kernel-panel/panel-xiaomi-m84-*.c; do
      add_file "$panel" "drivers/gpu/drm/panel/$(basename "$panel")"
    done
    add_file ${xun}/build/kernel-touch/ft8203-spi.c drivers/input/touchscreen/ft8203-spi.c
    add_file ${xun}/build/kernel-battery/sh366101.c drivers/power/supply/sh366101.c
    add_file ${xun}/build/kernel-audio/fs1815.c sound/soc/codecs/fs1815.c
  } > "$out"
''
