// SPDX-License-Identifier: GPL-2.0-only
/*
 * SYH62758 LED backlight driver for the Huawei MatePad 11 (DBY-W09).
 *
 * The stock board uses a SYH62758 at I2C 0x2e on bus 11.  Register values
 * follow the stock HarmonyOS hw_syh62758 init sequence.  The backlight IC's
 * EN pin is held high by the always-on bl-en-regulator, so this driver uses
 * that regulator as vcc and only talks to the chip over I2C.
 */

#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>
#include <linux/regulator/consumer.h>

#define SYH62758_REG_LEVEL_LSB	0x10
#define SYH62758_REG_LEVEL_MSB	0x11
#define SYH62758_MAX_BRIGHTNESS	255
#define SYH62758_LEVEL_MIN	8
#define SYH62758_LEVEL_MAX	0xF5C

struct syh62758 {
	struct regmap *regmap;
	struct regulator *vcc;
	bool powered;
};

/* hw_syh62758,backlight_ic_kernel_init_cmd */
static const struct reg_sequence syh62758_init[] = {
	{ 0x01, 0x85 }, { 0xa2, 0x20 }, { 0xa0, 0xff }, { 0xa1, 0xdf },
	{ 0xa3, 0x3e }, { 0xa4, 0x02 }, { 0xa5, 0x10 }, { 0xa6, 0x40 },
	{ 0xa7, 0xf7 }, { 0xa9, 0x80 }, { 0xaa, 0x0f }, { 0xae, 0x0e },
	{ 0x9e, 0x22 }, { 0x16, 0x1f }, { 0x00, 0x00 }, { 0x01, 0x84 },
	{ 0x9e, 0x02 }, { 0x9e, 0x22 },
};

static int syh62758_power(struct syh62758 *chip, bool on)
{
	int ret;

	if (chip->powered == on)
		return 0;

	if (!on) {
		/* If the first write fails, retain powered=true so a later update
		 * can retry the shutdown rather than leaking the regulator ref. */
		ret = regmap_write(chip->regmap, SYH62758_REG_LEVEL_LSB, 0);
		if (ret)
			return ret;
		ret = regmap_write(chip->regmap, SYH62758_REG_LEVEL_MSB, 0);
		if (ret)
			return ret;

		/* Balance the regulator reference acquired in the on path. */
		ret = regulator_disable(chip->vcc);
		if (ret)
			return ret;
		chip->powered = false;
		return 0;
	}

	ret = regulator_enable(chip->vcc);
	if (ret)
		return ret;
	msleep(30);
	ret = regmap_multi_reg_write(chip->regmap, syh62758_init,
				     ARRAY_SIZE(syh62758_init));
	if (ret) {
		regulator_disable(chip->vcc);
		return ret;
	}
	chip->powered = true;
	return 0;
}

/*
 * The LED current is linear in the level, the eye is not.  Use the same
 * CIE 1931 lightness curve as the RT8555 driver so the low end is smooth.
 */
static unsigned int syh62758_level(unsigned int brightness)
{
	u64 lightness = div_u64((u64)brightness << 16,
				SYH62758_MAX_BRIGHTNESS) * 100;
	u64 y;

	if (lightness <= 8ULL << 16) {
		y = DIV_ROUND_CLOSEST_ULL(lightness * 10, 9033);
	} else {
		y = div_u64(lightness + (16ULL << 16), 116);
		y = (y * y * y + (1ULL << 31)) >> 32;
	}
	return SYH62758_LEVEL_MIN +
		DIV_ROUND_CLOSEST_ULL(y * (SYH62758_LEVEL_MAX - SYH62758_LEVEL_MIN),
				      1 << 16);
}

static int syh62758_update_status(struct backlight_device *bl)
{
	struct syh62758 *chip = bl_get_data(bl);
	unsigned int brightness = backlight_get_brightness(bl);
	unsigned int level;
	int ret;

	if (!brightness)
		return syh62758_power(chip, false);

	level = syh62758_level(brightness);
	ret = syh62758_power(chip, true);
	if (ret)
		return ret;
	ret = regmap_write(chip->regmap, SYH62758_REG_LEVEL_LSB, level & 0xff);
	if (ret)
		return ret;
	return regmap_update_bits(chip->regmap, SYH62758_REG_LEVEL_MSB,
				  0x0f, level >> 8);
}

static const struct backlight_ops syh62758_ops = {
	.options = BL_CORE_SUSPENDRESUME,
	.update_status = syh62758_update_status,
};

static const struct regmap_config syh62758_regmap = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = 0xae,
};

static int syh62758_probe(struct i2c_client *client)
{
	struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.max_brightness = SYH62758_MAX_BRIGHTNESS,
		.brightness = 115,
		.scale = BACKLIGHT_SCALE_NON_LINEAR,
		.power = BACKLIGHT_POWER_ON,
	};
	struct device *dev = &client->dev;
	struct backlight_device *bl;
	struct syh62758 *chip;

	chip = devm_kzalloc(dev, sizeof(*chip), GFP_KERNEL);
	if (!chip)
		return -ENOMEM;
	chip->regmap = devm_regmap_init_i2c(client, &syh62758_regmap);
	if (IS_ERR(chip->regmap))
		return PTR_ERR(chip->regmap);
	chip->vcc = devm_regulator_get(dev, "vcc");
	if (IS_ERR(chip->vcc))
		return dev_err_probe(dev, PTR_ERR(chip->vcc), "vcc\n");

	bl = devm_backlight_device_register(dev, "panel0-backlight", dev, chip,
					    &syh62758_ops, &props);
	if (IS_ERR(bl))
		return dev_err_probe(dev, PTR_ERR(bl), "register backlight\n");
	i2c_set_clientdata(client, bl);
	return 0;
}

static const struct of_device_id syh62758_of_match[] = {
	{ .compatible = "syh,syh62758" },
	{ }
};
MODULE_DEVICE_TABLE(of, syh62758_of_match);

static struct i2c_driver syh62758_driver = {
	.driver = {
		.name = "syh62758-backlight",
		.of_match_table = syh62758_of_match,
	},
	.probe = syh62758_probe,
};
module_i2c_driver(syh62758_driver);

MODULE_DESCRIPTION("SYH62758 backlight driver");
MODULE_LICENSE("GPL");
