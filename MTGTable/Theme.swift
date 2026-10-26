import SwiftUI

/// Colors and shapes shared by everything on a player's half of the table.
struct ZoneStyle {
    /// True when the panel is a light color (white identity), so text must be dark.
    let dark: Bool

    var fg: Color { dark ? Color.black.opacity(0.88) : .white }
    var inverse: Color { dark ? .white : Color.black.opacity(0.88) }
    var chip: Color { dark ? Color.black.opacity(0.09) : Color.white.opacity(0.13) }
    var chipStrong: Color { dark ? Color.black.opacity(0.18) : Color.white.opacity(0.24) }
    var stroke: Color { dark ? Color.black.opacity(0.14) : Color.white.opacity(0.20) }
    var soft: Color { fg.opacity(0.72) }
}

enum Palette {
    static let gold = Color(red: 0.93, green: 0.74, blue: 0.27)
    static let good = Color(red: 0.33, green: 0.80, blue: 0.48)
    static let warn = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let danger = Color(red: 0.95, green: 0.33, blue: 0.30)
    static let panel = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let bar = Color(red: 0.06, green: 0.06, blue: 0.08)
}

/// A rounded text button used for most actions.
struct Pill: View {
    let text: String
    var icon: String? = nil
    let style: ZoneStyle
    var prominent = false
    var height: CGFloat = 50
    var fontSize: CGFloat = 17
    var iconOnly = false

    var body: some View {
        HStack(spacing: 7) {
            if let icon { Image(systemName: icon).font(.system(size: fontSize - 1, weight: .semibold)) }
            if !iconOnly { Text(text).font(.system(size: fontSize, weight: .semibold, design: .rounded)).lineLimit(1) }
        }
        .padding(.horizontal, iconOnly ? 16 : 18)
        .frame(height: height)
        .background(Capsule().fill(prominent ? style.fg : style.chip))
        .overlay(Capsule().strokeBorder(style.stroke, lineWidth: prominent ? 0 : 1))
        .foregroundStyle(prominent ? style.inverse : style.fg)
        .fixedSize()
    }
}

/// A round button with a symbol or short text.
struct RoundKey: View {
    var text: String? = nil
    var icon: String? = nil
    let size: CGFloat
    let style: ZoneStyle
    var fontSize: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(style.chip)
            Circle().strokeBorder(style.stroke, lineWidth: 1)
            if let icon { Image(systemName: icon).font(.system(size: fontSize * 0.8, weight: .bold)) }
            if let text { Text(text).font(.system(size: fontSize, weight: .bold, design: .rounded)) }
        }
        .frame(width: size, height: size)
        .foregroundStyle(style.fg)
        .contentShape(Circle())
    }
}

/// A small read-only badge, such as a counter value.
struct InfoPill: View {
    let icon: String?
    let text: String
    let style: ZoneStyle
    var warn = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            Text(text).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(warn ? Palette.danger : style.chipStrong))
        .foregroundStyle(warn ? Color.white : style.fg)
        .fixedSize()
    }
}
