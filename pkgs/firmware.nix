{
  runCommand,
  m4,
  alsa-utils,
  xun,
  audioreach,
  firmwareDir,
}:
runCommand "xun-firmware" {
  nativeBuildInputs = [ m4 alsa-utils ];
  passthru.compressFirmware = false;
} ''
  fw="$out/lib/firmware"
  mkdir -p "$fw/qcom/sm4250"
  ${if firmwareDir == null then "" else ''
    cp -rL ${firmwareDir}/. "$fw/"
    chmod -R u+w "$fw"
  ''}
  m4 -I ${audioreach} ${xun}/build/topology/SM6225-Xun.m4 > SM6225-Xun.conf
  alsatplg -c SM6225-Xun.conf -o "$fw/qcom/sm4250/SM6225-Xun-tplg.bin" ||
    test -s "$fw/qcom/sm4250/SM6225-Xun-tplg.bin"
''
