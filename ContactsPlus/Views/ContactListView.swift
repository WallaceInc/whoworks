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
    @AppStorage("density.level") private var storedDensity = DensityLevel.names.rawValue

    @State private var search = ""
    @State private var pinchBaseline: DensityLevel?
    @State private var badgeVisible = false
    @State private var badgeToken = 0
    @State private var card: ContactCard?

    /// Built off the main actor and cached — see `rebuild()`.
    @State private var sections: [ListSection] = []
    @State private var indexEntries: [IndexEntry] = []
    @State private var buildToken = 0
    @State private var hasBuilt = false

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
                .sheet(item: $card) {
                    // Anything could have changed while the card was open —
                    // an edit, or the contact being deleted outright.
                    Task {
                        await repo.reload()
                        rebuild()
                    }
                } content: { target in
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
                // Levels 0/1/2 share identical sectioning — only level 3 regroups,
                // so most zoom steps need no rebuild at all.
                .onChange(of: density.groupsByCompany) { rebuild() }
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
            if !hasBuilt {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                list
            }
        }
    }

    // MARK: - List
    //
    // A plain `List`, deliberately. This used to be a hand-rolled
    // `ScrollView`/`LazyVStack` with a `DragGesture` on every row, so a pinch
    // could hold its scroll position. But a SwiftUI `DragGesture` has to begin
    // tracking before it can decide it isn't interested, and that tracking
    // delayed the start of every scroll by a visible beat.
    //
    // Profiling settled it: zero hangs in 90 seconds of reproducing the
    // problem, main thread idle ~85% of the time. The app wasn't busy — the
    // touches weren't reaching the scroll view. `List` hands scrolling and
    // swipe actions to UITableView, which arbitrates them properly.
    //
    // The cost is that scroll position is no longer preserved across a zoom.
    // That's a fair trade for a list that scrolls the moment you ask it to.

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.people) { person in
                            row(person, in: section)
                        }
                    } header: {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .id(section.id)
                    }
                }
            }
            .listStyle(.plain)
            // Plain List leaves a generous gap above each header; the old
            // hand-rolled list was tighter and this restores that density.
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .trailing) {
                if search.isEmpty {
                    SectionIndexBar(entries: indexEntries) { entry in
                        proxy.scrollTo(entry.sectionID, anchor: .top)
                    }
                }
            }
        }
        .simultaneousGesture(pinch)
        .overlay(alignment: .top) { densityBadge }
        .sensoryFeedback(.selection, trigger: storedDensity)
    }

    private func row(_ person: Person, in section: ListSection) -> some View {
        ContactRowView(person: person, density: density)
            .listRowInsets(EdgeInsets())
            .alignmentGuide(.listRowSeparatorLeading) { _ in density.separatorInset }
            .contentShape(.rect)
            .onTapGesture { openCard(for: person.id) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let number = person.dialableNumber {
                    Button { launch("tel://\(number)") } label: {
                        Label("Call", systemImage: "phone.fill")
                    }
                    .tint(.green)

                    Button { launch("sms:\(number)") } label: {
                        Label("Message", systemImage: "message.fill")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { favorites.toggle(person.id) } label: {
                    Label(
                        favorites.contains(person.id) ? "Unfavourite" : "Favourite",
                        systemImage: favorites.contains(person.id) ? "star.slash.fill" : "star.fill"
                    )
                }
                .tint(.orange)
            }
            // A favourite appears both pinned at the top and in its normal
            // section, so the row id must include the section or they collide.
            .id("\(section.id)|\(person.id)")
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

    /// Sectioning is a *pure function* of these inputs, deliberately, so the
    /// work can run off the main actor.
    private func rebuild() {
        buildToken &+= 1
        let token = buildToken
        let people = repo.people
        let query = search
        let grouped = density.groupsByCompany
        let pinned = favorites.ids

        Task {
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildSections(people: people, query: query, groupByCompany: grouped, favorites: pinned)
            }.value
            // A newer rebuild may have started while this one ran.
            guard token == buildToken else { return }
            sections = built

            var seen = Set<String>()
            indexEntries = built.compactMap { section in
                guard seen.insert(section.indexLetter).inserted else { return nil }
                return IndexEntry(letter: section.indexLetter, sectionID: section.id)
            }
            hasBuilt = true
        }
    }

    struct ListSection: Identifiable, Sendable {
        let id: String
        let title: String
        let indexLetter: String
        let people: [Person]
    }

    nonisolated static func buildSections(
        people: [Person], query: String, groupByCompany: Bool, favorites: Set<String>
    ) -> [ListSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty ? people : people.filter { $0.matches(trimmed) }

        var result = groupByCompany
            ? companySections(filtered)
            : alphabeticalSections(filtered)

        // Favourites pin to the top, but not while searching — there you want
        // plain results rather than a pinned block.
        if trimmed.isEmpty {
            let starred = people
                .filter { favorites.contains($0.id) }
                .sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
            if !starred.isEmpty {
                result.insert(
                    ListSection(id: "★", title: "Favourites", indexLetter: "★", people: starred),
                    at: 0
                )
            }
        }
        return result
    }

    nonisolated private static func alphabeticalSections(_ people: [Person]) -> [ListSection] {
        var result: [ListSection] = []
        var currentKey: String?
        var bucket: [Person] = []

        for person in people {
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
    nonisolated private static func companySections(_ people: [Person]) -> [ListSection] {
        var groups: [String: [Person]] = [:]
        for person in people {
            let key = person.companyGroup.isEmpty ? unknownCompany : person.companyGroup
            groups[key, default: []].append(person)
        }

        var ordered = groups.keys
            .filter { $0 != unknownCompany }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if groups[unknownCompany] != nil { ordered.append(unknownCompany) }

        return ordered.map { company in
            let members = (groups[company] ?? []).sorted {
                $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
            }
            let letter = company == unknownCompany
                ? "#"
                : (company.first.map { String($0).uppercased() } ?? "#")
            return ListSection(id: "¶\(company)", title: company, indexLetter: letter, people: members)
        }
    }
}
