import Foundation
import XCTest

@testable import MonitorCore

/// Checks that every reading matches what macOS's own tools report, or follows a load the test creates
/// itself, on the real machine running the tests (a Mac, also on CI). Readings the machine can't produce
/// (no internet, no ICMP, no sensors in a virtual machine) are skipped, never faked.
final class AccuracyTests: XCTestCase {

    // MARK: - CPU

    /// Busy threads on half the cores must show up as at least that share of the CPU.
    func testCPUFollowsAKnownLoad() throws {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let busy = max(1, cores / 2)
        let probe = CPUProbe()
        _ = probe.sample()
        Thread.sleep(forTimeInterval: 1)
        let idle = try XCTUnwrap(probe.sample())

        let deadline = Date().addingTimeInterval(2)
        let group = DispatchGroup()
        for _ in 0..<busy {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                var x: UInt64 = 0
                while Date() < deadline { x &+= 1 }
                XCTAssertGreaterThan(x, 0)
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
        _ = probe.sample()
        Thread.sleep(forTimeInterval: 1.5)
        let loaded = try XCTUnwrap(probe.sample())
        group.wait()

        let expected = Float(busy) / Float(cores)
        print("cpu idle \(idle) loaded \(loaded) expected +\(expected)")
        XCTAssertGreaterThanOrEqual(loaded, expected * 0.8, "busy threads must show up")
        XCTAssertLessThanOrEqual(loaded, 1)
    }

    // MARK: - Memory

    /// The same page counts `vm_stat` prints give the same "Memory Used", and the total is `hw.memsize`.
    func testMemoryMatchesVMStat() throws {
        let sample = try XCTUnwrap(MemoryProbe().sample())
        let output = try run("/usr/bin/vm_stat")
        let pageSize = try XCTUnwrap(Self.number(in: output, after: "page size of "))
        func pages(_ label: String) throws -> UInt64 {
            try XCTUnwrap(Self.number(in: output, after: label + ":"), label)
        }
        let counts = VMPageCounts(
            free: try pages("Pages free"), anonymous: try pages("Anonymous pages"),
            external: try pages("File-backed pages"), purgeable: try pages("Pages purgeable"),
            wired: try pages("Pages wired down"), compressor: try pages("Pages occupied by compressor"))
        let total = try XCTUnwrap(Self.number(in: try run("/usr/sbin/sysctl", "-n", "hw.memsize"), after: ""))
        XCTAssertEqual(sample.totalBytes, total)
        let expected = counts.usedBytes(pageSize: pageSize, totalBytes: total)
        print("memory used \(sample.usedBytes) vm_stat \(expected) of \(total)")
        // Two reads a few milliseconds apart: allow 2 % of physical memory for pages that moved in between.
        XCTAssertLessThan(Self.distance(sample.usedBytes, expected), total / 50)

        let level = try run("/usr/sbin/sysctl", "-n", "kern.memorystatus_vm_pressure_level")
        let pressure = Int(level.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        XCTAssertEqual(sample.pressure, MemoryPressure(rawValue: pressure) ?? .normal)
    }

    // MARK: - Disk

    /// Finder's "Available" counts purgeable space, so it is at least what `df` calls free, on the same volume.
    func testDiskSpaceMatchesDF() throws {
        let space = try XCTUnwrap(DiskProbe().space())
        let lines = try run("/bin/df", "-k", "/").split(separator: "\n")
        let fields = try XCTUnwrap(lines.last).split(separator: " ", omittingEmptySubsequences: true)
        let dfTotal = try XCTUnwrap(UInt64(fields[1])) * 1024
        let dfAvailable = try XCTUnwrap(UInt64(fields[3])) * 1024
        print("disk available \(space.availableBytes) df \(dfAvailable), total \(space.totalBytes) df \(dfTotal)")
        XCTAssertLessThan(Self.distance(space.totalBytes, dfTotal), dfTotal / 50)
        XCTAssertGreaterThanOrEqual(space.availableBytes + dfTotal / 100, dfAvailable)
        XCTAssertLessThanOrEqual(space.availableBytes, space.totalBytes)
    }

    /// Writing and reading 64 MB past the cache must show up in the disk counters.
    func testDiskIOCountsWhatTheTestWrites() throws {
        let probe = DiskProbe()
        let size = 64 << 20
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dotwell-io-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try XCTUnwrap(probe.ioCounters())
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let chunk = [UInt8](repeating: 0xA5, count: 1 << 20)
        for _ in 0..<(size >> 20) {
            XCTAssertEqual(chunk.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }, chunk.count)
        }
        _ = fcntl(fd, F_FULLFSYNC)
        let written = try XCTUnwrap(probe.ioCounters())
        XCTAssertGreaterThanOrEqual(written.bytesWritten - before.bytesWritten, UInt64(size) * 9 / 10)

        lseek(fd, 0, SEEK_SET)
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var total = 0
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            total += n
        }
        XCTAssertEqual(total, size)
        let afterRead = try XCTUnwrap(probe.ioCounters())
        let readBytes = afterRead.bytesRead - written.bytesRead
        print("disk wrote \(written.bytesWritten - before.bytesWritten) read \(readBytes)")
        XCTAssertGreaterThanOrEqual(readBytes, UInt64(size) * 9 / 10)
    }

