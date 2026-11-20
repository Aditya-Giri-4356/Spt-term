import SwiftUI

struct TerminalTabBar: View {
    let selected: TabItem
    let onSelect: (TabItem) -> Void

    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TabItem.allCases) { item in
                let isSelected = selected == item
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 3) {
                        Text(item.asciiLogo)
                            .termType(
                                TermType.glyphMD,
                                color: isSelected ? theme.palette.onAccent : theme.palette.accent
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(item.badge)
                            .termType(
                                TermType.labelSM,
                                color: isSelected ? theme.palette.onAccent : theme.palette.textSecondary
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        isSelected
                            ? theme.palette.accent
                            : theme.palette.panelRaised
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TermRadius.button)
                            .strokeBorder(
                                isSelected ? theme.palette.accent : theme.palette.hairline,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TermRadius.button))
                }
                .buttonStyle(TermPressStyle())
                .accessibilityLabel(Text(item.title))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, TermSpace.sm)
        .padding(.top, TermSpace.xs)
        .padding(.bottom, TermSpace.xs)
        .background(theme.palette.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.palette.hairline).frame(height: 1)
        }
        .animation(TermMotion.snap, value: selected)
    }
}

struct TerminalTabBar_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            TerminalTabBarPreview()
        }
    }

    private struct TerminalTabBarPreview: View {
        @State private var selected = TabItem.player

        var body: some View {
            VStack {
                Spacer()
                TerminalTabBar(selected: selected) { item in
                    selected = item
                }
            }
        }
    }
}
