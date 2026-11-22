import SwiftUI

/// Placeholder views for tabs that are not yet implemented.
/// - Tag: [3:EXEC] and [4:THEME] tabs.
enum TemporaryPlaceholders {
    /// Placeholder for the Executive Controls tab ([3:EXEC]).
    static func execPlaceholder() -> some View {
        ExecPlaceholderView()
    }

    /// Placeholder for the Settings tab ([4:THEME]).
    static func themePlaceholder() -> some View {
        ThemePlaceholderView()
    }
}

struct ExecPlaceholderView: View {
    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.playerService) private var player
    @Environment(\.audioEffectsService) private var audioEffects

    @State private var inputCommand: String = ""
    @State private var consoleLines: [String] = [
        "spt.term in-process executor v1.0",
        "commands: play, pause, next, prev, repeat, shuffle, seek, open, theme, cmd, log"
    ]

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: TermSpace.md) {
                    TerminalHeader(subtitle: "Executor")

                    // Quick transport buttons
                    HStack(spacing: TermSpace.xs) {
                        BracketButton(title: "[PLAY]", glyph: "▶", variant: .primary) {
                            runCommand("play")
                        }
                        BracketButton(title: "[PAUSE]", glyph: "❚❚", variant: .ghost) {
                            runCommand("pause")
                        }
                        BracketButton(title: "[NEXT]", glyph: "⏭", variant: .ghost) {
                            runCommand("next")
                        }
                        BracketButton(title: "[PREV]", glyph: "⏮", variant: .ghost) {
                            runCommand("prev")
                        }
                    }

                    // Terminal Console Output & Stdin
                    ASCIIPanel(title: "TERMINAL CONSOLE", trailing: "[READY]") {
                        VStack(alignment: .leading, spacing: TermSpace.xs) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(consoleLines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .termType(TermType.telemetryTight, color: line.hasPrefix("$") ? theme.palette.cyan : (line.contains("not available") ? theme.palette.amber : theme.palette.accent))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(minHeight: 120, maxHeight: 180)
                            .padding(TermSpace.xs)
                            .background(theme.palette.panelRaised)
                            .overlay(Rectangle().strokeBorder(theme.palette.hairline, lineWidth: 1))

                            Rectangle()
                                .fill(theme.palette.hairline)
                                .frame(height: 1)
                                .padding(.vertical, 2)

                            HStack(spacing: TermSpace.xs) {
                                Text("spt.term:exec$")
                                    .termType(TermType.telemetryTight, color: theme.palette.cyan)
                                TextField("command", text: $inputCommand)
                                    .termType(TermType.telemetryTight, color: theme.palette.accent)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit {
                                        runCommand(inputCommand)
                                    }
                                Button(action: {
                                    runCommand(inputCommand)
                                }) {
                                    Text("[EXEC]")
                                        .termType(TermType.labelSM, color: theme.palette.onAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(theme.palette.accent)
                                        .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
                                }
                                .buttonStyle(TermPressStyle())
                            }
                        }
                    }

                    // Audio FX / DSP panel
                    ASCIIPanel(title: "AUDIO FX & DSP CONTROLS", trailing: "[DSP]") {
                        VStack(alignment: .leading, spacing: TermSpace.sm) {
                            Text("UI ONLY - does not process Spotify audio")
                                .termType(TermType.labelSM, color: theme.palette.amber)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("HARDWARE PRESETS:")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)

                            HStack(spacing: TermSpace.xs) {
                                ForEach(AudioPreset.builtIns.prefix(4), id: \.id) { preset in
                                    let isSelected = audioEffects.state.activePresetID == preset.id
                                    Button {
                                        audioEffects.applyPreset(preset)
                                        TermHaptic.tap()
                                    } label: {
                                        Text("[\(preset.name.uppercased())]")
                                            .termType(TermType.labelSM, color: isSelected ? theme.palette.onAccent : theme.palette.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(isSelected ? theme.palette.accent : theme.palette.background)
                                            .overlay(Rectangle().strokeBorder(theme.palette.accent, lineWidth: 1))
                                    }
                                    .buttonStyle(TermPressStyle())
                                }
                            }

                            Rectangle()
                                .fill(theme.palette.hairline)
                                .frame(height: 1)
                                .padding(.vertical, 2)

                            HStack {
                                BracketButton(title: "[ RESET DSP ]", glyph: "⟲", variant: .quiet) {
                                    audioEffects.resetBands()
                                    TermHaptic.tap()
                                }
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TermSpace.gutter)
                .padding(.top, TermSpace.sm)
                .padding(.bottom, 140)
            }
        }
        .accessibilityLabel("Executive controls and Audio FX")
    }

    private func runCommand(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        consoleLines.append("$ \(trimmed)")
        let context = STExecContext(player: player, theme: theme, audioEffects: audioEffects)
        let responses = STExecCommandRegistry.shared.execute(trimmed, context: context)
        consoleLines.append(contentsOf: responses)

        inputCommand = ""
        if consoleLines.count > 50 {
            consoleLines = Array(consoleLines.suffix(50))
        }
    }
}

