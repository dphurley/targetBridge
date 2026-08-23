import AppKit
import SwiftUI

// MARK: - Design system
//
// This file is the sender's design system: colour, type, spacing, and the
// reusable chrome (panels, buttons, status marks) every sender view is built
// from. It deliberately lives in the existing "surface views" file rather than
// a new TBDesignSystem.swift because the Xcode project is not a synchronized
// group — adding a source file means editing project.pbxproj, which the build
// rewrites and which other concurrent branches also touch.
//
// The language: near-black translucent panels over a real backdrop blur, a
// coral accent used sparingly (corner brackets, a 10%-fill primary button), a
// three-step text hierarchy, hairline 6% borders, SF Mono for data and SF Pro
// for chrome, tiny wide-tracked uppercase labels, and a barely-there grid.

enum TBTheme {
    /// #FF6B6B — used sparingly: one primary action, corner brackets, one dot.
    static let accent = Color(red: 1.0, green: 0.420, blue: 0.420)
    /// #4fd1c5 — the "good, settled" colour. Streaming, passed checks.
    static let teal = Color(red: 0.310, green: 0.820, blue: 0.773)
    static let warning = Color(red: 0.98, green: 0.78, blue: 0.35)

    /// #060606 — the ink every panel is mixed from.
    static let ink = Color(red: 0.024, green: 0.024, blue: 0.024)
    static let panel = ink.opacity(0.72)
    static let surface = Color(red: 0.063, green: 0.063, blue: 0.063).opacity(0.5)

    /// #e8e8e8 → rgba(160,160,160,.7) → rgba(100,100,100,.5)
    static let textPrimary = Color(white: 0.910)
    static let textSecondary = Color(white: 0.627).opacity(0.7)
    static let textDim = Color(white: 0.392).opacity(0.5)

    static let border = Color.white.opacity(0.06)
    /// Hover / emphasis border.
    static let borderStrong = Color.white.opacity(0.14)
}

enum TBFont {
    /// Tiny uppercase chrome label. Tracking is always 0.2em of the size.
    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium)
    }

    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func body(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// The one big thing on the screen.
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .ultraLight)
    }
}

// MARK: - Text

/// Tiny uppercase, wide-tracked label. The only kind of heading this app has.
struct TBLabel: View {
    let text: String
    var size: CGFloat = 10
    var tint: Color = TBTheme.textDim

    init(_ text: String, size: CGFloat = 10, tint: Color = TBTheme.textDim) {
        self.text = text
        self.size = size
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(TBFont.label(size))
            .tracking(size * 0.2)
            .foregroundStyle(tint)
    }
}

/// Hairline separator. `length` nil means "fill the available space".
struct TBRule: View {
    var vertical = false
    var length: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(TBTheme.border)
            .frame(
                width: vertical ? 1 : length,
                height: vertical ? length : 1
            )
    }
}

// MARK: - Background

/// Real behind-window blur. `.ultraThinMaterial` alone would only blur the
/// app's own background, which is already near-black.
struct TBVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// 40px grid at 1.5% — you should have to look for it.
struct TBGrid: View {
    var spacing: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.015)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The window ground: blur, near-black ink, grid.
struct TBBackground: View {
    var body: some View {
        ZStack {
            TBVisualEffectBackground()
            TBTheme.ink.opacity(0.88)
            TBGrid()
        }
        .ignoresSafeArea()
    }
}

/// Dissolves the title bar so the panel runs to the top of the window and the
/// traffic lights float over it. Zero-size, drawn behind everything.
struct TBWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Panels

/// Corner brackets — the accent's main job. 12pt L-marks at 35%.
struct TBCornerBrackets: View {
    var length: CGFloat = 12
    var lineWidth: CGFloat = 1.5
    var tint: Color = TBTheme.accent
    var opacity: Double = 0.35

    var body: some View {
        GeometryReader { geometry in
            let inset = lineWidth / 2
            let maxX = geometry.size.width - inset
            let maxY = geometry.size.height - inset
            Path { path in
                path.move(to: CGPoint(x: inset, y: inset + length))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset + length, y: inset))

                path.move(to: CGPoint(x: maxX - length, y: maxY))
                path.addLine(to: CGPoint(x: maxX, y: maxY))
                path.addLine(to: CGPoint(x: maxX, y: maxY - length))
            }
            .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}

