import CoreSpotlight
import SwiftUI

struct ContactListView: View {
    /// How far you have to pinch to cross one level. Higher is twitchier.
    /// 1.25 means a full level costs roughly an 80% spread.
    private static let pinchSensitivity = 1.25

    /// Deadband. The level only changes once the gesture travels this far past
    /// the *current* level — not the halfway point, which is what made it slip
    /// through two levels on one pinch. Re-measured from the new level after
    /// each change, so it gives hysteresis for free.
    private static let levelChangeThreshold = 0.7

    /// Heading for contacts with no company, when grouped by company.
    private static let unknownCompany = "Unknown"

    @State private var repo = ContactRepository()
    @State private var favorites = FavoritesStore()
    @State private var swipe = SwipeCoordinator()
    @AppStorage("density.level") private var storedDensity = DensityLevel.names.rawValue

    @State private var search = ""
    @State private var anchorID: String?
    @State private var pinchBaseline: DensityLevel?
    @State private var badgeVisible = false
    @State private var badgeToken = 0
    @State private var card: ContactCard?

    // Cached. `.scrollPosition(id:)` writes `anchorID` on every scroll update,
    // which re-runs this view's body — so as computed properties these
    // re-sectioned and re-sorted the whole address book while you scrolled.
    @State private var listItems: [ListItem] = []
    @State private var indexEntries: [IndexEntry] = []

