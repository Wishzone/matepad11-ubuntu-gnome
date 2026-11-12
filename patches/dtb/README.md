# Boot DTB: minimal deltas over the stock DBY-W09 DTB

The boot bundle uses the tablet's **stock** DTB with a small set of additions.
Do not replace it with the whole front-camera DTB: that DTB was built from a
different base and dropped the panel rotation/backlight/Bluetooth properties.

`scripts/patch-dtb.sh` covers the panel rotation and the SYH62758 backlight.
The following nodes are added by the tested 2026-11-12 boot bundle.

## 1. Front camera `camera@31`

Inside `/soc@0/cci@ac50000/i2c-bus@0` (the empty bus with
`phandle = <0x1e3>`):

```dts
camera@31 {
    compatible = "galaxycore,gc08a3";
    reg = <0x31>;
    reset-gpios = <0x3b 0x4e 0x01>;      /* tlmm GPIO 78, active low */
    pinctrl-names = "default", "suspend";
    pinctrl-0 = <0xe6>;                  /* cam2-default-state */
    pinctrl-1 = <0xe7>;                  /* cam2-suspend-state */
    clocks = <0xd9 0x4d>;                /* camcc MCLK2 */
    assigned-clocks = <0xd9 0x4d>;
    assigned-clock-rates = <0x16e3600>;   /* 24 MHz */
    avdd-supply = <0xdf>;                /* cam_avdd_2p8 */
    dvdd-supply = <0xe8>;                /* cam_front_dvdd */
    dovdd-supply = <0xde>;               /* PM8150L L5 */
    rotation = <0x10e>;                  /* 270 */
    orientation = <0x00>;                /* front facing */
    port {
        endpoint {
            link-frequencies = <0 0x277b6c00 0 0xa715700>;
            data-lanes = <0x01 0x02>;
            remote-endpoint = <0x990>;
            phandle = <0xeb>;
        };
    };
};
```

## 2. CAMSS `port@2`

Inside `/soc@0/camss@ac6a000/ports`, before `port@3`:

```dts
port@2 {
    reg = <0x02>;
    endpoint {
        clock-lanes = <0x07>;
        data-lanes = <0x00 0x01>;
        remote-endpoint = <0xeb>;
        phandle = <0x990>;
    };
};
```

## 3. Front rails pinctrl

Inside `/soc@0/pinctrl@f100000`, before `cci0-default-state`:

```dts
cam-front-rails-state {
    phandle = <0x900>;
    pins = "gpio26", "gpio153";
    function = "gpio";
    drive-strength = <0x02>;
    bias-disable;
};
```

Add `regulator-always-on; pinctrl-names = "default";
pinctrl-0 = <0x900>;` to `regulator-cam-avdd` (phandle `0xdf`) and
`regulator-cam-front-dvdd` (phandle `0xe8`).

## 4. Keyboard dock switch

```dts
keyboard-dock-sensor {
    compatible = "gpio-keys";
    label = "matepad-keyboard-dock";
    status = "disabled";
    ...
};
```

The kernel `huawei-thp-lite` driver registers a permanent
`matepad-tabletmode` switch instead, so the magnetic keyboard does not turn
auto-rotation off. Do **not** re-enable this node together with the kernel
switch, or Mutter sees two tablet-mode switches.

## 5. RTC (PM8150 SDAM offset)

Inside the PMIC node that contains `rtc@6000`, before it:

```dts
sdam@b100 {
    compatible = "qcom,spmi-sdam";
    reg = <0xb100 0x100>;
    #address-cells = <0x01>;
    #size-cells = <0x01>;

    rtc_offset@7c {
        reg = <0x7c 0x04>;
        phandle = <0x7f0>;
    };
};
```

and add to `rtc@6000`:

```dts
nvmem-cells = <0x7f0>;
nvmem-cell-names = "offset";
```

## 6. Bluetooth address

Leave the stock `local-bd-address = [00 00 00 00 00 00]`. The installer
(`dby-w09-installer`) or `upstream/linux-dby-w09/set_bd_address.py` writes the
tablet's own address from `/etc/matepad/bt-mac`. **Never commit a device MAC.**

## Phandle warning

The numbers above are the phandles in the tested boot DTB. If you start from a
different DTB, resolve each reference by node path (`&tlmm`, `&camcc`,
`&vreg_cam_avdd_2p8`, …) instead of copying the numbers. `dtc` reports
`duplicate phandle` if an added number is already used.
