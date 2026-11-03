#!/bin/sh
# Synthetic UIKit acceptance. Never operates another simulator without its explicit ID.
set -eu
cd "$(dirname "$0")/.."
preview_language=${IEB_PREVIEW_LANGUAGE:-he}
preview_appearance=${IEB_PREVIEW_APPEARANCE:-light}
case "$preview_language" in
  en) preview_locale=en_US ;;
  he) preview_locale=he_IL ;;
  *) echo "IEB_PREVIEW_LANGUAGE must be en or he" >&2; exit 2 ;;
esac
case "$preview_appearance" in
  light|dark) ;;
  *) echo "IEB_PREVIEW_APPEARANCE must be light or dark" >&2; exit 2 ;;
esac
preview_device=${1:-}
created=0
if [ -z "$preview_device" ]; then
  runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in reversed(json.load(sys.stdin)["runtimes"]) if r["isAvailable"] and "iOS" in r["name"]))')
  preview_device=$(xcrun simctl create IEB-Preview-QA com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$runtime")
  created=1
fi
cleanup() {
  if [ "$created" -eq 1 ]; then
    xcrun simctl shutdown "$preview_device" >/dev/null 2>&1 || true
    xcrun simctl delete "$preview_device"
  fi
}
trap cleanup EXIT INT TERM
app=.build/preview/IEBPreview.app
mkdir -p "$app"
python3 - "$app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.idonamaan.ieb-preview', CFBundleExecutable='IEBPreview', CFBundleName='IEB Preview', CFBundlePackageType='APPL', CFBundleVersion='2', CFBundleShortVersionString='0.2', MinimumOSVersion='17.0', UIDeviceFamily=[1], UILaunchScreen={}, CFBundleLocalizations=['en','he']),f)
PY
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc \
  -framework UIKit -framework Foundation -framework CoreGraphics -Wall -Wextra -Werror \
  tests/StatisticsPreview.m Sources/Presentation/*.m Sources/Diagnostics/*.m Sources/Statistics/*.m \
  Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -lsqlite3 -o "$app/IEBPreview"
xcrun simctl boot "$preview_device" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$preview_device" -b >/dev/null
xcrun simctl terminate "$preview_device" com.idonamaan.ieb-preview >/dev/null 2>&1 || true
xcrun simctl install "$preview_device" "$app"
data=$(xcrun simctl get_app_container "$preview_device" com.idonamaan.ieb-preview data)
rm -f "$data/Documents/qa.plist"
xcrun simctl ui "$preview_device" appearance "$preview_appearance"
xcrun simctl launch "$preview_device" com.idonamaan.ieb-preview -AppleLanguages "($preview_language)" -AppleLocale "$preview_locale" -IEBPreviewLanguage "$preview_language" -IEBPreviewAppearance "$preview_appearance"

python3 - "$data/Documents" "$preview_language" "$preview_appearance" <<'PY'
import pathlib,plistlib,shutil,sys,time
source=pathlib.Path(sys.argv[1])
language, appearance = sys.argv[2:]
target=pathlib.Path('.build/preview') / f'results-{language}-{appearance}'
target.mkdir(exist_ok=True)
for _ in range(30):
    if (source/'qa.plist').exists(): break
    time.sleep(1)
with (source/'qa.plist').open('rb') as f: qa=plistlib.load(f)
print(qa)
for name in ('preview.png','apps.png','details.png','panel.png','panel-scrolled.png','processes.png','history.png','comparison.png','qa.plist'): shutil.copyfile(source/name,target/name)
if language == 'he' and appearance == 'light':
    legacy=pathlib.Path('.build/preview/results'); legacy.mkdir(exist_ok=True)
    for path in target.iterdir(): shutil.copyfile(path,legacy/path.name)
print(f'Preview results: {target}')
assert qa['language'] == language and qa['appearance'] == appearance
assert qa['sections']==7 and qa['summary_rows']==3 and qa['app_rows']==2
required = ('language_selected','appearance_selected','layout_direction','panel_rebound','selection','reset','details','categories','app_icon','refresh_coalesced','clear_duration','missing_percent_explained','panel_scroll_stable','overview_retained','repeat_chart_tap','level_chart_tap','percent_column','cycle_reset','native_chart_host','live_processes','quality_and_report','unavailable_diagnostics','cycle_history')
failed = [key for key in required if not qa[key]]
assert not failed, f'Failed preview checks: {failed}'
PY