struct ThemePlaceholderView: View {
    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.serviceContainer) private var serviceContainer

    @State private var userProfile: STUserProfileDTO?
    @State private var profileError: String?
    @State private var isLoadingProfile: Bool = false
    @State private var showConfirmation: Bool = false

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: TermSpace.md) {
                    TerminalHeader(subtitle: "Settings")

                    ASCIIPanel(title: "SPOTIFY ACCOUNT", trailing: sessionTrailing) {
                        VStack(alignment: .leading, spacing: TermSpace.sm) {
                            HStack {
                                Text("STATUS:")
                                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                                Text("SESSION: ACTIVE")
                                    .termType(TermType.labelSM, color: theme.palette.cyan)
                                Spacer()
                            }

                            if isLoadingProfile {
                                Text("QUERYING /me ...")
                                    .termType(TermType.telemetryTight, color: theme.palette.textMuted)
                            } else if let profile = userProfile {
                                if let name = profile.display_name, !name.isEmpty {
                                    HStack {
                                        Text("USER:")
                                            .termType(TermType.labelSM, color: theme.palette.textMuted)
                                        Text(name)
                                            .termType(TermType.bodySM, color: theme.palette.textPrimary)
                                    }
                                }
                                HStack {
                                    Text("PRODUCT:")
                                        .termType(TermType.labelSM, color: theme.palette.textMuted)
                                    Text((profile.product ?? "free").uppercased())
                                        .termType(TermType.labelSM, color: (profile.product == "premium") ? theme.palette.accent : theme.palette.amber)
                                }
                            } else if let error = profileError {
                                HStack(alignment: .top) {
                                    Text("ERR /me:")
                                        .termType(TermType.labelSM, color: theme.palette.amber)
                                    Text(error)
                                        .termType(TermType.telemetryTight, color: theme.palette.amber)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Rectangle()
                                .fill(theme.palette.hairline)
                                .frame(height: 1)
                                .padding(.vertical, TermSpace.xs)

                            BracketButton(
                                title: "[ SIGN OUT ]",
                                glyph: "⏻",
                                variant: .primary
                            ) {
                                showConfirmation = true
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ASCIIPanel(title: "THEME CONFIGURATION", trailing: "[\(theme.definition.listNumber)]") {
                        VStack(alignment: .leading, spacing: TermSpace.sm) {
                            HStack {
                                Text("ACTIVE THEME:")
                                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                                Text("[\(theme.definition.listNumber)] \(theme.definition.name.uppercased())")
                                    .termType(TermType.labelSM, color: theme.palette.accent)
                            }
                            Text(theme.definition.detail)
                                .termType(TermType.bodySM, color: theme.palette.textSecondary)

                            HStack(spacing: TermSpace.xs) {
                                Text("PALETTE:")
                                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                                Rectangle()
                                    .fill(theme.palette.accent)
                                    .frame(width: 20, height: 12)
                                Rectangle()
                                    .fill(theme.palette.background)
                                    .frame(width: 20, height: 12)
                                    .overlay(Rectangle().stroke(theme.palette.hairline, lineWidth: 1))
                                Rectangle()
                                    .fill(theme.palette.cyan)
                                    .frame(width: 12, height: 12)
                                Rectangle()
                                    .fill(theme.palette.violet)
                                    .frame(width: 12, height: 12)
                                Rectangle()
                                    .fill(theme.palette.amber)
                                    .frame(width: 12, height: 12)
                            }

                            Rectangle()
                                .fill(theme.palette.hairline)
                                .frame(height: 1)
                                .padding(.vertical, 2)

                            Text("CRT EFFECTS:")
                                .termType(TermType.labelSM, color: theme.palette.textMuted)

                            HStack(spacing: TermSpace.sm) {
                                BracketButton(
                                    title: theme.scanlinesEnabled ? "[*SCANLINES ON]" : "[ SCANLINES OFF]",
                                    glyph: "≡",
                                    variant: theme.scanlinesEnabled ? .primary : .ghost
                                ) {
                                    theme.setScanlines(!theme.scanlinesEnabled)
                                }
                                BracketButton(
                                    title: theme.bloomEnabled ? "[*CRT BLOOM ON]" : "[ CRT BLOOM OFF]",
                                    glyph: "☼",
                                    variant: theme.bloomEnabled ? .primary : .ghost
                                ) {
                                    theme.setBloom(!theme.bloomEnabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ASCIIPanel(title: "THEME MATRIX", trailing: "[\(theme.catalog.count) THEMES]") {
                        VStack(spacing: 4) {
                            ForEach(theme.catalog) { item in
                                let isSelected = (theme.themeID == item.id && !theme.isCustomAccent)
                                Button {
                                    theme.select(item.id)
                                    TermHaptic.tap()
                                } label: {
                                    HStack(spacing: TermSpace.xs) {
                                        Text(isSelected ? "[*\(item.listNumber)]" : "[ \(item.listNumber)]")
                                            .termType(TermType.labelSM, color: isSelected ? theme.palette.onAccent : theme.palette.textMuted)
                                        Text(item.name.uppercased())
                                            .termType(TermType.labelSM, color: isSelected ? theme.palette.onAccent : theme.palette.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Rectangle()
                                                .fill(item.accent)
                                                .frame(width: 14, height: 10)
                                            Rectangle()
                                                .fill(item.background)
                                                .frame(width: 14, height: 10)
                                                .overlay(Rectangle().stroke(isSelected ? theme.palette.onAccent.opacity(0.6) : theme.palette.hairline, lineWidth: 0.8))
                                        }
                                    }
                                    .padding(.horizontal, TermSpace.xs)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? theme.palette.accent : Color.clear)
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(isSelected ? theme.palette.accent : theme.palette.hairline.opacity(0.6), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(TermPressStyle())
                                .accessibilityLabel("Select theme \(item.name)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TermSpace.gutter)
                .padding(.top, TermSpace.sm)
                .padding(.bottom, 140)
            }
        }
        .confirmationDialog(
            "SIGN OUT OF SPOTIFY?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("SIGN OUT", role: .destructive) {
                serviceContainer?.auth.signOut()
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("This will clear Keychain credentials, in-memory tokens, and return to the login gate.")
        }
        .task {
            await fetchProfile()
        }
        .accessibilityLabel("Settings and Theme")
    }

    private var sessionTrailing: String {
        if let product = userProfile?.product {
            return "[\(product.uppercased())]"
        }
        return "[ACTIVE]"
    }

    private func fetchProfile() async {
        guard let api = serviceContainer?.api else { return }
        isLoadingProfile = true
        profileError = nil
        do {
            userProfile = try await api.currentUserProfile()
        } catch {
            profileError = error.localizedDescription
        }
        isLoadingProfile = false
    }
}

struct TemporaryPlaceholders_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            VStack(spacing: TermSpace.lg) {
                ExecPlaceholderView()
                ThemePlaceholderView()
            }
        }
    }
}
