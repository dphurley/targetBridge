import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum TBPreferencesTab: Hashable {
    case general
    case interface
    case addons
    case about
}

/// App-wide preferences. Same rail idea as the session sheet: one concern on
/// screen, nothing stacked into an endless scroll.
struct TBDisplaySenderSettingsView: View {
    @ObservedObject var service: TBDisplaySenderService
    @State private var importError: String?
    @State private var tab: TBPreferencesTab = .general

    var body: some View {
        ZStack {
            TBBackground()

            VStack(alignment: .leading, spacing: 0) {
                header

                TBRule()

                HStack(alignment: .top, spacing: 0) {
                    TBSectionRail(items: railItems, selection: $tab)
                        .frame(width: 150, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)

                    TBRule(vertical: true)
                        .frame(maxHeight: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch tab {
                            case .general: generalSection
                            case .interface: interfaceSection
                            case .addons: addonsSection
                            case .about: aboutSection
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(TBTheme.accent)
        .alert(addonImportErrorTitle, isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
    }

    private var railItems: [TBRailItem<TBPreferencesTab>] {
        [
            TBRailItem(tab: .general, title: service.language.str("sender.section.general")),
            TBRailItem(tab: .interface, title: service.language.str("sender.section.interface")),
            TBRailItem(tab: .addons, title: service.language.str("sender.section.addons")),
            TBRailItem(tab: .about, title: service.language.str("sender.section.about"))
        ]
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsTitle)
                    .font(TBFont.display(24))
                    .foregroundStyle(TBTheme.textPrimary)
                Text(settingsSubtitle)
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            TBLabel("\(versionTitle) \(TBDisplaySenderBuildInfo.versionDisplay)")
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    // MARK: General

    private var generalSection: some View {
        Group {
            TBSettingRow(label: TBDisplaySenderL10n.languageGroup(service.language)) {
                HStack(spacing: 12) {
                    ForEach(TBDisplaySenderLanguage.allCases) { language in
                        Button(language.pickerTitle) {
                            service.language = language
                        }
                        .buttonStyle(TBTextActionStyle(accented: service.language == language))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(TBDisplaySenderL10n.settingsHint(service.language))
                Text(TBDisplaySenderL10n.modeLine3(service.language))
                Text(TBDisplaySenderL10n.modeLine5(service.language))
            }
            .font(TBFont.body(11))
            .foregroundStyle(TBTheme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }
    }

    // MARK: Interface

    private var interfaceSection: some View {
        Group {
            toggleRow(TBDisplaySenderL10n.showMenuBarIcon(service.language), isOn: $service.showsMenuBarIcon)
            toggleRow(
                TBDisplaySenderL10n.largeCursor(service.language),
                isOn: $service.largeCursor,
                disabled: service.anyConnected
            )
            toggleRow(TBDisplaySenderL10n.preventDisplaySleep(service.language), isOn: $service.preventDisplaySleep)
            toggleRow(TBDisplaySenderL10n.autoRestartOnWake(service.language), isOn: $service.autoRestartOnWake)
            toggleRow(TBDisplaySenderL10n.verboseDisplayLogging(service.language), isOn: $service.verboseDisplayLogging)
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        TBSettingRow(label: label) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TBTheme.accent)
                .disabled(disabled)
        }
    }

    // MARK: Add-ons

    private var addonsSection: some View {
        Group {
            Text(addonsSubtitle)
                .font(TBFont.body(11))
                .foregroundStyle(TBTheme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if service.anyConnected {
                Text(addonsConnectedHint)
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.warning.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(importAddonTitle) {
                    importAddonManifest()
                }
                .buttonStyle(TBPrimaryButtonStyle(wide: false))

                Button(refreshAddonsTitle) {
                    service.refreshAddons()
                }
                .buttonStyle(TBSecondaryButtonStyle())

                Button(openAddonsFolderTitle) {
                    service.openAddonsFolder()
                }
                .buttonStyle(TBSecondaryButtonStyle())
            }
            .padding(.vertical, 4)

            if service.addons.isEmpty {
                Text(noAddonsTitle)
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(service.addons) { addon in
                        addonCard(addon)
                    }
                }
            }
        }
    }

    private func addonCard(_ addon: TBAddonRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(addon.name)
                        .font(TBFont.body(14, weight: .light))
                        .foregroundStyle(TBTheme.textPrimary)
                    Text(addon.summary)
                        .font(TBFont.body(11))
                        .foregroundStyle(TBTheme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: { service.isAddonEnabled(addon) },
                    set: { service.setAddonEnabled($0, for: addon) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TBTheme.accent)
                .disabled(!service.isAddonCompatible(addon) || service.anyConnected)
            }

            HStack(spacing: 8) {
                TBTag(originTitle(for: addon.origin), tint: addon.origin == .bundled ? TBTheme.teal : TBTheme.textSecondary)
                TBTag("\(versionTitle) \(addon.version)")
                if addon.manifest.experimental {
                    TBTag(experimentalTitle, tint: TBTheme.warning)
                }
                if !service.isAddonCompatible(addon) {
                    TBTag(incompatibleTitle, tint: TBTheme.accent)
                }
            }

            if !addon.manifest.capabilities.isEmpty {
                HStack(spacing: 8) {
                    TBLabel(capabilitiesTitle)
                    ForEach(addon.manifest.capabilities, id: \.self) { capability in
                        TBTag(capabilityTitle(for: capability), tint: TBTheme.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tbPanel()
    }

    // MARK: About

    private var aboutSection: some View {
        Group {
            Text(aboutBody)
                .font(TBFont.body(11))
                .foregroundStyle(TBTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/swellweb/targetBridge")!) {
                    Text(githubTitle)
                }
                .buttonStyle(TBSecondaryButtonStyle())

                Link(destination: URL(string: "https://github.com/swellweb/targetBridge/releases/latest")!) {
                    Text(releaseTitle)
                }
                .buttonStyle(TBSecondaryButtonStyle())
            }
            .padding(.top, 6)
        }
    }

    private func importAddonManifest() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = importPanelMessage

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.importAddonManifest(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: Copy

    private var settingsTitle: String {
        switch service.language {
        case .italian: return "Impostazioni TargetBridge"
        case .english: return "TargetBridge Settings"
        case .german: return "TargetBridge-Einstellungen"
        case .french: return "Réglages TargetBridge"
        case .chinese: return "TargetBridge 设置"
        }
    }

    private var settingsSubtitle: String {
        switch service.language {
        case .italian: return "Preferenze globali dell’app separate dalla dashboard operativa."
        case .english: return "Global app preferences separated from the operational dashboard."
        case .german: return "Globale App-Einstellungen getrennt vom operativen Dashboard."
        case .french: return "Préférences globales de l’app séparées du tableau de bord opérationnel."
        case .chinese: return "全局应用偏好设置与主操作面板分离。"
        }
    }

    private var aboutBody: String {
        switch service.language {
        case .italian: return "TargetBridge e una utility open source per riutilizzare pannelli iMac Intel come display esterni per Mac moderni. Le preferenze generali vivono qui; le impostazioni operative di ogni sessione restano nella finestra principale."
        case .english: return "TargetBridge is an open-source utility for reusing Intel iMac panels as external displays for modern Macs. Global preferences live here; per-session operational settings stay in the main window."
        case .german: return "TargetBridge ist ein Open-Source-Werkzeug, um Intel-iMac-Panels als externe Displays für moderne Macs weiterzuverwenden. Globale Einstellungen sind hier; operative Sitzungsoptionen sind im Hauptfenster."
        case .french: return "TargetBridge est un utilitaire open source qui permet de réutiliser les dalles d’iMac Intel comme écrans externes pour les Mac modernes. Les préférences globales se trouvent ici ; les réglages de chaque session restent dans la fenêtre principale."
        case .chinese: return "TargetBridge 是一个开源工具，可将 Intel iMac 面板重新用作现代 Mac 的外接显示器。全局偏好设置在这里管理；每个会话的操作设置保留在主窗口中。"
        }
    }

    private var githubTitle: String {
        "GitHub"
    }

    private var releaseTitle: String {
        switch service.language {
        case .italian: return "Ultima release"
        case .english: return "Latest release"
        case .german: return "Letztes Release"
        case .french: return "Dernière version"
        case .chinese: return "最新发布"
        }
    }

    private var versionTitle: String {
        switch service.language {
        case .italian: return "Versione"
        case .english: return "Version"
        case .german: return "Version"
        case .french: return "Version"
        case .chinese: return "版本"
        }
    }

    private var addonsSubtitle: String {
        switch service.language {
        case .italian: return "Gli add-on vengono letti da manifest JSON sicuri. Quelli ufficiali sono inclusi nell'app, mentre quelli personalizzati si importano nella cartella Addons utente."
        case .english: return "Add-ons are loaded from safe JSON manifests. Official ones ship with the app, while custom ones can be imported into the user Addons folder."
        case .german: return "Add-ons werden aus sicheren JSON-Manifests geladen. Offizielle Add-ons sind in der App enthalten, benutzerdefinierte können in den Benutzer-Addons-Ordner importiert werden."
        case .french: return "Les extensions sont chargées depuis des manifestes JSON sûrs. Les extensions officielles sont incluses dans l’app ; les extensions personnalisées peuvent être importées dans le dossier utilisateur Addons."
        case .chinese: return "附加组件通过安全的 JSON 清单加载。官方附加组件随应用提供，自定义附加组件可导入到用户 Addons 文件夹。"
        }
    }

    private var importAddonTitle: String {
        switch service.language {
        case .italian: return "Importa Add-on..."
        case .english: return "Import Add-on..."
        case .german: return "Add-on importieren..."
        case .french: return "Importer une extension..."
        case .chinese: return "导入附加组件..."
        }
    }

    private var refreshAddonsTitle: String {
        switch service.language {
        case .italian: return "Ricarica"
        case .english: return "Reload"
        case .german: return "Neu laden"
        case .french: return "Recharger"
        case .chinese: return "重新加载"
        }
    }

    private var openAddonsFolderTitle: String {
        switch service.language {
        case .italian: return "Apri cartella Addons"
        case .english: return "Open Addons Folder"
        case .german: return "Add-ons-Ordner öffnen"
        case .french: return "Ouvrir le dossier Addons"
        case .chinese: return "打开 Addons 文件夹"
        }
    }

    private var noAddonsTitle: String {
        switch service.language {
        case .italian: return "Nessun add-on trovato. Importa un manifest JSON oppure usa quelli ufficiali inclusi."
        case .english: return "No add-ons found. Import a JSON manifest or use the bundled official ones."
        case .german: return "Keine Add-ons gefunden. Importiere ein JSON-Manifest oder nutze die eingebauten offiziellen Add-ons."
        case .french: return "Aucune extension trouvée. Importez un manifeste JSON ou utilisez les extensions officielles incluses."
        case .chinese: return "未找到附加组件。请导入 JSON 清单或使用内置官方附加组件。"
        }
    }

    private var addonsConnectedHint: String {
        switch service.language {
        case .italian: return "Ferma tutte le sessioni prima di attivare o disattivare un add-on."
        case .english: return "Stop all sessions before enabling or disabling an add-on."
        case .german: return "Beende alle Sitzungen, bevor du ein Add-on aktivierst oder deaktivierst."
        case .french: return "Arrêtez toutes les sessions avant d’activer ou de désactiver une extension."
        case .chinese: return "请先停止所有会话，再启用或禁用附加组件。"
        }
    }

    private var experimentalTitle: String {
        switch service.language {
        case .italian: return "Sperimentale"
        case .english: return "Experimental"
        case .german: return "Experimentell"
        case .french: return "Expérimentale"
        case .chinese: return "实验性"
        }
    }

    private var incompatibleTitle: String {
        switch service.language {
        case .italian: return "Incompatibile"
        case .english: return "Incompatible"
        case .german: return "Inkompatibel"
        case .french: return "Incompatible"
        case .chinese: return "不兼容"
        }
    }

    private var capabilitiesTitle: String {
        switch service.language {
        case .italian: return "Capability"
        case .english: return "Capabilities"
        case .german: return "Fähigkeiten"
        case .french: return "Fonctionnalités"
        case .chinese: return "能力"
        }
    }

    private var addonImportErrorTitle: String {
        switch service.language {
        case .italian: return "Importazione add-on fallita"
        case .english: return "Add-on import failed"
        case .german: return "Add-on-Import fehlgeschlagen"
        case .french: return "Échec de l’importation de l’extension"
        case .chinese: return "导入附加组件失败"
        }
    }

    private var importPanelMessage: String {
        switch service.language {
        case .italian: return "Seleziona un file manifest JSON per l'add-on."
        case .english: return "Choose a JSON manifest file for the add-on."
        case .german: return "Wähle eine JSON-Manifestdatei für das Add-on."
        case .french: return "Choisissez un fichier manifeste JSON pour l’extension."
        case .chinese: return "请选择附加组件的 JSON 清单文件。"
        }
    }

    private func originTitle(for origin: TBAddonOrigin) -> String {
        switch (origin, service.language) {
        case (.bundled, .italian): return "Ufficiale"
        case (.bundled, .english): return "Bundled"
        case (.bundled, .german): return "Mitgeliefert"
        case (.bundled, .french): return "Incluse"
        case (.bundled, .chinese): return "内置"
        case (.user, .italian): return "Utente"
        case (.user, .english): return "User"
        case (.user, .german): return "Benutzer"
        case (.user, .french): return "Utilisateur"
        case (.user, .chinese): return "用户"
        }
    }

    private func capabilityTitle(for capability: TBAddonCapability) -> String {
        switch (capability, service.language) {
        case (.networkLink, .chinese): return "网络链路"
        case (.networkLink, _): return "Network Link"
        case (.audioRelay, .french): return "Relais audio"
        case (.audioRelay, .chinese): return "音频转发"
        case (.audioRelay, _): return "Audio Relay"
        case (.inputDockstation, .french): return "Station d’accueil des entrées"
        case (.inputDockstation, .chinese): return "输入扩展坞"
        case (.inputDockstation, _): return "Input Dockstation"
        }
    }
}
