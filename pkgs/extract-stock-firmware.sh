set -euo pipefail

# The pinned ZIP stores payload.bin uncompressed at byte 4707.
# The OTA manifest gives the offset and length of each partition's data.
# Reconstruct a sparse payload at the original offsets so the dumper can
# verify and extract the four selected images normally.
payload_zip_offset=4707
truncate -s 4750800502 payload.bin

fetch_region() {
    local name=$1 offset=$2 length=$3
    local first=$((payload_zip_offset + offset))
    local last=$((first + length - 1))

    echo "Downloading $name ($length bytes)"
    curl --fail --silent --show-error --location --retry 4         --connect-timeout 20 --max-filesize "$length"         --range "$first-$last" --dump-header range.headers         --output range.bin "$url"

    tr -d '\r' < range.headers |
        grep -Fxi "content-range: bytes $first-$last/4750808881" > /dev/null
    test "$(stat -c %s range.bin)" -eq "$length"
    dd if=range.bin of=payload.bin bs=1M seek="${offset}B" conv=notrunc status=none
    rm range.bin range.headers
}

fetch_region manifest        0     188345
fetch_region bluetooth  395969     240604
fetch_region modem    23967413   12195896
fetch_region odm      36163309     947672
fetch_region vendor 3777443261  341955036

payload-dumper-go -q -p bluetooth,modem,odm,vendor -o partitions payload.bin

mkdir -p extracted/{bluetooth,modem,odm,vendor}
mcopy -s -i partitions/bluetooth.img ::/image extracted/bluetooth/
mcopy -s -i partitions/modem.img ::/image extracted/modem/
fsck.erofs --extract=extracted/odm --no-preserve partitions/odm.img
fsck.erofs --extract=extracted/vendor --no-preserve partitions/vendor.img

fw="$out/lib/firmware"
radio="$fw/qcom/sm6225/xiaomi/xun"
mkdir -p "$radio" "$fw/qca"
install -m644 extracted/modem/image/{adsp.*,modem.*,wlanmdsp.mbn,bdwlan*,bd84*} "$radio/"
install -m644 extracted/vendor/firmware/{a610_zap.mdt,a610_zap.b00,a610_zap.b01,a610_zap.b02,a630_sqe.fw} "$fw/qcom/"
install -m644 extracted/odm/firmware/{focaltech_ts_fw_boe_ft8203.bin,focaltech_ts_fw_huaxing_ft8203.bin} "$fw/"
install -m644 extracted/bluetooth/image/cmbtfw13.tlv "$fw/qca/crbtfw13.tlv"
install -m644 extracted/bluetooth/image/cmnv13.bin "$fw/qca/crnv13.bin"
