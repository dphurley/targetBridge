import Foundation

struct TBDiscoveredReceiver: Identifiable, Equatable {
    let serviceName: String
    let receiverName: String
    let preferredIP: String
    let thunderboltIP: String
    let usbIP: String
    let networkIP: String
    let ethernetIP: String
    let wifiIP: String
    let resolvedIPv4Addresses: [String]
    let panelSummary: String
    let version: String
    let supportsHEVCDecode: Bool
    let hostName: String?

    init(
        serviceName: String,
        receiverName: String,
        preferredIP: String,
        thunderboltIP: String,
        usbIP: String = "",
        networkIP: String,
        ethernetIP: String = "",
        wifiIP: String = "",
        resolvedIPv4Addresses: [String] = [],
        panelSummary: String,
        version: String,
        supportsHEVCDecode: Bool,
        hostName: String?
    ) {
        self.serviceName = serviceName
        self.receiverName = receiverName
        self.preferredIP = preferredIP
        self.thunderboltIP = thunderboltIP
        self.usbIP = usbIP
        self.networkIP = networkIP
        self.ethernetIP = ethernetIP
        self.wifiIP = wifiIP
        self.resolvedIPv4Addresses = resolvedIPv4Addresses
        self.panelSummary = panelSummary
        self.version = version
        self.supportsHEVCDecode = supportsHEVCDecode
        self.hostName = hostName
    }

    var id: String { "\(serviceName)|\(preferredIP)" }

    /// Bonjour service names survive link-local IP address changes after wake.
    /// Use this only for persisted receiver preferences, not Picker selection.
    var stableIdentity: String { "service:\(serviceName)" }

    var shortHostName: String? {
        guard let host = hostName, !host.isEmpty else { return nil }
        let stripped = host.hasSuffix(".") ? String(host.dropLast()) : host
        let components = stripped.split(separator: ".")
        guard let first = components.first, !first.isEmpty else { return nil }
        return String(first)
    }

    func ip(for transportKind: TBTransportKind, localInterfaceIP: String = "") -> String {
        switch transportKind {
        case .thunderboltBridge:
            return !thunderboltIP.isEmpty ? thunderboltIP : preferredIP
        case .networkLink:
            if localInterfaceIP.hasPrefix("169.254."), !usbIP.isEmpty {
                return usbIP
            }
            return !networkIP.isEmpty ? networkIP : preferredIP
        }
    }

    var displayText: String {
        var addresses: [(label: String, ip: String)] = []
        var seenIPs = Set<String>()
        func appendAddress(_ label: String, _ ip: String) {
            guard !ip.isEmpty, seenIPs.insert(ip).inserted else { return }
            addresses.append((label, ip))
        }
        appendAddress("TB", thunderboltIP)
        appendAddress("USB", usbIP)
        appendAddress("ETH", ethernetIP)
        appendAddress("Wi-Fi", wifiIP)
        appendAddress("NET", networkIP)

        let addressSummary: String
        if addresses.isEmpty {
            addressSummary = preferredIP
        } else if addresses.count == 1 {
            addressSummary = addresses[0].ip
        } else {
            addressSummary = addresses
                .map { "\($0.label) \($0.ip)" }
                .joined(separator: " · ")
        }

        let name: String
        if let host = shortHostName {
            name = "\(host) (\(addressSummary))"
        } else {
            name = addressSummary
        }

        if panelSummary.isEmpty {
            return name
        }
        return "\(name) · \(panelSummary)"
    }
}

