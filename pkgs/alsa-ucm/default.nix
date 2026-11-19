{
  runCommand,
  alsa-ucm-conf,
  xun,
}:

runCommand "xun-alsa-ucm" { } ''
  mkdir "$out"
  cp -r ${alsa-ucm-conf}/share/alsa/ucm2/. "$out/"
  chmod -R u+w "$out"
  cp -r --remove-destination ${xun}/build/ucm2/. "$out/"
''