struct TBPanelModifier: ViewModifier {
    var corner: CGFloat = 14
    var brackets = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(TBTheme.panel)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(TBTheme.border, lineWidth: 1)
            }
            .overlay {
                if brackets {
                    TBCornerBrackets()
                }
            }
    }
}

/// Flatter inner surface for grouped rows inside a panel.
struct TBSurfaceModifier: ViewModifier {
    var corner: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(TBTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(TBTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func tbPanel(corner: CGFloat = 14, brackets: Bool = false) -> some View {
        modifier(TBPanelModifier(corner: corner, brackets: brackets))
    }

    func tbSurface(corner: CGFloat = 10) -> some View {
        modifier(TBSurfaceModifier(corner: corner))
    }

    /// Sheets paint their own dark ground, so they must also force the dark
    /// colour scheme — otherwise semantic colours resolve dark-on-dark when the
    /// system is in Light mode.
    func tbSheetChrome(width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height)
            .background(TBBackground())
            .preferredColorScheme(.dark)
            // Pulls the system controls (focus rings, menu highlights) onto the
            // accent instead of the stock blue.
            .tint(TBTheme.accent)
    }
}

// MARK: - Buttons

/// Filled coral action. There is at most one of these on screen at a time.
struct TBPrimaryButtonStyle: ButtonStyle {
    var wide = true

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, wide: wide)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let wide: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .textCase(.uppercase)
                .font(TBFont.label(11))
                .tracking(11 * 0.18)
                .foregroundStyle(isEnabled ? TBTheme.accent : TBTheme.textDim)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TBTheme.accent.opacity(fill))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(TBTheme.accent.opacity(stroke), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.18), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var fill: Double {
            guard isEnabled else { return 0.03 }
            if configuration.isPressed { return 0.20 }
            return hovering ? 0.16 : 0.10
        }

        private var stroke: Double {
            guard isEnabled else { return 0.06 }
            return hovering ? 0.30 : 0.18
        }
    }
}

/// Quiet bordered action.
struct TBSecondaryButtonStyle: ButtonStyle {
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, wide: wide)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let wide: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .textCase(.uppercase)
                .font(TBFont.label(11))
                .tracking(11 * 0.14)
                .foregroundStyle(tint)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isEnabled ? (hovering ? 0.07 : 0.03) : 0.02))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.18), value: hovering)
        }

        private var tint: Color {
            guard isEnabled else { return TBTheme.textDim }
            return hovering ? TBTheme.textPrimary : TBTheme.textSecondary
        }

        private var border: Color {
            guard isEnabled else { return Color.white.opacity(0.05) }
            return hovering ? TBTheme.borderStrong : Color.white.opacity(0.07)
        }
    }
}

/// Text-only action: the header, the footer, and the row of verbs under a card.
struct TBTextActionStyle: ButtonStyle {
    var size: CGFloat = 10
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size, accented: accented)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let size: CGFloat
        let accented: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .textCase(.uppercase)
                .font(TBFont.label(size))
                .tracking(size * 0.16)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.18), value: hovering)
        }

        private var tint: Color {
            guard isEnabled else { return TBTheme.textDim.opacity(0.5) }
            if accented { return hovering ? TBTheme.accent : TBTheme.accent.opacity(0.7) }
            return hovering ? TBTheme.textSecondary : TBTheme.textDim
        }
    }
}

// MARK: - Status marks

/// Status dot. `pulsing` for transitional states, `ready` for a settled one.
struct TBStatusDot: View {
    var tint: Color
    var pulsing = false
    var size: CGFloat = 6

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.6), radius: animating ? 5 : 2)
            .opacity(animating ? 0.45 : 1.0)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
    }
}

/// The empty state: a coral hairline that breathes. Not a spinner, not a form.
struct TBBreathingLine: View {
    @State private var wide = false

    var body: some View {
        Rectangle()
            .fill(TBTheme.accent)
            .frame(width: wide ? 64 : 24, height: 1)
            .opacity(wide ? 0.5 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    wide = true
                }
            }
    }
}

