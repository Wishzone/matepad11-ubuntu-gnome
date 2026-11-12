/*
 * UPower compatibility shim for the DBY-W09 fuel gauge.
 *
 * Huawei's GEN4 gauge (and the matepad-fg driver) uses negative battery
 * current while *charging*. UPower 1.91's up-device-supply-battery.c forces
 * state=discharging whenever current_now < 0, even if sysfs status=Charging.
 * The kernel fix is preferred; this tiny preload lets UPower consume the
 * stock sign without rebuilding the kernel or boot image.
 *
 * Build: cc -shared -fPIC -O2 -o matepad-upower-sign.so matepad-upower-sign.c -ldl
 * Use:   /etc/systemd/system/upower.service.d/10-matepad-sign.conf
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <string.h>

typedef double (*get_double_fn)(void *device, const char *name);

double
g_udev_device_get_sysfs_attr_as_double_uncached(void *device, const char *name)
{
	static get_double_fn real;
	double value;

	if (!real)
		real = (get_double_fn)dlsym(RTLD_NEXT,
			"g_udev_device_get_sysfs_attr_as_double_uncached");
	if (!real)
		return 0.0;
	value = real(device, name);
	if (name && strcmp(name, "current_now") == 0)
		return fabs(value);
	return value;
}
