import SwiftUI

// MARK: - Pending integrations
//
// Two features are landing on the service object in parallel with this UI work.
// The views below are already laid out for them; these stubs are the single
// place to wire them up.

/// Bridges the views to the receiver-battery and auto-connect features, which
/// expose their state in shapes the view layer would otherwise have to know
/// the internals of.
///
/// Main-actor isolated because both features publish from the service, which
/// is. Every caller is a SwiftUI view body, so this costs nothing.
@MainActor
enum TBPendingIntegration {
    /// The receiver's battery, or nil when there is nothing truthful to show.
    ///
    /// Three cases collapse to nil deliberately: no session, nothing reported
    /// yet, and a receiver that reported it has no battery at all (a Mac mini
    /// or Studio). Only the last is a positive statement, and the UI treatment
    /// is the same for all three — show nothing.
    static func batteryState(for session: TBDisplaySenderSession) -> TBReceiverBatteryState? {
        guard let battery = session.receiverBattery, battery.isPresent else { return nil }
        return battery
    }

    /// Per-receiver "connect automatically".
    ///
    /// Auto-connect is keyed on the *discovered* receiver rather than the
    /// session, because trust has to survive the session being reconfigured and
    /// has to be evaluable before any session is pointed at it. A session
    /// holding a hand-typed address therefore has nothing to bind to, and this
    /// returns nil so the caller can hide the control rather than offer a
    /// switch that silently forgets.
    static func autoConnectBinding(for session: TBDisplaySenderSession) -> Binding<Bool>? {
        let service = TBDisplaySenderService.shared
        guard let receiver = service.discoveredReceivers.first(where: { $0.id == session.selectedReceiverID })
        else { return nil }
        return Binding(
            get: { service.isAutoConnectEnabled(for: receiver) },
            set: { service.setAutoConnectEnabled($0, for: receiver) }
        )
    }
}

/// Convenience over the shared localisation store so views read cleanly.
extension TBDisplaySenderLanguage {
    func str(_ key: String, _ values: [String: String] = [:]) -> String {
        TBDisplaySenderL10n.text(key, self, values)
    }
}

// MARK: - Main window
//
// One target on screen at a time, vertically centred. The header is a wordmark
// plus text-only actions; the footer carries the link summary and the version.
// Everything configurable lives one click away in a sheet.

struct TBDisplaySenderContentView: View {
    @ObservedObject var service: TBDisplaySenderService
    @State private var showingAbout = false
    @State private var activeIndex = 0

    var body: some View {
        ZStack {
            TBBackground()
            TBWindowChrome()

            VStack(spacing: 0) {
                header
                stage
                footer
            }
        }
        .frame(minWidth: 620, minHeight: 540)
        .preferredColorScheme(.dark)
        .tint(TBTheme.accent)
        .task {
            service.refreshLocalInterfaces()
        }
        .onChange(of: service.sessions.count) { _, count in
            if activeIndex >= count {
                activeIndex = max(0, count - 1)
            }
        }
        .sheet(isPresented: $showingAbout) {
            TBDisplaySenderAboutView(service: service)
        }
    }

    private var activeSession: TBDisplaySenderSession? {
        let sessions = service.sessions
        guard !sessions.isEmpty else { return nil }
        return sessions[min(activeIndex, sessions.count - 1)]
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            TBLabel(TBDisplaySenderL10n.appName(service.language), size: 11, tint: TBTheme.textSecondary)

            if service.anyStreaming {
                TBStatusDot(tint: TBTheme.teal, size: 5)
            }

            TBRule(vertical: true, length: 10)

            Text(service.summaryStatusText())
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            Button(TBDisplaySenderL10n.addSessionButton(service.language)) {
                service.addSession()
                withAnimation(.easeOut(duration: 0.25)) {
                    activeIndex = max(0, service.sessions.count - 1)
                }
            }
            .buttonStyle(TBTextActionStyle())

            TBRule(vertical: true, length: 10)

            Button(service.language.str("sender.section.about")) {
                showingAbout = true
            }
            .buttonStyle(TBTextActionStyle())

            TBRule(vertical: true, length: 10)

            SettingsLink {
                Text(TBDisplaySenderL10n.settingsTitle(service.language))
            }
            .buttonStyle(TBTextActionStyle())
        }
        // Clears the traffic lights: the title bar is transparent, so the
        // header sits in the same plane as the window controls.
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 16)
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            if service.sessions.count > 1 {
                // Bounded so the arrows stay beside the card instead of
                // drifting to the window edges on a wide window.
                HStack(spacing: 0) {
                    carouselArrow(direction: -1, symbol: "chevron.left")
                    Spacer(minLength: 0)
                    carouselArrow(direction: 1, symbol: "chevron.right")
                }
                .frame(maxWidth: 580)
            }

            VStack(spacing: 20) {
                if let session = activeSession {
                    TBTargetCard(service: service, session: session)
                        .id(session.id)
                        .frame(maxWidth: 440)
                        .transition(.opacity)
                }

                if service.sessions.count > 1 {
                    carouselDots
                }
            }
            .padding(.horizontal, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func carouselArrow(direction: Int, symbol: String) -> some View {
        Button {
            step(by: direction)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .light))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(TBTextActionStyle(size: 15))
    }

    private var carouselDots: some View {
        HStack(spacing: 7) {
            ForEach(Array(service.sessions.enumerated()), id: \.element.id) { index, session in
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { activeIndex = index }
                } label: {
                    Capsule(style: .continuous)
                        .fill(index == currentIndex ? TBTheme.accent : Color.white.opacity(0.14))
                        .frame(width: index == currentIndex ? 18 : 5, height: 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(service.sessionTitle(for: session))
            }
        }
        .animation(.easeOut(duration: 0.25), value: currentIndex)
    }

    private var currentIndex: Int {
        min(activeIndex, max(0, service.sessions.count - 1))
    }

    private func step(by direction: Int) {
        let count = service.sessions.count
        guard count > 1 else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            activeIndex = (currentIndex + (direction >= 0 ? 1 : count - 1)) % count
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            TBLabel(service.language.str("sender.footer.link"))

            Text(service.localInterfaceSummaryText)
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Button(TBDisplaySenderL10n.refreshIPButton(service.language)) {
                service.refreshLocalInterfaces()
            }
            .buttonStyle(TBTextActionStyle(size: 9))

            Spacer(minLength: 12)

            if service.anyConnected {
                Button(TBDisplaySenderL10n.stopAllButton(service.language)) {
                    service.stopAll()
                }
                .buttonStyle(TBTextActionStyle(size: 9, accented: true))

                TBRule(vertical: true, length: 10)
            }

            Text("\(TBDisplaySenderL10n.versionLabel(service.language)) \(TBDisplaySenderBuildInfo.versionDisplay)")
                .font(TBFont.mono(9))
                .foregroundStyle(TBTheme.textDim)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            TBRule()
        }
    }
}