/// Per-receiver opt-in for automatic connection, persisted across launches.
///
/// Keyed by `TBDiscoveredReceiver.stableIdentity` (the Bonjour service name)
/// rather than `id`: the link-local IP baked into `id` changes every time the
/// Thunderbolt bridge comes back up, which is exactly the moment auto-connect
/// has to recognise the receiver. This mirrors the keying rule already used for
/// persisted per-receiver preferences (see `TBVirtualDisplayModeMemory`).
///
/// The whole set lives under one defaults key so the app can tell, at launch and
/// without a discovery result in hand, whether auto-connect is armed at all.
struct TBAutoConnectTrustStore {
    static let defaultsKey = "fd.tbdisplaysender.autoConnect.trustedReceivers.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func save(_ identities: Set<String>) {
        if identities.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            // Sorted so the stored value is stable and diffable.
            defaults.set(identities.sorted(), forKey: Self.defaultsKey)
        }
    }

    func isTrusted(identity: String) -> Bool {
        load().contains(identity)
    }

    /// Applies the change and returns the resulting set, so the caller can
    /// publish it without a second read.
    @discardableResult
    func setTrusted(_ trusted: Bool, identity: String) -> Set<String> {
        var identities = load()
        if trusted {
            identities.insert(identity)
        } else {
            identities.remove(identity)
        }
        save(identities)
        return identities
    }
}

/// Decides *when* a trusted receiver seen over Bonjour should be connected to.
///
/// Bonjour re-announces the same service repeatedly, and a Thunderbolt link that
/// is being plugged in (or a receiver that is waking) flaps in and out of the
/// browse results for a few seconds. This gate turns that noisy sighting stream
/// into at most one connect attempt per receiver per backoff window:
///
/// * **Settle** — a receiver must have been continuously visible for
///   `settleInterval` before it is eligible, so a flap does not trigger a dial.
/// * **Single flight** — one attempt at a time; nothing else is attempted until
///   it succeeds or times out.
/// * **Backoff** — each failed attempt blocks the receiver for an exponentially
///   growing window, capped at `maximumBackoff`, instead of retrying in a loop.
/// * **Absence grace** — a receiver has to stay gone for `absenceGrace` before
///   its state is discarded, so a brief dropout neither restarts the settle
///   clock nor forgets an accumulated backoff.
/// * **User stop suppression** — after a manual Stop the receiver is suppressed
///   until it genuinely disappears, otherwise auto-connect would immediately
///   undo the user's Stop.
///
/// Pure value type with injected time so the policy can be unit tested without
/// waiting on wall-clock or on Bonjour.
struct TBAutoConnectGate {
    struct Policy: Equatable {
        /// Continuous visibility required before a receiver is eligible.
        var settleInterval: TimeInterval = 2
        /// How long a receiver must be missing before its state is forgotten.
        var absenceGrace: TimeInterval = 8
        /// How long an in-flight attempt blocks further attempts. Must exceed the
        /// session's own 5 s connect watchdog so the session has already torn a
        /// failed dial down by the time this expires.
        var attemptTimeout: TimeInterval = 15
        var initialBackoff: TimeInterval = 10
        var maximumBackoff: TimeInterval = 300
        var backoffMultiplier: Double = 2

        static let `default` = Policy()
    }

    struct Attempt: Equatable {
        let identity: String
        let deadline: Date
    }

    private struct ReceiverState {
        var firstSeenAt: Date?
        var absentSince: Date?
        var failureCount = 0
        var blockedUntil: Date?
        var userSuppressed = false
    }

    let policy: Policy
    private var states: [String: ReceiverState] = [:]
    private(set) var attemptInFlight: Attempt?

    init(policy: Policy = .default) {
        self.policy = policy
    }

    /// Feed the current Bonjour browse result. Call this before `candidate`.
    mutating func updateVisibility(_ visible: Set<String>, now: Date) {
        for identity in visible {
            var state = states[identity] ?? ReceiverState()
            state.absentSince = nil
            if state.firstSeenAt == nil {
                state.firstSeenAt = now
            }
            states[identity] = state
        }

        // Snapshot the keys: the loop mutates `states`.
        for identity in Array(states.keys) where !visible.contains(identity) {
            guard var state = states[identity] else { continue }
            guard let absentSince = state.absentSince else {
                state.absentSince = now
                states[identity] = state
                continue
            }
            if now.timeIntervalSince(absentSince) >= policy.absenceGrace {
                // Really gone (cable out, receiver quit). Forget everything —
                // including any user-stop suppression — so plugging back in is
                // an unambiguous "connect me again".
                states.removeValue(forKey: identity)
            }
        }
    }

