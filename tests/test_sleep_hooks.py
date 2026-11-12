#!/usr/bin/python3
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SystemSleepHookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = os.environ.copy()
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]

    def tearDown(self):
        self.tmp.cleanup()

    def test_sensor_stream_is_paused_and_resumed_with_ack(self):
        state = self.root / "sensor-state"
        pidfile = self.root / "sensord.pid"
        ready = self.root / "sensord-ready"
        remoteproc_state = self.root / "remoteproc-state"
        stop_marker = self.root / "slpi-stopped"
        commands = self.root / "systemctl-calls"
        remoteproc_state.write_text("running\n")
        (self.bin / "systemctl").write_text(
            "#!/bin/sh\n"
            "case \"$1\" in\n"
            "  show) cat \"$MATEPAD_TEST_PIDFILE\" ;;\n"
            "  *) echo \"$*\" >> \"$MATEPAD_TEST_CALLS\" ;;\n"
            "esac\n"
        )
        (self.bin / "tee").write_text(
            "#!/bin/sh\n"
            "value=$(cat)\n"
            "case \"$value\" in stop) value=offline;; start) value=running;; esac\n"
            "printf '%s\\n' \"$value\" > \"$1\"\n"
            "printf '%s\\n' \"$value\"\n"
        )
        (self.bin / "systemctl").chmod(0o755)
        (self.bin / "tee").chmod(0o755)
        self.env["MATEPAD_SENSORD_PM_STATE"] = str(state)
        self.env["MATEPAD_SENSORD_UNIT"] = "test-sensord.service"
        self.env["MATEPAD_HEXAGONRPC_UNIT"] = "test-hexagon.service"
        self.env["MATEPAD_TEST_PIDFILE"] = str(pidfile)
        self.env["MATEPAD_REMOTEPROC_STATE"] = str(remoteproc_state)
        self.env["MATEPAD_SLPI_STOP_MARKER"] = str(stop_marker)
        self.env["MATEPAD_TEST_CALLS"] = str(commands)
        self.env["MATEPAD_TEST_READY"] = str(ready)
        helper = (
            "import os,signal,time\n"
            "state=os.environ['MATEPAD_SENSORD_PM_STATE']\n"
            "signal.signal(signal.SIGUSR1, lambda *_: open(state,'w').write('suspended\\n'))\n"
            "signal.signal(signal.SIGUSR2, lambda *_: open(state,'w').write('awake\\n'))\n"
            "open(os.environ['MATEPAD_TEST_READY'],'w').close()\n"
            "time.sleep(30)\n"
        )
        process = subprocess.Popen(["python3", "-c", helper], env=self.env)
        pidfile.write_text("%d\n" % process.pid)
        for _ in range(100):
            if ready.exists():
                break
            if process.poll() is not None:
                self.fail("fake sensor daemon exited before installing signal handlers")
            time.sleep(0.01)
        hook = ROOT / "overrides/sensors/matepad-system-sleep"

        try:
            subprocess.run([str(hook), "pre", "suspend"], env=self.env, check=True)
            self.assertEqual(state.read_text().strip(), "suspended")
            self.assertEqual(remoteproc_state.read_text().strip(), "offline")
            self.assertTrue(stop_marker.exists())
            subprocess.run([str(hook), "post", "suspend"], env=self.env, check=True)
            for _ in range(100):
                if state.read_text().strip() == "awake":
                    break
                time.sleep(0.01)
            self.assertEqual(state.read_text().strip(), "awake")
            self.assertEqual(remoteproc_state.read_text().strip(), "running")
            self.assertFalse(stop_marker.exists())
            self.assertIn("stop test-hexagon.service", commands.read_text())
            self.assertNotIn("start test-hexagon.service", commands.read_text())
            subprocess.run([str(hook), "pre", "poweroff"], env=self.env, check=True)
            self.assertEqual(state.read_text().strip(), "awake")
        finally:
            process.terminate()
            process.wait(timeout=3)

    def test_backlight_hook_saves_and_restores_around_suspend_only(self):
        calls = self.root / "calls"
        daemon = self.bin / "backlight-daemon"
        daemon.write_text("#!/bin/sh\necho \"$1\" >> \"$CALLS\"\n")
        daemon.chmod(0o755)
        self.env["CALLS"] = str(calls)
        self.env["MATEPAD_BACKLIGHT_DAEMON"] = str(daemon)
        hook = ROOT / "overrides/backlight/matepad-system-sleep"

        subprocess.run([str(hook), "pre", "suspend"], env=self.env, check=True)
        subprocess.run([str(hook), "post", "suspend"], env=self.env, check=True)
        subprocess.run([str(hook), "pre", "poweroff"], env=self.env, check=True)
        self.assertEqual(calls.read_text().splitlines(), ["--save", "--restore"])


if __name__ == "__main__":
    unittest.main()
