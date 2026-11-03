"""Catch installers that omit, alter or replace language resources with links."""
import gzip
import importlib.util
import io
import plistlib
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from test_release_license import ar_member

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'var/jb/Library/Application Support/iOSExtendBattery/IEBLocalizations.bundle/'

def package(*, omit=False, changed=False, symlink=False, binary=False):
    output = io.BytesIO()
    files = sorted((ROOT / 'Resources/Localizations').glob('*.lproj/Localizable.strings'))
    with tarfile.open(fileobj=output, mode='w') as archive:
        items = [(f'{p.parent.name}/{p.name}', p.read_bytes()) for p in files]
        if binary:
            spec = importlib.util.spec_from_file_location('fixture_strings', ROOT / 'tools/validate-localizations.py')
            parser = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(parser)
            items = [(f'{p.parent.name}/{p.name}', plistlib.dumps(parser.read_strings(p), fmt=plistlib.FMT_BINARY)) for p in files]
        items.append(('Info.plist', plistlib.dumps({'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': [p.parent.stem for p in files]})))
        for index, (name, content) in enumerate(items):
            if omit and index == 0:
                continue
            member = tarfile.TarInfo(PREFIX + name)
            if index == 0 and symlink:
                member.type, member.linkname = tarfile.SYMTYPE, '/outside'
                archive.addfile(member)
            else:
                data = b'changed' if changed and index == 0 else content
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
    return b'!<arch>\n' + ar_member('debian-binary', b'2.0\n') + ar_member('control.tar.gz', gzip.compress(b'control fixture')) + ar_member('data.tar.gz', gzip.compress(output.getvalue()))

class LocalizationPackageTests(unittest.TestCase):
    def invoke(self, **changes):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.deb'
            path.write_bytes(package(**changes))
            return subprocess.run([sys.executable, str(ROOT / 'tools/verify_localization_package.py'), str(path)], capture_output=True, text=True)

    def test_all_exact_resources_pass(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_theos_binary_plist_optimization_preserves_values(self):
        result = self.invoke(binary=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_changed_or_symlinked_resources_fail(self):
        for changes in ({'omit': True}, {'changed': True}, {'symlink': True}):
            with self.subTest(changes=changes):
                self.assertNotEqual(self.invoke(**changes).returncode, 0)
