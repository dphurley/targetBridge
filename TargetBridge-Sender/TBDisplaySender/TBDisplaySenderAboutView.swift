import SwiftUI

/// About: one panel, centred. The wordmark, one sentence about what this is,
/// two links, and the people who made it.
struct TBDisplaySenderAboutView: View {
    @ObservedObject var service: TBDisplaySenderService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text(TBDisplaySenderL10n.appName(service.language))
                    .font(TBFont.display(38))
                    .tracking(1)
                    .foregroundStyle(TBTheme.textPrimary)

                TBAccentUnderline(width: 56)
                    .padding(.top, 14)

                Text(aboutSubtitle)
                    .font(TBFont.body(12))
                    .foregroundStyle(TBTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                    .padding(.top, 24)

                HStack(spacing: 10) {
                    TBLabel("\(TBDisplaySenderL10n.versionLabel(service.language)) \(TBDisplaySenderBuildInfo.versionDisplay)")
                    TBRule(vertical: true, length: 10)
                    TBLabel("swellweb")
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 14) {
                    Text(projectDescription)
                        .font(TBFont.body(11))
                        .foregroundStyle(TBTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TBRule()

                    VStack(alignment: .leading, spacing: 8) {
                        TBLabel(creditsTitle)
                        Text(creditsBody)
                            .font(TBFont.body(11))
                            .foregroundStyle(TBTheme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: 460, alignment: .leading)
                .tbPanel(brackets: true)
                .padding(.top, 30)

                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/swellweb/targetBridge")!) {
                        Text(githubTitle)
                    }
                    .buttonStyle(TBSecondaryButtonStyle())

                    Link(destination: URL(string: "https://github.com/swellweb/targetBridge/releases/latest")!) {
                        Text(releaseTitle)
                    }
                    .buttonStyle(TBSecondaryButtonStyle())
                }
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)

            Button(service.language.str("common.close")) {
                dismiss()
            }
            .buttonStyle(TBTextActionStyle())
            .padding(20)
        }
        .tbSheetChrome(width: 560, height: 560)
    }

    private var aboutSubtitle: String {
        switch service.language {
        case .italian: return "Riporta l'idea di Target Display Mode nel mondo Apple Silicon con una pipeline diretta Mac-to-Mac."
        case .english: return "Brings the Target Display Mode idea back to Apple Silicon with a direct Mac-to-Mac display pipeline."
        case .german: return "Bringt die Idee von Target Display Mode mit einer direkten Mac-zu-Mac-Display-Pipeline zurück auf Apple Silicon."
        case .french: return "Redonne vie à l’idée du Target Display Mode sur Apple Silicon grâce à une chaîne d’affichage directe de Mac à Mac."
        case .chinese: return "通过直接的 Mac 到 Mac 显示管线，把 Target Display Mode 的理念带回 Apple Silicon 时代。"
        }
    }

    private var projectDescription: String {
        switch service.language {
        case .italian: return "TargetBridge cattura il desktop o il monitor virtuale sul Mac sender, codifica lo stream e lo presenta su un iMac receiver via Thunderbolt Bridge o Network Link sperimentale."
        case .english: return "TargetBridge captures the sender desktop or virtual display, encodes the stream, and presents it on an iMac receiver over Thunderbolt Bridge or experimental Network Link."
        case .german: return "TargetBridge erfasst den Sender-Desktop oder das virtuelle Display, kodiert den Stream und zeigt ihn auf einem iMac-Empfänger über Thunderbolt Bridge oder experimentellen Network Link an."
        case .french: return "TargetBridge capture le bureau ou l’écran virtuel du sender, encode le flux et l’affiche sur un iMac receiver via Thunderbolt Bridge ou Network Link expérimental."
        case .chinese: return "TargetBridge 会捕获发送端 Mac 的桌面或虚拟显示器，对流进行编码，并通过 Thunderbolt Bridge 或实验性的 Network Link 在 iMac 接收端上显示。"
        }
    }

    private var creditsTitle: String {
        switch service.language {
        case .italian: return "Crediti"
        case .english: return "Credits"
        case .german: return "Mitwirkende"
        case .french: return "Crédits"
        case .chinese: return "致谢"
        }
    }

    private var creditsBody: String {
        switch service.language {
        case .italian: return "Creato da swellweb con il supporto della community open source TargetBridge. Contributi chiave da tester e collaboratori come ThomasWaldmann, DrDavidL, potar712 e altri membri della community."
        case .english: return "Created by swellweb with support from the TargetBridge open-source community. Key contributions from testers and collaborators such as ThomasWaldmann, DrDavidL, potar712, and other community members."
        case .german: return "Erstellt von swellweb mit Unterstützung der TargetBridge-Open-Source-Community. Wichtige Beiträge von Testern und Mitwirkenden wie ThomasWaldmann, DrDavidL, potar712 und weiteren Community-Mitgliedern."
        case .french: return "Créé par swellweb avec le soutien de la communauté open source TargetBridge. Contributions essentielles de testeurs et collaborateurs comme ThomasWaldmann, DrDavidL, potar712 et d’autres membres de la communauté."
        case .chinese: return "由 swellweb 在 TargetBridge 开源社区的支持下创建。ThomasWaldmann、DrDavidL、potar712 以及其他社区成员提供了重要测试和协作贡献。"
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
}