    // MARK: - Network

    /// Downloading 10 MB must add at least 10 MB to the received counter.
    func testNetworkCountsADownload() throws {
        let probe = NetworkProbe()
        let bytes = 10_000_000
        let before = try XCTUnwrap(probe.sample())
        let url = try XCTUnwrap(URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)"))
        let done = expectation(description: "download")
        var received = 0
        URLSession(configuration: .ephemeral).dataTask(with: url) { data, _, _ in
            received = data?.count ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        try XCTSkipIf(received < bytes, "No internet here")
        let after = try XCTUnwrap(probe.sample())
        print("network received \(after.received - before.received) for a \(bytes) byte download")
        XCTAssertGreaterThanOrEqual(after.received - before.received, UInt64(bytes))
    }

    // MARK: - Ping

    /// ICMP round trips match `/sbin/ping` to the same host.
    func testICMPMatchesSystemPing() throws {
        let system = try systemPing("1.1.1.1")
        let ours = try XCTUnwrap(probeMinimum(PingTarget(name: "c", host: "1.1.1.1", method: .icmp)))
        print("icmp ours \(ours) ping \(system)")
        XCTAssertLessThan(abs(ours - system), max(2, system * 0.2))
    }

    /// A TCP handshake is one round trip, so to the same host it matches ping.
    func testTCPHandshakeMatchesSystemPing() throws {
        let system = try systemPing("1.1.1.1")
        let ours = try XCTUnwrap(probeMinimum(PingTarget(name: "c", host: "1.1.1.1", method: .tcp(port: 443))))
        print("tcp ours \(ours) ping \(system)")
        XCTAssertLessThan(abs(ours - system), max(3, system * 0.25))
    }

    /// The DNS row's query time matches `dig` against the same resolver.
    func testDNSMatchesDig() throws {
        let server = try XCTUnwrap(DNSServer.primaryIPv4().map(Traceroute.text), "No IPv4 DNS server here")
        var digTimes: [Float] = []
        for _ in 0..<3 {
            let output = try run("/usr/bin/dig", "+tries=1", "+time=2", "@\(server)", DNSQuery.name, "A")
            if let ms = Self.number(in: output, after: "Query time: ") { digTimes.append(Float(ms)) }
        }
        let dig = try XCTUnwrap(digTimes.min(), "dig got no answer")
        let ours = try XCTUnwrap(probeMinimum(.dns))
        print("dns \(server) ours \(ours) dig \(dig)")
        // dig reports whole milliseconds.
        XCTAssertLessThan(abs(ours - dig), max(3, dig * 0.3))
    }

    /// The servers the DNS detail lists as answering first are the ones `scutil --dns` lists for its first
    /// resolver, the system's default.
    func testDNSSetupMatchesScutil() throws {
        let setup = try XCTUnwrap(DNSSetup.current(), "configd has no DNS setup")
        let output = try run("/usr/sbin/scutil", "--dns")
        guard let first = output.components(separatedBy: "resolver #").dropFirst().first else {
            throw XCTSkip("No DNS resolver here")
        }
        // IPv4 only: scutil writes link-local IPv6 servers with their interface ("fe80::1%en0").
        let servers = first.split(separator: "\n").compactMap { line -> String? in
            guard line.contains("nameserver[") else { return nil }
            return line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        }
        print("dns setup \(setup.servers) scutil \(servers)")
        XCTAssertEqual(setup.servers.filter { $0.contains(".") }, servers.filter { $0.contains(".") })
        if let measured = DNSServer.primaryIPv4().map(Traceroute.text) {
            XCTAssertTrue(setup.resolvers.contains { $0.servers.contains(measured) } || setup.resolvers.isEmpty)
        }
    }

    // MARK: - Top apps

    /// Touching 256 MB must add that much to this process's app in the memory ranking.
    func testTopAppMemoryFollowsAnAllocation() throws {
        let probe = ProcessProbe()
        let me = ProcessProbe.group(pid: getpid()).id
        func footprint() -> UInt64 {
            probe.usage(now: DispatchTime.now().uptimeNanoseconds).apps.first { $0.id == me }?.memoryBytes ?? 0
        }
        let before = footprint()
        let size = 256 << 20
        let block = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        defer { block.deallocate() }
        for offset in stride(from: 0, to: size, by: 4096) {
            block.storeBytes(of: 1, toByteOffset: offset, as: UInt8.self)
        }
        let after = footprint()
        print("top app memory before \(before) after \(after)")
        XCTAssertGreaterThanOrEqual(after - min(after, before), UInt64(size) * 9 / 10)
    }

    // MARK: - Helpers

    /// Minimum of five round trips, probing like the sampler: send, then collect a tick later.
    private func probeMinimum(_ target: PingTarget) throws -> Float? {
        let queue = DispatchQueue(label: "accuracy.ping")
        let engine = PingEngine(targets: [target], queue: queue)
        var results: [Float] = []
        engine.onResult = { _, ms in if let ms { results.append(ms) } }
        queue.sync { engine.probe([0]) }  // resolves the address
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.4)
            queue.sync {
                engine.collect()
                engine.probe([0])
            }
        }
        Thread.sleep(forTimeInterval: 0.4)
        return queue.sync {
            engine.collect()
            return results.min()
        }
    }

    /// Minimum round trip from `/sbin/ping`, or a skip when this machine gets no replies.
    private func systemPing(_ host: String) throws -> Float {
        let output = try run("/sbin/ping", "-c", "5", "-i", "0.3", "-t", "5", "-q", host)
        guard let line = output.split(separator: "\n").first(where: { $0.contains("round-trip") }),
            let numbers = line.split(separator: "=").last?.split(separator: "/"),
            let min = Float(numbers[0].trimmingCharacters(in: .whitespaces))
        else { throw XCTSkip("No ping replies from \(host) here") }
        return min
    }

    private func run(_ path: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// The first whole number after `label` in `text` (`vm_stat` ends counts with a period).
    static func number(in text: String, after label: String) -> UInt64? {
        let start = label.isEmpty ? text.startIndex : text.range(of: label)?.upperBound
        guard let start else { return nil }
        let digits = text[start...].drop { $0 == " " }.prefix { $0.isNumber }
        return UInt64(digits)
    }

    static func distance(_ a: UInt64, _ b: UInt64) -> UInt64 { a > b ? a - b : b - a }
}
