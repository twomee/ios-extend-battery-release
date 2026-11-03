#!/usr/bin/env python3
"""Verify that the rootless installer carries the exact project license/notices."""
import argparse
import io
import lzma
from pathlib import Path
import sys
import tarfile
import zlib

from package_ownership import InvalidPackage, compression, read_ar


def verify(package, project_root):
    data = next(member for member in read_ar(package.read_bytes()) if member[0].startswith("data.tar"))
    raw = compression(data[0])[0](data[2])
    expected = {
        "copyright": project_root / "LICENSE",
        "THIRD_PARTY_NOTICES.md": project_root / "THIRD_PARTY_NOTICES.md",
    }
    prefix = "var/jb/usr/share/doc/com.idonamaan.iebproducerprobe/"
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as archive:
        matches = {}
        for member in archive:
            name = member.name.removeprefix("./")
            if name.startswith(prefix) and name[len(prefix):] in expected:
                key = name[len(prefix):]
                if key in matches or not member.isfile():
                    raise InvalidPackage(f"invalid or duplicate license member: {name}")
                with archive.extractfile(member) as content:
                    matches[key] = content.read()
        for key, source in expected.items():
            if key not in matches or matches[key] != source.read_bytes():
                raise InvalidPackage(f"missing or mismatched release license: {key}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    arguments = parser.parse_args()
    try:
        verify(arguments.package, Path(__file__).resolve().parents[1])
    except (OSError, ValueError, EOFError, tarfile.TarError, lzma.LZMAError, zlib.error) as error:
        print(f"Invalid release: {error}", file=sys.stderr)
        return 1
    print(f"Release license and notices verified: {arguments.package}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
