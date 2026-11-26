import XCTest

@testable import MonitorCore

final class ProbeMathTests: XCTestCase {
    func testCPUUsage() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 130, system: 60, idle: 850, nice: 60)
        // busy = 30+10+10 = 50, total = 100
        XCTAssertEqual(CPUTicks.usage(from: a, to: b), 0.5, accuracy: 0.0001)
    }

    func testCPUUsageCounterWrap() {
        let a = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        // busy = 20 (wrapped), idle = 20
        XCTAssertEqual(CPUTicks.usage(from: a, to: b), 0.5, accuracy: 0.0001)
    }

    func testCPUUsageNoTime() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(CPUTicks.usage(from: a, to: a), 0)
    }

    func testNetworkRates() {
        let a = NetworkCounters(received: 1_000, sent: 500)
        let b = NetworkCounters(received: 2_000, sent: 1_500)
        let r = NetworkCounters.rates(from: a, to: b, seconds: 2)
        XCTAssertEqual(r.down, 4_000)  // 1000 bytes * 8 / 2 s
        XCTAssertEqual(r.up, 4_000)
    }

    func testNetworkRatesCounterReset() {
        let r = NetworkCounters.rates(
            from: NetworkCounters(received: 5_000, sent: 5_000),
            to: NetworkCounters(received: 10, sent: 10), seconds: 1)
        XCTAssertEqual(r.down, 0)
        XCTAssertEqual(r.up, 0)
    }

    func testMemoryUsedMatchesActivityMonitor() {
        // Activity Monitor on a 36 GB Apple Silicon Mac: App 10.64 GB, Wired 4.15 GB, Compressed 2.59 GB,
        // Cached Files 14.66 GB, Memory Used 18.85 GB (about 1.47 GB more than App + Wired + Compressed).
        let gib = 1_073_741_824.0
        let page: UInt64 = 16_384
        func pages(_ gb: Double) -> UInt64 { UInt64((gb * gib / Double(page)).rounded()) }
        let total = UInt64(36 * gib)
        let counts = VMPageCounts(
            free: pages(2.49), anonymous: pages(11.64), external: pages(13.66), purgeable: pages(1.0),
            wired: pages(4.15), compressor: pages(2.59))
        let used = Double(counts.usedBytes(pageSize: page, totalBytes: total)) / gib
        XCTAssertEqual(used, 18.85, accuracy: 0.01)
    }

    func testMemoryUsedNeverBelowAppWiredCompressed() {
        let counts = VMPageCounts(free: 900, anonymous: 300, external: 0, purgeable: 100, wired: 50, compressor: 50)
        // Page counts add up to more than the total: fall back to App + Wired + Compressed.
        XCTAssertEqual(counts.usedBytes(pageSize: 1, totalBytes: 1_000), 300)
    }

    func testMemoryUsedClampedToTotal() {
        let counts = VMPageCounts(free: 0, anonymous: 2_000, external: 0, purgeable: 0, wired: 0, compressor: 0)
        XCTAssertEqual(counts.usedBytes(pageSize: 1, totalBytes: 1_000), 1_000)
    }

    func testWatts() {
        XCTAssertEqual(PowerProbe.watts(millivolts: 12_000, milliamps: -1_500), 18, accuracy: 0.0001)
    }

    /// The battery gauge reports hundredths of a degree: 3062 is 30.62 °C.
    func testBatteryTemperature() throws {
        XCTAssertEqual(try XCTUnwrap(PowerProbe.batteryCelsius(hundredths: 3062)), 30.62, accuracy: 0.001)
        XCTAssertNil(PowerProbe.batteryCelsius(hundredths: 0xFFFF))  // unreadable gauge
        XCTAssertNil(PowerProbe.batteryCelsius(hundredths: -4000))
        // On a Mac with a battery the live reading must be a plausible room-to-warm temperature.
        if let celsius = PowerProbe().sample()?.batteryCelsius {
            XCTAssertGreaterThan(celsius, 5)
            XCTAssertLessThan(celsius, 60)
        }
    }

    /// Smoke test: real probes return sane values on the CI Mac.
    func testLiveProbes() {
        let cpu = CPUProbe()
        _ = cpu.sample()
        usleep(100_000)
        if let usage = cpu.sample() { XCTAssert((0...1).contains(usage)) }

        let mem = MemoryProbe().sample()
        XCTAssertNotNil(mem)
        if let mem { XCTAssertGreaterThan(mem.totalBytes, 0); XCTAssertLessThanOrEqual(mem.usedBytes, mem.totalBytes) }

        XCTAssertNotNil(NetworkProbe().sample())
        let space = DiskProbe().space()
        XCTAssertNotNil(space)
        if let space { XCTAssertLessThanOrEqual(space.availableBytes, space.totalBytes) }
        _ = DiskProbe().ioCounters()
        _ = PowerProbe().sample()  // CI runners have no battery; must not crash
    }
}
