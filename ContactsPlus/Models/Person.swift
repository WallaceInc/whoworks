import Contacts
import Foundation

/// A flattened, `Sendable` snapshot of a `CNContact`.
///
/// `CNContact` is neither `Sendable` nor cheap to hold onto in bulk, so the
/// repository converts every record once on a background task and the UI only
/// ever sees these value types.
struct Person: Identifiable, Hashable, Sendable {
    let id: String
    let givenName: String
    let familyName: String
    let organizationName: String
    let jobTitle: String
    let primaryPhone: String?
    let primaryEmail: String?
    let thumbnail: Data?

    /// Lowercased, diacritic-folded key used for sorting and sectioning.
    let sortKey: String

    /// Primary line: the person's name.
    var displayName: String {
        let full = [givenName, familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !full.isEmpty { return full }
        if !organizationName.isEmpty { return organizationName }
        return primaryEmail ?? primaryPhone ?? "No Name"
    }

    // MARK: - Company

    /// The company as actually typed on the contact.
    var enteredCompany: String? {
        organizationName.isEmpty ? nil : organizationName
    }

    /// A company guessed from a work email address, used only when the Company
    /// field is empty.
    ///
    /// Most people never fill Company in, which would leave the whole point of
    /// this app blank on a typical address book. A work email is the next best
    /// evidence of where somebody works.
    var inferredCompany: String? {
        guard enteredCompany == nil, let email = primaryEmail else { return nil }
        return Self.company(fromEmail: email)
    }

    /// Entered company if there is one, otherwise the guess.
    var company: String? { enteredCompany ?? inferredCompany }

    /// True when the company was guessed rather than entered. The row renders
    /// these dimmer so a guess never reads as fact.
    var isCompanyInferred: Bool { enteredCompany == nil && inferredCompany != nil }

    /// The company line. `nil` when there's nothing to show, so the row simply
    /// doesn't reserve the space.
    var companyLine: String? {
        guard let company else { return nil }
        // A company-only contact already shows the org as its name; repeating
        // it underneath would be noise.
        return displayName == company ? nil : company
    }

    /// Heading this contact files under when the list is grouped by company.
    /// Empty means "no company" — the caller buckets those under Unknown.
    var companyGroup: String {
        (company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Other fields

    /// Digits only (keeping a leading `+`) for use in `tel:` and `sms:` URLs.
    var dialableNumber: String? {
        guard let phone = primaryPhone else { return nil }
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return phone.hasPrefix("+") ? "+" + digits : digits
    }

    /// A–Z bucket, with everything non-alphabetic collected under "#".
    var sectionKey: String {
        guard let first = sortKey.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    var initials: String {
        let letters = [givenName, familyName]
            .filter { !$0.isEmpty }
            .compactMap(\.first)
        if !letters.isEmpty { return String(letters.prefix(2)).uppercased() }
        if let first = organizationName.first { return String(first).uppercased() }
        return "?"
    }

    /// Matches against name, company (entered or inferred), job title and email
    /// — so the company is searchable without smuggling it into the last name.
    func matches(_ query: String) -> Bool {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !needle.isEmpty else { return true }
        let haystack = [displayName, company ?? "", jobTitle, primaryEmail ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return haystack.contains(needle)
    }
}

// MARK: - Email domain → company

extension Person {
    /// Consumer mail providers say nothing about where someone works.
    private static let personalEmailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com",
        "outlook.com", "outlook.co.uk", "hotmail.com", "hotmail.co.uk",
        "live.com", "live.co.uk", "msn.com", "yahoo.com", "yahoo.co.uk",
        "ymail.com", "rocketmail.com", "aol.com", "protonmail.com", "proton.me",
        "pm.me", "gmx.com", "gmx.de", "mail.com", "zoho.com", "yandex.com",
        "fastmail.com", "hey.com", "duck.com", "qq.com", "163.com", "126.com",
        "naver.com", "rediffmail.com", "comcast.net", "verizon.net", "att.net",
        "sbcglobal.net", "cox.net", "charter.net", "bellsouth.net",
        "earthlink.net", "juno.com", "btinternet.com", "sky.com",
        "virginmedia.com", "talktalk.net", "orange.fr", "free.fr", "wanadoo.fr",
        "web.de", "t-online.de", "libero.it", "bigpond.com", "optusnet.com.au",
        "shaw.ca", "rogers.com", "sympatico.ca",
    ]

    /// Second-level pieces that belong to the suffix rather than the name —
    /// `bbc.co.uk` should give "BBC", not "Co".
    private static let suffixParts: Set<String> = [
        "co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "gouv",
    ]

    static func company(fromEmail email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        let domain = String(trimmed[trimmed.index(after: at)...])
        guard !domain.isEmpty, !personalEmailDomains.contains(domain) else { return nil }

        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }

        // Walk past the public suffix: acme.com → acme, acme.co.uk → acme.
        var index = parts.count - 2
        if parts.count >= 3, suffixParts.contains(parts[index]) {
            index = parts.count - 3
        }
        let token = parts[index]
        guard !token.isEmpty, token != "mail", token != "email" else { return nil }

        // "ibm" reads better as IBM; "stripe" as Stripe.
        return token
            .split(separator: "-")
            .map { $0.count <= 3 ? $0.uppercased() : $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Building from CNContact

extension Person {
    init(contact: CNContact, sortOrder: CNContactSortOrder) {
        id = contact.identifier
        givenName = contact.givenName
        familyName = contact.familyName
        organizationName = contact.organizationName
        jobTitle = contact.jobTitle
        primaryPhone = contact.phoneNumbers.first?.value.stringValue
        primaryEmail = contact.emailAddresses.first?.value as String?
        thumbnail = contact.thumbnailImageData

        let ordered: [String] = sortOrder == .familyName
            ? [contact.familyName, contact.givenName]
            : [contact.givenName, contact.familyName]
        let base = ordered.filter { !$0.isEmpty }.joined(separator: " ")
        sortKey = (base.isEmpty ? contact.organizationName : base)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
