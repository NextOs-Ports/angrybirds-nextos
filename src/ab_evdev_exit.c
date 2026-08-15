/* Capability-based evdev fallback for the standard handheld exit chord.
 *
 * Some firmware SDL databases omit SELECT/START even though the Linux input
 * device exposes them. Published Geometry Dash SubZero proved the relevant
 * kernel ABIs on real hardware: BTN_SELECT/BTN_START and, on RK3326-class
 * handhelds, BTN_TRIGGER_HAPPY1/2. We poll current key state instead of raw
 * button ordinals, so reconnects and missed events cannot leave a key stuck.
 * This remains adapter-local until another framework release is justified.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "ab_evdev_exit.h"
#include "ab_exit_chord.h"
#include "ab_port.h"

#define AB_EVDEV_MAX_INDEX 32
#define AB_EVDEV_MAX_PADS 8
#define AB_EVDEV_RESCAN_MS 2000u
#define AB_BITS_PER_LONG (8u * (unsigned int)sizeof(unsigned long))
#define AB_KEY_WORDS ((KEY_MAX / AB_BITS_PER_LONG) + 1u)
#define AB_KEY_DOWN(bits, code)                                             \
  (((bits)[(unsigned int)(code) / AB_BITS_PER_LONG] >>                      \
    ((unsigned int)(code) % AB_BITS_PER_LONG)) &                            \
   1ul)

typedef struct ab_evdev_slot {
  int fd;
  int event_index;
} ab_evdev_slot;

static ab_evdev_slot g_slots[AB_EVDEV_MAX_PADS];
static int g_initialized;
static uint32_t g_next_scan;
static ab_exit_chord_state g_chord;

static int slot_count(void) {
  int count = 0;
  int i;
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++)
    if (g_slots[i].fd >= 0)
      count++;
  return count;
}

static int has_event_index(int event_index) {
  int i;
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++)
    if (g_slots[i].fd >= 0 && g_slots[i].event_index == event_index)
      return 1;
  return 0;
}

static int free_slot(void) {
  int i;
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++)
    if (g_slots[i].fd < 0)
      return i;
  return -1;
}

static int supports_exit_pair(int fd, int *standard_pair,
                              int *trigger_happy_pair) {
  unsigned long keys[AB_KEY_WORDS];
  int standard;
  int trigger_happy;
  int gamepad;

  memset(keys, 0, sizeof(keys));
  if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0)
    return 0;
  standard = AB_KEY_DOWN(keys, BTN_SELECT) && AB_KEY_DOWN(keys, BTN_START);
  trigger_happy = AB_KEY_DOWN(keys, BTN_TRIGGER_HAPPY1) &&
                  AB_KEY_DOWN(keys, BTN_TRIGGER_HAPPY2);
  gamepad = AB_KEY_DOWN(keys, BTN_SOUTH) || AB_KEY_DOWN(keys, BTN_A) ||
            trigger_happy;
  if (standard_pair)
    *standard_pair = standard;
  if (trigger_happy_pair)
    *trigger_happy_pair = trigger_happy;
  return gamepad && (standard || trigger_happy);
}

static void scan_devices(uint32_t now) {
  int event_index;

  for (event_index = 0; event_index < AB_EVDEV_MAX_INDEX; event_index++) {
    char path[64];
    char name[128] = "?";
    int standard = 0;
    int trigger_happy = 0;
    int target;
    int fd;

    if (has_event_index(event_index))
      continue;
    target = free_slot();
    if (target < 0)
      break;
    (void)snprintf(path, sizeof(path), "/dev/input/event%d", event_index);
    fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
      continue;
    if (!supports_exit_pair(fd, &standard, &trigger_happy)) {
      close(fd);
      continue;
    }
    (void)ioctl(fd, EVIOCGNAME(sizeof(name)), name);
    g_slots[target].fd = fd;
    g_slots[target].event_index = event_index;
    ab_log("[input] fallback evdev %s (%s): SELECT+START %s%s", path, name,
           standard ? "BTN" : "",
           trigger_happy ? (standard ? "+TRIGGER_HAPPY" : "TRIGGER_HAPPY")
                         : "");
  }
  g_next_scan = now + AB_EVDEV_RESCAN_MS;
}

void ab_evdev_exit_init(uint32_t now) {
  int i;

  if (g_initialized)
    return;
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++) {
    g_slots[i].fd = -1;
    g_slots[i].event_index = -1;
  }
  memset(&g_chord, 0, sizeof(g_chord));
  g_initialized = 1;
  scan_devices(now);
  if (slot_count() == 0)
    ab_log("[input] fallback evdev indisponivel; SELECT+START segue pela SDL");
}

int ab_evdev_exit_poll(uint32_t now) {
  int chord_down = 0;
  int force_scan = 0;
  int i;

  if (!g_initialized)
    ab_evdev_exit_init(now);
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++) {
    unsigned long keys[AB_KEY_WORDS];
    int select_down;
    int start_down;

    if (g_slots[i].fd < 0)
      continue;
    memset(keys, 0, sizeof(keys));
    if (ioctl(g_slots[i].fd, EVIOCGKEY(sizeof(keys)), keys) < 0) {
      if (errno == ENODEV || errno == EIO || errno == EBADF) {
        close(g_slots[i].fd);
        g_slots[i].fd = -1;
        g_slots[i].event_index = -1;
        force_scan = 1;
      }
      continue;
    }
    select_down = AB_KEY_DOWN(keys, BTN_SELECT) ||
                  AB_KEY_DOWN(keys, BTN_TRIGGER_HAPPY1);
    start_down = AB_KEY_DOWN(keys, BTN_START) ||
                 AB_KEY_DOWN(keys, BTN_TRIGGER_HAPPY2);
    if (select_down && start_down)
      chord_down = 1;
  }
  if (force_scan || (int32_t)(now - g_next_scan) >= 0)
    scan_devices(now);
  return ab_exit_chord_update(&g_chord, chord_down, chord_down);
}

void ab_evdev_exit_shutdown(void) {
  int i;
  if (!g_initialized)
    return;
  for (i = 0; i < AB_EVDEV_MAX_PADS; i++) {
    if (g_slots[i].fd >= 0)
      close(g_slots[i].fd);
    g_slots[i].fd = -1;
    g_slots[i].event_index = -1;
  }
  memset(&g_chord, 0, sizeof(g_chord));
  g_initialized = 0;
  g_next_scan = 0;
}
