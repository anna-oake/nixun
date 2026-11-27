// SPDX-License-Identifier: GPL-2.0-only
/*
 * NT36532 touchscreen for the Redmi Pad SE. Protocol based on Novatek's
 * GPLv2 driver in Xiaomi's ruan-u-oss tree, copyright 2010-2022 Novatek, Inc.
 */
#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/gpio/consumer.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of_irq.h>
#include <linux/regulator/consumer.h>
#include <linux/spi/spi.h>
#include <linux/unaligned.h>

#define NVT_FIRMWARE "novatek/nt36532-xun.bin"
#define NVT_EVENT 0x125800
#define NVT_RESET_STATE (NVT_EVENT + 0x60)
#define NVT_SW_RESET 0x1fb43e
#define NVT_TRIM_ID 0x1fb104
#define NVT_BOOT_READY 0x1fb50d
#define NVT_AUTO_COPY 0x1fc925
#define NVT_ADDR_MAX 0x7fffff
#define NVT_TRANSFER 1024
#define NVT_FRAME 108
#define NVT_TOUCHES 10
/* The xun firmware reports ten coordinate units per display pixel. */
#define NVT_WIDTH 12000
#define NVT_HEIGHT 19200

struct nvt_ts {
	struct spi_device *spi;
	struct gpio_desc *reset;
	struct input_dev *input;
	struct touchscreen_properties properties;
	u8 *tx;
	u8 *rx;
};

static int nvt_page(struct nvt_ts *ts, u32 addr)
{
	u8 page[] = { 0xff, addr >> 15, addr >> 7 };

	return spi_write_then_read(ts->spi, page, sizeof(page), NULL, 0);
}

static int nvt_write(struct nvt_ts *ts, u32 addr, const u8 *data, size_t size)
{
	int ret = nvt_page(ts, addr);

	if (ret)
		return ret;
	ts->tx[0] = 0x80 | (addr & 0x7f);
	memcpy(ts->tx + 1, data, size);
	return spi_write(ts->spi, ts->tx, size + 1);
}

static int nvt_write_byte(struct nvt_ts *ts, u32 addr, u8 value)
{
	return nvt_write(ts, addr, &value, 1);
}

static int nvt_read(struct nvt_ts *ts, u32 addr, u8 *data, size_t size)
{
	struct spi_transfer transfer = {
		.tx_buf = ts->tx, .rx_buf = ts->rx, .len = size + 2,
	};
	int ret = nvt_page(ts, addr);

	if (ret)
		return ret;
	memset(ts->tx, 0, transfer.len);
	ts->tx[0] = addr & 0x7f;
	ret = spi_sync_transfer(ts->spi, &transfer, 1);
	if (!ret)
		memcpy(data, ts->rx + 2, size);
	return ret;
}

static int nvt_bootloader_reset(struct nvt_ts *ts)
{
	int ret = nvt_write_byte(ts, NVT_SW_RESET, 0x69);

	usleep_range(5000, 7000);
	return ret;
}

static int nvt_check_id(struct nvt_ts *ts)
{
	static const u8 trim[] = { 0x32, 0x65, 0x03 };
	u8 clear[6] = {};
	u8 id[6];
	int ret;

	gpiod_set_value_cansleep(ts->reset, 1);
	msleep(20);
	gpiod_set_value_cansleep(ts->reset, 0);
	msleep(20);

	ret = nvt_bootloader_reset(ts);
	if (ret)
		return ret;
	ret = nvt_write(ts, NVT_TRIM_ID, clear, sizeof(clear));
	if (ret)
		return ret;
	ret = nvt_read(ts, NVT_TRIM_ID, id, sizeof(id));
	if (ret)
		return ret;
	if (memcmp(id + 3, trim, sizeof(trim))) {
		dev_err(&ts->spi->dev, "unexpected trim ID %*ph\n", (int)sizeof(id), id);
		return -ENODEV;
	}
	return 0;
}

