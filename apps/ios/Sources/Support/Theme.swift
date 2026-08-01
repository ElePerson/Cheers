import SwiftUI

// MARK: - Design tokens
//
// Layout and brand accents stay aligned with the web client. Neutral surfaces,
// labels and separators use UIKit semantic colors so iOS owns appearance,
// contrast and accessibility adaptation.

extension Color {
    /// Hex initializer, e.g. Color(hex: 0x09090B).
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Dynamic color that follows the system light/dark appearance.
    static func cheers(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }
}

enum Theme {
    // MARK: Spacing (spacing-first grouping; HIG hit floor)
    /// 4pt — tight intra-row gaps (name / subtitle stacks).
    static let space1: CGFloat = 4
    /// 8pt — default control padding / compact section gaps.
    static let space2: CGFloat = 8
    /// 12pt — row gutters / field padding.
    static let space3: CGFloat = 12
    /// 16pt — screen horizontal inset / section padding.
    static let space4: CGFloat = 16
    /// 24pt — card / form block padding.
    static let space5: CGFloat = 24
    /// HIG minimum interactive hit target (pt).
    static let hitMin: CGFloat = 44
    /// Comfortable list-row vertical inset (beyond default List insets).
    static let rowVertical: CGFloat = 10
    /// Avatar size for primary list rows (friends / conversations).
    static let avatarList: CGFloat = 40

    // System semantic surfaces and labels inherit iOS contrast, accessibility,
    // increased-contrast and light/dark appearance behavior automatically.
    static let bgApp = Color(uiColor: .systemBackground)
    static let bgSurface = Color(uiColor: .secondarySystemBackground)
    static let bgRaised = Color(uiColor: .tertiarySystemBackground)
    static let bgSelected = Color(uiColor: .systemGray5)

    // Borders
    static let border = Color(uiColor: .separator)
    static let borderStrong = Color(uiColor: .opaqueSeparator)

    // Text
    static let textPrimary = Color.primary
    static let textBody = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color(uiColor: .tertiaryLabel)
    static let textFaint = Color(uiColor: .quaternaryLabel)

    // Accent (indigo — same in both themes, matching the web brand)
    static let accent = Color(hex: 0x4F46E5)                                   // indigo-600
    static let accentHover = Color(hex: 0x6366F1)                              // indigo-500
    static let link = Color.cheers(light: 0x4F46E5, dark: 0x818CF8)           // indigo-600 / indigo-400
    static let botBadgeBg = Color.cheers(light: 0xE0E7FF, dark: 0x312E81)     // indigo-100 / indigo-900
    static let botBadgeText = Color.cheers(light: 0x4338CA, dark: 0xA5B4FC)   // indigo-700 / indigo-300

    // Status
    static let online = Color(hex: 0x10B981)                                   // emerald-500
    static let danger = Color.cheers(light: 0xDC2626, dark: 0xF87171)         // red-600 / red-400
    static let warning = Color.cheers(light: 0xD97706, dark: 0xFBBF24)        // amber-600 / amber-400
    static let mention = Color(hex: 0xE11D48)                                  // rose-600 (constant)

    // Bubbles — ONE color for every message; sender is shown by side + avatar,
    // never by bubble color (no bright accent fills at all).
    static let bubbleOther = Color(uiColor: .secondarySystemBackground)
    static let bubbleOtherText = Color.primary
    static let bubbleOwn = bubbleOther
    static let bubbleOwnText = bubbleOtherText

    /// Deterministic avatar palette — must match `AVATAR_COLORS` in
    /// frontend/src/lib/format.ts so avatar colors agree across platforms.
    static let avatarColors: [Color] = [
        Color(hex: 0x4F46E5), // indigo-600
        Color(hex: 0x7C3AED), // violet-600
        Color(hex: 0x2563EB), // blue-600
        Color(hex: 0x059669), // emerald-600
        Color(hex: 0xE11D48), // rose-600
        Color(hex: 0xD97706), // amber-600
        Color(hex: 0x0891B2), // cyan-600
        Color(hex: 0xDB2777), // pink-600
    ]

    /// Port of `avatarColor()` in frontend/src/lib/format.ts:
    /// `hash = (hash * 31 + id.charCodeAt(i)) & 0xffffffff` (JS bitwise AND
    /// coerces to signed Int32), then `Math.abs(hash) % 8`.
    static func avatarColor(for id: String) -> Color {
        var hash: Int64 = 0
        for unit in id.utf16 {
            hash = Int64(Int32(truncatingIfNeeded: hash * 31 + Int64(unit)))
        }
        let index = Int(hash.magnitude % UInt64(avatarColors.count))
        return avatarColors[index]
    }

    /// Port of `initials()` in frontend/src/lib/format.ts.
    static func initials(_ name: String?, fallback: String = "?") -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        if parts.count == 1 {
            return String(parts[0].prefix(2)).uppercased()
        }
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.last?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - Time formatting (parity with frontend/src/lib/format.ts)

enum TimeFormat {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return Self.iso.date(from: iso) ?? Self.isoNoFraction.date(from: iso)
    }

    /// "HH:MM" 2-digit style, like `formatTime`.
    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        return timeFormatter.string(from: date)
    }

    /// "Today" / "Yesterday" / "Monday, June 1" style, like `formatDayLabel`.
    static func dayLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return fullDayFormatter.string(from: date)
    }

    /// Compact stamp for conversation list rows: time today, "Yesterday",
    /// else short date.
    static func listStamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time(date) }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return shortDayFormatter.string(from: date)
    }

    static func sameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}
