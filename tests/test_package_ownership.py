"""Package metadata stays portable across numeric- and name-based extractors."""

import gzip
import io
import lzma
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/package_ownership.py"


def ar_member(name, payload):
    header = (f"{name + '/':<16}{123:<12}{0:<6}{0:<6}"
              f"{'100644':<8}{len(payload):<10}`\n").encode("ascii")
    return header + payload + (b"\n" if len(payload) % 2 else b"")


def tar_bytes(control=False):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name in (".",) if control else (".", "var", "var/jb", "var/jb/usr", "var/jb/usr/libexec"):
            member = tarfile.TarInfo(name)
            member.type = tarfile.DIRTYPE
            member.mode = 0o755
            member.uid, member.gid = 501, 20
            member.uname, member.gname = "root", "wheel"
            archive.addfile(member)
        member = tarfile.TarInfo("control" if control else "var/jb/usr/libexec/reader")
        member.uid, member.gid = 501, 20
        member.uname, member.gname = "root", "wheel"
        member.mode = 0o644 if control else 0o755
        member.mtime = 123
        member.pax_headers = {"uid": "501", "gid": "20", "comment": "keep me"}
        content = b"Package: example\n" if control else b"executable\x00bytes\n"
        member.size = len(content)
        archive.addfile(member, io.BytesIO(content))
        if not control:
            link = tarfile.TarInfo("var/jb/usr/libexec/reader-link")
            link.type, link.linkname = tarfile.SYMTYPE, "reader"
            link.uid, link.gid = 501, 20
            link.uname, link.gname = "root", "wheel"
            link.mode = 0o777
            archive.addfile(link)
    return output.getvalue()


def package():
    return (b"!<arch>\n" + ar_member("debian-binary", b"2.0\n")
            + ar_member("control.tar.gz", gzip.compress(tar_bytes(True), mtime=0))
            + ar_member("data.tar.lzma", lzma.compress(tar_bytes(), format=lzma.FORMAT_ALONE)))


def members(data):
    result = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        size = int(header[48:58])
        result[header[:16].decode().strip().rstrip("/")] = data[offset + 60:offset + 60 + size]
        offset += 60 + size + size % 2
    return result


def tar_snapshot(payload):
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as archive:
        return [(m.name, m.mode, m.type, m.linkname, m.mtime,
                 archive.extractfile(m).read() if m.isfile() else None)
                for m in archive]


class PackageOwnershipTests(unittest.TestCase):
    def invoke(self, path, *args):
        return subprocess.run([sys.executable, str(TOOL), *args, str(path)],
                              capture_output=True, text=True, check=False)

    def test_normalizes_named_root_with_nonroot_numeric_ids_and_preserves_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "example.deb"
            original = package()
            path.write_bytes(original)
            path.chmod(0o640)
            result = self.invoke(path)
            self.assertEqual(result.returncode, 0, result.stderr)
            normalized = path.read_bytes()
            self.assertNotEqual(normalized, original)
            before, after = members(original), members(normalized)
            self.assertEqual(before.keys(), after.keys())
            self.assertEqual(after["debian-binary"], b"2.0\n")
            for name in ("control.tar.gz", "data.tar.lzma"):
                self.assertEqual(tar_snapshot(before[name]), tar_snapshot(after[name]))
                with tarfile.open(fileobj=io.BytesIO(after[name]), mode="r:*") as archive:
                    for member in archive:
                        self.assertEqual((member.uid, member.gid, member.uname, member.gname),
                                         (0, 0, "root", "wheel"))
                        self.assertEqual(member.pax_headers.get("comment", "keep me"), "keep me")
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(self.invoke(path, "--check").returncode, 0)
            self.assertEqual(self.invoke(path).returncode, 0)
            self.assertEqual(path.read_bytes(), normalized)
            # Compression remains gzip + legacy LZMA, rather than silently becoming xz.
            self.assertTrue(after["control.tar.gz"].startswith(b"\x1f\x8b"))
            self.assertEqual(lzma.decompress(after["data.tar.lzma"], format=lzma.FORMAT_ALONE)[-1024:],
                             b"\0" * 1024)

    def test_check_reports_numeric_mismatch_without_modifying_package(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "example.deb"
            original = package()
            path.write_bytes(original)
            result = self.invoke(path, "--check")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ownership", result.stderr.lower())
            self.assertIn("control.tar.gz", result.stderr)
            self.assertEqual(path.read_bytes(), original)

    def test_corrupt_archive_fails_explicitly_and_leaves_original_untouched(self):
        for data in (b"not an ar", package()[:-15],
                     b"!<arch>\n" + ar_member("debian-binary", b"2.0\n")
                     + ar_member("control.tar.gz", b"corrupt")
                     + ar_member("data.tar.lzma", lzma.compress(tar_bytes(), format=lzma.FORMAT_ALONE))):
            with self.subTest(data_length=len(data)), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "example.deb"
                path.write_bytes(data)
                result = self.invoke(path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid package", result.stderr.lower())
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(list(Path(directory).iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
