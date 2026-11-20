import SwiftUI

struct ArtistDetailPlaceholder: View {
    let artistID: String

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ASCIIPanel(title: "DETAIL :: PLACEHOLDER", trailing: "artist detail") {
                Text("ARTIST DETAIL — \(artistID)")
                    .termType(TermType.bodySM, color: theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(TermSpace.md)
        }
    }
}
