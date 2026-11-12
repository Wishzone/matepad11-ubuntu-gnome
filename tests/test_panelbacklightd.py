#!/usr/bin/python3
import importlib.util
import importlib.machinery
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "overrides/backlight/matepad-panelbacklightd"
SPEC = importlib.util.spec_from_file_location("matepad_panelbacklightd", SOURCE)
if SPEC is None:
    SPEC = importlib.util.spec_from_loader(
        "matepad_panelbacklightd", importlib.machinery.SourceFileLoader(
            "matepad_panelbacklightd", str(SOURCE)
        )
    )
BACKLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BACKLIGHT)


class BacklightPersistenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.brightness = root / "brightness"
        self.maximum = root / "max_brightness"
        self.state = root / "var/lib/matepad/panel-brightness"
        self.systemd_state = root / "var/lib/systemd/backlight/platform:backlight:panel0-backlight"
        self.dpms = root / "dpms"
        self.brightness.write_text("0\n")
        self.maximum.write_text("255\n")
        self.dpms.write_text("On\n")
        BACKLIGHT.BACKLIGHT = str(self.brightness)
        BACKLIGHT.MAX_BRIGHTNESS = str(self.maximum)
        BACKLIGHT.STATE_FILE = str(self.state)
        BACKLIGHT.SYSTEMD_STATE_GLOB = str(self.systemd_state.parent / "*:backlight:panel0-backlight")
        BACKLIGHT.DPMS_GLOB = str(self.dpms)

    def tearDown(self):
        self.tmp.cleanup()

    def test_boot_restores_systemd_saved_brightness_instead_of_driver_default(self):
        self.systemd_state.parent.mkdir(parents=True)
        self.systemd_state.write_text("206\n")
        follower = BACKLIGHT.BacklightFollower()

        follower.step()

        self.assertEqual(self.brightness.read_text().strip(), "206")
        self.assertEqual(self.state.read_text().strip(), "206")

    def test_existing_user_value_wins_over_older_systemd_value(self):
        self.systemd_state.parent.mkdir(parents=True)
        self.systemd_state.write_text("206\n")
        self.state.parent.mkdir(parents=True)
        self.state.write_text("77\n")
        self.brightness.write_text("206\n")
        follower = BACKLIGHT.BacklightFollower()

        follower.step()

        self.assertEqual(self.brightness.read_text().strip(), "77")
        self.assertEqual(self.state.read_text().strip(), "77")

    def test_start_while_dpms_off_does_not_replace_saved_user_value(self):
        self.systemd_state.parent.mkdir(parents=True)
        self.systemd_state.write_text("206\n")
        self.state.parent.mkdir(parents=True)
        self.state.write_text("77\n")
        self.brightness.write_text("206\n")
        self.dpms.write_text("Off\n")
        follower = BACKLIGHT.BacklightFollower()

        follower.step()

        self.assertEqual(self.brightness.read_text().strip(), "0")
        self.assertEqual(self.state.read_text().strip(), "77")

        self.dpms.write_text("On\n")
        follower.step()
        self.assertEqual(self.brightness.read_text().strip(), "77")

    def test_tracks_user_changes_and_restores_after_blank_and_resume(self):
        self.state.parent.mkdir(parents=True)
        self.state.write_text("77\n")
        self.brightness.write_text("115\n")
        follower = BACKLIGHT.BacklightFollower()

        follower.step()
        self.assertEqual(self.brightness.read_text().strip(), "77")

        self.brightness.write_text("91\n")
        follower.step()
        self.assertEqual(self.state.read_text().strip(), "91")

        self.dpms.write_text("Off\n")
        follower.step()
        self.assertEqual(self.brightness.read_text().strip(), "0")
        self.dpms.write_text("On\n")
        follower.step()
        self.assertEqual(self.brightness.read_text().strip(), "91")

    def test_resume_helper_restores_only_when_panel_is_on(self):
        self.state.parent.mkdir(parents=True)
        self.state.write_text("83\n")
        self.dpms.write_text("Off\n")
        self.assertEqual(BACKLIGHT.restore_after_resume(), 0)
        self.assertEqual(self.brightness.read_text().strip(), "0")

        self.dpms.write_text("On\n")
        self.assertEqual(BACKLIGHT.restore_after_resume(), 0)
        self.assertEqual(self.brightness.read_text().strip(), "83")

    def test_suspend_helper_persists_last_nonzero_value(self):
        self.brightness.write_text("92\n")
        self.assertEqual(BACKLIGHT.save_before_suspend(), 0)
        self.assertEqual(self.state.read_text().strip(), "92")

        self.brightness.write_text("0\n")
        self.assertEqual(BACKLIGHT.save_before_suspend(), 0)
        self.assertEqual(self.state.read_text().strip(), "92")

    def test_uses_current_nonzero_brightness_if_no_persisted_state_exists(self):
        self.brightness.write_text("64\n")
        follower = BACKLIGHT.BacklightFollower()

        follower.step()

        self.assertEqual(self.brightness.read_text().strip(), "64")
        self.assertEqual(self.state.read_text().strip(), "64")


if __name__ == "__main__":
    unittest.main()
