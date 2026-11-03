"""Reject malformed connection inputs before invoking any network tools."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RunnerInputTests(unittest.TestCase):
    def invoke(self, target="mobile@example.invalid", port="22", arguments=()):
        env = dict(os.environ, IEB_SSH_TARGET=target,
                   IEB_SSH_PORT=port, IEB_SSH_IDENTITY="/does/not/exist")
        return subprocess.run(["sh", "tools/run-device-probe.sh", *arguments],
                              cwd=ROOT, env=env, capture_output=True, text=True,
                              timeout=3, check=False)

    def test_rejects_leading_option(self):
        result = self.invoke(target="-V")
        self.assertEqual(result.returncode, 64)
        self.assertIn("Invalid SSH target", result.stderr)

    def test_rejects_shell_metacharacters(self):
        result = self.invoke(target="mobile@host;exit")
        self.assertEqual(result.returncode, 64)

    def test_rejects_invalid_port(self):
        result = self.invoke(port="22 -oProxyCommand=bad")
        self.assertEqual(result.returncode, 64)

    def test_rejects_unknown_probe_flag(self):
        result = self.invoke(arguments=("--reset",))
        self.assertEqual(result.returncode, 64)
        self.assertIn("Usage:", result.stderr)


class RunnerForwardingTests(unittest.TestCase):
    def test_producer_mode_quotes_identity_and_propagates_remote_failure(self):
        self.check_forwarding("--producer-query")

    def test_matrix_mode_quotes_identity_and_propagates_remote_failure(self):
        self.check_forwarding("--producer-matrix")

    def check_forwarding(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            (root / ".build").mkdir()
            fakebin = root / "fakebin"
            fakebin.mkdir()
            shutil.copy(ROOT / "tools/run-device-probe.sh", root / "tools")
            build = root / "tools/build-probe.sh"
            build.write_text("#!/bin/sh\nset -eu\n: > .build/ieb-probe\n")
            build.chmod(0o755)
            stub = f"#!{sys.executable}\n" + (
                "import json,os,sys\n"
                "from pathlib import Path\n"
                "with open(os.environ['PROBE_TEST_LOG'],'a') as f:\n"
                " json.dump({'command':Path(sys.argv[0]).name,'args':sys.argv[1:]},f);f.write('\\n')\n"
                "sys.exit(20 if Path(sys.argv[0]).name=='ssh' else 0)\n"
            )
            for name in ("scp", "ssh", "ldid"):
                executable = fakebin / name
                executable.write_text(stub)
                executable.chmod(0o755)
            log = root / "calls.jsonl"
            env = dict(os.environ, PATH=f"{fakebin}:{os.environ['PATH']}",
                       IEB_SSH_TARGET="mobile@example.invalid", IEB_SSH_PORT="2222",
                       IEB_SSH_IDENTITY="/a key/identity", PROBE_TEST_LOG=str(log))
            result = subprocess.run(["sh", "tools/run-device-probe.sh", mode],
                                    cwd=root, env=env, capture_output=True, text=True,
                                    timeout=3, check=False)
            self.assertEqual(result.returncode, 20, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual([call['command'] for call in calls], ['scp', 'ssh'])
            for call in calls:
                args = call['args']
                self.assertEqual(args[args.index('-i') + 1], '/a key/identity')
                self.assertIn('StrictHostKeyChecking=yes', args)
            self.assertEqual(calls[1]['args'][-2:], [
                'mobile@example.invalid', '/var/mobile/ieb-probe ' + mode])


if __name__ == "__main__":
    unittest.main()
