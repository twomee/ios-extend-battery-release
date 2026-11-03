#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/PlatformSupportTests.m -o .build/platform-support-tests
LLVM_PROFILE_FILE=.build/platform-support.profraw .build/platform-support-tests
xcrun llvm-profdata merge -sparse .build/platform-support.profraw -o .build/platform-support.profdata
xcrun llvm-cov report .build/platform-support-tests -instr-profile=.build/platform-support.profdata Sources/Compatibility/IEBPlatformSupport.h

xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/ProbeSupportTests.m tests/ProducerEvidenceTests.m tools/IEBProbeSupport.m tools/IEBProducerEvidence.m -o .build/probe-tests
LLVM_PROFILE_FILE=.build/probe-tests.profraw .build/probe-tests
xcrun llvm-profdata merge -sparse .build/probe-tests.profraw -o .build/probe-tests.profdata
xcrun llvm-cov report .build/probe-tests -instr-profile=.build/probe-tests.profdata tools/IEBProbeSupport.m tools/IEBProducerEvidence.m
xcrun llvm-cov export .build/probe-tests -instr-profile=.build/probe-tests.profdata \
  -summary-only tools/IEBProbeSupport.m tools/IEBProducerEvidence.m > .build/coverage.json
python3 -c 'import json; d=json.load(open(".build/coverage.json")); p=d["data"][0]["totals"]["lines"]["percent"]; print(f"Probe response evaluator line coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)'

python3 -m unittest discover -s tests -p 'test_*.py'

xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/SessionStateTests.m Sources/Session/IEBSessionState.m -o .build/session-tests
LLVM_PROFILE_FILE=.build/session-tests.profraw .build/session-tests
xcrun llvm-profdata merge -sparse .build/session-tests.profraw -o .build/session-tests.profdata
xcrun llvm-cov report .build/session-tests -instr-profile=.build/session-tests.profdata Sources/Session/IEBSessionState.m
xcrun llvm-cov export .build/session-tests -instr-profile=.build/session-tests.profdata \
  -summary-only Sources/Session/IEBSessionState.m > .build/session-coverage.json
python3 -c 'import json; p=json.load(open(".build/session-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Session model line coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)'


xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/SessionStoreTests.m Sources/Session/IEBSessionState.m Sources/Session/IEBSessionStore.m -o .build/session-store-tests
LLVM_PROFILE_FILE=.build/session-store.profraw .build/session-store-tests
xcrun llvm-profdata merge -sparse .build/session-store.profraw -o .build/session-store.profdata
xcrun llvm-cov report .build/session-store-tests -instr-profile=.build/session-store.profdata Sources/Session/IEBSessionStore.m
xcrun llvm-cov export .build/session-store-tests -instr-profile=.build/session-store.profdata \
  -summary-only Sources/Session/IEBSessionStore.m > .build/session-store-coverage.json
python3 -c 'import json; p=json.load(open(".build/session-store-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Session store line coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)'

xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  -fprofile-instr-generate -fcoverage-mapping \
  tests/ActivityEvidenceTests.m Sources/Statistics/IEBActivityEvidence.m -o .build/activity-tests
LLVM_PROFILE_FILE=.build/activity.profraw .build/activity-tests
xcrun llvm-profdata merge -sparse .build/activity.profraw -o .build/activity.profdata
xcrun llvm-cov export .build/activity-tests -instr-profile=.build/activity.profdata \
  -summary-only Sources/Statistics/IEBActivityEvidence.m > .build/activity-coverage.json
python3 -c 'import json; p=json.load(open(".build/activity-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Activity evaluator line coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)'

# Real collector/timer/file integration; fake only the external power observer.
# Production builds never enable the test directory or accelerated timer.
xcrun clang -DIEB_ACTIVITY_CAPTURE_TESTING=1 -fobjc-arc -framework Foundation -Wall -Wextra -Werror \
  tests/ActivityCaptureTests.m producerprobe/IEBActivityCapture.m producerprobe/IEBNativeCapture.m \
  Sources/Statistics/IEBActivityEvidence.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m Sources/Session/IEBNativePowerWindow.m \
  -lsqlite3 Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/activity-capture-tests
