import AppKit
import SwiftUI

/// Per-session editor for receiver-master shortcut bindings.
struct TBInputBindingsView: View {
    @ObservedObject var session: TBDisplaySenderSession
    let language: TBDisplaySenderLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TBLabel(
                    TBDisplaySenderL10n.text("sender.input_bindings.title", language),
                    tint: TBTheme.textSecondary
                )
                Spacer()
                Button(TBDisplaySenderL10n.text("sender.input_bindings.add", language)) {
                    session.inputBindings.append(
                        TBInputBinding(
                            trigger: TBInputShortcut(keyCode: 123, modifiers: TBInputShortcut.control | TBInputShortcut.option),
                            action: TBInputShortcut(keyCode: 123, modifiers: TBInputShortcut.control)
                        )
                    )
                }
                .buttonStyle(TBTextActionStyle(accented: true))
            }

            if session.inputBindings.isEmpty {
                Text(TBDisplaySenderL10n.text("sender.input_bindings.empty", language))
                    .font(TBFont.body(11))
                    .foregroundStyle(TBTheme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($session.inputBindings) { $binding in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $binding.enabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        TBShortcutRecorderButton(shortcut: $binding.trigger, language: language)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(TBTheme.textDim)

                        TBShortcutRecorderButton(shortcut: $binding.action, language: language)

                        Spacer()

                        Button {
                            session.inputBindings.removeAll { $0.id == binding.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(TBTextActionStyle(size: 9))
                    }
                }
            }

            Text(TBDisplaySenderL10n.text("sender.input_bindings.details", language))
                .font(TBFont.body(11))
                .foregroundStyle(TBTheme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A button that records a single key combo when clicked (press the shortcut).
struct TBShortcutRecorderButton: View {
    @Binding var shortcut: TBInputShortcut
    let language: TBDisplaySenderLanguage
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            toggleRecording()
        } label: {
            Text(recording ? TBDisplaySenderL10n.text("sender.input_bindings.record", language) : shortcut.displayString)
                .font(TBFont.mono(11))
                .frame(minWidth: 84)
        }
        .buttonStyle(TBRecorderButtonStyle(recording: recording))
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore standalone modifier presses; require a real key.
            if TBInputBindingEngine.isModifierKeyCode(event.keyCode) {
                return nil
            }
            shortcut = TBInputShortcut(
                keyCode: event.keyCode,
                modifiers: TBInputShortcut.modifiers(from: event.modifierFlags)
            )
            stopRecording()
            return nil // swallow so the captured key doesn't act
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = false
    }
}

/// Shortcut field: reads as an input, turns coral while it is listening.
private struct TBRecorderButtonStyle: ButtonStyle {
    let recording: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(recording ? TBTheme.accent : TBTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(recording ? TBTheme.accent.opacity(0.08) : Color.white.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        recording ? TBTheme.accent.opacity(0.35) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
    }
}
