import SwiftUI
import UIKit

/// Brim's palette borrows Cap's blue so recordings feel at home next to the
/// web dashboard, on top of a neutral gray scale. The mark, name and layout
/// are Brim's own. Semantic variants keep text readable in both appearances.
enum Theme {
    enum Colors {
        /// Cap's primary blue (#005CB1) and its lighter dark-mode counterpart (#2EB4FF).
        static let brand        = adaptive(light: 0x005CB1, dark: 0x2EB4FF)
        static let brandSoft    = adaptive(light: 0xC5EAFF, dark: 0x0F3A5F)
        static let background   = adaptive(light: 0xF8F9FB, dark: 0x0B0F14)
        static let card         = adaptive(light: 0xFFFFFF, dark: 0x161B22)
        static let cardBorder   = adaptive(light: 0xE6E8EC, dark: 0x262D36)
        static let ink          = adaptive(light: 0x0D1B2A, dark: 0xF3F6F9)
        static let inkSoft      = adaptive(light: 0x5B6572, dark: 0xA9B4C0)
        static let inkFaint     = adaptive(light: 0x9AA3AE, dark: 0x6B7684)
        static let filler       = adaptive(light: 0xEFEFEF, dark: 0x1F262E)
        static let success      = adaptive(light: 0x1B7F4B, dark: 0x5CE7A4)
        static let warning      = adaptive(light: 0x946500, dark: 0xFFD166)
        static let danger       = adaptive(light: 0xC2362F, dark: 0xFF7B73)

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    static let cornerRadius: CGFloat = 12
    static let thumbnailRadius: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0,
            alpha: 1
        )
    }
}

// MARK: - Shared formatting

enum Format {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "Just now", "12 min ago", "3 hours ago", "Yesterday", "4 days ago",
    /// then a calendar date ("Sep 13" this year, "Sep 13, 2025" otherwise).
    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 {
            let h = Int(seconds / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400)) days ago" }
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        // Two explicit styles: `.year(.omitted)` only exists on iOS 18+.
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func absolute(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n.formatted()) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}

// MARK: - Small reusable views

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.Colors.cardBorder, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct BrandButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color.white : Theme.Colors.brand)
            .background(prominent ? Theme.Colors.brand : Theme.Colors.brandSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct Pill: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = Theme.Colors.inkSoft
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.Colors.filler, in: Capsule())
    }
}
