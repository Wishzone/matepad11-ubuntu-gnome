// SPDX-License-Identifier: GPL-2.0
/*
 * matepad-touch-rightclick - MatePad touch gestures for DBY-W09
 *
 * The Huawei touchscreen is an MT device ("input_mt_wrapper",
 * /dev/input/event2). Mutter maps its native portrait coordinates to the
 * rotated logical output with:
 *
 *   Rotate270:
 *     x = (raw_y / raw_ymax) * logical_width
 *     y = (1 - raw_x / raw_xmax) * logical_height
 *
 * This daemon watches the touchscreen read-only and provides two-finger-tap
 * and long-press right clicks plus two-finger wheel scrolling through a
 * virtual uinput pointer. It accepts both Type-A and Type-B touch reports.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define MAX_CONTACTS 10
#define DEFAULT_TOUCH_NAME "input_mt_wrapper"
#define DEFAULT_WIDTH 1280
#define DEFAULT_HEIGHT 800
#define DEFAULT_ROTATION 270
#define DEFAULT_TAP_MS 350
#define DEFAULT_LONG_PRESS_MS 550
#define DEFAULT_SCROLL_STEP 40
#define DEFAULT_MOVE 600
#define SINGLE_TOUCH_DELAY_MS 180

struct config {
	char touch_name[64];
	char device[64];
	int width;
	int height;
	int rotation;
	int tap_ms;
	int long_press_ms;
	int scroll_step;
	int move_threshold;
	int debug;
	int dry_run;
	char rotation_file[256];
};

static volatile sig_atomic_t running = 1;

static void stop(int sig)
{
	(void)sig;
	running = 0;
}

static uint64_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void load_config(struct config *cfg, const char *path)
{
	FILE *f;
	char line[256];

	f = fopen(path, "r");
	if (!f)
		return;

	while (fgets(line, sizeof(line), f)) {
		int v;
		char s[64];

		if (sscanf(line, "SCREEN_WIDTH=%d", &v) == 1)
			cfg->width = v;
		else if (sscanf(line, "SCREEN_HEIGHT=%d", &v) == 1)
			cfg->height = v;
		else if (sscanf(line, "ROTATION=%d", &v) == 1)
			cfg->rotation = v;
		else if (sscanf(line, "TAP_MS=%d", &v) == 1)
			cfg->tap_ms = v;
		else if (sscanf(line, "LONG_PRESS_MS=%d", &v) == 1)
			cfg->long_press_ms = v;
		else if (sscanf(line, "SCROLL_STEP=%d", &v) == 1)
			cfg->scroll_step = v;
		else if (sscanf(line, "MOVE_THRESHOLD=%d", &v) == 1)
			cfg->move_threshold = v;
		else if (sscanf(line, "TOUCH_NAME=%63s", s) == 1)
			snprintf(cfg->touch_name, sizeof(cfg->touch_name), "%s", s);
		else if (sscanf(line, "ROTATION_FILE=%255s", cfg->rotation_file) == 1)
			continue;
	}
	fclose(f);
}

static int read_rotation_index(const struct config *cfg, int *index)
{
	FILE *f;
	int r;

	if (!cfg->rotation_file[0])
		return -1;
	f = fopen(cfg->rotation_file, "r");
	if (!f)
		return -1;
	r = fscanf(f, "%d", index);
	fclose(f);
	if (r != 1 || *index < 0 || *index > 3)
		return -1;
	return 0;
}

static bool orientation_is_portrait(int rotation_index)
{
	return rotation_index == 0 || rotation_index == 2;
}

static int find_touch_device(const char *name, char *out, size_t out_len)
{
	int i;

	for (i = 0; i < 64; i++) {
		char path[128], buf[128];
		FILE *f;
		size_t n;

		snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (!fgets(buf, sizeof(buf), f)) {
			fclose(f);
			continue;
		}
		fclose(f);
		n = strlen(buf);
		while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
			buf[--n] = 0;
		if (strcmp(buf, name) == 0) {
			snprintf(out, out_len, "/dev/input/event%d", i);
			return 0;
		}
	}
	return -1;
}

static int uinput_create(const struct config *cfg)
{
	int fd;
	struct uinput_user_dev u;

	fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0) {
		perror("open /dev/uinput");
		return -1;
	}

	ioctl(fd, UI_SET_EVBIT, EV_SYN);
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
	ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT);
	ioctl(fd, UI_SET_KEYBIT, BTN_MIDDLE);
	ioctl(fd, UI_SET_EVBIT, EV_REL);
	ioctl(fd, UI_SET_RELBIT, REL_WHEEL);
	ioctl(fd, UI_SET_RELBIT, REL_HWHEEL);
	ioctl(fd, UI_SET_EVBIT, EV_ABS);
	ioctl(fd, UI_SET_ABSBIT, ABS_X);
	ioctl(fd, UI_SET_ABSBIT, ABS_Y);
	ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_POINTER);

	memset(&u, 0, sizeof(u));
	snprintf(u.name, sizeof(u.name), "MatePad Touch Right Click");
	u.id.bustype = BUS_USB;
	u.id.vendor = 0x1209;
	u.id.product = 0x0001;
	u.id.version = 1;
	u.absmin[ABS_X] = 0;
	u.absmax[ABS_X] = cfg->width - 1;
	u.absmin[ABS_Y] = 0;
	u.absmax[ABS_Y] = cfg->height - 1;

	if (write(fd, &u, sizeof(u)) != sizeof(u)) {
		perror("uinput write");
		close(fd);
		return -1;
	}
	if (ioctl(fd, UI_DEV_CREATE) < 0) {
		perror("UI_DEV_CREATE");
		close(fd);
		return -1;
	}
	return fd;
}

static void emit(int fd, int type, int code, int value)
{
	struct input_event ev;
	int ret;

	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.code = code;
	ev.value = value;
	ret = write(fd, &ev, sizeof(ev));
	(void)ret;
}

static void right_click(int fd, int x, int y)
{
	if (fd < 0)
		return;
	emit(fd, EV_ABS, ABS_X, x);
	emit(fd, EV_ABS, ABS_Y, y);
	emit(fd, EV_SYN, SYN_REPORT, 0);
	usleep(30000);
	emit(fd, EV_KEY, BTN_RIGHT, 1);
	emit(fd, EV_SYN, SYN_REPORT, 0);
	usleep(30000);
	emit(fd, EV_KEY, BTN_RIGHT, 0);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static void scroll_wheel(int fd, int x, int y, bool horizontal, int direction)
{
	if (fd < 0) {
		fprintf(stderr, "scroll %s %d at %d,%d\n",
			horizontal ? "horizontal" : "vertical", direction, x, y);
		return;
	}
	emit(fd, EV_ABS, ABS_X, x);
	emit(fd, EV_ABS, ABS_Y, y);
	emit(fd, EV_REL, horizontal ? REL_HWHEEL : REL_WHEEL, direction);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static void pointer_position(int fd, int x, int y)
{
	if (fd < 0)
		return;
	emit(fd, EV_ABS, ABS_X, x);
	emit(fd, EV_ABS, ABS_Y, y);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static void pointer_left(int fd, int x, int y, bool down)
{
	if (fd < 0) {
		fprintf(stderr, "pointer-left %s at %d,%d\n",
			down ? "down" : "up", x, y);
		return;
	}
	emit(fd, EV_ABS, ABS_X, x);
	emit(fd, EV_ABS, ABS_Y, y);
	emit(fd, EV_KEY, BTN_LEFT, down);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static void pointer_tap(int fd, int x, int y)
{
	pointer_left(fd, x, y, true);
	pointer_left(fd, x, y, false);
}

static void map_point(const struct config *cfg, int x, int y,
		      int xmax, int ymax, int *lx, int *ly)
{
	double u = xmax > 0 ? (double)x / xmax : 0.0;
	double v = ymax > 0 ? (double)y / ymax : 0.0;
	double nx, ny;
	switch (cfg->rotation) {
	case 90:
		nx = 1.0 - v;
		ny = u;
		break;
	case 180:
		nx = 1.0 - u;
		ny = 1.0 - v;
		break;
	case 270:
		nx = v;
		ny = 1.0 - u;
		break;
	case 0:
	default:
		nx = u;
		ny = v;
		break;
	}

	*lx = (int)lround(nx * (cfg->width - 1));
	*ly = (int)lround(ny * (cfg->height - 1));
	if (*lx < 0)
		*lx = 0;
	if (*lx >= cfg->width)
		*lx = cfg->width - 1;
	if (*ly < 0)
		*ly = 0;
	if (*ly >= cfg->height)
		*ly = cfg->height - 1;
}

struct contact {
	int x;
	int y;
	int pressure;
	bool has_x;
	bool has_y;
};

struct gesture {
	bool down;
	bool two_seen;
	bool three_seen;
	bool moved;
	bool single_seen;
	bool single_moved;
	bool single_pending;
	bool pointer_left_down;
	bool long_press_sent;
	bool long_press_pending;
	bool scrolling;
	bool pinching;
	uint64_t start_ms;
	uint64_t two_start_ms;
	uint64_t last_two_ms;
	uint64_t last_click_ms;
	int max_contacts;
	double two_cx;
	double two_cy;
	double two_spread;
	double last_cx;
	double last_cy;
	int single_start_x;
	int single_start_y;
	int single_x;
	int single_y;
	int last_logical_x;
	int last_logical_y;
	int scroll_remainder_x;
	int scroll_remainder_y;
};

static void reset_gesture(struct gesture *g)
{
	uint64_t last_click = g->last_click_ms;

	memset(g, 0, sizeof(*g));
	g->last_click_ms = last_click;
}

static int apply_orientation(struct config *cfg, int *ufd, int *rotation_index,
			    struct gesture *g, int next_index)
{
	if (next_index == *rotation_index)
		return 0;

	if (orientation_is_portrait(next_index) !=
	    orientation_is_portrait(*rotation_index)) {
		int width = cfg->width;
		cfg->width = cfg->height;
		cfg->height = width;
	}
	cfg->rotation = next_index * 90;
	*rotation_index = next_index;
	reset_gesture(g);
	if (cfg->dry_run) {
		fprintf(stderr,
			"orientation changed: %d degrees, logical screen=%dx%d\n",
			cfg->rotation, cfg->width, cfg->height);
		return 1;
	}

	if (*ufd >= 0) {
		ioctl(*ufd, UI_DEV_DESTROY);
		close(*ufd);
		*ufd = -1;
	}
	*ufd = uinput_create(cfg);
	if (*ufd < 0)
		return -1;
	fprintf(stderr,
		"orientation changed: %d degrees, logical screen=%dx%d\n",
		cfg->rotation, cfg->width, cfg->height);
	return 1;
}

static void process_long_press(const struct config *cfg, struct gesture *g,
			       uint64_t now)
{
	if (!g->down || !g->single_seen || g->long_press_sent ||
	    g->long_press_pending ||
	    g->single_moved || g->two_seen || g->three_seen ||
	    g->max_contacts != 1 ||
	    now - g->start_ms < (uint64_t)cfg->long_press_ms)
		return;

	/* Defer the synthetic mouse click until touch-up. Emitting BTN_RIGHT
	 * while the touchscreen still owns this contact races GTK/GNOME's native
	 * touch long-press handling (notably on desktop icons). */
	g->long_press_pending = true;
}