for scenario in start-failure runtime-failure corrupt; do
  .build/activity-capture-tests "$scenario"
done

for kind in Interval Reader; do
  xcrun clang -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
    -fprofile-instr-generate -fcoverage-mapping \
    "tests/Energy${kind}Tests.m" Sources/Statistics/IEBEnergy*.m -o ".build/energy-${kind}-tests"
  LLVM_PROFILE_FILE=".build/energy-${kind}.profraw" ".build/energy-${kind}-tests"
done
xcrun llvm-profdata merge -sparse .build/energy-Interval.profraw .build/energy-Reader.profraw -o .build/energy.profdata
xcrun llvm-cov report .build/energy-Reader-tests -instr-profile=.build/energy.profdata Sources/Statistics/IEBEnergy*.m
xcrun llvm-cov export .build/energy-Reader-tests -instr-profile=.build/energy.profdata \
  -summary-only Sources/Statistics/IEBEnergy*.m > .build/energy-coverage.json
python3 -c 'import json; p=json.load(open(".build/energy-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Energy source line coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)'

# Native source journal and its actual asynchronous collector integration.
for kind in NativePowerWindow NativeJournal; do
  xcrun clang -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
    -fprofile-instr-generate -fcoverage-mapping "tests/${kind}Tests.m" \
    Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m \
    Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m Sources/Statistics/IEBActivityEvidence.m -o ".build/${kind}-tests"
  LLVM_PROFILE_FILE=".build/${kind}.profraw" ".build/${kind}-tests"
  xcrun llvm-profdata merge -sparse ".build/${kind}.profraw" -o ".build/${kind}.profdata"
  case "$kind" in
    NativePowerWindow) source_file=Sources/Session/IEBNativePowerWindow.m ;;
    NativeJournal) source_file=Sources/Statistics/IEBNativeJournal.m ;;
  esac
  xcrun llvm-cov export ".build/${kind}-tests" -instr-profile=".build/${kind}.profdata" \
    -summary-only "$source_file" > ".build/${kind}-coverage.json"
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]["percent"]; print(f"{sys.argv[2]} coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)' ".build/${kind}-coverage.json" "$kind"
done
xcrun clang -fprofile-instr-generate -fcoverage-mapping -DIEB_NATIVE_CAPTURE_TESTING=1 -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tests/NativeCaptureTests.m producerprobe/IEBNativeCapture.m producerprobe/IEBActivityCapture.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m Sources/Statistics/IEBCaptureSnapshot.m \
  Sources/Statistics/IEBActivityEvidence.m Sources/Session/IEBNativePowerWindow.m \
  Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/native-capture-tests
for scenario in bridge throwing clock metadata storage gap-rejected; do
  LLVM_PROFILE_FILE=".build/native-capture-${scenario}.profraw" .build/native-capture-tests "$scenario"
done

xcrun clang -fprofile-instr-generate -fcoverage-mapping -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror \
  tests/CaptureSnapshotTests.m Sources/Statistics/IEBCaptureSnapshot.m Sources/Statistics/IEBNativeJournal.m Sources/Statistics/IEBCycleSummary.m \
  Sources/Statistics/IEBActivityEvidence.m Sources/Session/IEBNativePowerWindow.m \
  Sources/Session/IEBSessionStore.m Sources/Session/IEBSessionState.m -o .build/capture-snapshot-tests
LLVM_PROFILE_FILE=.build/capture-snapshot.profraw .build/capture-snapshot-tests

xcrun llvm-profdata merge -sparse .build/native-capture-*.profraw -o .build/native-capture.profdata
xcrun llvm-profdata merge -sparse .build/capture-snapshot.profraw -o .build/capture-snapshot.profdata
for kind in native-capture capture-snapshot; do
  case "$kind" in
    native-capture) source_file=producerprobe/IEBNativeCapture.m ;;
    capture-snapshot) source_file=Sources/Statistics/IEBCaptureSnapshot.m ;;
  esac
  xcrun llvm-cov export ".build/${kind}-tests" -instr-profile=".build/${kind}.profdata" \
    -summary-only "$source_file" > ".build/${kind}-coverage.json"
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]["percent"]; print(f"{sys.argv[2]} coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p >= 50 else 1)' ".build/${kind}-coverage.json" "$kind"
done

xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping \
  tests/StatisticsModelTests.m Sources/Statistics/IEBScreenActivity.m -lsqlite3 Sources/Statistics/IEBStatisticsModel.m Sources/Statistics/IEBEnergyIntervals.m \
  Sources/Statistics/IEBActivityEvidence.m -o .build/statistics-model-tests
LLVM_PROFILE_FILE=.build/statistics-model.profraw .build/statistics-model-tests
xcrun llvm-profdata merge -sparse .build/statistics-model.profraw -o .build/statistics-model.profdata
xcrun llvm-cov export .build/statistics-model-tests -instr-profile=.build/statistics-model.profdata \
  -summary-only Sources/Statistics/IEBStatisticsModel.m > .build/statistics-model-coverage.json
python3 -c 'import json; p=json.load(open(".build/statistics-model-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Statistics model coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Source category membership must not change accounting totals or app background ownership.
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping \
  tests/SourceGroupsTests.m Sources/Statistics/IEBSourceGroups.m -o .build/source-groups-tests
LLVM_PROFILE_FILE=.build/source-groups.profraw .build/source-groups-tests
xcrun llvm-profdata merge -sparse .build/source-groups.profraw -o .build/source-groups.profdata
xcrun llvm-cov export .build/source-groups-tests -instr-profile=.build/source-groups.profdata \
  -summary-only Sources/Statistics/IEBSourceGroups.m > .build/source-groups-coverage.json
python3 -c 'import json; p=json.load(open(".build/source-groups-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Source groups coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

xcrun clang -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping \
  tests/ScreenActivityTests.m Sources/Statistics/IEBScreenActivity.m -o .build/screen-activity-tests
LLVM_PROFILE_FILE=.build/screen-activity.profraw .build/screen-activity-tests
xcrun llvm-profdata merge -sparse .build/screen-activity.profraw -o .build/screen-activity.profdata
xcrun llvm-cov export .build/screen-activity-tests -instr-profile=.build/screen-activity.profdata \
  -summary-only Sources/Statistics/IEBScreenActivity.m > .build/screen-activity-coverage.json
python3 -c 'import json; p=json.load(open(".build/screen-activity-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Screen activity coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Native chart adapter and process diagnostics preserve unavailable/ambiguous values.
for diagnostic in NativeChartData ProcessSnapshot ProcessAttribution; do
  case "$diagnostic" in
    NativeChartData) diagnostic_sources="Sources/Statistics/IEBNativeChartData.m" ;;
    *) diagnostic_sources="Sources/Diagnostics/IEBProcessSnapshot.m Sources/Diagnostics/IEBProcessAttribution.m" ;;
  esac
  xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping "tests/${diagnostic}Tests.m" $diagnostic_sources -o ".build/${diagnostic}-tests"
  LLVM_PROFILE_FILE=".build/${diagnostic}.profraw" ".build/${diagnostic}-tests"
  xcrun llvm-profdata merge -sparse ".build/${diagnostic}.profraw" -o ".build/${diagnostic}.profdata"
  case "$diagnostic" in
    NativeChartData) diagnostic_coverage=Sources/Statistics/IEBNativeChartData.m ;;
    *) diagnostic_coverage="Sources/Diagnostics/IEB${diagnostic}.m" ;;
  esac
  xcrun llvm-cov export ".build/${diagnostic}-tests" -instr-profile=".build/${diagnostic}.profdata" -summary-only "$diagnostic_coverage" > ".build/${diagnostic}-coverage.json"
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]["percent"]; print(f"{sys.argv[2]} coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)' ".build/${diagnostic}-coverage.json" "$diagnostic"
done

# Privileged-reader boundary: schema/auth policy and real anonymous XPC transport.
for root_case in Protocol Transport; do
  root_sources="Sources/Diagnostics/IEBRootProcessProtocol.m"
  if [ "$root_case" = Transport ]; then
    root_sources="$root_sources Sources/Diagnostics/IEBRootProcessClient.m Sources/Diagnostics/IEBProcessSnapshot.m rootreader/IEBRootProcessServer.m"
  fi
  xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping "tests/RootProcess${root_case}Tests.m" $root_sources -o ".build/root-${root_case}-tests"
  LLVM_PROFILE_FILE=".build/root-${root_case}.profraw" ".build/root-${root_case}-tests"
  xcrun llvm-profdata merge -sparse ".build/root-${root_case}.profraw" -o ".build/root-${root_case}.profdata"
  case "$root_case" in
    Protocol) root_coverage=Sources/Diagnostics/IEBRootProcessProtocol.m ;;
    Transport) root_coverage=Sources/Diagnostics/IEBRootProcessClient.m ;;
  esac
  xcrun llvm-cov export ".build/root-${root_case}-tests" -instr-profile=".build/root-${root_case}.profdata" -summary-only "$root_coverage" > ".build/root-${root_case}-coverage.json"
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]["percent"]; print(f"Root {sys.argv[2]} coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)' ".build/root-${root_case}-coverage.json" "$root_case"
done
for root_script in producerprobe/layout/DEBIAN/postinst producerprobe/layout/DEBIAN/prerm; do sh -n "$root_script"; done
python3 tools/test_root_layout.py

# Freshness metadata must not certify per-app coverage from global watermarks.
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/DataQualityTests.m Sources/Statistics/IEBDataQuality.m -o .build/data-quality-tests
LLVM_PROFILE_FILE=.build/data-quality.profraw .build/data-quality-tests
xcrun llvm-profdata merge -sparse .build/data-quality.profraw -o .build/data-quality.profdata
xcrun llvm-cov export .build/data-quality-tests -instr-profile=.build/data-quality.profdata -summary-only Sources/Statistics/IEBDataQuality.m > .build/data-quality-coverage.json
python3 -c 'import json; p=json.load(open(".build/data-quality-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Data quality coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

for diagnostic in ProcessReaderStatus DiagnosticReport; do
  xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping "tests/${diagnostic}Tests.m" Sources/Diagnostics/IEBProcessReaderStatus.m Sources/Diagnostics/IEBDiagnosticReport.m Sources/Statistics/IEBDataQuality.m -o ".build/${diagnostic}-tests"
  LLVM_PROFILE_FILE=".build/${diagnostic}.profraw" ".build/${diagnostic}-tests"
  xcrun llvm-profdata merge -sparse ".build/${diagnostic}.profraw" -o ".build/${diagnostic}.profdata"
  if [ "$diagnostic" = DiagnosticReport ]; then
    xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/ReadableDiagnosticTests.m Sources/Diagnostics/IEBProcessReaderStatus.m Sources/Diagnostics/IEBDiagnosticReport.m Sources/Statistics/IEBDataQuality.m -o .build/readable-report-tests
    LLVM_PROFILE_FILE=.build/readable-report.profraw .build/readable-report-tests
    xcrun llvm-profdata merge -sparse ".build/${diagnostic}.profraw" .build/readable-report.profraw -o ".build/${diagnostic}.profdata"
  fi
  xcrun llvm-cov export ".build/${diagnostic}-tests" -instr-profile=".build/${diagnostic}.profdata" -summary-only "Sources/Diagnostics/IEB${diagnostic}.m" > ".build/${diagnostic}-coverage.json"
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]["percent"]; print(f"{sys.argv[2]} coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)' ".build/${diagnostic}-coverage.json" "$diagnostic"
done

xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/DiagnosticExportTests.m Sources/Diagnostics/IEBDiagnosticExport.m -o .build/diagnostic-export-tests
LLVM_PROFILE_FILE=.build/diagnostic-export.profraw .build/diagnostic-export-tests
xcrun llvm-profdata merge -sparse .build/diagnostic-export.profraw -o .build/diagnostic-export.profdata
xcrun llvm-cov export .build/diagnostic-export-tests -instr-profile=.build/diagnostic-export.profdata -summary-only Sources/Diagnostics/IEBDiagnosticExport.m > .build/diagnostic-export-coverage.json
python3 -c 'import json; p=json.load(open(".build/diagnostic-export-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Diagnostic export coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Presentation search must retain unknown measurements and immutable full samples.
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/ProcessQueryTests.m Sources/Diagnostics/IEBProcessQuery.m -o .build/process-query-tests
LLVM_PROFILE_FILE=.build/process-query.profraw .build/process-query-tests
xcrun llvm-profdata merge -sparse .build/process-query.profraw -o .build/process-query.profdata
xcrun llvm-cov export .build/process-query-tests -instr-profile=.build/process-query.profdata -summary-only Sources/Diagnostics/IEBProcessQuery.m > .build/process-query-coverage.json
python3 -c 'import json; p=json.load(open(".build/process-query-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Process query coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Real private SQLite archive, restart/clock boundaries and lazy native enrichment.
xcrun clang -fobjc-arc -framework Foundation -lsqlite3 -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/CycleHistoryTests.m Sources/Statistics/*.m Sources/Session/IEBNativePowerWindow.m Sources/Session/IEBSessionState.m Sources/Session/IEBSessionStore.m -o .build/cycle-history-tests
LLVM_PROFILE_FILE=.build/cycle-history.profraw .build/cycle-history-tests
xcrun llvm-profdata merge -sparse .build/cycle-history.profraw -o .build/cycle-history.profdata
xcrun llvm-cov export .build/cycle-history-tests -instr-profile=.build/cycle-history.profdata -summary-only Sources/Statistics/IEBCycleSummary.m > .build/cycle-history-coverage.json
python3 -c 'import json; p=json.load(open(".build/cycle-history-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Cycle summary coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Synthetic availability orders exercise bootstrap retry, not foreign-OS compatibility.
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/CollectorBootstrapTests.m Sources/Compatibility/IEBCollectorBootstrap.m -o .build/collector-bootstrap-tests
LLVM_PROFILE_FILE=.build/collector-bootstrap.profraw .build/collector-bootstrap-tests
xcrun llvm-profdata merge -sparse .build/collector-bootstrap.profraw -o .build/collector-bootstrap.profdata
xcrun llvm-cov export .build/collector-bootstrap-tests -instr-profile=.build/collector-bootstrap.profdata -summary-only Sources/Compatibility/IEBCollectorBootstrap.m > .build/collector-bootstrap-coverage.json
python3 -c 'import json; p=json.load(open(".build/collector-bootstrap-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Collector bootstrap coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'

# Metadata diagnostics must never confuse selector presence with supported runtime behavior.
xcrun clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror -fprofile-instr-generate -fcoverage-mapping tests/CompatibilityEvidenceTests.m tools/IEBCompatibilityEvidence.m -o .build/compatibility-evidence-tests
LLVM_PROFILE_FILE=.build/compatibility-evidence.profraw .build/compatibility-evidence-tests
xcrun llvm-profdata merge -sparse .build/compatibility-evidence.profraw -o .build/compatibility-evidence.profdata
xcrun llvm-cov export .build/compatibility-evidence-tests -instr-profile=.build/compatibility-evidence.profdata -summary-only tools/IEBCompatibilityEvidence.m > .build/compatibility-evidence-coverage.json
python3 -c 'import json; p=json.load(open(".build/compatibility-evidence-coverage.json"))["data"][0]["totals"]["lines"]["percent"]; print(f"Compatibility evidence coverage: {p:.1f}% (minimum 50%)"); raise SystemExit(0 if p>=50 else 1)'
