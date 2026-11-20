import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Creates a color from a `#RRGGBB` / `RRGGBB` / `#RGB` string.
    init(termHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt64(text, radix: 16) else {
            self = .black
            return
        }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// Small color algebra used by the derived theme tokens.
enum TermColorMath {
    static func components(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }
        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return (white, white, white, alpha)
        }
        return (0, 0, 0, 1)
        #elseif canImport(AppKit)
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return (nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent, nsColor.alphaComponent)
        #else
        return (0, 0, 0, 1)
        #endif
    }

    static func mix(_ start: Color, _ end: Color, _ amount: Double) -> Color {
        let t = CGFloat(min(max(amount, 0), 1))
        let a = components(start)
        let b = components(end)
        return Color(
            .sRGB,
            red: Double(a.red + (b.red - a.red) * t),
            green: Double(a.green + (b.green - a.green) * t),
            blue: Double(a.blue + (b.blue - a.blue) * t),
            opacity: Double(a.alpha + (b.alpha - a.alpha) * t)
        )
    }

    static func withAlpha(_ color: Color, _ alpha: Double) -> Color {
        let parts = components(color)
        return Color(
            .sRGB,
            red: Double(parts.red),
            green: Double(parts.green),
            blue: Double(parts.blue),
            opacity: min(max(alpha, 0), 1)
        )
    }

    /// Relative luminance (WCAG), used to decide light vs dark derivations.
    static func luminance(_ color: Color) -> Double {
        let parts = components(color)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(parts.red) + 0.7152 * linear(parts.green) + 0.0722 * linear(parts.blue)
    }
}
