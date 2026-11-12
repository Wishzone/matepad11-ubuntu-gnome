// SPDX-License-Identifier: MIT
//
// Add a flashlight toggle to the GNOME quick settings panel.
//
// The rear camera flash is exposed by the kernel as
// /sys/class/leds/white:flash and 61-matepad-flashlight.rules makes the
// brightness file writable by the logged-in user.  matepad-flashlight
// switches it between 0 and max_brightness; no root or D-Bus service is
// needed.

import Gio from 'gi://Gio';
import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {QuickToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const HELPER = '/usr/local/bin/matepad-flashlight';

function setFlashlight(on) {
    try {
        Gio.Subprocess.new(
            [HELPER, on ? 'on' : 'off'],
            Gio.SubprocessFlags.STDOUT_SILENCE |
            Gio.SubprocessFlags.STDERR_SILENCE);
    } catch (e) {
        logError(e, 'matepad-flashlight');
    }
}

const FlashlightToggle = GObject.registerClass(
class FlashlightToggle extends QuickToggle {
    _init() {
        super._init({
            title: 'Flashlight',
            iconName: 'media-flash-symbolic',
            toggleMode: true,
        });
        this.connect('clicked', () => setFlashlight(this.checked));
    }
});

const FlashlightIndicator = GObject.registerClass(
class FlashlightIndicator extends SystemIndicator {
    _init() {
        super._init();
        this._toggle = new FlashlightToggle();
        this.quickSettingsItems.push(this._toggle);
    }
});

export default class MatePadFlashlightExtension extends Extension {
    enable() {
        this._indicator = new FlashlightIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.quickSettingsItems.forEach(item => item.destroy());
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
