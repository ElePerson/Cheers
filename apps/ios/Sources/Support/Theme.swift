import SwiftUI

// MARK: - Design tokens
//
// iOS owns appearance, contrast, Dynamic Type, Increased Contrast and
// light/dark adaptation. Product-specific color values do not belong here.

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
    /// Separation after a complete message group (including its agent trace).
    /// This is deliberately larger than `space2` so adjacent messages remain
    /// visually distinct without loosening the sender/content relationship.
    static let messageGroupGap: CGFloat = 20
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

    // Interactive emphasis follows the app's system tint. Badge emphasis uses
    // semantic fills and labels instead of a product-specific purple palette.
    static let accent = Color.accentColor
    static let accentHover = Color.accentColor
    static let link = Color.accentColor
    static let botBadgeBg = Color(uiColor: .quaternarySystemFill)
    static let botBadgeText = Color.secondary

    // System status colors retain their platform meaning and automatically
    // adapt to appearance and accessibility settings.
    static let online = Color(uiColor: .systemGreen)
    static let danger = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)
    static let mention = Color.accentColor

    // Bubbles — ONE color for every message; sender is shown by side + avatar,
    // never by bubble color (no bright accent fills at all).
    static let bubbleOther = Color(uiColor: .secondarySystemBackground)
    static let bubbleOtherText = Color.primary
    static let bubbleOwn = bubbleOther
    static let bubbleOwnText = bubbleOtherText

    /// Neutral fallback for identities without a real image. The id remains in
    /// the signature so callers do not need a compatibility branch.
    static func avatarColor(for id: String) -> Color {
        _ = id
        return Color(uiColor: .systemGray)
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
