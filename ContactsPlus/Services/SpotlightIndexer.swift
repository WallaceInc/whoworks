import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes contacts into system-wide search, so swiping down on the home
/// screen and typing a company name surfaces the people who work there.
enum SpotlightIndexer {
    static let domain = "com.whoworks.ios.contacts"

    private static let signatureKey = "spotlight.signature"
    private static let batchSize = 250

    /// Stable across launches — `Hasher` is seeded randomly per process, so it
    /// can't be persisted and compared.
    private static func signature(of people: [Person]) -> String {
        var hash: UInt64 = 5381
        for person in people {
            for byte in person.id.utf8 { hash = hash &* 33 &+ UInt64(byte) }
            for byte in person.displayName.utf8 { hash = hash &* 33 &+ UInt64(byte) }
            for byte in person.organizationName.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        }
        return "\(people.count)-\(hash)"
    }

    static func index(_ people: [Person]) async {
        // Re-indexing thousands of contacts on every launch burns CPU right when
        // the list is first being scrolled. Only do it when something changed.
        let current = signature(of: people)
        guard UserDefaults.standard.string(forKey: signatureKey) != current else {
            print("[spotlight] unchanged, skipping reindex")
            return
        }

        let items = people.map { person -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .contact)
            attributes.title = person.displayName
            attributes.displayName = person.displayName

            if let company = person.company {
                attributes.organizations = [company]
                // Shown as the result's subtitle — the whole point of this app.
                attributes.contentDescription = company
            }
            if let phone = person.primaryPhone {
                attributes.phoneNumbers = [phone]
            }
            if let email = person.primaryEmail {
                attributes.emailAddresses = [email]
            }
            attributes.keywords = [
                person.givenName, person.familyName, person.company ?? "", person.jobTitle,
            ].filter { !$0.isEmpty }

            let item = CSSearchableItem(
                uniqueIdentifier: person.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
            item.expirationDate = .distantFuture
            return item
        }

        let index = CSSearchableIndex.default()
        do {
            // Clear the domain first so contacts deleted elsewhere don't linger
            // in search results pointing at records that no longer exist.
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])

            // Submitted in batches with a pause between. One large batch is a
            // single sustained burst of work that lands while the list is being
            // scrolled; this stays out of the way instead.
            for start in stride(from: 0, to: items.count, by: batchSize) {
                let batch = Array(items[start ..< min(start + batchSize, items.count)])
                try await index.indexSearchableItems(batch)
                try? await Task.sleep(for: .milliseconds(80))
            }

            UserDefaults.standard.set(current, forKey: signatureKey)
            print("[spotlight] indexed \(items.count) contacts")
        } catch {
            print("[spotlight] indexing failed: \(error)")
        }
    }
}
