"""Native startup failures must preserve unknown diagnostic evidence."""
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CompatibilityProcessTests(unittest.TestCase):
    def run_probe(self, *defines):
        with tempfile.TemporaryDirectory(prefix="ieb-compat-") as folder:
            executable = str(Path(folder) / "probe")
            subprocess.run(["xcrun", "clang", "-DIEB_COMPATIBILITY_TEST_CHILD=1", *defines,
                            "-fobjc-arc", "-framework", "Foundation", "-Wall", "-Wextra", "-Werror",
                            str(ROOT / "tools/compatibility_probe.m"),
                            str(ROOT / "tools/IEBCompatibilityEvidence.m"), "-o", executable], check=True)
            result = subprocess.run([executable, "collector"], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 20)
            report = json.loads(result.stdout)
            self.assertEqual(report["summary"]["status"], "environment_unavailable")
            self.assertIsNone(report["observations"])
            self.assertFalse(report["inspection_completed"])
            self.assertNotIn("supported", report)
            invalid = subprocess.run([executable, "invalid"], capture_output=True, timeout=5)
            self.assertEqual(invalid.returncode, 64)
            return report

    def test_native_initializer_exit_remains_unknown(self):
        report = self.run_probe()
        self.assertEqual(report["child_exit_code"], 1)
        self.assertEqual(report["failure_stage"], "child_execution")

    def test_spawn_permission_failure_remains_unknown(self):
        report = self.run_probe("-DIEB_COMPATIBILITY_TEST_SPAWN_ERROR=1")
        self.assertEqual(report["failure_stage"], "spawn")
        self.assertEqual(report["launch_error"], 1)
        self.assertIsNone(report["child_exit_code"])

    def test_stalled_child_is_bounded_without_support_claim(self):
        report = self.run_probe("-DIEB_COMPATIBILITY_TEST_TIMEOUT=1")
        self.assertEqual(report["child_signal"], signal.SIGKILL)
        self.assertIsNone(report["child_exit_code"])