/// Accent underline that draws itself in under a title.
struct TBAccentUnderline: View {
    var width: CGFloat = 40
    @State private var shown = false

    var body: some View {
        Rectangle()
            .fill(TBTheme.accent)
            .frame(width: shown ? width : 0, height: 1)
            .opacity(shown ? 0.3 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7)) { shown = true }
            }
    }
}

struct TBSpinner: View {
    var size: CGFloat = 18
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(TBTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - Rows

/// Mono key/value line — the shape all diagnostic data takes.
struct TBDataRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 132
    var tint: Color = TBTheme.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TBLabel(label)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(TBFont.mono(11))
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Label + control + optional explanation. The only settings row shape.
struct TBSettingRow<Content: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                TBLabel(label, tint: TBTheme.textSecondary)
                Spacer(minLength: 12)
                content
                    .frame(maxWidth: 320, alignment: .trailing)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .tbSurface()
    }
}

/// Small tag: transport, "auto", capability, add-on origin.
struct TBTag: View {
    let text: String
    var tint: Color = TBTheme.textDim

    init(_ text: String, tint: Color = TBTheme.textDim) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(TBFont.label(9))
            .tracking(9 * 0.2)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
    }
}

/// Slider row: glyph, track, mono readout. Used for brightness and volume.
struct TBSliderRow: View {
    let label: String
    let minSymbol: String
    let maxSymbol: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            TBLabel(label)
                .frame(width: 78, alignment: .leading)
            Image(systemName: minSymbol)
                .font(.system(size: 10))
                .foregroundStyle(TBTheme.textDim)
            Slider(value: $value, in: 0.0...1.0)
                .controlSize(.small)
                .tint(TBTheme.accent)
            Image(systemName: maxSymbol)
                .font(.system(size: 12))
                .foregroundStyle(TBTheme.textDim)
            Text("\(Int((value * 100).rounded()))%")
                .font(TBFont.mono(11))
                .foregroundStyle(TBTheme.textSecondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// Toggle rendered as a text action so it can sit in a row of verbs.
struct TBInlineToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? TBTheme.accent : Color.white.opacity(0.14))
                    .frame(width: 5, height: 5)
                Text(title.uppercased())
            }
        }
        .buttonStyle(TBTextActionStyle(accented: isOn))
    }
}

// MARK: - Warnings

/// Permission / attention card. Warning colour, never the coral accent.
struct TBWarningPanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var statusText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TBTheme.warning)
                TBLabel(title, tint: TBTheme.warning)
            }

            Text(message)
                .font(TBFont.body(11))
                .foregroundStyle(TBTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(TBSecondaryButtonStyle())
                }
                if let statusText {
                    Text(statusText)
                        .font(TBFont.mono(10))
                        .foregroundStyle(TBTheme.textDim)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TBTheme.warning.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TBTheme.warning.opacity(0.20), lineWidth: 1)
        }
    }
}

// MARK: - Sheet chrome

/// Sheet header: title, optional subtitle, close action.
struct TBSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    let closeTitle: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(TBFont.display(22))
                    .foregroundStyle(TBTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(TBFont.body(11))
                        .foregroundStyle(TBTheme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Button(closeTitle, action: onClose)
                .buttonStyle(TBTextActionStyle())
        }
    }
}

struct TBRailItem<Tab: Hashable>: Identifiable {
    let tab: Tab
    let title: String

    var id: Tab { tab }
}

/// Vertical rail of tiny uppercase section names. Replaces the long scroll of
/// stacked cards: one section on screen at a time, the rest one click away.
struct TBSectionRail<Tab: Hashable>: View {
    let items: [TBRailItem<Tab>]
    @Binding var selection: Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                Button {
                    selection = item.tab
                } label: {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(selection == item.tab ? TBTheme.accent.opacity(0.6) : Color.clear)
                            .frame(width: 1, height: 12)
                        Text(item.title.uppercased())
                            .font(TBFont.label(10))
                            .tracking(2)
                            .foregroundStyle(selection == item.tab ? TBTheme.textPrimary : TBTheme.textDim)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
