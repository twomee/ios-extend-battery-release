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
.build/venv/bin/clang-format --dry-run --Werror tools/*.m tools/*.h tests/*.m Sources/Session/*.[hm] Sources/Statistics/*.[hm] Sources/Presentation/*.[hm] Sources/Diagnostics/*.[hm] Sources/Compatibility/*.[hm] Sources/Localization/*.[hm] rootreader/*.[hm] producerprobe/*.[hm]
sh tools/test.sh
sh tools/build-probe.sh
THEOS="$HOME/theos" make -C producerprobe package FINALPACKAGE=1
```

For UI changes, run every supported language in both appearances on an installed Simulator runtime:

```sh
sh tools/preview-localizations.sh
```

The UIKit preview uses fixtures; it does not certify private battery APIs on a device. The package build also verifies root ownership and embedded license files. The root-level Makefile builds a historical prototype; use `producerprobe` for the current tweak.

Install the optional local hooks with `pre-commit install` after installing pre-commit and Gitleaks. Formatting and secret checks run before commits; the full suite runs before pushes. Run `.build/venv/bin/pip-audit -r requirements-dev.txt` to audit development dependencies locally. CI configuration covers formatting, tests, coverage, builds and security scans. Cloud checks may be skipped when the owner's Actions quota is exhausted; report local results honestly and leave the PR unmerged until the required checks can run.

## Compatibility diagnostics

`sh tools/build-probe.sh` also builds/signs `.build/ieb-compatibility-probe` with an iOS15 deployment minimum. Copy this standalone executable to an appropriate device using your existing trusted SSH setup, then run `./ieb-compatibility-probe settings` and `./ieb-compatibility-probe collector` separately. It loads a fixed framework list and reads method/ivar metadata, including inherited and category methods. It installs no hooks and invokes no private selectors or battery-history queries. Framework loading can produce system logs. A 20-second alarm bounds inspection and terminates only this diagnostic if loading stalls (no JSON report in that case).

The aggregate JSON contains OS identity, image availability and exact encoding comparisons; no app/process history or credentials. The collector scope isolates framework initialization in a child process with a 25-second parent limit. If a framework exits before reporting, the parent returns `environment_unavailable` with unknown observations, failure stage and child exit/signal, rather than claiming an ABI mismatch. Native child logs are not exported.

Exit22 means metadata matched,20 means unavailable/incomplete,21 means ABI mismatch,23 means invalid evidence/inspection failure,64 means invalid arguments,74 means report output failed. A match never certifies support. Missing classes in a standalone or Simulator process do not prove that device Settings lacks them. Simulator build identity is unavailable in this report; record the runtime version/build separately with `simctl list runtimes -j`. Keep collected reports outside Git.

The shipping version gate is unchanged. Additional device acceptance must verify injection, clocks, live database semantics, chart lifecycle and accounting before broadening it.

## Design and review

Keep collection, persistence, statistics, privileged IPC and UI separate. Preserve unknown/partial measurements and native chart ownership. CPU time is not battery energy. OS support is checked in `Sources/Compatibility/IEBPlatformSupport.h`; broaden it only after actual-device validation, including version/build and private API behavior.

Add regression tests for behavior changes and run the full suite. Do not commit device data, credentials, Apple firmware or generated binaries. Keep dependency attribution in `THIRD_PARTY_NOTICES.md`.

Contributions are accepted under the [MIT license](LICENSE).

## Translations

See [TRANSLATING.md](TRANSLATING.md) for web-based edits, new languages, format validation and translation status. UI and readable reports share a dedicated offline resource bundle. Missing entries use English; malformed translation formats fail validation.
