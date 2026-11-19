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
