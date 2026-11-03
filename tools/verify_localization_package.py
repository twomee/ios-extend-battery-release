#!/usr/bin/env python3
"""Check that the installer contains exact, readable offline language resources."""
import io
import importlib.util
import plistlib
import sys
import tarfile
from pathlib import Path
from package_ownership import InvalidPackage, compression, read_ar

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'var/jb/Library/Application Support/iOSExtendBattery/IEBLocalizations.bundle/'

def verify(package):
    files = sorted((ROOT / 'Resources/Localizations').glob('*.lproj/Localizable.strings'))
    spec = importlib.util.spec_from_file_location('ieb_package_strings', ROOT / 'tools/validate-localizations.py')
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)
    expected = {f'{p.parent.name}/{p.name}': parser.read_strings(p) for p in files}
    payloads = [member for member in read_ar(Path(package).read_bytes()) if member[0].startswith('data.tar')]
    if len(payloads) != 1:
        raise InvalidPackage('expected one installer data archive')
    name, _, content, _ = payloads[0]
    raw = compression(name)[0](content)
    found = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
        for member in archive:
            path = member.name.removeprefix('./')
            if not path.startswith(PREFIX) or member.isdir():
                continue
            key = path[len(PREFIX):]
            if key in found or not member.isfile() or not member.mode & 0o004 or member.mode & 0o022:
                raise InvalidPackage(f'invalid, unreadable or duplicate localization resource: {key}')
            with archive.extractfile(member) as resource:
                found[key] = resource.read()
    info = plistlib.loads(found.pop('Info.plist', b''))
    if info.get('CFBundleDevelopmentRegion') != 'en' or sorted(info.get('CFBundleLocalizations', [])) != sorted(p.parent.stem for p in files):
        raise InvalidPackage('localization bundle language manifest differs from source')
    found = {key: plistlib.loads(data) if data.startswith((b'bplist', b'<?xml')) else parser.parse_strings(data.decode('utf-8-sig'), key) for key, data in found.items()}
    if found != expected:
        raise InvalidPackage('missing, unexpected or changed localization resources')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify_localization_package.py <package.deb>')
    try:
        verify(sys.argv[1])
    except (OSError, ValueError, EOFError, tarfile.TarError, plistlib.InvalidFileException) as error:
        print(f'Invalid localization package: {error}', file=sys.stderr)
        raise SystemExit(1)
    print(f'Localization package verified: {sys.argv[1]}')
