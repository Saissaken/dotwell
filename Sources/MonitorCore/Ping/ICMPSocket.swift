import Darwin

/// The unprivileged datagram ICMP socket shared by `PingEngine` and `Traceroute`.
///
/// Replies are timestamped by the kernel when they arrive (`SO_TIMESTAMP_MONOTONIC`), so a round trip
/// measures the network only: not the time the reply waits while the sampling queue finishes a tick,
/// nor how long a `.utility` thread takes to be scheduled on a busy Mac.
enum ICMPSocket {
    /// `SO_TIMESTAMP_MONOTONIC` and `SCM_TIMESTAMP_MONOTONIC` from `<sys/socket.h>`: a `UInt64` in
    /// `mach_absolute_time` units, the clock `DispatchTime` uses.
    private static let timestampOption: Int32 = 0x0800
    private static let timestampMessage: Int32 = 0x04

    /// Every ICMP socket gets a copy of every ICMP packet the Mac receives, including the replies to the
    /// route trace's probes, so the buffer holds a few seconds of them even when read only once per tick.
    private static let receiveBuffer: Int32 = 256 * 1024

    /// A non-blocking socket, or -1.
    static func open() -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return -1 }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, timestampOption, &on, socklen_t(MemoryLayout<Int32>.size))
        var size = receiveBuffer
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// One received packet.
    struct Packet {
        var length: Int
        var from: in_addr
        /// When the kernel received it, in `now()` nanoseconds.
        var receivedAt: UInt64
        /// False when the kernel gave no timestamp and `receivedAt` is the time it was read instead.
        var kernelTimestamp: Bool
    }

    /// Reads the next waiting packet into `buffer`, or returns nil when there is none.
    static func receive(_ fd: Int32, into buffer: inout [UInt8]) -> Packet? {
        var from = sockaddr_in()
        var control = [UInt8](repeating: 0, count: 64)
        var controlLength = 0
        let count: Int = buffer.withUnsafeMutableBytes { data -> Int in
            control.withUnsafeMutableBytes { controlBytes -> Int in
                withUnsafeMutablePointer(to: &from) { fromPointer -> Int in
                    var iov = iovec(iov_base: data.baseAddress, iov_len: data.count)
                    return withUnsafeMutablePointer(to: &iov) { iovPointer -> Int in
                        var message = msghdr(
                            msg_name: UnsafeMutableRawPointer(fromPointer),
                            msg_namelen: socklen_t(MemoryLayout<sockaddr_in>.size),
                            msg_iov: iovPointer, msg_iovlen: 1,
                            msg_control: controlBytes.baseAddress,
                            msg_controllen: socklen_t(controlBytes.count), msg_flags: 0)
                        let n = recvmsg(fd, &message, 0)
                        controlLength = Int(message.msg_controllen)
                        return n
                    }
                }
            }
        }
        guard count > 0 else { return nil }
        let kernelTicks = control.withUnsafeBytes { timestamp(in: $0, length: controlLength) }
        return Packet(
            length: count, from: from.sin_addr, receivedAt: kernelTicks.map(nanoseconds) ?? now(),
            kernelTimestamp: kernelTicks != nil)
    }

    /// Finds the monotonic receive timestamp among the control messages. Darwin aligns each message and its
    /// data to 4 bytes (`__DARWIN_ALIGN32`); `cmsghdr` is 12 bytes, so the data starts right after it.
    static func timestamp(in control: UnsafeRawBufferPointer, length: Int) -> UInt64? {
        let header = MemoryLayout<cmsghdr>.size
        var offset = 0
        let end = min(length, control.count)
        while offset + header <= end {
            let message = control.loadUnaligned(fromByteOffset: offset, as: cmsghdr.self)
            let size = Int(message.cmsg_len)
            guard size >= header, offset + size <= end else { return nil }
            if message.cmsg_level == SOL_SOCKET, message.cmsg_type == timestampMessage,
                size >= header + MemoryLayout<UInt64>.size
            {
                return control.loadUnaligned(fromByteOffset: offset + header, as: UInt64.self)
            }
            offset += (size + 3) & ~3
        }
        return nil
    }

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? (1, 1) : (UInt64(info.numer), UInt64(info.denom))
    }()

    /// Uptime in nanoseconds, on the same clock as the kernel's receive timestamps.
    static func now() -> UInt64 { nanoseconds(mach_absolute_time()) }

    /// `mach_absolute_time` units to nanoseconds, without overflowing on long uptimes.
    static func nanoseconds(_ ticks: UInt64) -> UInt64 {
        let (numer, denom) = timebase
        guard numer != denom else { return ticks }
        return ticks / denom * numer + ticks % denom * numer / denom
    }
}
