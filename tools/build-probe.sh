#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
python3 tools/build-localizations.py .build/IEBLocalizations.bundle
# Standalone metadata diagnostics intentionally run on unadmitted OS versions.
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tools/compatibility_probe.m tools/IEBCompatibilityEvidence.m -o .build/ieb-compatibility-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tests/PlatformSupportTests.m -o .build/ieb-platform-support-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror -Wl,-rpath,/usr/lib/swift \
  tools/device_probe.m tools/IEBProbeSupport.m tools/IEBProducerEvidence.m -o .build/ieb-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tests/SessionStateTests.m Sources/Session/IEBSessionState.m -o .build/ieb-session-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tools/accounting_probe.m tools/IEBProbeSupport.m Sources/Statistics/IEBEnergy*.m -o .build/ieb-accounting-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tools/session_observer.m Sources/Session/*.m -o .build/ieb-session-observer
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tests/SessionStoreTests.m Sources/Session/IEBSessionState.m Sources/Session/IEBSessionStore.m -o .build/ieb-session-store-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tools/activity_probe.m Sources/Statistics/IEBActivityEvidence.m Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/ieb-activity-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tests/ActivityEvidenceTests.m Sources/Statistics/IEBActivityEvidence.m -o .build/ieb-activity-tests
for kind in NativePowerWindow NativeJournal; do
  xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
    -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
    "tests/${kind}Tests.m" Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m \
    Sources/Session/IEBSessionState.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m \
    Sources/Statistics/IEBActivityEvidence.m -o ".build/ieb-${kind}-tests"
done
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tools/native_probe.m Sources/Statistics/IEBCaptureSnapshot.m Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m \
  Sources/Session/IEBSessionState.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m \
  Sources/Statistics/IEBActivityEvidence.m -o .build/ieb-native-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tests/CaptureSnapshotTests.m Sources/Statistics/IEBCaptureSnapshot.m Sources/Session/IEBNativePowerWindow.m \
  Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m \
  Sources/Statistics/IEBActivityEvidence.m -o .build/ieb-capture-snapshot-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -DIEB_NATIVE_CAPTURE_TESTING=1 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tests/NativeCaptureTests.m producerprobe/IEBNativeCapture.m producerprobe/IEBActivityCapture.m \
  Sources/Statistics/IEBCaptureSnapshot.m Sources/Session/IEBNativePowerWindow.m \
  Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m \
  Sources/Statistics/IEBActivityEvidence.m -o .build/ieb-native-capture-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tools/statistics_probe.m Sources/Statistics/*.m Sources/Session/IEBNativePowerWindow.m \
  Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/ieb-statistics-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror \
  tests/StatisticsModelTests.m Sources/Statistics/IEBScreenActivity.m -lsqlite3 Sources/Statistics/IEBStatisticsModel.m \
  Sources/Statistics/IEBEnergyIntervals.m Sources/Statistics/IEBActivityEvidence.m -o .build/ieb-statistics-model-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -framework UIKit -framework CoreGraphics -lsqlite3 -Wall -Wextra -Werror \
  tools/catalog_probe.m Sources/Presentation/IEBApplicationCatalog.m Sources/Statistics/*.m \
  Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m \
  Sources/Session/IEBSessionState.m -o .build/ieb-catalog-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tests/ScreenActivityTests.m Sources/Statistics/IEBScreenActivity.m -o .build/ieb-screen-activity-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -framework UIKit -framework CoreGraphics -lsqlite3 -Wall -Wextra -Werror \
  tools/process_probe.m Sources/Diagnostics/*.m Sources/Presentation/IEBApplicationCatalog.m Sources/Statistics/*.m \
  Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m Sources/Localization/IEBLocalization.m -o .build/ieb-process-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -framework UIKit -framework CoreGraphics -Wall -Wextra -Werror \
  tools/native_chart_probe.m Sources/Presentation/IEBNativeChartController.m Sources/Statistics/IEBNativeChartData.m -o .build/ieb-native-chart-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -framework UIKit -framework CoreGraphics -Wall -Wextra -Werror \
  tools/native_chart_attachment_probe.m Sources/Presentation/IEBNativeBatteryCells.m \
  Sources/Presentation/IEBNativeChartController.m Sources/Statistics/IEBNativeChartData.m -o .build/ieb-native-chart-attachment-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -framework UIKit -framework CoreGraphics -Wall -Wextra -Werror \
  tools/native_row_discovery_probe.m Sources/Presentation/IEBNativeBatteryCells.m \
  Sources/Presentation/IEBNativeChartController.m Sources/Statistics/IEBNativeChartData.m -o .build/ieb-native-row-discovery-probe
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror rootreader/main.m rootreader/IEBRootProcessServer.m \
  Sources/Diagnostics/IEBRootProcessClient.m Sources/Diagnostics/IEBRootProcessProtocol.m Sources/Diagnostics/IEBProcessSnapshot.m -o .build/ieb-root-reader
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror tests/RootProcessTransportTests.m rootreader/IEBRootProcessServer.m \
  Sources/Diagnostics/IEBRootProcessClient.m Sources/Diagnostics/IEBRootProcessProtocol.m Sources/Diagnostics/IEBProcessSnapshot.m -o .build/ieb-root-transport-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror tests/ReadableDiagnosticTests.m Sources/Diagnostics/IEBDiagnosticReport.m \
  Sources/Diagnostics/IEBProcessReaderStatus.m Sources/Statistics/IEBDataQuality.m Sources/Localization/IEBLocalization.m -o .build/ieb-readable-report-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror tests/DiagnosticExportTests.m Sources/Diagnostics/IEBDiagnosticExport.m Sources/Localization/IEBLocalization.m -o .build/ieb-diagnostic-export-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -lsqlite3 -Wall -Wextra -Werror tests/CycleHistoryTests.m Sources/Statistics/*.m \
  Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/ieb-cycle-history-tests
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc \
  -framework Foundation -Wall -Wextra -Werror tests/ProcessQueryTests.m Sources/Diagnostics/IEBProcessQuery.m -o .build/ieb-process-query-tests
# Local jailbreak execution needs an ad-hoc signature; the CI build need not run on device.
if command -v ldid >/dev/null 2>&1; then
  ldid -S .build/ieb-platform-support-tests
  ldid -S .build/ieb-cycle-history-tests
  ldid -S .build/ieb-process-query-tests
  ldid -S .build/ieb-readable-report-tests
  ldid -S .build/ieb-diagnostic-export-tests
  ldid -S .build/ieb-native-chart-probe
  ldid -S .build/ieb-native-chart-attachment-probe
  ldid -S .build/ieb-native-row-discovery-probe
  ldid -S .build/ieb-process-probe
  ldid -S .build/ieb-root-reader
  ldid -S .build/ieb-root-transport-tests
  ldid -S .build/ieb-compatibility-probe
  ldid -S .build/ieb-probe
  ldid -S .build/ieb-screen-activity-tests
  ldid -S .build/ieb-catalog-probe
  ldid -S .build/ieb-session-tests
  ldid -S .build/ieb-accounting-probe
  ldid -S .build/ieb-session-observer
  ldid -S .build/ieb-session-store-tests
  ldid -S .build/ieb-activity-probe
  ldid -S .build/ieb-activity-tests
  ldid -S .build/ieb-NativePowerWindow-tests
  ldid -S .build/ieb-NativeJournal-tests
  ldid -S .build/ieb-native-probe
  ldid -S .build/ieb-statistics-probe
  ldid -S .build/ieb-statistics-model-tests
  ldid -S .build/ieb-capture-snapshot-tests
  ldid -S .build/ieb-native-capture-tests
fi