    private var density: DensityLevel { DensityLevel.clamped(storedDensity) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Contacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { densityMenu }
                .searchable(
                    text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Name or company"
                )
                .sheet(item: $card) { target in
                    ContactCardView(contact: target.contact) { card = nil }
                        .ignoresSafeArea()
                }
                // Opening a Spotlight result jumps straight to that person's card.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
                    else { return }
                    openCard(for: id)
                }
                .onChange(of: search) { rebuild() }
                .onChange(of: storedDensity) { rebuild() }
                .onChange(of: favorites.ids) { rebuild() }
        }
        .task {
            await repo.load()
            rebuild()

            // Detached and delayed: indexing must never compete with the first
            // few seconds of scrolling.
            let people = repo.people
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(6))
                await SpotlightIndexer.index(people)
            }

            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--density"), index + 1 < arguments.count,
               let level = Int(arguments[index + 1]) {
                storedDensity = DensityLevel.clamped(level).rawValue
            }
            if arguments.contains("--open-card"), let first = repo.people.first {
                openCard(for: first.id)
            }
            #endif
        }
    }

    private func launch(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    private func openCard(for id: String) {
        guard let contact = ContactCardView.fetch(id: id) else { return }
        card = ContactCard(id: id, contact: contact)
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch repo.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .denied:
            ContentUnavailableView {
                Label("No Access to Contacts", systemImage: "lock")
            } description: {
                Text("Grant access in Settings to see your contacts here.")
            } actions: {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }

        case .failed(let message):
            ContentUnavailableView("Couldn't Load Contacts", systemImage: "exclamationmark.triangle", description: Text(message))

        case .ready:
            if listItems.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                list
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(listItems) { item in
                        switch item {
                        case .header(_, let title):
                            SectionHeader(title: title).id(item.id)
                        case .person(let person, _):
                            SwipeableRow(
                                rowID: item.id,
                                phoneNumber: person.dialableNumber,
                                isFavorite: favorites.contains(person.id),
                                onCall: { launch("tel://\(person.dialableNumber ?? "")") },
                                onMessage: { launch("sms:\(person.dialableNumber ?? "")") },
                                onToggleFavorite: { favorites.toggle(person.id) },
                                onTap: { openCard(for: person.id) },
                                coordinator: swipe
                            ) {
                                ContactRowView(person: person, density: density)
                            }
                            .id(item.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $anchorID, anchor: .top)
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .trailing) {
                if search.isEmpty {
                    SectionIndexBar(entries: indexEntries) { entry in
                        proxy.scrollTo(entry.sectionID, anchor: .top)
                    }
                }
            }
            .onChange(of: storedDensity) {
                // Rows just changed shape underneath us. Re-pin whatever was at
                // the top so a pinch zooms in place instead of teleporting.
                guard let anchorID else { return }
                proxy.scrollTo(anchorID, anchor: .top)
            }
        }
        .simultaneousGesture(pinch)
        .overlay(alignment: .top) { densityBadge }
        .sensoryFeedback(.selection, trigger: storedDensity)
    }

    // MARK: - Pinch

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.1)
            .onChanged { value in
                let baseline = pinchBaseline ?? density
                if pinchBaseline == nil { pinchBaseline = baseline }

                let steps = log2(max(value.magnification, 0.25)) * Self.pinchSensitivity
                let continuous = Double(baseline.rawValue) + steps

                // Must clear the deadband around the level we're currently on.
                guard abs(continuous - Double(density.rawValue)) >= Self.levelChangeThreshold
                else { return }

                let level = DensityLevel.clamped(Int(continuous.rounded()))
                guard level.rawValue != storedDensity else { return }
                withAnimation(.snappy(duration: 0.22)) { storedDensity = level.rawValue }
                flashBadge()
            }
            .onEnded { _ in pinchBaseline = nil }
    }

    /// The gesture is invisible, so confirm it landed.
    @ViewBuilder
    private var densityBadge: some View {
        if badgeVisible {
            Label(density.name, systemImage: density.symbol)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func flashBadge() {
        badgeToken += 1
        let token = badgeToken
        withAnimation(.easeOut(duration: 0.15)) { badgeVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard token == badgeToken else { return }
            withAnimation(.easeIn(duration: 0.3)) { badgeVisible = false }
        }
    }

    /// Same control, discoverable. Nobody finds a hidden pinch on their own.
    private var densityMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Zoom Level", selection: $storedDensity) {
                    ForEach(DensityLevel.allCases) { level in
                        Label(level.name, systemImage: level.symbol).tag(level.rawValue)
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
        }
    }

    // MARK: - Sectioning

    private var filtered: [Person] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repo.people }
        return repo.people.filter { $0.matches(query) }
    }

    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let indexLetter: String
        let people: [Person]
    }

    private var sections: [ListSection] {
        var result = density.groupsByCompany ? companySections : alphabeticalSections
        if let pinned = favoritesSection { result.insert(pinned, at: 0) }
        return result
    }

    /// Pinned to the top at every zoom level. Hidden while searching, where you
    /// want plain results rather than a pinned block.
    private var favoritesSection: ListSection? {
        guard search.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let people = repo.people
            .filter { favorites.contains($0.id) }
            .sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        guard !people.isEmpty else { return nil }
        return ListSection(id: "★", title: "Favorites", indexLetter: "★", people: people)
    }

    private var alphabeticalSections: [ListSection] {
        var result: [ListSection] = []
        var currentKey: String?
        var bucket: [Person] = []

        for person in filtered {
            if person.sectionKey != currentKey {
                if let key = currentKey {
                    result.append(ListSection(id: "§\(key)", title: key, indexLetter: key, people: bucket))
                }
                currentKey = person.sectionKey
                bucket = []
            }
            bucket.append(person)
        }
        if let key = currentKey {
            result.append(ListSection(id: "§\(key)", title: key, indexLetter: key, people: bucket))
        }
        return result
    }

    /// Grouped by company, alphabetically, with everyone lacking a company
    /// collected under "Unknown" at the bottom.
    private var companySections: [ListSection] {
        var groups: [String: [Person]] = [:]
        for person in filtered {
            let key = person.companyGroup.isEmpty ? Self.unknownCompany : person.companyGroup
            groups[key, default: []].append(person)
        }

        let named = groups.keys
            .filter { $0 != Self.unknownCompany }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var ordered = named
        if groups[Self.unknownCompany] != nil { ordered.append(Self.unknownCompany) }

        return ordered.map { company in
            let people = (groups[company] ?? []).sorted {
                $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
            }
            let isUnknown = company == Self.unknownCompany
            let letter = isUnknown
                ? "#"
                : (company.first.map { String($0).uppercased() } ?? "#")
            return ListSection(id: "¶\(company)", title: company, indexLetter: letter, people: people)
        }
    }

    /// Headers and rows flattened into one sequence. Keeping them as direct
    /// children of `scrollTargetLayout()` is what lets `scrollPosition(id:)`
    /// anchor on an individual contact.
    private func rebuild() {
        let built = sections
        listItems = built.flatMap { section in
            [ListItem.header(id: section.id, title: section.title)]
                + section.people.map { ListItem.person($0, sectionID: section.id) }
        }

        // One tick per distinct letter, pointing at the first section using it.
        var seen = Set<String>()
        indexEntries = built.compactMap { section in
            guard seen.insert(section.indexLetter).inserted else { return nil }
            return IndexEntry(letter: section.indexLetter, sectionID: section.id)
        }
    }

    enum ListItem: Identifiable, Hashable {
        case header(id: String, title: String)
        case person(Person, sectionID: String)

        var id: String {
            switch self {
            case .header(let id, _): id
            // A favourite appears both pinned at the top and in its normal
            // letter section, so the row id must include the section or the
            // two copies collide.
            case .person(let person, let sectionID): "\(sectionID)|\(person.id)"
            }
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DensityLevel.Layout.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(Color(uiColor: .secondarySystemBackground))
    }
}
