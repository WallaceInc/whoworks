#if DEBUG
import Contacts
import Foundation

/// Simulator-only fixture data. The stock simulator address book has six
/// contacts and almost no company or phone fields, which isn't enough to see
/// what the zoom levels actually do.
///
/// Run with:  xcrun simctl launch booted com.whoworks.ios --seed-test-contacts
enum DebugSeed {
    private static let marker = "Okonkwo"

    /// Deliberately patchy: some contacts have no company, some no phone, so
    /// the "just don't show the field" behaviour is visible.
    private static let fixtures: [(first: String, last: String, org: String, phone: String, email: String)] = [
        // Company entered outright
        ("Ada", "Okonkwo", "Northwind Ventures", "555-0142", "ada@northwind.vc"),
        ("Marcus", "Feld", "Northwind Ventures", "555-0188", "marcus@northwind.vc"),
        ("Priya", "Raman", "Northwind Ventures", "", ""),
        ("Tomas", "Boyd", "Acme Plumbing", "555-0110", "tomas@acmeplumbing.com"),
        ("Rosa", "Lindqvist", "Acme Plumbing", "555-0111", ""),
        ("Dev", "Sharma", "Vestry Capital", "555-0155", "dev@vestry.capital"),
        ("Ingrid", "Salas", "Vestry Capital", "", ""),
        ("Owen", "Achebe", "Bright Dental", "555-0173", "owen@brightdental.com"),
        ("Nina", "Castellanos", "Zephyr Roofing", "", ""),
        // No company — should be inferred from the work email domain
        ("Felix", "Barnard", "", "555-0199", "felix.barnard@siemens.com"),
        ("Sol", "Petrov", "", "", "s.petrov@ibm.com"),
        ("Marta", "Vidal", "", "555-0166", "m.vidal@bbc.co.uk"),
        ("Ines", "Duarte", "", "", "ines@long-harbour.co"),
        // Personal email — must NOT be treated as a company
        ("Junia", "Wren", "", "555-0121", "junia.wren@gmail.com"),
        ("Cass", "Miles", "", "555-0133", "cass@icloud.com"),
    ]

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--seed-test-contacts") else { return }

        let store = CNContactStore()
        let keys = [CNContactFamilyNameKey as CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: marker)
        if let existing = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
           !existing.isEmpty {
            return  // already seeded
        }

        let request = CNSaveRequest()
        for fixture in fixtures {
            let contact = CNMutableContact()
            contact.givenName = fixture.first
            contact.familyName = fixture.last
            contact.organizationName = fixture.org
            if !fixture.phone.isEmpty {
                contact.phoneNumbers = [
                    CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                   value: CNPhoneNumber(stringValue: fixture.phone))
                ]
            }
            if !fixture.email.isEmpty {
                contact.emailAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: fixture.email as NSString)
                ]
            }
            request.add(contact, toContainerWithIdentifier: nil)
        }
        try? store.execute(request)
    }
}
#endif