static int nvt_write_segment(struct nvt_ts *ts, const struct firmware *fw,
			     u32 offset, u32 addr, u32 last)
{
	size_t bytes = (size_t)last + 1;

	if (!last)
		return 0;
	if (offset >= fw->size || bytes > fw->size - offset ||
	    addr > NVT_ADDR_MAX || bytes > NVT_ADDR_MAX + 1 - addr)
		return -EINVAL;
	while (bytes) {
		size_t chunk = min_t(size_t, bytes, NVT_TRANSFER);
		int ret = nvt_write(ts, addr, fw->data + offset, chunk);

		if (ret)
			return ret;
		addr += chunk;
		offset += chunk;
		bytes -= chunk;
	}
	return 0;
}

static int nvt_crc_bank(struct nvt_ts *ts, u32 destination, u32 length,
			u32 crc, const u8 *header, const u8 *checksum)
{
	int ret = nvt_write(ts, destination, header + 4, 3);

	if (ret)
		return ret;
	ret = nvt_write(ts, length, header + 8, 3);
	if (ret)
		return ret;
	return nvt_write(ts, crc, checksum, 4);
}

static int nvt_upload(struct nvt_ts *ts, const struct firmware *fw)
{
	const u8 *data = fw->data;
	const u8 enable_crc[] = { 0xae, 0 };
	u8 state[6] = {};
	u32 header, first_end, pos;
	bool cascade;
	int ret;

	if (fw->size < 0x40)
		return -EINVAL;
	header = get_unaligned_le32(data);
	cascade = data[0x20] & BIT(1);
	first_end = cascade ? header / 2 : header;
	/* The stock xun image has no overlays or SPI DMA staging table. */
	if (first_end < 0x30 || header % 16 || first_end % 16 ||
	    header > fw->size || data[0x28] & BIT(4) ||
	    (cascade && (data[0x29] & BIT(0))))
		return -EINVAL;

	ret = nvt_bootloader_reset(ts);
	if (ret)
		return ret;
	ret = nvt_crc_bank(ts, 0x1fb528, 0x1fb518, 0x1fb500, data, data + 0x18);
	if (ret)
		return ret;
	ret = nvt_crc_bank(ts, 0x1fb52c, 0x1fb530, 0x1fb504, data + 12, data + 0x1c);
	if (ret)
		return ret;
	if (cascade) {
		ret = nvt_write_byte(ts, NVT_AUTO_COPY, 0x56);
		if (ret)
			return ret;
	}
	for (pos = 0; pos < 24; pos += 12) {
		ret = nvt_write_segment(ts, fw, get_unaligned_le32(data + pos),
					get_unaligned_le32(data + pos + 4),
					get_unaligned_le32(data + pos + 8));
		if (ret)
			return ret;
	}
	for (pos = 0x30; pos < header; pos += 16) {
		const u8 *segment;

		/* The second cascade header supplies only its last descriptor. */
		if (cascade && pos == first_end)
			pos = header - 16;
		segment = data + pos;
		ret = nvt_write_segment(ts, fw, get_unaligned_le32(segment + 8),
					get_unaligned_le32(segment),
					get_unaligned_le32(segment + 4));
		if (ret)
			return ret;
	}

	if (cascade) {
		for (pos = 0; pos < 200; pos++) {
			ret = nvt_read(ts, NVT_AUTO_COPY, state, 1);
			if (ret)
				return ret;
			if (!state[0])
				break;
			usleep_range(1000, 2000);
		}
		if (pos == 200)
			return dev_err_probe(&ts->spi->dev, -ETIMEDOUT, "cascade copy timed out\n");
	}

	ret = nvt_write(ts, NVT_RESET_STATE, state, sizeof(state));
	if (ret)
		return ret;
	ret = nvt_write(ts, NVT_EVENT + 0x50, enable_crc, sizeof(enable_crc));
	if (ret)
		return ret;
	ret = nvt_write_byte(ts, NVT_BOOT_READY, 1);
	if (ret)
		return ret;
	for (pos = 0; pos < 100; pos++) {
		usleep_range(10000, 12000);
		ret = nvt_read(ts, NVT_RESET_STATE, state, sizeof(state));
		if (ret)
			return ret;
		if (state[0] >= 0xa0 && state[0] <= 0xaf)
			return 0;
	}
	dev_err(&ts->spi->dev, "firmware boot timed out (state %*ph)\n",
		(int)sizeof(state), state);
	return -ETIMEDOUT;
}