    /// The first receiver in `trustedVisible` (caller's preference order) that is
    /// settled, unsuppressed and out of backoff. Returns nil while an attempt is
    /// in flight.
    func candidate(from trustedVisible: [String], now: Date) -> String? {
        guard attemptInFlight == nil else { return nil }
        return trustedVisible.first { identity in
            guard let state = states[identity] else { return false }
            guard !state.userSuppressed, state.absentSince == nil else { return false }
            guard let firstSeenAt = state.firstSeenAt,
                  now.timeIntervalSince(firstSeenAt) >= policy.settleInterval
            else { return false }
            if let blockedUntil = state.blockedUntil, now < blockedUntil { return false }
            return true
        }
    }

    mutating func beginAttempt(identity: String, now: Date) {
        attemptInFlight = Attempt(
            identity: identity,
            deadline: now.addingTimeInterval(policy.attemptTimeout)
        )
    }

    /// The in-flight attempt if it has run out of time, otherwise nil.
    func timedOutAttempt(now: Date) -> Attempt? {
        guard let attempt = attemptInFlight, now >= attempt.deadline else { return nil }
        return attempt
    }

    mutating func noteSuccess() {
        guard let attempt = attemptInFlight else { return }
        attemptInFlight = nil
        states[attempt.identity]?.failureCount = 0
        states[attempt.identity]?.blockedUntil = nil
    }

    mutating func noteFailure(now: Date) {
        guard let attempt = attemptInFlight else { return }
        attemptInFlight = nil
        var state = states[attempt.identity] ?? ReceiverState()
        state.failureCount += 1
        state.blockedUntil = now.addingTimeInterval(backoff(afterFailures: state.failureCount))
        states[attempt.identity] = state
    }

    /// The user pressed Stop. Hold off until this receiver actually disappears.
    mutating func noteUserStopped(identity: String) {
        var state = states[identity] ?? ReceiverState()
        state.userSuppressed = true
        states[identity] = state
        if attemptInFlight?.identity == identity {
            attemptInFlight = nil
        }
    }

    /// Explicit opt-in: clear backoff and suppression and treat the receiver as
    /// already settled, so turning the toggle on connects promptly instead of
    /// waiting out another settle window.
    mutating func arm(identity: String, now: Date) {
        var state = states[identity] ?? ReceiverState()
        state.firstSeenAt = now.addingTimeInterval(-policy.settleInterval)
        state.absentSince = nil
        state.failureCount = 0
        state.blockedUntil = nil
        state.userSuppressed = false
        states[identity] = state
    }

    mutating func forget(identity: String) {
        states.removeValue(forKey: identity)
        if attemptInFlight?.identity == identity {
            attemptInFlight = nil
        }
    }

    func backoff(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let raw = policy.initialBackoff * pow(policy.backoffMultiplier, Double(failures - 1))
        return min(policy.maximumBackoff, raw)
    }

    // Test seams.
    func isSuppressed(identity: String) -> Bool { states[identity]?.userSuppressed ?? false }
    func failureCount(identity: String) -> Int { states[identity]?.failureCount ?? 0 }
    func isTracking(identity: String) -> Bool { states[identity] != nil }
}

