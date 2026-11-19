{
  runCommand,
  fetchurl,
  payload-dumper-go,
  mtools,
  erofs-utils,
}:
let
  url = "https://cdnorg.d.miui.com/OS2.0.207.0.VMUEUXM/xun_eea_global-ota_full-OS2.0.207.0.VMUEUXM-user-15.0-6b1513122d.zip";
  # payload.bin is stored uncompressed at this byte offset in the pinned ZIP.
  payloadZipOffset = 4707;
  fetchRegion =
    name: offset: length: hash:
    let
      first = payloadZipOffset + offset;
      last = first + length - 1;
    in
    fetchurl {
      inherit url hash;
      name = "xun-ota-OS2.0.207.0.VMUEUXM-${name}";
      # fetchurl enables curl's resume option, which conflicts with --range.
      curlOptsList = [
        "--header"
        "Range: bytes=${toString first}-${toString last}"
        "--max-filesize"
        (toString length)
      ];
    };

  # These offsets are relative to payload.bin, as recorded in the OTA manifest.
  regions = [
    { name = "manifest"; offset = 0; length = 188345; hash = "sha256-aI8e+BP2yiGroT+BqEFY9P/vlRMVXi3nHSBY/4a8lE4="; }
    { name = "bluetooth"; offset = 395969; length = 240604; hash = "sha256-ao1S84VHmMg4dS4W/szsGheYgHTmHxrZOvQRG+Vv8Is="; }
    { name = "modem"; offset = 23967413; length = 12195896; hash = "sha256-kW5G7UWaQT9aj/L8L+ryHMLVKtFdzuTPMKsHwlOgSCo="; }
    { name = "odm"; offset = 36163309; length = 947672; hash = "sha256-pIVszycwQFO5Fyc2MHcMeXVMIvW2VGIr0k/3Mrms2J8="; }
    { name = "vendor"; offset = 3777443261; length = 341955036; hash = "sha256-bpfJkZ3VH+gViqJPh7kGBWXpyBegu8uqjwXI/15gCME="; }
  ];
in
runCommand "xun-firmware-OS2.0.207.0.VMUEUXM" {
  nativeBuildInputs = [
    payload-dumper-go
    mtools
    erofs-utils
  ];
  passthru.compressFirmware = false;
} (''
  set -euo pipefail

  # Reconstruct a sparse payload at the original offsets. The dumper verifies
  # each selected partition image against the checksum in the manifest.
  truncate -s 4750800502 payload.bin
'' + builtins.concatStringsSep "\n" (map (
  region:
  "dd if=${fetchRegion region.name region.offset region.length region.hash} of=payload.bin bs=1M seek=${toString region.offset}B conv=notrunc status=none"
) regions) + "\n" + builtins.readFile ./extract-stock-firmware.sh)
