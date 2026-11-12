SHELL := /bin/bash
PROJ := $(abspath .)
IMG  := $(shell ls -t $(PROJ)/build/out/ubuntu-26.04-gnome-dby-w09-*.img 2>/dev/null | head -1)

.PHONY: all tools upstream rootfs image kernel test-qemu verify clean-image clean-rootfs

all: image

tools:
	./scripts/prepare-host-tools.sh

upstream:
	./scripts/fetch-upstream.sh

rootfs:
	./scripts/build-rootfs.sh

image:
	./scripts/make-image.sh

kernel:
	./scripts/build-kernel.sh

test-qemu:
	./scripts/test-qemu.sh

verify:
	./scripts/verify-image.sh $(IMG)

clean-image:
	rm -rf build/image-work build/out

clean-rootfs:
	rm -rf build/rootfs
