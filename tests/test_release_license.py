"""The shipped binary carries the same MIT grant and notices as the source."""
import gzip
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def ar_member(name, content):
    header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(content):<10}`\n".encode()
    return header + content + (b"\n" if len(content) % 2 else b"")


def package(license_content=None, include_notice=True, duplicate=False, symlink=False):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w") as archive:
        items = [("copyright", (ROOT / "LICENSE").read_bytes() if license_content is None else license_content)]
        if include_notice:
            items.append(("THIRD_PARTY_NOTICES.md", (ROOT / "THIRD_PARTY_NOTICES.md").read_bytes()))
        if duplicate:
            items.append(items[0])
        for name, content in items:
            member = tarfile.TarInfo("./var/jb/usr/share/doc/com.idonamaan.iebproducerprobe/" + name)
            if symlink and name == "copyright":
                member.type, member.linkname = tarfile.SYMTYPE, "/tmp/elsewhere"
                archive.addfile(member)
            else:
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
    return (b"!<arch>\n" + ar_member("debian-binary", b"2.0\n")
            + ar_member("control.tar.gz", gzip.compress(b"not read by this verifier", mtime=0))
            + ar_member("data.tar.gz", gzip.compress(raw.getvalue(), mtime=0)))


class ReleaseLicenseTests(unittest.TestCase):
    def invoke(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.deb"
            path.write_bytes(content)
            result = subprocess.run([sys.executable, str(ROOT / "tools/verify_release_license.py"), str(path)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(path.read_bytes(), content)
            return result

    def test_exact_license_and_notice_pass_without_modifying_package(self):
        result = self.invoke(package())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_or_changed_license_fails(self):
        for content in (package(license_content=b"wrong"), package(include_notice=False)):
            with self.subTest(content_size=len(content)):
                result = self.invoke(content)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("missing or mismatched", result.stderr)

    def test_duplicate_or_symlink_license_fails(self):
        for content in (package(duplicate=True), package(symlink=True)):
            result = self.invoke(content)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid or duplicate", result.stderr)


if __name__ == "__main__":
    unittest.main()
