import SwiftUI

/// `┌── [DIRECTORY TREE]` label with optional right-aligned telemetry.
struct SectionHeader: View {
    @EnvironmentObject private var theme: TerminalTheme

    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: TermSpace.xs) {
            Text("┌── [\(title.uppercased())]")
                .termType(TermType.labelLG, color: theme.palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let trailing {
                Spacer(minLength: TermSpace.xs)
                Text(trailing)
                    .termType(TermType.labelSM, color: theme.palette.textMuted)
                    .lineLimit(1)
            } else {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            VStack(alignment: .leading, spacing: TermSpace.md) {
                SectionHeader(title: "Mounted Playlist Directories", trailing: "RO:TRUE")
                SectionHeader(title: "Queue Buffer")
                SectionHeader(title: "Colorway Themes Matrix", trailing: "SELECT [1-36]")
            }
        }
    }
}
