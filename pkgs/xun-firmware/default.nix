{
  lib,
  stdenvNoCC,
  fetchurl,
  ath10k,
  payload-dumper-go,
  mtools,
  erofs-utils,
}:
let
  dspDir = "qcom/sm6225/xiaomi/xun";
  version = "OS2.0.207.0.VMUEUXM";
  url = "https://cdnorg.d.miui.com/${version}/xun_eea_global-ota_full-${version}-user-15.0-6b1513122d.zip";
  fetchRegion =
    { name, offset, length, hash }:
    let
      # payload.bin starts at byte 4707 in the ZIP.
      first = 4707 + offset;
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
      name = "modem-odm";
      offset = 23967413;
      length = 13143568;
      hash = "sha256-maPHbUHztlqbQ9rZEFyNbjleCiQtbvh+zCzQMsDtIKI=";
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
  outputs = [ "out" "sensors" ];

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
    mkdir extracted/sensors
    fsck.erofs --extract=extracted/sensors --path=/etc/sensors --no-preserve partitions/vendor.img

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    fw="$out/lib/firmware"
    radio="$fw/${dspDir}"
    mkdir -p "$radio" "$fw/qca"
    cp -r ${ath10k}/ath10k "$fw/"
    install -Dm644 ${ath10k}/LICENSES/LICENSE.QualcommAtheros_ath10k \
      "$out/share/licenses/xun-firmware/LICENSE.QualcommAtheros_ath10k"
    install -m644 extracted/modem/image/{adsp.*,modem.*,wlanmdsp.mbn,bdwlan*,bd84*} "$radio/"
    install -m644 extracted/vendor/{a610_zap.mdt,a610_zap.b0[0-2],a630_sqe.fw} "$fw/qcom/"
    install -m644 extracted/odm/focaltech_ts_fw_{boe,huaxing}_ft8203.bin "$fw/"
    install -Dm644 extracted/odm/novatek_ts_fw_tianma.bin "$fw/novatek/nt36532-xun.bin"
    install -m644 extracted/bluetooth/image/cmbtfw13.tlv "$fw/qca/crbtfw13.tlv"
    install -m644 extracted/bluetooth/image/cmnv13.bin "$fw/qca/crnv13.bin"

    mkdir -p "$sensors"
    cp -r extracted/sensors/config "$sensors/"
    install -m644 extracted/sensors/sns_reg_config "$sensors/sns_reg.conf"

    runHook postInstall
  '';

  passthru = {
    compressFirmware = false;
    initrdFirmwarePaths = [
      "qcom/a630_sqe.fw"
      "qcom/a610_zap.mdt"
      "qcom/a610_zap.b00"
      "qcom/a610_zap.b01"
      "qcom/a610_zap.b02"
      "focaltech_ts_fw_huaxing_ft8203.bin"
      "focaltech_ts_fw_boe_ft8203.bin"
      "novatek/nt36532-xun.bin"
      "qca/crbtfw13.tlv"
      "qca/crnv13.bin"
      "${dspDir}/adsp.mdt"
    ] ++ map (n: "${dspDir}/adsp.b${lib.fixedWidthNumber 2 n}") (lib.remove 11 (lib.range 0 35));
  };
}
