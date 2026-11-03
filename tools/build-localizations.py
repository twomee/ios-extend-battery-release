#!/usr/bin/env python3
"""Stage the dedicated, offline tweak localization bundle."""
import importlib.util
import plistlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def build(destination):
    destination = Path(destination)
    if destination.name != 'IEBLocalizations.bundle' or destination.is_symlink():
        raise ValueError('destination must be an owned IEBLocalizations.bundle directory')
    spec = importlib.util.spec_from_file_location('ieb_translation_validation', ROOT / 'tools/validate-localizations.py')
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    files = validator.validate(ROOT / 'Resources/Localizations')
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for path in files:
        target = destination / path.parent.name
        target.mkdir()
        shutil.copyfile(path, target / path.name)
    with (destination / 'Info.plist').open('wb') as output:
        plistlib.dump({'CFBundleIdentifier': 'com.idonamaan.ieb.localizations',
                      'CFBundleName': 'IEBLocalizations', 'CFBundlePackageType': 'BNDL',
                      'CFBundleDevelopmentRegion': 'en',
                      'CFBundleLocalizations': [path.parent.stem for path in files]}, output)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: build-localizations.py <owned-path>/IEBLocalizations.bundle')
    try:
        build(sys.argv[1])
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