final class TBReceiverDiscovery: NSObject, ObservableObject {
    @Published private(set) var receivers: [TBDiscoveredReceiver] = []

    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]

    override init() {
        super.init()
        browser.delegate = self
        start()
    }

    func refresh() {
        stop()
        start()
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func start() {
        browser.searchForServices(ofType: "_targetbridge._tcp.", inDomain: "local.")
    }

    private func stop() {
        browser.stop()
        services.values.forEach { service in
            service.stop()
            service.delegate = nil
        }
        services.removeAll()
        receivers = []
    }

    private func upsertReceiver(from service: NetService) {
        guard let txtData = service.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord: txtData)

        func stringValue(_ key: String) -> String {
            guard let data = txt[key], !data.isEmpty else { return "" }
            return String(decoding: data, as: UTF8.self)
        }

        let receiverName = stringValue("name").isEmpty ? service.name : stringValue("name")
        let receiverIP = stringValue("ip")
        let thunderboltIP = stringValue("tbIP")
        let usbIP = stringValue("usbIP")
        let networkIP = stringValue("netIP")
        let ethernetIP = stringValue("ethernetIP")
        let wifiIP = stringValue("wifiIP")
        let resolvedIPv4Addresses = resolvedIPv4Addresses(from: service)
        let preferredIP = !receiverIP.isEmpty
            ? receiverIP
            : (!thunderboltIP.isEmpty
                ? thunderboltIP
                : (!usbIP.isEmpty
                    ? usbIP
                    : (!networkIP.isEmpty ? networkIP : (resolvedIPv4Addresses.first ?? ""))))
        guard !preferredIP.isEmpty else { return }

        let panelName = stringValue("panel")
        let panelWidth = stringValue("panelWidth")
        let panelHeight = stringValue("panelHeight")
        let version = stringValue("version")
        let supportsHEVCDecode = stringValue("supportsHEVCDecode") == "1"

        let panelSummary: String
        if !panelWidth.isEmpty, !panelHeight.isEmpty, !panelName.isEmpty {
            panelSummary = "\(panelName) (\(panelWidth)x\(panelHeight))"
        } else if !panelName.isEmpty {
            panelSummary = panelName
        } else if !panelWidth.isEmpty, !panelHeight.isEmpty {
            panelSummary = "\(panelWidth)x\(panelHeight)"
        } else {
            panelSummary = ""
        }

        let receiver = TBDiscoveredReceiver(
            serviceName: service.name,
            receiverName: receiverName,
            preferredIP: preferredIP,
            thunderboltIP: thunderboltIP,
            usbIP: usbIP,
            networkIP: networkIP,
            ethernetIP: ethernetIP,
            wifiIP: wifiIP,
            resolvedIPv4Addresses: resolvedIPv4Addresses,
            panelSummary: panelSummary,
            version: version,
            supportsHEVCDecode: supportsHEVCDecode,
            hostName: service.hostName
        )

        if let index = receivers.firstIndex(where: { $0.serviceName == receiver.serviceName }) {
            receivers[index] = receiver
        } else {
            receivers.append(receiver)
        }
        receivers.sort { lhs, rhs in
            if lhs.receiverName == rhs.receiverName {
                return lhs.preferredIP < rhs.preferredIP
            }
            return lhs.receiverName.localizedCaseInsensitiveCompare(rhs.receiverName) == .orderedAscending
        }
    }

    private func resolvedIPv4Addresses(from service: NetService) -> [String] {
        guard let addresses = service.addresses else { return [] }
        var result: [String] = []
        var seen = Set<String>()

        for addressData in addresses {
            let address: String? = addressData.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress,
                      rawBuffer.count >= MemoryLayout<sockaddr>.size
                else { return nil }
                let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
                guard socketAddress.pointee.sa_family == UInt8(AF_INET) else { return nil }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(min(rawBuffer.count, Int(socketAddress.pointee.sa_len)))
                guard getnameinfo(
                    socketAddress,
                    length,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 else { return nil }
                return String(cString: host)
            }
            if let address, seen.insert(address).inserted {
                result.append(address)
            }
        }

        return result.sorted()
    }

    private func removeService(_ service: NetService) {
        services.removeValue(forKey: service.name)
        receivers.removeAll { $0.serviceName == service.name }
    }

    deinit {
        stop()
    }
}

extension TBReceiverDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            service.delegate = self
            services[service.name] = service
            service.resolve(withTimeout: 5)
            if !moreComing {
                objectWillChange.send()
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            removeService(service)
            if !moreComing {
                objectWillChange.send()
            }
        }
    }
}

extension TBReceiverDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        runOnMain { [weak self] in
            self?.upsertReceiver(from: sender)
        }
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        runOnMain { [weak self] in
            self?.upsertReceiver(from: sender)
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        runOnMain { [weak self] in
            guard sender.txtRecordData() != nil else { return }
            self?.upsertReceiver(from: sender)
        }
    }
}
