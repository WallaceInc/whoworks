import Foundation

/// Collapses formatting differences in company names so that variants of the
/// same employer group together.
///
/// This is deliberately conservative — it only removes things that carry no
/// meaning: case, accents, punctuation, and trailing legal suffixes. Two names
/// only collide if they are genuinely the same string underneath.
///
/// It does **not** attempt fuzzy matching. "Apple Inc" and "Apple Bank" are two
/// characters apart and completely unrelated, and no threshold separates that
/// case from a real typo. Nor does it expand abbreviations: nothing connects
/// "Acme Plmb" to "Acme Plumbing" without a company dictionary, which would
/// mean a network call.
enum CompanyNormalizer {
    /// Stripped only when they *trail* the name, where they're a legal form
    /// rather than part of the identity. "Group" and "Holdings" are absent on
    /// purpose: "Acme Group" and "Acme" can be different entities.
    private static let legalSuffixes: Set<String> = [
        "inc", "incorporated", "llc", "l l c", "llp", "lllp", "lp", "ltd",
        "limited", "co", "corp", "corporation", "company", "plc", "pllc", "pc",
        "ag", "gmbh", "sa", "sas", "sarl", "nv", "bv", "ab", "oy", "oyj", "as",
        "pty", "srl", "spa", "kg", "kk",
    ]

    /// The key two spellings must share to be treated as one company.
    static func key(_ raw: String) -> String {
        var text = raw.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        // "H&M" and "H and M" are the same company written two ways.
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = String(text.map { $0.isLetter || $0.isNumber || $0.isWhitespace ? $0 : " " })

        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // Several can stack up: "Acme Ltd Co".
        while tokens.count > 1, let last = tokens.last, legalSuffixes.contains(last) {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }

    /// Which spelling to show for a group: the one used most often, and on a
    /// tie the shortest — "Siemens" reads better as a heading than "Siemens AG".
    static func preferredSpelling(from spellings: [String]) -> String {
        var counts: [String: Int] = [:]
        for spelling in spellings { counts[spelling, default: 0] += 1 }
        return counts
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                if left.key.count != right.key.count { return left.key.count < right.key.count }
                return left.key < right.key
            }
            .first?.key ?? spellings.first ?? ""
    }
}
