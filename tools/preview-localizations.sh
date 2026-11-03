#!/bin/sh
# Reuse one owned Simulator for full acceptance in both appearances.
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -eq 0 ]; then
  set -- $(python3 -c 'from pathlib import Path; print(" ".join(sorted(p.stem for p in Path("Resources/Localizations").glob("*.lproj"))))')
fi
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in reversed(json.load(sys.stdin)["runtimes"]) if r["isAvailable"] and "iOS" in r["name"]))')
qa_sim=$(xcrun simctl create IEB-Localization-QA com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$runtime")
cleanup() {
  xcrun simctl shutdown "$qa_sim" >/dev/null 2>&1 || true
  xcrun simctl delete "$qa_sim"
}
trap cleanup EXIT INT TERM
for language in "$@"; do
  for appearance in light dark; do
    IEB_PREVIEW_LANGUAGE="$language" IEB_PREVIEW_APPEARANCE="$appearance" sh tools/preview-ui.sh "$qa_sim"
  done
done
