import SwiftUI

/// The four states the list zooms between.
///
/// Pinch out steps up, pinch in steps back down. Levels 0–2 add a line of
/// information each; level 3 changes how the list is *grouped* rather than
/// what each row shows.
enum DensityLevel: Int, CaseIterable, Identifiable, Comparable, Sendable {
    /// Names only — what Apple's Contacts shows today.
    case names = 0
    /// Name, with the company directly below it.
    case companies = 1
    /// Adds the email address below the company.
    case emails = 2
    /// Regrouped: section headings are companies, not letters.
    case byCompany = 3

    var id: Int { rawValue }

    static func < (lhs: DensityLevel, rhs: DensityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var name: String {
        switch self {
        case .names: "Names"
        case .companies: "Names & Companies"
        case .emails: "With Email"
        case .byCompany: "Grouped by Company"
        }
    }

    var symbol: String {
        switch self {
        case .names: "person.crop.circle"
        case .companies: "building.2"
        case .emails: "envelope"
        case .byCompany: "list.bullet.indent"
        }
    }

    // MARK: - What each row shows

    /// The company line is redundant at `.byCompany` — it's the section heading.
    var showsCompany: Bool { self == .companies || self == .emails }
    var showsEmail: Bool { self == .emails || self == .byCompany }
    var groupsByCompany: Bool { self == .byCompany }

    // MARK: - Row metrics

    var avatarSize: CGFloat {
        switch self {
        case .names: 34
        case .companies, .byCompany: 42
        case .emails: 48
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .names: 8
        case .companies, .byCompany: 9
        case .emails: 10
        }
    }

    var lineSpacing: CGFloat {
        self == .names ? 0 : 1
    }

    var nameFont: Font { .body }
    var detailFont: Font { .caption }

    /// Left inset for the hairline separator, so it lines up under the text.
    var separatorInset: CGFloat {
        avatarSize + Layout.horizontalPadding + Layout.avatarGap
    }

    enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let avatarGap: CGFloat = 12
    }

    // MARK: - Stepping

    static func clamped(_ raw: Int) -> DensityLevel {
        DensityLevel(rawValue: min(max(raw, 0), allCases.count - 1)) ?? .names
    }
}
