// Measures one running process from the outside, the way Activity Monitor does, and prints JSON.
//
//   swiftc -O measure.swift -o measure && ./measure <pid> <seconds>
//
// CPU time, wakeups and energy come from the kernel's counters (proc_pid_rusage), read once at the
// start and once at the end, so the measurement itself never wakes the process. Memory is sampled
// every second and reported as the median.
import Darwin
import Foundation

func rusage(_ pid: pid_t) -> rusage_info_v6? {
    var info = rusage_info_v6()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
        }
    }
    return result == 0 ? info : nil
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]), let seconds = Double(arguments[2]), seconds > 0 else {
    fail("usage: measure <pid> <seconds>")
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
// CPU times in rusage are Mach ticks on Apple silicon (1:1 with nanoseconds on Intel).
func nanos(_ ticks: UInt64) -> Double { Double(ticks) * Double(timebase.numer) / Double(timebase.denom) }

guard let start = rusage(pid) else { fail("process \(pid) not found") }
let startTime = DispatchTime.now().uptimeNanoseconds
var resident: [Double] = []
var footprint: [Double] = []
let deadline = startTime + UInt64(seconds * 1e9)
while DispatchTime.now().uptimeNanoseconds < deadline {
    Thread.sleep(forTimeInterval: min(1, Double(deadline - DispatchTime.now().uptimeNanoseconds) / 1e9))
    guard let sample = rusage(pid) else { fail("process \(pid) exited during the measurement") }
    resident.append(Double(sample.ri_resident_size) / 1_048_576)
    footprint.append(Double(sample.ri_phys_footprint) / 1_048_576)
}
guard let end = rusage(pid) else { fail("process \(pid) exited during the measurement") }
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1e9

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

let cpuNanos = nanos((end.ri_user_time &+ end.ri_system_time) &- (start.ri_user_time &+ start.ri_system_time))
let result: [String: Double] = [
    "seconds": elapsed,
    // Percent of one core, like Activity Monitor's "% CPU".
    "cpu_percent": cpuNanos / (elapsed * 1e9) * 100,
    "rss_mb": median(resident),
    "footprint_mb": median(footprint),
    "peak_footprint_mb": footprint.max() ?? 0,
    // All wakeups from idle (timers, interrupts), and the subset that woke an idle CPU package.
    "wakeups_per_s": Double(end.ri_interrupt_wkups &- start.ri_interrupt_wkups) / elapsed,
    "idle_wakeups_per_s": Double(end.ri_pkg_idle_wkups &- start.ri_pkg_idle_wkups) / elapsed,
    // Average power in milliwatts. Virtual machines usually report 0.
    "energy_mw": Double(end.ri_energy_nj &- start.ri_energy_nj) / elapsed / 1e6,
]
let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: json, as: UTF8.self))
