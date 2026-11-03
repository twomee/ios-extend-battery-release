# Contributing

Open an issue, create a branch from the current development revision, and submit a pull request explaining the problem, change and validation.

## Setup

Use macOS with Xcode, Python 3.11+ and Theos (CI uses Python 3.14). No cloud credentials are required to build or test.

```sh
python3 -m venv .build/venv
.build/venv/bin/pip install -r requirements-dev.txt
```

## Local checks

```sh
.build/venv/bin/clang-format --dry-run --Werror tools/*.m tools/*.h tests/*.m Sources/Session/*.[hm] Sources/Statistics/*.[hm] Sources/Presentation/*.[hm] Sources/Diagnostics/*.[hm] Sources/Compatibility/*.h rootreader/*.[hm] producerprobe/*.[hm]
sh tools/test.sh
sh tools/build-probe.sh
THEOS="$HOME/theos" make -C producerprobe package FINALPACKAGE=1
```

For UI changes, run both languages and appearances on an installed Simulator runtime:

```sh
for language in en he; do
  for appearance in light dark; do
    IEB_PREVIEW_LANGUAGE="$language" IEB_PREVIEW_APPEARANCE="$appearance" sh tools/preview-ui.sh
  done
done
```

The UIKit preview uses fixtures; it does not certify private battery APIs on a device. The package build also verifies root ownership and embedded license files. The root-level Makefile builds a historical prototype; use `producerprobe` for the current tweak.

Install the optional local hooks with `pre-commit install` after installing pre-commit and Gitleaks. Formatting and secret checks run before commits; the full suite runs before pushes. Run `.build/venv/bin/pip-audit -r requirements-dev.txt` to audit development dependencies locally. CI configuration covers formatting, tests, coverage, builds and security scans. Cloud checks may be skipped when the owner's Actions quota is exhausted; report local results honestly and leave the PR unmerged until the required checks can run.

## Design and review

Keep collection, persistence, statistics, privileged IPC and UI separate. Preserve unknown/partial measurements and native chart ownership. CPU time is not battery energy. OS support is checked in `Sources/Compatibility/IEBPlatformSupport.h`; broaden it only after actual-device validation, including version/build and private API behavior.

Add regression tests for behavior changes and run the full suite. Do not commit device data, credentials, Apple firmware or generated binaries. Keep dependency attribution in `THIRD_PARTY_NOTICES.md`.

Contributions are accepted under the [MIT license](LICENSE).
