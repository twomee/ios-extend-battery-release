#!/usr/bin/env python3
"""Validate community .strings files without requiring Xcode or a jailbreak."""
import argparse
import json
import re
import sys
from pathlib import Path

TOKEN = r'"(?:\\.|[^"\\])*"'
ENTRY = re.compile(rf'({TOKEN})\s*=\s*({TOKEN})\s*;', re.S)
SPACE = re.compile(r'\s+|/\*.*?\*/|//[^\n]*(?:\n|$)', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+#0 \']*(?:\d+)?(?:\.\d+)?(hh|ll|[hlqztjL])?([@diuoxXfFeEgGaAcCsSpn%])')
LANGUAGE = re.compile(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\Z')

def read_strings(path):
    return parse_strings(Path(path).read_text(encoding='utf-8-sig'), str(path))

def parse_strings(text, path='<strings>'):
    result = {}
    offset = 0
    while offset < len(text):
        skip = SPACE.match(text, offset)
        if skip:
            offset = skip.end()
            continue
        entry = ENTRY.match(text, offset)
        if not entry:
            raise ValueError(f'{path}: invalid .strings syntax at line {text.count(chr(10), 0, offset) + 1}')
        key, value = (json.loads(re.sub(r'\\U([0-9a-fA-F]{4})', r'\\u\1', item)) for item in entry.groups())
        if key in result:
            raise ValueError(f'{path}: duplicate key {key}')
        if not value.strip():
            raise ValueError(f'{path}: empty translation for {key}')
        result[key] = value
        offset = entry.end()
    return result

def format_signature(text):
    arguments = {}
    next_argument = 1
    modes = set()
    offset = 0
    while offset < len(text):
        start = text.find('%', offset)
        if start < 0:
            break
        match = FORMAT.match(text, start)
        if not match or match.group(3) == 'n':
            raise ValueError('invalid or unsafe printf placeholder')
        position, length, conversion = match.groups()
        offset = match.end()
        if conversion == '%':
            if match.group(0) != '%%':
                raise ValueError('literal percent must be %%')
            continue
        modes.add(bool(position))
        index = int(position) if position else next_argument
        next_argument += not bool(position)
        if index < 1 or index > 64:
            raise ValueError('invalid printf argument index')
        kind = re.sub(r'^%\d+\$', '%', match.group(0))
        if index in arguments and arguments[index] != kind:
            raise ValueError('conflicting printf argument types')
        arguments[index] = kind
    if len(modes) > 1:
        raise ValueError('do not mix positional and sequential printf placeholders')
    return arguments

def validate(resources, strict=False):
    resources = Path(resources)
    base = read_strings(resources / 'en.lproj' / 'Localizable.strings')
    if not base:
        raise ValueError('English source catalog is empty')
    base_formats = {key: format_signature(value) for key, value in base.items()}
    files = sorted(resources.glob('*.lproj/Localizable.strings'))
    for path in files:
        language = path.parent.stem
        if not LANGUAGE.fullmatch(language):
            raise ValueError(f'{path}: invalid language directory')
        values = read_strings(path)
        unknown = values.keys() - base.keys()
        missing = base.keys() - values.keys()
        if unknown:
            raise ValueError(f'{path}: unknown keys: {", ".join(sorted(unknown))}')
        if missing and strict:
            raise ValueError(f'{path}: missing {len(missing)} English keys')
        for key, value in values.items():
            if format_signature(value) != base_formats[key]:
                raise ValueError(f'{path}: printf arguments differ for {key}')
            original = base[key]
            whitespace = lambda s: (re.match(r'\s*', s)[0], re.search(r'\s*\Z', s)[0], s.count('\n'))
            if whitespace(value) != whitespace(original):
                raise ValueError(f'{path}: preserve outer whitespace and newline count for {key}')
        suffix = f'; {len(missing)} use English fallback' if missing else ''
        print(f'{language}: {len(values)}/{len(base)} entries{suffix}')
    return files

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=Path(__file__).resolve().parents[1] / 'Resources/Localizations')
    parser.add_argument('--strict', action='store_true', help='also require every English key in every language')
    args = parser.parse_args()
    try:
        validate(args.resources, args.strict)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