static void process_single_touch(const struct config *cfg, int ufd,
				struct gesture *g, uint64_t now,
				int xmax, int ymax)
{
	int lx, ly;

	if (!g->down || !g->single_seen || g->two_seen || g->three_seen)
		return;

	map_point(cfg, g->single_x, g->single_y, xmax, ymax, &lx, &ly);
	if (g->pointer_left_down) {
		pointer_position(ufd, lx, ly);
		return;
	}
	if (g->single_pending && now - g->start_ms >= SINGLE_TOUCH_DELAY_MS) {
		pointer_left(ufd, lx, ly, true);
		g->single_pending = false;
		g->pointer_left_down = true;
	}
}

static void process_frame(const struct config *cfg, int ufd,
			  struct gesture *g, struct contact *c, int n,
			  uint64_t now, int xmax, int ymax)
{
	if (n > 0) {
		if (!g->down) {
			reset_gesture(g);
			g->down = true;
			g->start_ms = now;
		}
		if (n > g->max_contacts)
			g->max_contacts = n;
		if (n > 1) {
			g->single_pending = false;
			g->long_press_pending = false;
			if (g->pointer_left_down) {
				pointer_left(ufd, g->last_logical_x,
					     g->last_logical_y, false);
				g->pointer_left_down = false;
			}
		}
		if (n > 2) {
			g->three_seen = true;
			g->pinching = true;
			g->moved = true;
		}

		if (n == 1 && !g->two_seen && !g->three_seen) {
			if (!g->single_seen) {
				g->single_seen = true;
				g->single_start_x = c[0].x;
				g->single_start_y = c[0].y;
				g->single_pending = true;
			} else if (abs(c[0].x - g->single_start_x) > cfg->move_threshold ||
				   abs(c[0].y - g->single_start_y) > cfg->move_threshold) {
				g->single_moved = true;
				g->single_pending = false;
				g->long_press_pending = false;
				if (!g->pointer_left_down) {
					int lx, ly;

					map_point(cfg, c[0].x, c[0].y, xmax, ymax,
						  &lx, &ly);
					pointer_left(ufd, lx, ly, true);
					g->pointer_left_down = true;
				}
			}
			g->single_x = c[0].x;
			g->single_y = c[0].y;
			map_point(cfg, g->single_x, g->single_y, xmax, ymax,
				  &g->last_logical_x, &g->last_logical_y);
			process_single_touch(cfg, ufd, g, now, xmax, ymax);
			process_long_press(cfg, g, now);
		}

		if (n == 2) {
			double cx = (c[0].x + c[1].x) / 2.0;
			double cy = (c[0].y + c[1].y) / 2.0;
			double spread = hypot((double)c[0].x - c[1].x,
					      (double)c[0].y - c[1].y);
			int logical_x, logical_y;

			map_point(cfg, (int)lround(cx), (int)lround(cy),
				  xmax, ymax, &logical_x, &logical_y);

			if (!g->two_seen) {
				g->two_seen = true;
				g->two_start_ms = now;
				g->two_cx = cx;
				g->two_cy = cy;
				g->two_spread = spread;
				g->last_logical_x = logical_x;
				g->last_logical_y = logical_y;
			} else {
				if (fabs(spread - g->two_spread) > cfg->move_threshold) {
					g->pinching = true;
					g->moved = true;
				}
				if (!g->pinching &&
				    (fabs(cx - g->two_cx) > cfg->move_threshold ||
				     fabs(cy - g->two_cy) > cfg->move_threshold)) {
					g->scrolling = true;
					g->moved = true;
				}
				if (g->scrolling && !g->pinching) {
					g->scroll_remainder_x += logical_x - g->last_logical_x;
					g->scroll_remainder_y += logical_y - g->last_logical_y;
					while (g->scroll_remainder_y <= -cfg->scroll_step) {
						scroll_wheel(ufd, logical_x, logical_y, false, -1);
						g->scroll_remainder_y += cfg->scroll_step;
					}
					while (g->scroll_remainder_y >= cfg->scroll_step) {
						scroll_wheel(ufd, logical_x, logical_y, false, 1);
						g->scroll_remainder_y -= cfg->scroll_step;
					}
					while (g->scroll_remainder_x <= -cfg->scroll_step) {
						scroll_wheel(ufd, logical_x, logical_y, true, -1);
						g->scroll_remainder_x += cfg->scroll_step;
					}
					while (g->scroll_remainder_x >= cfg->scroll_step) {
						scroll_wheel(ufd, logical_x, logical_y, true, 1);
						g->scroll_remainder_x -= cfg->scroll_step;
					}
				}
				g->last_logical_x = logical_x;
				g->last_logical_y = logical_y;
			}
			g->last_two_ms = now;
			g->last_cx = cx;
			g->last_cy = cy;
		} else if (n == 1 && g->two_seen &&
			   now - g->last_two_ms > 120) {
			g->moved = true;
		}
		return;
	}

	if (!g->down)
		return;

	if (g->single_pending && g->single_seen && !g->two_seen &&
	    !g->three_seen && !g->single_moved) {
		int lx, ly;

		map_point(cfg, g->single_x, g->single_y, xmax, ymax, &lx, &ly);
		pointer_tap(ufd, lx, ly);
		g->single_pending = false;
	}
	if (g->pointer_left_down) {
		pointer_left(ufd, g->last_logical_x, g->last_logical_y, false);
		g->pointer_left_down = false;
	}

	if (g->long_press_pending && !g->single_moved) {
		int lx, ly;

		map_point(cfg, g->single_x, g->single_y, xmax, ymax, &lx, &ly);
		fprintf(stderr, "right-click at %d,%d (long press)\n", lx, ly);
		right_click(ufd, lx, ly);
		g->long_press_sent = true;
		g->last_click_ms = now;
	}

	{
		uint64_t duration = now - g->start_ms;
		uint64_t tail = g->last_two_ms ? now - g->last_two_ms : 0;
		bool ok = g->two_seen && !g->three_seen && !g->moved &&
			  !g->long_press_sent &&
			  g->max_contacts == 2 &&
			  duration >= 30 && duration <= (uint64_t)cfg->tap_ms &&
			  tail <= 120 &&
			  now - g->last_click_ms > 400;

		if (ok) {
			int lx, ly;

			map_point(cfg, (int)lround(g->last_cx),
				  (int)lround(g->last_cy), xmax, ymax, &lx, &ly);
			fprintf(stderr,
				"right-click at %d,%d (two-finger tap)\n", lx, ly);
			if (cfg->debug)
				fprintf(stderr,
					"  raw=(%.0f,%.0f) duration=%llums\n",
					g->last_cx, g->last_cy,
					(unsigned long long)duration);
			right_click(ufd, lx, ly);
			g->last_click_ms = now;
		} else if (cfg->debug) {
			fprintf(stderr,
				"ignored frame: two=%d three=%d moved=%d max=%d dur=%llums tail=%llums\n",
				g->two_seen, g->three_seen, g->moved,
				g->max_contacts,
				(unsigned long long)duration,
				(unsigned long long)tail);
		}
	}
	g->down = false;
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"Usage: %s [--device PATH] [--config PATH] [--debug] [--dry-run]\n", argv0);
}

