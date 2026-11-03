# Licensing scope and third-party components

The [MIT license](LICENSE) covers this project's original source and documentation. Third-party software and Apple intellectual property retain their own licenses and rights. This repository does not distribute Apple SDKs, frameworks or private device databases.

## Build tools (not vendored in this source snapshot)

- **Theos / Logos**: GPL-3.0-or-later with the upstream statement that projects created using Theos/Logos are not required to use GPL. Follow the license supplied with the pinned Theos checkout when redistributing Theos itself. CI references an upstream commit, not a bundled copy. [Upstream repository](https://github.com/theos/theos).
- **Xcode / Apple SDKs and system frameworks**: separately provided by Apple; not included in the source release or installer. Private API declarations, selectors and observed ABI are compatibility information, not a grant to redistribute Apple's framework binaries, application icons or SDKs.
- **ldid**: an external signing tool, not included. Its license remains the license of the chosen upstream distribution.
- **Python, clang-format, pre-commit, Gitleaks, Trivy and GitHub Actions**: external development/CI tools under their respective licenses. They are not bundled into the tweak or relabeled as MIT by this repository.

## Runtime dependencies

- **UIKit, Foundation, CoreGraphics, libproc, XPC and other OS facilities** are supplied by the device. No Apple framework binaries or private device databases are distributed in the release snapshot.
- **SQLite** is linked as a system library; no separately vendored SQLite source or library is included.
- **Substrate-compatible injection (`mobilesubstrate`) / the installed jailbreak environment** is supplied separately. The package does not distribute or license a jailbreak, certify its supported firmware, or bundle its implementation.

The binary installer includes the project's MIT license and this notice under `/var/jb/usr/share/doc/com.idonamaan.iebproducerprobe/`. Distributors should retain both. New external code/assets must carry their original license/attribution and be recorded here before inclusion.
