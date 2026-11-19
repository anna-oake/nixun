{
  lib,
  stdenvNoCC,
  fetchurl,
  payload-dumper-go,
  mtools,
  erofs-utils,
}:
let
  version = "OS2.0.207.0.VMUEUXM";
  url = "https://cdnorg.d.miui.com/${version}/xun_eea_global-ota_full-${version}-user-15.0-6b1513122d.zip";
  # ZIP offset of the uncompressed payload.bin.
  payloadZipOffset = 4707;
  fetchRegion =
    { name, offset, length, hash }:
    let
      first = payloadZipOffset + offset;
      last = first + length - 1;
    in
    fetchurl {
      inherit url hash;
      name = "xun-ota-${version}-${name}";
      # fetchurl enables curl's resume option, which conflicts with --range.
      curlOptsList = [
        "--header"
        "Range: bytes=${toString first}-${toString last}"
        "--max-filesize"
        (toString length)
      ];
    };

  # Offsets relative to payload.bin from the OTA manifest.
  regions = [
    {
      name = "manifest";
      offset = 0;
      length = 188345;
      hash = "sha256-aI8e+BP2yiGroT+BqEFY9P/vlRMVXi3nHSBY/4a8lE4=";
    }
    {
      name = "bluetooth";
      offset = 395969;
      length = 240604;
      hash = "sha256-ao1S84VHmMg4dS4W/szsGheYgHTmHxrZOvQRG+Vv8Is=";
    }
    {
      name = "modem";
      offset = 23967413;
      length = 12195896;
      hash = "sha256-kW5G7UWaQT9aj/L8L+ryHMLVKtFdzuTPMKsHwlOgSCo=";
    }
    {
      name = "odm";
      offset = 36163309;
      length = 947672;
      hash = "sha256-pIVszycwQFO5Fyc2MHcMeXVMIvW2VGIr0k/3Mrms2J8=";
    }
    {
      name = "vendor";
      offset = 3777443261;
      length = 341955036;
      hash = "sha256-bpfJkZ3VH+gViqJPh7kGBWXpyBegu8uqjwXI/15gCME=";
    }
  ];
in
stdenvNoCC.mkDerivation {
  pname = "xun-firmware";
  inherit version;

  nativeBuildInputs = [
    payload-dumper-go
    mtools
    erofs-utils
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack

    truncate -s 4750800502 payload.bin
    ${lib.concatMapStringsSep "\n" (region: ''
      dd if=${fetchRegion region} of=payload.bin bs=1M seek=${toString region.offset}B conv=notrunc status=none
    '') regions}

    payload-dumper-go -q -p bluetooth,modem,odm,vendor -o partitions payload.bin

    mkdir -p extracted/{bluetooth,modem,odm,vendor}
    mcopy -s -i partitions/bluetooth.img ::/image extracted/bluetooth/
    mcopy -s -i partitions/modem.img ::/image extracted/modem/
    for partition in odm vendor; do
      fsck.erofs --extract="extracted/$partition" --path=/firmware --no-preserve "partitions/$partition.img"
    done

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    fw="$out/lib/firmware"
    radio="$fw/qcom/sm6225/xiaomi/xun"
    mkdir -p "$radio" "$fw/qca"
    install -m644 extracted/modem/image/{adsp.*,modem.*,wlanmdsp.mbn,bdwlan*,bd84*} "$radio/"
    install -m644 extracted/vendor/{a610_zap.mdt,a610_zap.b0[0-2],a630_sqe.fw} "$fw/qcom/"
    install -m644 extracted/odm/focaltech_ts_fw_{boe,huaxing}_ft8203.bin "$fw/"
    install -m644 extracted/bluetooth/image/cmbtfw13.tlv "$fw/qca/crbtfw13.tlv"
    install -m644 extracted/bluetooth/image/cmnv13.bin "$fw/qca/crnv13.bin"

    runHook postInstall
  '';

  passthru.compressFirmware = false;
}
