import SwiftUI

/// `[--all] [--playlists] [--artists]` filter chips.
struct FlagBar: View {
    @EnvironmentObject private var theme: TerminalTheme

    let flags: [String]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TermSpace.xs) {
                ForEach(Array(flags.enumerated()), id: \.offset) { index, flag in
                    flagButton(index: index, flag: flag)
                }
            }
            .padding(.trailing, TermSpace.margin)
        }
    }

    private func flagButton(index: Int, flag: String) -> some View {
        let isSelected = index == selection
        return Button {
            guard selection != index else { return }
            selection = index
            TermHaptic.tap()
        } label: {
            Text(flag)
                .termType(TermType.labelSM, color: isSelected ? theme.palette.onAccent : theme.palette.accent)
                .lineLimit(1)
                .padding(.horizontal, TermSpace.sm)
                .frame(minHeight: TermSpace.hit)
                .background(isSelected ? theme.palette.accent : theme.palette.background)
                .overlay(
                    Rectangle()
                        .strokeBorder(isSelected ? theme.palette.accent : theme.palette.accentDeep, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: TermRadius.button))
        }
        .buttonStyle(TermPressStyle())
        .accessibilityLabel(Text(flag))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct FlagBar_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            StatefulPreview()
        }
    }

    private struct StatefulPreview: View {
        @State private var selection = 0

        var body: some View {
            FlagBar(
                flags: ["[--all]", "[--playlists]", "[--artists]", "[--albums]", "[--downloaded]", "[--sort:recent]"],
                selection: $selection
            )
        }
    }
}
