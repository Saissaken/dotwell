import Foundation

/// GPU power on Apple silicon from the `GPU Energy` channel of IOReport's `Energy Model` group: the energy
/// counters `powermetrics` reports, readable without root.
///
/// IOReport (`/usr/lib/libIOReport.dylib`) has no public headers, so its functions are looked up at runtime.
/// When any is missing, or the Mac has no such channel (Intel, virtual machines), `watts` returns nil.
/// Power is energy over time, so each reading covers the time since the previous one.
final class GPUEnergyReader {
    private typealias CopyChannelsInGroup =
        @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> UnsafeMutableRawPointer?
    private typealias CreateSubscription =
        @convention(c) (
            UnsafeRawPointer?, UnsafeMutableRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>, UInt64,
            UnsafeRawPointer?
        ) -> UnsafeMutableRawPointer?
    private typealias CreateSamples =
        @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesDelta =
        @convention(c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    /// Returns a CFString the caller doesn't own.
    private typealias ChannelGetString = @convention(c) (UnsafeRawPointer) -> UnsafeMutableRawPointer?
    private typealias SimpleGetIntegerValue = @convention(c) (UnsafeRawPointer, Int32) -> Int64

    private struct API {
        var copyChannelsInGroup: CopyChannelsInGroup
        var createSubscription: CreateSubscription
        var createSamples: CreateSamples
        var createSamplesDelta: CreateSamplesDelta
        var channelName: ChannelGetString
        var unitLabel: ChannelGetString
        var integerValue: SimpleGetIntegerValue

        static func load() -> API? {
            guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else { return nil }
            func symbol<T>(_ name: String, as _: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let copyChannelsInGroup = symbol("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
                let createSubscription = symbol("IOReportCreateSubscription", as: CreateSubscription.self),
                let createSamples = symbol("IOReportCreateSamples", as: CreateSamples.self),
                let createSamplesDelta = symbol("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self),
                let channelName = symbol("IOReportChannelGetChannelName", as: ChannelGetString.self),
                let unitLabel = symbol("IOReportChannelGetUnitLabel", as: ChannelGetString.self),
                let integerValue = symbol("IOReportSimpleGetIntegerValue", as: SimpleGetIntegerValue.self)
            else { return nil }
            return API(
                copyChannelsInGroup: copyChannelsInGroup, createSubscription: createSubscription,
                createSamples: createSamples, createSamplesDelta: createSamplesDelta, channelName: channelName,
                unitLabel: unitLabel, integerValue: integerValue)
        }
    }

    private lazy var api = API.load()
    private var subscribed = false
    /// The subscription is made once and kept for the life of the app, so it is never released.
    private var subscription: UnsafeMutableRawPointer?
    private var channels: CFMutableDictionary?
    private var last: (samples: CFDictionary, nanos: UInt64)?

    /// Average GPU power since the previous call, or nil on the first call.
    func watts(now: UInt64) -> Double? {
        guard let api else { return nil }
        if !subscribed { subscribe(api) }
        guard let subscription, let channels,
            let raw = api.createSamples(subscription, Unmanaged.passUnretained(channels).toOpaque(), nil)
        else { return nil }
        let samples = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue()
        defer { last = (samples, now) }
        guard let (previous, then) = last, now > then,
            let deltaRaw = api.createSamplesDelta(
                Unmanaged.passUnretained(previous).toOpaque(), Unmanaged.passUnretained(samples).toOpaque(), nil)
        else { return nil }
        let delta = Unmanaged<CFDictionary>.fromOpaque(deltaRaw).takeRetainedValue()
        guard let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return nil }

        var joules = 0.0
        var found = false
        for item in items {
            let channel = UnsafeRawPointer(Unmanaged.passUnretained(item).toOpaque())
            guard let name = api.channelName(channel).map(Self.string), Self.isGPUChannel(name),
                let value = Self.joules(api.integerValue(channel, 0), unit: api.unitLabel(channel).map(Self.string))
            else { continue }
            joules += value
            found = true
        }
        return found ? joules / (Double(now - then) / 1e9) : nil
    }

    func reset() {
        last = nil
    }

    private func subscribe(_ api: API) {
        subscribed = true
        guard let raw = api.copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0) else { return }
        let desired = Unmanaged<CFMutableDictionary>.fromOpaque(raw).takeRetainedValue()
        var subscribedChannels: UnsafeMutableRawPointer?
        guard
            let subscription = api.createSubscription(
                nil, Unmanaged.passUnretained(desired).toOpaque(), &subscribedChannels, 0, nil),
            let subscribedChannels
        else { return }
        self.subscription = subscription
        channels = Unmanaged<CFMutableDictionary>.fromOpaque(subscribedChannels).takeRetainedValue()
    }

    // MARK: - Parsing

    static func isGPUChannel(_ name: String) -> Bool { name == "GPU Energy" }

    /// Converts a counter to joules using the channel's unit label.
    static func joules(_ value: Int64, unit: String?) -> Double? {
        guard value >= 0 else { return nil }
        switch unit?.trimmingCharacters(in: .whitespaces) {
        case "mJ": return Double(value) / 1e3
        case "uJ", "µJ": return Double(value) / 1e6
        case "nJ": return Double(value) / 1e9
        default: return nil
        }
    }

    private static func string(_ pointer: UnsafeMutableRawPointer) -> String {
        Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
