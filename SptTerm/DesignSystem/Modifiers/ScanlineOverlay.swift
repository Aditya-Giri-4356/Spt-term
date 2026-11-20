import SwiftUI

/// Persistent 1px raster sweep every 3pt, over the whole app.
/// Controlled by the `CRT Scanline Raster Overlay` flag in Settings.
struct ScanlineOverlay: View {
    @EnvironmentObject private var theme: TerminalTheme

    var body: some View {
        if theme.scanlinesEnabled {
            let lineColor = TermColorMath.withAlpha(theme.palette.accent, theme.palette.isLight ? 0.05 : 0.09)
            Canvas { context, size in
                var path = Path()
                var y: CGFloat = 0
                while y < size.height {
                    path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    y += 3
                }
                context.fill(path, with: .color(lineColor))
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

struct ScanlineOverlay_Previews: PreviewProvider {
    static var previews: some View {
        TerminalPreview {
            ZStack {
                Color.black
                Text("CRT :: SCANLINES")
                    .termType(TermType.labelLG, color: .green)
            }
        }
    }
}
