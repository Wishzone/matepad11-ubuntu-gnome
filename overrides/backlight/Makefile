# Build syh62758_bl.ko against the DBY-W09 kernel tree.
#
#   make KDIR=/path/to/linux-7.0.14
#
# The module in this directory was built for 7.0.14-dby-w09. Rebuild it if the
# kernel release changes; the vermagic must match exactly.
obj-m += syh62758_bl.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
