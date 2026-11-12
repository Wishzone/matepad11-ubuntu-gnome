# Audio: q6asm-dai S16 / 4-channel fix

## Symptom

The ALSA card and the `q6asm` front ends existed, but WirePlumber never
created a hardware sink; only "Dummy Output" was available. The ACP probe
opened `hw:0,0` with 8 channels/S24, while the SM8250 backend only supports
4 channels/S16, so `snd_pcm_hw_params` returned `EINVAL`.

## Fix

`patches/sound/q6asm-dai-s16-4ch.patch` changes the playback front end:

- `.formats = SNDRV_PCM_FMTBIT_S16_LE` (no S24).
- `.channels_max = 4`.
- the same two values in the `Q6ASM_FEDAI_DRIVER` macro.

The capture side keeps S16/S24 and 4 channels.

## Apply

```bash
cd "$KSRC"                      # Linux 7.0.14-dby-w09 source
patch -p1 < /path/to/patches/sound/q6asm-dai-s16-4ch.patch
make -C "$KSRC" O="$OUT" ARCH=arm64 \
     sound/soc/qcom/qdsp6/q6asm-dai.ko
```

Install the module into `/lib/modules/7.0.14-dby-w09/...`, run `depmod -a`
and reboot. The hardware sink appears as `内置音频 Speakers`; set its
volume to 1.0 (the UCM route maps the four speakers).

The patch is generated against the vanilla Linux 7.0.14 file
(`sound/soc/qcom/qdsp6/q6asm-dai.c`); it does not depend on the DBY board
patches.