// MARK: - Target card
//
// One receiver: its name, three facts about it, and one action. Everything
// else is a verb underneath or a panel that has to be asked for.

private struct TBTargetCard: View {
    @ObservedObject var service: TBDisplaySenderService
    @ObservedObject var session: TBDisplaySenderSession
    @State private var showingConfiguration = false
    @State private var showingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if hasTarget {
                connectedBody
            } else {
                emptyBody
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingConfiguration) {
            TBSessionConfigurationSheet(service: service, session: session)
        }
    }

    // MARK: Empty state

    private var emptyBody: some View {
        VStack(spacing: 0) {
            TBBreathingLine()

            Text(service.language.str("sender.stage.scanning"))
                .font(TBFont.body(13))
                .tracking(1.2)
                .foregroundStyle(TBTheme.textSecondary)
                .padding(.top, 34)

            Text(service.language.str("sender.stage.scanning_hint"))
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textDim)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            if !service.discoveredReceivers.isEmpty {
                VStack(spacing: 8) {
                    TBLabel(service.language.str("sender.stage.discovered"))
                        .padding(.bottom, 2)

                    ForEach(service.discoveredReceivers.prefix(3)) { receiver in
                        Button(receiver.receiverName.isEmpty ? receiver.preferredIP : receiver.receiverName) {
                            service.applyDiscoveredReceiver(receiver, to: session)
                        }
                        .buttonStyle(TBSecondaryButtonStyle(wide: true))
                    }
                }
                .frame(maxWidth: 260)
                .padding(.top, 32)
            }

            Button(service.language.str("sender.action.enter_address")) {
                showingConfiguration = true
            }
            .buttonStyle(TBTextActionStyle())
            .padding(.top, 28)
        }
    }

    // MARK: Configured target

    private var connectedBody: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(TBFont.display(34))
                .tracking(0.5)
                .foregroundStyle(session.isConnected ? TBTheme.textPrimary : TBTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            TBAccentUnderline()
                .padding(.top, 12)

            metaRow
                .padding(.top, 24)

            if session.isStreaming || TBPendingIntegration.batteryState(for: session) != nil {
                liveRow
                    .padding(.top, 12)
            }

            Text(session.statusText)
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textDim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.horizontal, 8)

            primaryAction
                .frame(maxWidth: 240)
                .padding(.top, 26)

            verbs
                .padding(.top, 18)

            if session.isConnected {
                displayControls
                    .padding(.top, 24)
            }

            if showingDetails {
                detailsPanel
                    .padding(.top, 14)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            TBLabel(session.transportKind.title(service.language))

            TBRule(vertical: true, length: 10)

            Text(trimmedReceiverIP.isEmpty ? "—" : trimmedReceiverIP)
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textDim)
                .textSelection(.enabled)

            TBRule(vertical: true, length: 10)

            HStack(spacing: 7) {
                TBStatusDot(tint: statusTint, pulsing: session.isConnected && !session.isStreaming, size: 5)
                TBLabel(statusTitle, tint: session.isStreaming ? TBTheme.textSecondary : TBTheme.textDim)
            }

            if TBPendingIntegration.autoConnectBinding(for: session)?.wrappedValue == true {
                TBTag(service.language.str("sender.tag.auto"))
            }
        }
        .lineLimit(1)
    }

    /// Second meta line: only exists while there is something live to report.
    private var liveRow: some View {
        HStack(spacing: 12) {
            if session.isStreaming {
                TBLiveFPSLabel(metrics: session.liveMetrics)
            }

            if let battery = TBPendingIntegration.batteryState(for: session) {
                if session.isStreaming {
                    TBRule(vertical: true, length: 10)
                }
                batteryRow(battery)
            }
        }
    }

    private func batteryRow(_ battery: TBReceiverBatteryState) -> some View {
        HStack(spacing: 7) {
            Image(systemName: batterySymbol(battery))
                .font(.system(size: 11))
                .foregroundStyle(battery.isCharging ? TBTheme.teal : TBTheme.textDim)
            Text("\(battery.percentage)%")
                .font(TBFont.mono(10))
                .foregroundStyle(TBTheme.textSecondary)
            TBLabel(
                battery.isCharging
                    ? service.language.str("sender.battery.charging")
                    : service.language.str("sender.battery.on_battery")
            )
        }
        .help(service.language.str("sender.battery.label"))
    }

    private func batterySymbol(_ battery: TBReceiverBatteryState) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percentage {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var primaryAction: some View {
        Button(session.isConnected
               ? TBDisplaySenderL10n.stopButton(service.language)
               : TBDisplaySenderL10n.connectButton(service.language)) {
            if session.isConnected {
                session.stop()
            } else {
                session.connect()
            }
        }
        .buttonStyle(TBPrimaryButtonStyle())
        .disabled(!session.isConnected && (trimmedReceiverIP.isEmpty || session.localInterfaceIP.isEmpty))
    }

    private var verbs: some View {
        HStack(spacing: 14) {
            Button(service.language.str("sender.action.configure")) {
                showingConfiguration = true
            }
            .buttonStyle(TBTextActionStyle())

            TBRule(vertical: true, length: 10)

            Button(service.language.str("sender.action.details")) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showingDetails.toggle()
                }
            }
            .buttonStyle(TBTextActionStyle(accented: showingDetails))

            TBRule(vertical: true, length: 10)

            Button(TBDisplaySenderL10n.removeSessionButton(service.language)) {
                service.removeSession(session)
            }
            .buttonStyle(TBTextActionStyle())
            .disabled(service.sessions.count == 1 || session.isConnected || session.isStreaming)
        }
    }

    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TBLabel(service.language.str("sender.section.display_controls"))

            TBSliderRow(
                label: service.language.str("sender.display.brightness"),
                minSymbol: "sun.min.fill",
                maxSymbol: "sun.max.fill",
                value: $session.brightness
            )

            if session.audioEnabled {
                TBSliderRow(
                    label: service.language.str("sender.display.volume"),
                    minSymbol: "speaker.fill",
                    maxSymbol: "speaker.wave.3.fill",
                    value: $session.volume
                )
            }

            if session.receiverSupportsNightShift || session.receiverSupportsTrueTone {
                HStack(spacing: 16) {
                    if session.receiverSupportsNightShift {
                        TBInlineToggle(
                            title: service.language.str("sender.display.night_shift"),
                            isOn: $session.nightShiftEnabled
                        )
                    }
                    if session.receiverSupportsTrueTone {
                        TBInlineToggle(
                            title: service.language.str("sender.display.true_tone"),
                            isOn: $session.trueToneEnabled
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tbPanel(brackets: true)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            TBDataRow(label: TBDisplaySenderL10n.receiverLabel(service.language), value: session.receiverPanelText)
            TBDataRow(label: TBDisplaySenderL10n.virtualDisplayLabel(service.language), value: session.virtualDisplayText)
            TBDataRow(label: TBDisplaySenderL10n.streamLabel(service.language), value: session.streamResolutionText)
            TBDataRow(label: TBDisplaySenderL10n.captureLabel(service.language), value: session.captureDisplayText)
            TBDataRow(label: TBDisplaySenderL10n.stateLabel(service.language), value: session.displayStateText)
            TBDataRow(label: service.language.str("sender.label.status"), value: session.statusText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tbPanel()
    }

    // MARK: Derived

    private var hasTarget: Bool {
        !trimmedReceiverIP.isEmpty
    }

    private var trimmedReceiverIP: String {
        session.receiverIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        let name = session.receiverDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? service.sessionTitle(for: session) : name
    }

    private var statusTitle: String {
        if session.isStreaming { return TBDisplaySenderL10n.statusChipLive(service.language) }
        if session.isConnected { return TBDisplaySenderL10n.statusChipConnected(service.language) }
        return TBDisplaySenderL10n.statusChipIdle(service.language)
    }

    private var statusTint: Color {
        if session.isStreaming { return TBTheme.teal }
        if session.isConnected { return TBTheme.accent }
        return TBTheme.textDim
    }
}

/// The FPS readout updates once a second. Keeping it in its own observer means
/// that tick only redraws these few characters.
private struct TBLiveFPSLabel: View {
    @ObservedObject var metrics: TBSessionLiveMetrics

    var body: some View {
        Text("\(metrics.senderFPS) FPS")
            .font(TBFont.mono(10))
            .foregroundStyle(TBTheme.textSecondary)
    }
}

// MARK: - Session configuration sheet
//
// Everything that used to crowd the main window. A rail of four sections
// instead of one long scroll, so a single concern is on screen at a time.

private enum TBConfigurationTab: Hashable {
    case connection
    case output
    case input
    case diagnostics
}

private struct TBSessionConfigurationSheet: View {
    @ObservedObject var service: TBDisplaySenderService
    @ObservedObject var session: TBDisplaySenderSession
    @Environment(\.dismiss) private var dismiss
    @State private var tab: TBConfigurationTab = .connection
    @State private var configurationChecks: [TBConfigurationCheck] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TBSheetHeader(
                title: title,
                subtitle: settingsSubtitle,
                closeTitle: service.language.str("common.close"),
                onClose: { dismiss() }
            )
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 20)

            TBRule()

            HStack(alignment: .top, spacing: 0) {
                TBSectionRail(items: railItems, selection: $tab)
                    .frame(width: 150, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                TBRule(vertical: true, length: nil)
                    .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch tab {
                        case .connection: connectionSection
                        case .output: outputSection
                        case .input: inputSection
                        case .diagnostics: diagnosticsSection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                }
            }
        }
        .tbSheetChrome(width: 760, height: 620)
        .onAppear {
            if tab == .input && !service.inputDockstationAvailable {
                tab = .connection
            }
        }
    }

    private var railItems: [TBRailItem<TBConfigurationTab>] {
        var items = [
            TBRailItem(tab: TBConfigurationTab.connection, title: TBDisplaySenderL10n.connectionGroup(service.language)),
            TBRailItem(tab: TBConfigurationTab.output, title: TBDisplaySenderL10n.outputTitle(service.language))
        ]
        if service.inputDockstationAvailable {
            items.append(TBRailItem(tab: .input, title: service.language.str("sender.section.input")))
        }
        items.append(TBRailItem(tab: .diagnostics, title: service.language.str("sender.section.diagnostics")))
        return items
    }

    private var title: String {
        let name = session.receiverDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? service.sessionTitle(for: session) : name
    }

    // MARK: Connection

    private var connectionSection: some View {
        Group {
            TBSettingRow(label: TBDisplaySenderL10n.transportKind(service.language), detail: transportDetails) {
                Picker("", selection: $session.transportKind) {
                    ForEach(service.availableTransportKinds) { transportKind in
                        Text(transportKind.title(service.language)).tag(transportKind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: session.transportKind) { _, _ in
                    service.transportDidChange(for: session)
                }
                .disabled(session.isConnected || session.isStreaming)
            }

            TBSettingRow(label: TBDisplaySenderL10n.localInterfaceIP(service.language), detail: localInterfaceDetails) {
                Picker("", selection: $session.localInterfaceIP) {
                    Text(TBDisplaySenderL10n.notDetected(service.language)).tag("")
                    ForEach(service.availableInterfaces(for: session.transportKind)) { localInterface in
                        Text(localInterface.displayText(service.language)).tag(localInterface.ip)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(session.isConnected || session.isStreaming)
            }

            TBSettingRow(label: TBDisplaySenderL10n.discoveredReceiver(service.language), detail: discoveryDetails) {
                Picker("", selection: $session.selectedReceiverID) {
                    Text(TBDisplaySenderL10n.manualReceiverEntry(service.language)).tag("")
                    ForEach(service.discoveredReceivers) { receiver in
                        Text(receiver.displayText).tag(receiver.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: session.selectedReceiverID) { _, newValue in
                    guard let receiver = service.discoveredReceivers.first(where: { $0.id == newValue }) else { return }
                    service.applyDiscoveredReceiver(receiver, to: session)
                }
                .disabled(session.isConnected || session.isStreaming)
            }

            TBSettingRow(label: TBDisplaySenderL10n.receiverIP(service.language), detail: receiverDetails) {
                TextField("169.254.x.x / 192.168.x.x", text: $session.receiverIP)
                    .textFieldStyle(.roundedBorder)
                    .font(TBFont.mono(11))
                    .disabled(session.isConnected || session.isStreaming)
            }

            // Only offered for a receiver that came from discovery: trust is
            // keyed on the discovered receiver, so a hand-typed address has
            // nowhere to store it.
            if let autoConnect = TBPendingIntegration.autoConnectBinding(for: session) {
                TBSettingRow(
                    label: service.language.str("sender.toggle.auto_connect"),
                    detail: service.language.str("sender.toggle.auto_connect_hint")
                ) {
                    Toggle("", isOn: autoConnect)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(TBTheme.accent)
                }
            }

            if !service.discoveredReceivers.isEmpty {
                Text(TBDisplaySenderL10n.discoveryHint(service.language))
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Output

    private var outputSection: some View {
        Group {
            TBSettingRow(
                label: TBDisplaySenderL10n.displayProfiles(service.language),
                detail: TBDisplaySenderL10n.displayProfilesHint(service.language)
            ) {
                HStack(spacing: 8) {
                    ForEach(TBDisplayProfile.allCases) { profile in
                        Button(TBDisplaySenderL10n.displayProfileTitle(profile, language: service.language)) {
                            service.applyDisplayProfile(profile, to: session)
                        }
                        .buttonStyle(TBSecondaryButtonStyle())
                        .disabled(session.isConnected || session.isStreaming)
                    }
                }
            }

            TBSettingRow(label: TBDisplaySenderL10n.captureSource(service.language), detail: captureModeDetails) {
                Picker("", selection: $session.captureSource) {
                    ForEach(TBDisplayCaptureSource.allCases) { source in
                        Text(source.title(service.language)).tag(source)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(session.isConnected || session.isStreaming)
            }

            TBSettingRow(label: TBDisplaySenderL10n.streamProfile(service.language), detail: streamProfileDetails) {
                Picker("", selection: $session.capturePreset) {
                    ForEach(TBDisplayCapturePreset.allCases, id: \.self) { preset in
                        Text("\(preset.title(service.language)) · \(preset.description)").tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(session.isConnected || session.isStreaming)
            }

            if session.captureSource == .extendedDesktop {
                TBSettingRow(label: renderMatchingTitle, detail: renderMatchingDetails) {
                    Toggle("", isOn: $session.matchRenderToStream)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(TBTheme.accent)
                        .disabled(session.isConnected || session.isStreaming)
                }
            }

            if service.audioRelayAvailable {
                TBSettingRow(label: TBDisplaySenderL10n.streamAudio(service.language), detail: audioDetails) {
                    Toggle("", isOn: $session.audioEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(TBTheme.accent)
                        .disabled(session.isConnected || session.isStreaming)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(TBDisplaySenderL10n.streamHint1(service.language))
                Text(TBDisplaySenderL10n.streamHint2(service.language))
            }
            .font(TBFont.body(11))
            .foregroundStyle(TBTheme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
    }

    // MARK: Input

    @ViewBuilder
    private var inputSection: some View {
        TBSettingRow(label: inputDockstationTitle, detail: inputDockstationDetails) {
            Picker(
                "",
                selection: Binding(
                    get: { session.inputControlRole },
                    set: { service.setInputControlRole($0, for: session) }
                )
            ) {
                ForEach(TBInputControlRole.allCases) { role in
                    Text(inputControlRoleTitle(role)).tag(role)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!session.isConnected)
        }

        if session.inputControlRole == .senderMaster {
            TBSettingRow(label: inputGestureModeTitle, detail: inputGestureModeDetails) {
                Picker("", selection: $session.inputGestureMode) {
                    ForEach(TBInputGestureMode.allCases) { mode in
                        Text(inputGestureModeOptionTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!session.isConnected)
            }
        }

        if session.inputControlRole == .receiverMaster {
            TBInputBindingsView(session: session, language: service.language)
                .padding(14)
                .tbSurface()
        }

        if session.inputControlRole == .senderMaster, !service.localInputMonitoringTrusted {
            TBWarningPanel(
                title: localInputMonitoringWarningTitle,
                message: localInputMonitoringWarningBody,
                actionTitle: openInputMonitoringSettingsTitle,
                action: { service.openInputMonitoringSettings() },
                statusText: "listen=false"
            )
        }

        if session.inputControlRole == .senderMaster, session.receiverAccessibilityTrustedHint == false {
            TBWarningPanel(
                title: receiverAccessibilityWarningTitle,
                message: receiverAccessibilityWarningBody,
                statusText: "receiver accessibility=false"
            )
        }

        if session.inputControlRole == .receiverMaster, !service.localInputInjectionTrusted {
            TBWarningPanel(
                title: inputPermissionWarningTitle,
                message: inputPermissionWarningBody,
                actionTitle: openAccessibilitySettingsTitle,
                action: { service.openAccessibilitySettings() },
                statusText: inputPermissionStatusText
            )
        }

        if session.inputControlRole == .receiverMaster, session.receiverInputMonitoringTrustedHint == false {
            TBWarningPanel(
                title: receiverInputMonitoringWarningTitle,
                message: receiverInputMonitoringWarningBody,
                statusText: "receiver input-monitoring=false"
            )
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        TBLabel(
                            TBDisplaySenderL10n.text("sender.diagnostics.guided_title", service.language),
                            tint: TBTheme.textSecondary
                        )
                        Text(TBDisplaySenderL10n.text("sender.diagnostics.guided_hint", service.language))
                            .font(TBFont.body(11))
                            .foregroundStyle(TBTheme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button(TBDisplaySenderL10n.text("sender.diagnostics.check_configuration", service.language)) {
                        configurationChecks = service.configurationChecks(for: session)
                    }
                    .buttonStyle(TBPrimaryButtonStyle(wide: false))
                }

                if !configurationChecks.isEmpty {
                    TBRule()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(configurationChecks) { check in
                            configurationCheckRow(check)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tbPanel()

            VStack(alignment: .leading, spacing: 14) {
                TBLabel(TBDisplaySenderL10n.cableTestGroup(service.language))

                HStack(spacing: 12) {
                    Button {
                        session.startCableTest()
                    } label: {
                        HStack(spacing: 8) {
                            if session.isCableTesting {
                                TBSpinner(size: 11)
                            }
                            Text(session.isCableTesting
                                 ? TBDisplaySenderL10n.testingButton(service.language)
                                 : TBDisplaySenderL10n.cableTestButton(service.language))
                        }
                    }
                    .buttonStyle(TBSecondaryButtonStyle())
                    .disabled(session.isConnected || session.isStreaming || session.isCableTesting
                              || trimmedReceiverIP.isEmpty || session.localInterfaceIP.isEmpty)

                    Text(cableRateText)
                        .font(TBFont.mono(11))
                        .foregroundStyle(session.cableTestResult == nil ? TBTheme.textDim : TBTheme.teal)

                    Spacer(minLength: 12)

                    Button(TBDisplaySenderL10n.restartCaptureButton(service.language)) {
                        session.restartCaptureNow()
                    }
                    .buttonStyle(TBSecondaryButtonStyle())
                    .disabled(!session.canRestartCapture)
                }

                TBRule()

                VStack(alignment: .leading, spacing: 9) {
                    TBDataRow(label: TBDisplaySenderL10n.captureLabel(service.language), value: session.captureDisplayText)
                    TBDataRow(label: TBDisplaySenderL10n.stateLabel(service.language), value: session.displayStateText)
                    TBDataRow(label: service.language.str("sender.label.status"), value: session.statusText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tbPanel()
        }
    }

    private func configurationCheckRow(_ check: TBConfigurationCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: configurationCheckIcon(for: check.state))
                .font(.system(size: 11))
                .foregroundStyle(configurationCheckColor(for: check.state))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(TBDisplaySenderL10n.text(check.titleKey, service.language))
                    .font(TBFont.body(11, weight: .medium))
                    .foregroundStyle(TBTheme.textSecondary)
                Text(TBDisplaySenderL10n.text(check.detailKey, service.language, check.values))
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func configurationCheckIcon(for state: TBConfigurationCheckState) -> String {
        switch state {
        case .passed: return "checkmark.circle"
        case .attention: return "exclamationmark.triangle.fill"
        case .pending: return "clock"
        }
    }

    private func configurationCheckColor(for state: TBConfigurationCheckState) -> Color {
        switch state {
        case .passed: return TBTheme.teal
        case .attention: return TBTheme.warning
        case .pending: return TBTheme.textDim
        }
    }

    private var trimmedReceiverIP: String {
        session.receiverIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cableRateText: String {
        if let rate = session.cableTestResult {
            return String(format: "%.2f Gbits/s", rate)
        }
        return TBDisplaySenderL10n.noTestResult(service.language)
    }

    // MARK: Copy

    private var settingsSubtitle: String {
        switch service.language {
        case .italian: return "Configura trasporto, output e diagnostica senza sporcare la dashboard principale."
        case .english: return "Configure transport, output, and diagnostics without cluttering the main dashboard."
        case .german: return "Transport, Ausgabe und Diagnose konfigurieren, ohne das Haupt-Dashboard zu überladen."
        case .french: return "Configurez le transport, la sortie et le diagnostic sans encombrer le tableau de bord principal."
        case .chinese: return "在不干扰主控制面板的情况下配置传输、输出和诊断。"
        }
    }

    private var transportDetails: String {
        switch service.language {
        case .italian: return "Scegli il percorso di rete per questa sessione. Thunderbolt Bridge resta il profilo raccomandato; Network Link e sperimentale."
        case .english: return "Choose the network path for this session. Thunderbolt Bridge remains the recommended profile; Network Link is experimental."
        case .german: return "Wähle den Netzwerkpfad für diese Sitzung. Thunderbolt Bridge bleibt die empfohlene Option; Network Link ist experimentell."
        case .french: return "Choisissez le chemin réseau de cette session. Thunderbolt Bridge reste le profil recommandé ; Network Link est expérimental."
        case .chinese: return "为该会话选择网络路径。Thunderbolt Bridge 仍然是推荐模式；Network Link 为实验性功能。"
        }
    }

    private var localInterfaceDetails: String {
        switch service.language {
        case .italian: return "L'interfaccia locale determina da quale indirizzo il sender apre la connessione."
        case .english: return "The local interface controls which source address the sender binds before opening the connection."
        case .german: return "Die lokale Schnittstelle bestimmt, an welche Quelladresse der Sender beim Verbindungsaufbau bindet."
        case .french: return "L’interface locale détermine l’adresse source à laquelle le sender se lie avant d’ouvrir la connexion."
        case .chinese: return "本地接口决定 sender 在建立连接前绑定的源地址。"
        }
    }

    private var discoveryDetails: String {
        switch service.language {
        case .italian: return "Seleziona un receiver rilevato automaticamente oppure lascia inserimento manuale."
        case .english: return "Select an automatically discovered receiver or keep manual entry."
        case .german: return "Wähle einen automatisch gefundenen Empfänger oder bleibe bei der manuellen Eingabe."
        case .french: return "Sélectionnez un receiver détecté automatiquement ou conservez la saisie manuelle."
        case .chinese: return "选择自动发现的 receiver，或者保持手动输入。"
        }
    }

    private var receiverDetails: String {
        switch service.language {
        case .italian: return "Indirizzo diretto del receiver. Puoi usare IP Thunderbolt o LAN a seconda del trasporto."
        case .english: return "Direct receiver address. You can use a Thunderbolt or LAN IP depending on the selected transport."
        case .german: return "Direkte Empfängeradresse. Je nach gewähltem Transport kann eine Thunderbolt- oder LAN-IP verwendet werden."
        case .french: return "Adresse directe du receiver. Vous pouvez utiliser une IP Thunderbolt ou LAN selon le transport sélectionné."
        case .chinese: return "receiver 的直连地址。可以根据所选传输使用 Thunderbolt 或局域网 IP。"
        }
    }

    private var captureModeDetails: String {
        switch service.language {
        case .italian: return "Mirror per duplicare il desktop, Extended per creare un display indipendente."
        case .english: return "Mirror duplicates the desktop, Extended creates a separate display."
        case .german: return "Mirror dupliziert den Desktop, Extended erstellt ein separates Display."
        case .french: return "Dupliquer recopie le bureau, Étendu crée un écran distinct."
        case .chinese: return "Mirror 复制桌面，Extended 创建独立显示器。"
        }
    }

    private var streamProfileDetails: String {
        switch service.language {
        case .italian: return "Parti da preset conservativi su Wi-Fi o reti lente, poi sali se la stabilita rimane buona."
        case .english: return "Start with conservative presets on Wi-Fi or slower links, then move up if stability stays good."
        case .german: return "Beginne bei WLAN oder langsameren Verbindungen mit konservativen Profilen und wähle höhere Einstellungen, wenn die Verbindung stabil bleibt."
        case .french: return "Commencez avec des préréglages prudents sur Wi-Fi ou les liaisons lentes, puis augmentez-les si la stabilité reste bonne."
        case .chinese: return "在 Wi‑Fi 或较慢链路上先使用保守预设，稳定后再逐步提高。"
        }
    }

    private var audioDetails: String {
        switch service.language {
        case .italian: return "Invia anche l'audio di sistema del sender al receiver per questa sessione."
        case .english: return "Also send the sender’s system audio to the receiver for this session."
        case .german: return "Überträgt für diese Sitzung auch den Systemton des Senders an den Empfänger."
        case .french: return "Envoie aussi l’audio système du sender au receiver pour cette session."
        case .chinese: return "同时将 sender 的系统音频传到此会话的 receiver。"
        }
    }

    private var renderMatchingTitle: String {
        switch service.language {
        case .italian: return "Rendering alla risoluzione dello stream"
        case .english: return "Match render to stream"
        case .german: return "Rendern in Stream-Auflösung"
        case .french: return "Adapter le rendu au flux"
        case .chinese: return "渲染匹配串流分辨率"
        }
    }

    private var renderMatchingDetails: String {
        let desktop = session.renderMatchedDesktopText
        switch service.language {
        case .italian: return "Dimensiona il display virtuale sul profilo dello stream: nessun ridimensionamento in cattura. Il desktop appare come \(desktop) HiDPI."
        case .english: return "Sizes the virtual display to the stream profile so capture is 1:1 — no rescale before encoding. Desktop looks like \(desktop) HiDPI."
        case .german: return "Passt das virtuelle Display an das Stream-Profil an, sodass die Aufnahme 1:1 erfolgt. Der Desktop erscheint als \(desktop) HiDPI."
        case .french: return "Dimensionne l’écran virtuel selon le profil de flux pour une capture 1:1, sans redimensionnement avant l’encodage. Le bureau apparaît en \(desktop) HiDPI."
        case .chinese: return "使虚拟显示器匹配串流分辨率，捕获无需缩放。桌面显示为 \(desktop) HiDPI。"
        }
    }

    private var inputDockstationTitle: String {
        switch service.language {
        case .italian: return "Input Dockstation"
        case .english: return "Input Dockstation"
        case .german: return "Input Dockstation"
        case .french: return "Station d’accueil des entrées"
        case .chinese: return "输入扩展坞"
        }
    }

    private var inputDockstationDetails: String {
        switch service.language {
        case .italian: return "Definisce il ruolo input di questa sessione. Una sola sessione puo avere un master attivo alla volta: questo Mac puo controllare il receiver, oppure il receiver puo controllare questo Mac. Per uscire rapidamente dal controllo usa Ctrl+Option+Command+K."
        case .english: return "Defines the input role for this session. Only one session can have an active master at a time: this Mac can control the receiver, or the receiver can control this Mac. Use Control+Option+Command+K to exit control quickly."
        case .german: return "Legt die Eingaberolle für diese Sitzung fest. Nur eine Sitzung kann gleichzeitig einen aktiven Master haben: Dieser Mac kann den Empfänger steuern oder der Empfänger kann diesen Mac steuern. Mit Ctrl+Option+Command+K beendest du die Steuerung schnell."
        case .french: return "Définit le rôle d’entrée de cette session. Une seule session peut avoir un master actif à la fois : ce Mac peut contrôler le receiver, ou le receiver peut contrôler ce Mac. Utilisez Contrôle+Option+Commande+K pour quitter rapidement le contrôle."
        case .chinese: return "定义此会话的输入角色。同一时间只能有一个活动 master：这台 Mac 可以控制 receiver，或者 receiver 可以控制这台 Mac。按下 Control+Option+Command+K 可以快速退出控制。"
        }
    }

    private var inputGestureModeTitle: String {
        switch service.language {
        case .italian: return "Cambio slave"
        case .english: return "Slave switching"
        case .german: return "Slave-Wechsel"
        case .french: return "Changement de slave"
        case .chinese: return "Slave 切换"
        }
    }

    private var inputGestureModeDetails: String {
        switch service.language {
        case .italian:
            return "Decide come passare da uno slave all'altro quando 'Questo Mac e Master' e attivo. In modalita nativa, macOS continua a gestire normalmente il desktop del master. In modalita relay, TargetBridge usa il bordo sinistro/destro dello schermo e le hotkey Ctrl+Option+Freccia Sinistra/Destra per spostare il controllo allo slave precedente o successivo."
        case .english:
            return "Chooses how to move control from one slave to another when 'This Mac is Master' is active. In native mode, macOS keeps handling the master's desktop normally. In relay mode, TargetBridge uses the left/right screen edge and the Ctrl+Option+Left/Right hotkeys to move control to the previous or next slave."
        case .german:
            return "Legt fest, wie die Steuerung von einem Slave zum anderen wechselt, wenn 'Dieser Mac ist Master' aktiv ist. Im nativen Modus verwaltet macOS den Desktop des Masters normal weiter. Im Relay-Modus nutzt TargetBridge den linken/rechten Bildschirmrand und die Hotkeys Ctrl+Option+Links/Rechts, um zum vorherigen oder nächsten Slave zu wechseln."
        case .french:
            return "Définit comment déplacer le contrôle d’un slave à l’autre lorsque « Ce Mac est Master » est actif. En mode natif, macOS continue de gérer normalement le bureau du master. En mode relais, TargetBridge utilise les bords gauche et droit de l’écran ainsi que les raccourcis Ctrl+Option+Gauche/Droite pour déplacer le contrôle vers le slave précédent ou suivant."
        case .chinese:
            return "决定在“这台 Mac 是 Master”启用时如何在不同 slave 之间切换控制。原生模式下，macOS 继续正常处理 master 的桌面；relay 模式下，TargetBridge 会使用屏幕左右边缘以及 Ctrl+Option+Left/Right 热键，把控制切换到上一个或下一个 slave。"
        }
    }

    private func inputGestureModeOptionTitle(_ mode: TBInputGestureMode) -> String {
        switch (mode, service.language) {
        case (.native, .italian): return "Lascia il desktop nativo del master"
        case (.native, .english): return "Keep master's desktop native"
        case (.native, .german): return "Desktop des Masters nativ lassen"
        case (.native, .french): return "Conserver le bureau natif du master"
        case (.native, .chinese): return "保留 master 的原生桌面行为"
        case (.relayToSlave, .italian): return "Usa bordi schermo e hotkey per cambiare slave"
        case (.relayToSlave, .english): return "Use screen edges and hotkeys to switch slave"
        case (.relayToSlave, .german): return "Bildschirmränder und Hotkeys für Slave-Wechsel nutzen"
        case (.relayToSlave, .french): return "Utiliser les bords de l’écran et les raccourcis pour changer de slave"
        case (.relayToSlave, .chinese): return "使用屏幕边缘和热键切换 slave"
        }
    }

    private func inputControlRoleTitle(_ role: TBInputControlRole) -> String {
        switch (role, service.language) {
        case (.off, .italian): return "Off"
        case (.off, .english): return "Off"
        case (.off, .german): return "Aus"
        case (.off, .french): return "Désactivé"
        case (.off, .chinese): return "关闭"
        case (.senderMaster, .italian): return "Questo Mac e Master"
        case (.senderMaster, .english): return "This Mac is Master"
        case (.senderMaster, .german): return "Dieser Mac ist Master"
        case (.senderMaster, .french): return "Ce Mac est Master"
        case (.senderMaster, .chinese): return "这台 Mac 是 Master"
        case (.receiverMaster, .italian): return "Receiver e Master"
        case (.receiverMaster, .english): return "Receiver is Master"
        case (.receiverMaster, .german): return "Empfänger ist Master"
        case (.receiverMaster, .french): return "Le receiver est Master"
        case (.receiverMaster, .chinese): return "Receiver 是 Master"
        }
    }

    private var inputPermissionWarningTitle: String {
        switch service.language {
        case .italian: return "Il sender non puo ancora iniettare input"
        case .english: return "The sender cannot inject input yet"
        case .german: return "Der Sender kann noch keine Eingaben injizieren"
        case .french: return "Le sender ne peut pas encore injecter d’entrées"
        case .chinese: return "Sender 目前还不能注入输入"
        }
    }

    private var inputPermissionWarningBody: String {
        switch service.language {
        case .italian:
            return "Per usare 'Receiver e Master', questa app TargetBridge sul sender deve essere autorizzata in Privacy e Sicurezza > Accessibilita. Apri le impostazioni, abilita l'app che stai usando e poi riapri la sessione. Le scorciatoie configurate richiedono inoltre una sola autorizzazione macOS per controllare System Events."
        case .english:
            return "To use 'Receiver is Master', this TargetBridge app on the sender must be allowed under Privacy & Security > Accessibility. Open the settings, enable the app you are actually running, then reopen the session. Configured shortcuts also require a one-time macOS permission to control System Events."
        case .german:
            return "Um 'Empfänger ist Master' zu verwenden, muss diese TargetBridge-App auf dem Sender unter Datenschutz & Sicherheit > Bedienungshilfen erlaubt sein. Öffne die Einstellungen, aktiviere die wirklich verwendete App und öffne dann die Sitzung erneut. Konfigurierte Kurzbefehle benötigen außerdem einmalig die macOS-Erlaubnis, System Events zu steuern."
        case .french:
            return "Pour utiliser « Le receiver est Master », cette app TargetBridge sur le sender doit être autorisée dans Confidentialité et sécurité > Accessibilité. Ouvrez les réglages, activez l’app que vous utilisez réellement, puis rouvrez la session. Les raccourcis configurés exigent aussi une autorisation macOS unique pour contrôler System Events."
        case .chinese:
            return "要使用“Receiver 是 Master”，sender 上这份 TargetBridge 必须在“隐私与安全性 > 辅助功能”中被允许。打开设置，启用你当前运行的这份应用，然后重新打开会话。已配置的快捷键还需要一次性授权 TargetBridge 控制 System Events。"
        }
    }

    private var openAccessibilitySettingsTitle: String {
        switch service.language {
        case .italian: return "Apri Accessibilita"
        case .english: return "Open Accessibility"
        case .german: return "Bedienungshilfen öffnen"
        case .french: return "Ouvrir Accessibilité"
        case .chinese: return "打开辅助功能"
        }
    }

    private var inputPermissionStatusText: String {
        service.localInputInjectionTrusted ? "trusted=true" : "trusted=false"
    }

    private var localInputMonitoringWarningTitle: String {
        switch service.language {
        case .italian: return "Manca il monitoraggio input sul sender"
        case .english: return "Input Monitoring is missing on the sender"
        case .german: return "Eingabeüberwachung fehlt auf dem Sender"
        case .french: return "La surveillance des entrées manque sur le sender"
        case .chinese: return "sender 缺少输入监控权限"
        }
    }

    private var localInputMonitoringWarningBody: String {
        switch service.language {
        case .italian:
            return "Per usare 'Questo Mac e Master' in modo affidabile anche fuori dalla finestra attiva, il sender deve avere il permesso Monitoraggio input. Senza questo permesso alcuni tasti o movimenti globali possono non essere catturati."
        case .english:
            return "To use 'This Mac is Master' reliably outside the active app window, the sender needs Input Monitoring permission. Without it, some keys or global pointer events may not be captured."
        case .german:
            return "Damit 'Dieser Mac ist Master' auch außerhalb des aktiven Fensters zuverlässig funktioniert, braucht der Sender die Berechtigung für Eingabeüberwachung. Ohne diese können einige Tasten oder globale Zeigerereignisse fehlen."
        case .french:
            return "Pour utiliser « Ce Mac est Master » de façon fiable en dehors de la fenêtre active, le sender a besoin de l’autorisation Surveillance des entrées. Sans elle, certaines touches ou certains événements globaux du pointeur peuvent ne pas être capturés."
        case .chinese:
            return "要让“这台 Mac 是 Master”在活动窗口之外也可靠工作，sender 需要“输入监控”权限。没有它，一些按键或全局指针事件可能无法被捕获。"
        }
    }

    private var receiverAccessibilityWarningTitle: String {
        switch service.language {
        case .italian: return "Manca Accessibilita sul receiver"
        case .english: return "Accessibility is missing on the receiver"
        case .german: return "Bedienungshilfen fehlen auf dem Empfänger"
        case .french: return "L’accessibilité manque sur le receiver"
        case .chinese: return "receiver 缺少辅助功能权限"
        }
    }

    private var receiverAccessibilityWarningBody: String {
        switch service.language {
        case .italian:
            return "Con 'Questo Mac e Master', il receiver deve poter iniettare click e tastiera. Sul Mac receiver abilita TargetBridge Receiver in Privacy e Sicurezza > Accessibilita."
        case .english:
            return "With 'This Mac is Master', the receiver must be allowed to inject clicks and keyboard events. On the receiver Mac, enable TargetBridge Receiver under Privacy & Security > Accessibility."
        case .german:
            return "Bei 'Dieser Mac ist Master' muss der Empfänger Klicks und Tastatureingaben injizieren dürfen. Aktiviere auf dem Empfänger-Mac TargetBridge-Receiver unter Datenschutz & Sicherheit > Bedienungshilfen."
        case .french:
            return "Avec « Ce Mac est Master », le receiver doit pouvoir injecter les clics et les événements clavier. Sur le Mac receiver, activez TargetBridge Receiver dans Confidentialité et sécurité > Accessibilité."
        case .chinese:
            return "在“这台 Mac 是 Master”模式下，receiver 必须被允许注入点击和键盘事件。请在 receiver Mac 的“隐私与安全性 > 辅助功能”中启用 TargetBridge Receiver。"
        }
    }

    private var receiverInputMonitoringWarningTitle: String {
        switch service.language {
        case .italian: return "Manca Monitoraggio input sul receiver"
        case .english: return "Input Monitoring is missing on the receiver"
        case .german: return "Eingabeüberwachung fehlt auf dem Empfänger"
        case .french: return "La surveillance des entrées manque sur le receiver"
        case .chinese: return "receiver 缺少输入监控权限"
        }
    }

    private var receiverInputMonitoringWarningBody: String {
        switch service.language {
        case .italian:
            return "Con 'Receiver e Master', il Mac receiver deve poter leggere tastiera e mouse locali. Sul receiver abilita TargetBridge Receiver in Privacy e Sicurezza > Monitoraggio input."
        case .english:
            return "With 'Receiver is Master', the receiver Mac must be allowed to read local keyboard and mouse input. On the receiver, enable TargetBridge Receiver under Privacy & Security > Input Monitoring."
        case .german:
            return "Bei 'Empfänger ist Master' muss der Empfänger-Mac lokale Tastatur- und Mauseingaben lesen dürfen. Aktiviere dort TargetBridge-Receiver unter Datenschutz & Sicherheit > Eingabeüberwachung."
        case .french:
            return "Avec « Le receiver est Master », le Mac receiver doit pouvoir lire les entrées clavier et souris locales. Sur le receiver, activez TargetBridge Receiver dans Confidentialité et sécurité > Surveillance des entrées."
        case .chinese:
            return "在“Receiver 是 Master”模式下，receiver Mac 必须被允许读取本地键盘和鼠标输入。请在 receiver 上的“隐私与安全性 > 输入监控”中启用 TargetBridge Receiver。"
        }
    }

    private var openInputMonitoringSettingsTitle: String {
        switch service.language {
        case .italian: return "Apri Monitoraggio input"
        case .english: return "Open Settings"
        case .german: return "Einstellungen öffnen"
        case .french: return "Ouvrir les réglages"
        case .chinese: return "打开设置"
        }
    }
}
