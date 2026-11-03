"""Catch contributor edits that would break lookup or variadic formatting."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class LocalizationValidationTests(unittest.TestCase):
    def check_catalog(self, english, translated, *, strict=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for language, content in (("en", english), ("fr", translated)):
                path = root / f"{language}.lproj" / "Localizable.strings"
                path.parent.mkdir()
                path.write_text(content, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(ROOT / "tools/validate-localizations.py"), "--resources", str(root)]
                + (["--strict"] if strict else []), capture_output=True, text=True)

    def test_valid_reordered_positional_arguments(self):
        result = self.check_catalog('"key" = "%ld apps: %@";', '"key" = "%2$@ : %1$ld applications";')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_partial_language_is_reported_and_falls_back(self):
        result = self.check_catalog('"a" = "A"; "b" = "B";', '"a" = "Un";')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1/2", result.stdout)
        self.assertNotEqual(self.check_catalog('"a" = "A"; "b" = "B";', '"a" = "Un";', strict=True).returncode, 0)

    def test_rejects_unsafe_or_broken_edits(self):
        cases = [
            ('"key" = "%@";', '"key" = "%n";'),
            ('"key" = "%lu";', '"key" = "%ld";'),
            ('"key" = "%ld";', '"key" = "%999999999ld";'),
            ('"key" = "%@ %@";', '"key" = "%@";'),
            ('"key" = "%@";', '"key" = "%@ %@";'),
            ('"key" = "%@";', '"key" = "%2$@";'),
            ('"key" = "%@ %@";', '"key" = "%1$@ %@";'),
            ('"key" = "Value";', '"key" = "";'),
            ('"key" = "Value";', '"key" = "A"; "key" = "B";'),
            ('"key" = "Value";', '"renamed" = "Valeur";'),
            ('"key" = "Value";', '"key" = "Valeur"'),
            ('"key" = "Prefix: ";', '"key" = "Préfixe:";'),
            ('"key" = "Line\\nNext";', '"key" = "Ligne suivante";'),
            ('"key" = "CPU %% %@";', '"key" = "CPU % %@";'),
        ]
        for english, translated in cases:
            with self.subTest(translated=translated):
                self.assertNotEqual(self.check_catalog(english, translated).returncode, 0)

    def test_quotes_and_comments_remain_supported(self):
        result = self.check_catalog('/* comment */ "key" = "Say \\"yes\\"";', '// note\n"key" = "Dire \\"oui\\"";')
        self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == "__main__":
    unittest.main()
