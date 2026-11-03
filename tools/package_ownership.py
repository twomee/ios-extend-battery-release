#!/usr/bin/env python3
"""Normalize Debian archive ownership without extracting files or needing root.

Some Theos dm.pl versions set tar owner names to root/wheel while retaining the
builder's numeric IDs. Both representations must agree across package managers.
Only unsigned, three-member Debian 2.0 packages are accepted: changing a signed
package would invalidate its signature. Compression types and file metadata other
than ownership are preserved. Already normalized packages remain byte-identical.
"""

import argparse
import bz2
import copy
import gzip
import io
import lzma
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile
import tempfile
import zlib


class InvalidPackage(ValueError):
    """A package cannot be safely inspected or normalized."""


def read_ar(data):
    if not data.startswith(b"!<arch>\n"):
        raise InvalidPackage("missing ar signature")
    members = []
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise InvalidPackage("invalid or truncated ar header")
        try:
            name = header[:16].decode("ascii").strip().removesuffix("/")
            size = int(header[48:58])
            uid, gid = int(header[28:34]), int(header[34:40])
            int(header[16:28])  # Validate timestamp and mode without changing them.
            int(header[40:48], 8)
        except (ValueError, UnicodeError) as error:
            raise InvalidPackage("invalid ar member metadata") from error
        end = offset + 60 + size
        if size < 0 or end + size % 2 > len(data):
            raise InvalidPackage("truncated ar member")
        if size % 2 and data[end:end + 1] != b"\n":
            raise InvalidPackage("invalid ar padding")
        members.append((name, header, data[offset + 60:end], uid == 0 and gid == 0))
        offset = end + size % 2
    names = [member[0] for member in members]
    if (len(names) != 3 or names[0] != "debian-binary"
            or not names[1].startswith("control.tar") or not names[2].startswith("data.tar")
            or members[0][2] != b"2.0\n"):
        raise InvalidPackage("expected unsigned Debian 2.0 control/data archives")
    return members


def compression(name):
    suffix = name[name.index(".tar") + 4:]
    if suffix == "":
        return lambda data: data, lambda data: data
    if suffix == ".gz":
        return gzip.decompress, lambda data: gzip.compress(data, mtime=0)
    if suffix == ".bz2":
        return bz2.decompress, bz2.compress
    if suffix == ".xz":
        return (lambda data: lzma.decompress(data, format=lzma.FORMAT_XZ),
                lambda data: lzma.compress(data, format=lzma.FORMAT_XZ))
    if suffix == ".lzma":
        return (lambda data: lzma.decompress(data, format=lzma.FORMAT_ALONE),
                lambda data: lzma.compress(data, format=lzma.FORMAT_ALONE))
    raise InvalidPackage(f"unsupported compression: {name}")


def normalize_tar(name, payload, check):
    decompress, compress = compression(name)
    raw = decompress(payload)
    if len(raw) % 512 or len(raw) < 1024 or raw[-1024:] != b"\0" * 1024:
        raise InvalidPackage(f"incomplete tar archive: {name}")
    output = io.BytesIO()
    changed = False
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as source:
        with tarfile.open(fileobj=output, mode="w", format=tarfile.PAX_FORMAT) as target:
            count = 0
            for member in source:
                count += 1
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or "\0" in member.name:
                    raise InvalidPackage(f"unsafe tar member: {name}: {member.name!r}")
                correct = (member.uid, member.gid, member.uname, member.gname) == (0, 0, "root", "wheel")
                if check and not correct:
                    raise InvalidPackage(f"ownership mismatch: {name}: {member.name}")
                changed |= not correct
                normalized = copy.copy(member)
                normalized.uid, normalized.gid = 0, 0
                normalized.uname, normalized.gname = "root", "wheel"
                normalized.pax_headers = dict(member.pax_headers)
                for key, value in (("uid", "0"), ("gid", "0"),
                                   ("uname", "root"), ("gname", "wheel")):
                    if key in normalized.pax_headers:
                        normalized.pax_headers[key] = value
                content = source.extractfile(member) if member.isfile() else None
                try:
                    target.addfile(normalized, content)
                finally:
                    if content is not None:
                        content.close()
            if not count:
                raise InvalidPackage(f"empty tar archive: {name}")
    return compress(output.getvalue()) if changed else payload


def normalize(data, check=False):
    output = bytearray(b"!<arch>\n")
    for name, header, payload, root in read_ar(data):
        if check and not root:
            raise InvalidPackage(f"ownership mismatch: ar member {name}")
        if name != "debian-binary":
            payload = normalize_tar(name, payload, check)
        header = header[:28] + b"0     0     " + header[40:48] + f"{len(payload):<10}".encode("ascii") + header[58:]
        output.extend(header)
        output.extend(payload)
        if len(payload) % 2:
            output.extend(b"\n")
    return bytes(output)


def process(path, check=False):
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise InvalidPackage("package path must be a regular file")
    original = path.read_bytes()
    result = normalize(original, check)
    if check or result == original:
        return
    # Verify all generated metadata before touching the original artifact.
    normalize(result, check=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
            temporary = Path(handle.name)
            os.fchmod(handle.fileno(), stat.S_IMODE(metadata.st_mode))
            handle.write(result)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify ownership without modifying the package")
    parser.add_argument("package", type=Path)
    arguments = parser.parse_args()
    try:
        process(arguments.package, arguments.check)
    except (OSError, ValueError, EOFError, tarfile.TarError, lzma.LZMAError, zlib.error) as error:
        print(f"Invalid package: {error}", file=sys.stderr)
        return 1
    print(f"Package ownership {'verified' if arguments.check else 'normalized'}: {arguments.package}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
