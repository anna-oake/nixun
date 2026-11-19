{
  runCommand,
  curl,
  cacert,
  payload-dumper-go,
  mtools,
  erofs-utils,
}:

runCommand "xun-firmware-OS2.0.207.0.VMUEUXM" {
  nativeBuildInputs = [
    curl
    payload-dumper-go
    mtools
    erofs-utils
  ];

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-/34yp5yCIlJDr5i43G2uFsM7IgSZnh51AoOgMffHDOc=";
  passthru.compressFirmware = false;

  CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  url = "https://cdnorg.d.miui.com/OS2.0.207.0.VMUEUXM/xun_eea_global-ota_full-OS2.0.207.0.VMUEUXM-user-15.0-6b1513122d.zip";
} (builtins.readFile ./extract-stock-firmware.sh)
