#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
/// Mach absolute ticks to seconds; NAN for an invalid timebase.
FOUNDATION_EXPORT double IEBProcessTicksToSeconds(uint64_t ticks, uint32_t numerator, uint32_t denominator);
/// Returns nil on restart/PID reuse, missing/malformed counters, or a nonpositive sample window.
/// cpu_percent is per core (can exceed 100); it is never battery attribution.
FOUNDATION_EXPORT NSDictionary *_Nullable IEBProcessCPUDelta(NSDictionary *_Nullable before,
                                                             NSDictionary *_Nullable after);
/// Read-only, one-shot libproc snapshot. Run off the main thread. No persistence or task ports.
/// rows: pid, name (possibly empty), start_ticks, cpu_seconds, sampled_at (monotonic seconds).
/// CPU is user + system for the current process lifetime, excluding children.
/// Top-level counts expose partial failures; status is available, partial, or unavailable.
/// Names and PIDs are private on-device data: do not export rows in diagnostic reports.
FOUNDATION_EXPORT NSDictionary *IEBReadProcessSnapshot(void);
NS_ASSUME_NONNULL_END
