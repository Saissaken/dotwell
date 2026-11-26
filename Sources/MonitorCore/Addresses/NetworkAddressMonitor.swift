import Foundation
import Network

/// What the Network module shows about the Mac's addresses.
public struct NetworkAddresses: Sendable, Equatable {
    /// `nil` when the Mac is not connected to any network.
    public var local: LocalAddress?
    /// `nil` until the first lookup finishes; empty when it failed.
    public var publicAddresses: PublicAddresses?
    public var isLoadingPublic = false

    public init(local: LocalAddress? = nil, publicAddresses: PublicAddresses? = nil, isLoadingPublic: Bool = false) {
        self.local = local
        self.publicAddresses = publicAddresses
        self.isLoadingPublic = isLoadingPublic
    }
}

/// Keeps the local and public addresses current while the popover is open, and nothing while it is closed.
///
/// The local address is read on open and whenever the network path changes. The public address needs a
/// request, so it is cached: it is looked up again only when the local address or interface changed,
/// or the cached answer is older than ``maxAge``.
@MainActor
public final class NetworkAddressMonitor {
    public private(set) var addresses = NetworkAddresses() {
        didSet { if addresses != oldValue { onChange?(addresses) } }
    }
    public var onChange: ((NetworkAddresses) -> Void)?

    /// How long a public address stays valid while the local network stays the same.
    public var maxAge: TimeInterval = 10 * 60

    private var pathMonitor: NWPathMonitor?
    private var lookup: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var fetchedFor: LocalAddress?
    private var fetchedAt: Date?
    private lazy var session = PublicAddressLookup.makeSession()

    public init() {}

    public func start() {
        guard pathMonitor == nil else { return }
        refresh()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        lookup?.cancel()
        lookup = nil
        addresses.isLoadingPublic = false
    }

    /// The routing table can lag the path update slightly, so wait for it to settle.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        let local = LocalAddressReader.read()
        var next = addresses
        next.local = local
        guard let local else {
            lookup?.cancel()
            lookup = nil
            fetchedFor = nil
            fetchedAt = nil
            next.publicAddresses = nil
            next.isLoadingPublic = false
            addresses = next
            return
        }
        let networkChanged = local != fetchedFor
        let stale = fetchedAt.map { Date().timeIntervalSince($0) > maxAge } ?? true
        if networkChanged { next.publicAddresses = nil }
        addresses = next
        if (networkChanged || stale) && lookup == nil { lookUpPublic(for: local) }
    }

    private func lookUpPublic(for local: LocalAddress) {
        addresses.isLoadingPublic = true
        let session = session
        lookup = Task { [weak self] in
            let result = await PublicAddressLookup.fetch(using: session)
            guard !Task.isCancelled, let self else { return }
            self.lookup = nil
            self.addresses.isLoadingPublic = false
            self.addresses.publicAddresses = result
            // Failures are not cached, so the next open tries again.
            self.fetchedFor = result.isEmpty ? nil : local
            self.fetchedAt = result.isEmpty ? nil : Date()
            // The network may have changed while the request was in flight.
            if self.addresses.local != local { self.refresh() }
        }
    }
}