int main(int argc, char **argv)
{
	struct config cfg = {
		.touch_name = DEFAULT_TOUCH_NAME,
		.width = DEFAULT_WIDTH,
		.height = DEFAULT_HEIGHT,
		.rotation = DEFAULT_ROTATION,
		.tap_ms = DEFAULT_TAP_MS,
		.long_press_ms = DEFAULT_LONG_PRESS_MS,
		.scroll_step = DEFAULT_SCROLL_STEP,
		.move_threshold = DEFAULT_MOVE,
	};
	const char *config_path = "/etc/matepad-touch-rightclick.conf";
	const char *device_override = NULL;
	int tfd, ufd;
	int xmax = 12799, ymax = 20479;
	struct input_absinfo ai;
	struct input_absinfo slot_info;
	struct gesture g = { 0 };
	struct contact cur, contacts[MAX_CONTACTS];
	struct contact type_b_contacts[MAX_CONTACTS] = { 0 };
	bool type_b_active[MAX_CONTACTS] = { 0 };
	unsigned char abs_bits[(ABS_MAX + 8) / 8] = { 0 };
	struct pollfd pfd;
	int ncontacts = 0;
	int current_slot = 0;
	bool type_b = false;
	bool suppress_until_lift = false;
	int rotation_index;
	uint64_t next_rotation_check = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--device") == 0 && i + 1 < argc)
			device_override = argv[++i];
		else if (strcmp(argv[i], "--config") == 0 && i + 1 < argc)
			config_path = argv[++i];
		else if (strcmp(argv[i], "--debug") == 0)
			cfg.debug = 1;
		else if (strcmp(argv[i], "--dry-run") == 0)
			cfg.dry_run = 1;
		else {
			usage(argv[0]);
			return 1;
		}
	}

	load_config(&cfg, config_path);
	if (cfg.width < 2 || cfg.height < 2 || cfg.rotation < 0 ||
	    cfg.rotation > 270 || cfg.rotation % 90 || cfg.tap_ms < 30 ||
	    cfg.long_press_ms < 100 || cfg.scroll_step < 1 ||
	    cfg.move_threshold < 0) {
		fprintf(stderr, "invalid gesture configuration\n");
		return 1;
	}
	rotation_index = cfg.rotation / 90;
	{
		int file_rotation;
		if (!read_rotation_index(&cfg, &file_rotation)) {
			if (orientation_is_portrait(rotation_index) !=
			    orientation_is_portrait(file_rotation)) {
				int width = cfg.width;
				cfg.width = cfg.height;
				cfg.height = width;
			}
			rotation_index = file_rotation;
			cfg.rotation = file_rotation * 90;
		}
	}
	if (device_override)
		snprintf(cfg.device, sizeof(cfg.device), "%s", device_override);
	else if (find_touch_device(cfg.touch_name, cfg.device, sizeof(cfg.device)) < 0) {
		fprintf(stderr, "touchscreen '%s' not found\n", cfg.touch_name);
		return 1;
	}

	tfd = open(cfg.device, O_RDONLY);
	if (tfd < 0) {
		perror(cfg.device);
		return 1;
	}
	if (ioctl(tfd, EVIOCGABS(ABS_MT_POSITION_X), &ai) == 0 && ai.maximum > 0)
		xmax = ai.maximum;
	if (ioctl(tfd, EVIOCGABS(ABS_MT_POSITION_Y), &ai) == 0 && ai.maximum > 0)
		ymax = ai.maximum;
	/* Type-B devices may omit ABS_MT_SLOT 0 because it is already selected. */
		if (ioctl(tfd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits) >= 0 &&
	    (abs_bits[ABS_MT_SLOT / 8] & (1U << (ABS_MT_SLOT % 8))) &&
	    ioctl(tfd, EVIOCGABS(ABS_MT_SLOT), &slot_info) == 0) {
		type_b = true;
		if (slot_info.minimum != 0 || slot_info.maximum >= MAX_CONTACTS) {
			fprintf(stderr, "unsupported slot range\n");
			close(tfd);
			return 1;
		}
		if (slot_info.value >= 0 && slot_info.value < MAX_CONTACTS)
			current_slot = slot_info.value;
		/* Axes are stateful: a new touch need not resend unchanged values. */
		for (int axis = ABS_MT_POSITION_X; axis <= ABS_MT_POSITION_Y; axis++) {
			int values[MAX_CONTACTS + 1] = { axis };
			if (ioctl(tfd, EVIOCGMTSLOTS(sizeof(values)), values) == 0) {
				for (i = 0; i <= slot_info.maximum; i++) {
					if (axis == ABS_MT_POSITION_X) {
						type_b_contacts[i].x = values[i + 1];
						type_b_contacts[i].has_x = true;
					} else {
						type_b_contacts[i].y = values[i + 1];
						type_b_contacts[i].has_y = true;
					}
				}
			}
		}
	}

	ufd = -1;
	if (!cfg.dry_run) {
		ufd = uinput_create(&cfg);
		if (ufd < 0) {
			close(tfd);
			return 1;
		}
	}
	if (ioctl(tfd, EVIOCGRAB, 1) < 0) {
		perror("grab touchscreen for gesture filtering");
		if (ufd >= 0) {
			ioctl(ufd, UI_DEV_DESTROY);
			close(ufd);
		}
		close(tfd);
		return 1;
	}

	signal(SIGTERM, stop);
	signal(SIGINT, stop);
	reset_gesture(&g);
	memset(&cur, 0, sizeof(cur));
	memset(contacts, 0, sizeof(contacts));

	fprintf(stderr,
		"matepad-touch-rightclick ready: device=%s screen=%dx%d rotation=%d raw=%dx%d; single touch is pointer-emulated, multitouch is filtered\n",
		cfg.device, cfg.width, cfg.height, cfg.rotation, xmax, ymax);

	pfd.fd = tfd;
	pfd.events = POLLIN;
	while (running) {
		struct input_event ev;
		ssize_t n;
		int pr = poll(&pfd, 1, 50);
		uint64_t now = now_ms();

		if (now >= next_rotation_check) {
			int file_rotation;
			int changed = 0;
			next_rotation_check = now + 250;
			if (!read_rotation_index(&cfg, &file_rotation)) {
				changed = apply_orientation(&cfg, &ufd, &rotation_index,
						    &g, file_rotation);
				if (changed < 0) {
					perror("recreate uinput pointer after rotation");
					break;
				}
				if (changed > 0)
					suppress_until_lift = true;
			}
		}
		now = now_ms();

		if (pr < 0) {
			if (errno == EINTR)
				continue;
			perror("poll touchscreen");
			break;
		}
		if (pr == 0) {
			process_single_touch(&cfg, ufd, &g, now, xmax, ymax);
			process_long_press(&cfg, &g, now);
			continue;
		}
		if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL))
			break;

		n = read(tfd, &ev, sizeof(ev));
		if (n < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			perror("read touchscreen");
			break;
		}
		if (n != sizeof(ev))
			break;
		/* Reopen and resync on overflow rather than emit a stale gesture. */
		if (ev.type == EV_SYN && ev.code == SYN_DROPPED)
			break;

		if (ev.type == EV_ABS) {
			switch (ev.code) {
			case ABS_MT_SLOT:
				current_slot = ev.value;
				if (current_slot < 0 || current_slot >= MAX_CONTACTS)
					goto disconnected;
				break;
			case ABS_MT_TRACKING_ID:
				if (!type_b || current_slot < 0 || current_slot >= MAX_CONTACTS)
					break;
				type_b_active[current_slot] = ev.value >= 0;
				break;
			case ABS_MT_POSITION_X:
				if (type_b) {
					type_b_contacts[current_slot].x = ev.value;
					type_b_contacts[current_slot].has_x = true;
				} else {
					cur.x = ev.value;
					cur.has_x = true;
				}
				break;
			case ABS_MT_POSITION_Y:
				if (type_b) {
					type_b_contacts[current_slot].y = ev.value;
					type_b_contacts[current_slot].has_y = true;
				} else {
					cur.y = ev.value;
					cur.has_y = true;
				}
				break;
			case ABS_MT_PRESSURE:
				if (type_b)
					type_b_contacts[current_slot].pressure = ev.value;
				else
					cur.pressure = ev.value;
				break;
			case ABS_X:
				if (!cur.has_x) {
					cur.x = ev.value;
					cur.has_x = true;
				}
				break;
			case ABS_Y:
				if (!cur.has_y) {
					cur.y = ev.value;
					cur.has_y = true;
				}
				break;
			default:
				break;
			}
		} else if (ev.type == EV_SYN) {
			if (ev.code == SYN_MT_REPORT && !type_b) {
				if (cur.has_x && cur.has_y &&
				    ncontacts < MAX_CONTACTS)
					contacts[ncontacts++] = cur;
				memset(&cur, 0, sizeof(cur));
			} else if (ev.code == SYN_REPORT) {
				if (type_b) {
					ncontacts = 0;
					for (i = 0; i < MAX_CONTACTS; i++) {
						if (type_b_active[i] &&
						    type_b_contacts[i].has_x &&
						    type_b_contacts[i].has_y &&
						    ncontacts < MAX_CONTACTS)
							contacts[ncontacts++] = type_b_contacts[i];
					}
				} else if (cur.has_x && cur.has_y &&
					   ncontacts < MAX_CONTACTS) {
					contacts[ncontacts++] = cur;
				}
				if (suppress_until_lift) {
					if (ncontacts == 0)
						suppress_until_lift = false;
					ncontacts = 0;
					if (!type_b)
						memset(&cur, 0, sizeof(cur));
					continue;
				}
				process_frame(&cfg, ufd, &g, contacts, ncontacts,
				      now, xmax, ymax);
				ncontacts = 0;
				if (!type_b)
					memset(&cur, 0, sizeof(cur));
			}
		}
	}

disconnected:
	if (ufd >= 0) {
		ioctl(ufd, UI_DEV_DESTROY);
		close(ufd);
	}
	close(tfd);
	fprintf(stderr, "matepad-touch-rightclick stopped\n");
	return running ? 1 : 0;
}
