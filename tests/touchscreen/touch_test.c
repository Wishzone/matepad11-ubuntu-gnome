// SPDX-License-Identifier: GPL-2.0
/* Inject type-A/type-B touchscreen gestures for right-click daemon tests. */
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

static int fd;
static int type_b;
static void emit(int type, int code, int value) {
	struct input_event ev;
	memset(&ev, 0, sizeof(ev));
	ev.type = type; ev.code = code; ev.value = value;
	if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) perror("write");
}
static void slot_state(int slot, int tracking_id, int x, int y) {
	emit(EV_ABS, ABS_MT_SLOT, slot);
	emit(EV_ABS, ABS_MT_TRACKING_ID, tracking_id);
	if (tracking_id >= 0) {
		emit(EV_ABS, ABS_MT_POSITION_X, x);
		emit(EV_ABS, ABS_MT_POSITION_Y, y);
		emit(EV_ABS, ABS_MT_PRESSURE, 40);
	}
}
static void frame(int x1, int y1, int x2, int y2, int down) {
	if (down) {
		emit(EV_ABS, ABS_MT_POSITION_X, x1);
		emit(EV_ABS, ABS_MT_POSITION_Y, y1);
		emit(EV_ABS, ABS_MT_PRESSURE, 40);
		emit(EV_ABS, ABS_MT_TRACKING_ID, 1);
		emit(EV_SYN, SYN_MT_REPORT, 0);
		emit(EV_ABS, ABS_MT_POSITION_X, x2);
		emit(EV_ABS, ABS_MT_POSITION_Y, y2);
		emit(EV_ABS, ABS_MT_PRESSURE, 40);
		emit(EV_ABS, ABS_MT_TRACKING_ID, 2);
		emit(EV_SYN, SYN_MT_REPORT, 0);
		emit(EV_KEY, BTN_TOUCH, 1);
	} else {
		emit(EV_SYN, SYN_MT_REPORT, 0);
		emit(EV_KEY, BTN_TOUCH, 0);
	}
	emit(EV_SYN, SYN_REPORT, 0);
}
static void frame_b_two_at(int down, int x1, int x2) {
	if (down) {
		slot_state(0, 1, x1, 5000);
		slot_state(1, 2, x2, 5000);
		emit(EV_KEY, BTN_TOUCH, 1);
	} else {
		slot_state(0, -1, 0, 0);
		slot_state(1, -1, 0, 0);
		emit(EV_KEY, BTN_TOUCH, 0);
	}
	emit(EV_SYN, SYN_REPORT, 0);
}
static void frame_b_two(int down) { frame_b_two_at(down, 3000, 5000); }
static void frame_b_single(int down) {
	if (down) {
		slot_state(0, 3, 4000, 6000);
		emit(EV_KEY, BTN_TOUCH, 1);
	} else {
		slot_state(0, -1, 0, 0);
		emit(EV_KEY, BTN_TOUCH, 0);
	}
	emit(EV_SYN, SYN_REPORT, 0);
}
static void frame_a_single(int down) {
	if (down) {
		emit(EV_ABS, ABS_MT_POSITION_X, 4000);
		emit(EV_ABS, ABS_MT_POSITION_Y, 6000);
		emit(EV_ABS, ABS_MT_PRESSURE, 40);
		emit(EV_ABS, ABS_MT_TRACKING_ID, 3);
		emit(EV_SYN, SYN_MT_REPORT, 0);
		emit(EV_KEY, BTN_TOUCH, 1);
	} else {
		emit(EV_SYN, SYN_MT_REPORT, 0);
		emit(EV_KEY, BTN_TOUCH, 0);
	}
	emit(EV_SYN, SYN_REPORT, 0);
}
static void find_node(char *out, size_t n) {
	for (int i = 0; i < 64; i++) {
		char p[128], b[128]; FILE *f;
		snprintf(p, sizeof(p), "/sys/class/input/event%d/device/name", i);
		f = fopen(p, "r"); if (!f) continue;
		if (fgets(b, sizeof(b), f) && strstr(b, "Virtual Test Touchscreen")) {
			fclose(f); snprintf(out, n, "/dev/input/event%d", i); return;
		}
		fclose(f);
	}
	out[0] = 0;
}
int main(int argc, char **argv) {
	struct uinput_user_dev u; char node[64];
	int long_press = 0;
	int scroll = 0;
	int single_tap = 0;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--type-b")) type_b = 1;
		else if (!strcmp(argv[i], "--long-press")) long_press = 1;
		else if (!strcmp(argv[i], "--scroll")) scroll = 1;
		else if (!strcmp(argv[i], "--single-tap")) single_tap = 1;
		else {
			fprintf(stderr, "Usage: %s [--type-b] [--single-tap] [--long-press] [--scroll]\n", argv[0]);
			return 1;
		}
	}
	fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0) { perror("uinput"); return 1; }
	ioctl(fd, UI_SET_EVBIT, EV_SYN);
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);
	ioctl(fd, UI_SET_EVBIT, EV_ABS);
	ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_X);
	ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_Y);
	ioctl(fd, UI_SET_ABSBIT, ABS_MT_PRESSURE);
	ioctl(fd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID);
	if (type_b)
		ioctl(fd, UI_SET_ABSBIT, ABS_MT_SLOT);
	ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);
	memset(&u, 0, sizeof(u));
	snprintf(u.name, sizeof(u.name), "Virtual Test Touchscreen");
	u.id.bustype = BUS_USB; u.id.vendor = 0x1209; u.id.product = 0x0002;
	u.absmin[ABS_MT_POSITION_X] = 0; u.absmax[ABS_MT_POSITION_X] = 12799;
	u.absmin[ABS_MT_POSITION_Y] = 0; u.absmax[ABS_MT_POSITION_Y] = 20479;
	u.absmin[ABS_MT_PRESSURE] = 0; u.absmax[ABS_MT_PRESSURE] = 100;
	u.absmin[ABS_MT_TRACKING_ID] = 0; u.absmax[ABS_MT_TRACKING_ID] = 9;
	if (type_b) {
		u.absmin[ABS_MT_SLOT] = 0;
		u.absmax[ABS_MT_SLOT] = 9;
	}
	if (write(fd, &u, sizeof(u)) != sizeof(u)) { perror("setup"); return 1; }
	if (ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }
	sleep(1);
	find_node(node, sizeof(node));
	printf("TEST_NODE=%s\n", node); fflush(stdout);
	sleep(3);
	for (int i = 0; i < 5; i++) {
		if (type_b)
			frame_b_two(1);
		else
			frame(3000, 5000, 5000, 5000, 1);
		usleep(80000);
		if (type_b)
			frame_b_two(0);
		else
			frame(0, 0, 0, 0, 0);
		usleep(1000000);
	}
	if (single_tap) {
		if (type_b)
			frame_b_single(1);
		else
			frame_a_single(1);
		usleep(50000);
		if (type_b)
			frame_b_single(0);
		else
			frame_a_single(0);
		usleep(300000);
	}
	if (long_press) {
		if (type_b)
			frame_b_single(1);
		else
			frame_a_single(1);
		sleep(1);
		puts("LONG_PRESS_RELEASE");
		fflush(stdout);
		usleep(100000);
		if (type_b)
			frame_b_single(0);
		else
			frame_a_single(0);
	}
	if (scroll) {
		if (type_b)
			frame_b_two_at(1, 3000, 5000);
		else
			frame(3000, 5000, 5000, 5000, 1);
		usleep(80000);
		for (int i = 1; i <= 8; i++) {
			if (type_b)
				frame_b_two_at(1, 3000 + i * 250, 5000 + i * 250);
			else
				frame(3000 + i * 250, 5000, 5000 + i * 250, 5000, 1);
			usleep(80000);
		}
		if (type_b)
			frame_b_two_at(0, 0, 0);
		else
			frame(0, 0, 0, 0, 0);
	}
	usleep(500000);
	ioctl(fd, UI_DEV_DESTROY);
	close(fd);
	return 0;
}