static irqreturn_t nvt_irq(int irq, void *data)
{
	struct nvt_ts *ts = data;
	u8 frame[NVT_FRAME];
	u8 checksum = 0;
	bool touched = false;
	unsigned int i;

	if (nvt_read(ts, NVT_EVENT, frame, sizeof(frame)))
		return IRQ_HANDLED;
	for (i = 0; i < 65; i++)
		checksum += frame[i];
	if (checksum)
		return IRQ_HANDLED;

	for (i = 0; i < NVT_TOUCHES; i++) {
		const u8 *point = frame + i * 6;
		unsigned int id = point[0] >> 3;
		unsigned int state = point[0] & 7;
		unsigned int x = get_unaligned_be16(point + 1);
		unsigned int y = get_unaligned_be16(point + 3);

		if (!id || id > NVT_TOUCHES || (state != 1 && state != 2) ||
		    x >= NVT_WIDTH || y >= NVT_HEIGHT)
			continue;
		input_mt_slot(ts->input, id - 1);
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(ts->input, &ts->properties, x, y, true);
		touched = true;
	}
	input_report_key(ts->input, BTN_TOUCH, touched);
	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
	return IRQ_HANDLED;
}

static int nvt_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	const struct firmware *firmware;
	struct nvt_ts *ts;
	struct input_dev *input;
	int irq, ret;

	irq = of_irq_get(dev->of_node, 0);
	if (irq <= 0)
		return dev_err_probe(dev, irq ?: -EINVAL, "cannot map touchscreen interrupt\n");

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->spi = spi;
	ts->tx = devm_kmalloc(dev, NVT_TRANSFER + 1, GFP_KERNEL);
	ts->rx = devm_kmalloc(dev, NVT_FRAME + 2, GFP_KERNEL);
	if (!ts->tx || !ts->rx)
		return -ENOMEM;

	ret = devm_regulator_get_enable(dev, "vcc");
	if (ret)
		return dev_err_probe(dev, ret, "cannot enable touchscreen supply\n");
	ts->reset = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ts->reset))
		return dev_err_probe(dev, PTR_ERR(ts->reset), "cannot acquire reset GPIO\n");

	ret = nvt_check_id(ts);
	if (ret)
		return dev_err_probe(dev, ret, "cannot identify NT36532\n");
	ret = request_firmware(&firmware, NVT_FIRMWARE, dev);
	if (ret)
		return dev_err_probe(dev, ret, "cannot load touchscreen firmware\n");
	ret = nvt_upload(ts, firmware);
	release_firmware(firmware);
	if (ret)
		return dev_err_probe(dev, ret, "cannot start touchscreen firmware\n");

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;
	ts->input = input;
	input->name = "Novatek NT36532 Touchscreen";
	input->id.bustype = BUS_SPI;
	input_set_capability(input, EV_KEY, BTN_TOUCH);
	input_set_abs_params(input, ABS_MT_POSITION_X, 0, NVT_WIDTH - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, NVT_HEIGHT - 1, 0, 0);
	touchscreen_parse_properties(input, true, &ts->properties);
	ret = input_mt_init_slots(input, NVT_TOUCHES, INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (ret)
		return ret;
	ret = input_register_device(input);
	if (ret)
		return ret;
	ret = devm_request_threaded_irq(dev, irq, NULL, nvt_irq,
					IRQF_ONESHOT | IRQF_TRIGGER_RISING, dev_name(dev), ts);
	if (ret)
		return dev_err_probe(dev, ret, "cannot request touchscreen interrupt\n");

	dev_info(dev, "NT36532 touch firmware started\n");
	return 0;
}

static const struct of_device_id nvt_of_match[] = {
	{ .compatible = "novatek,nt36532-xun" },
	{}
};
MODULE_DEVICE_TABLE(of, nvt_of_match);

static const struct spi_device_id nvt_ids[] = {
	{ "nt36532-xun" },
	{}
};
MODULE_DEVICE_TABLE(spi, nvt_ids);

static struct spi_driver nvt_driver = {
	.driver = {
		.name = "nt36532-xun",
		.of_match_table = nvt_of_match,
	},
	.probe = nvt_probe,
	.id_table = nvt_ids,
};
module_spi_driver(nvt_driver);

MODULE_DESCRIPTION("Novatek NT36532 touchscreen driver for Xiaomi Redmi Pad SE");
MODULE_LICENSE("GPL");
MODULE_FIRMWARE(NVT_FIRMWARE);
