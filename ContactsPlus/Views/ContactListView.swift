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
    @State private var creatingContact = false
    @State private var variantInfo: VariantInfo?
    @State private var moreOptions: Person?
    @State private var pendingDelete: Person?

    /// Built off the main actor and cached — see `rebuild()`.
    @State private var sections: [ListSection] = []
    @State private var indexEntries: [IndexEntry] = []
    @State private var buildToken = 0
    @State private var hasBuilt = false

    private var density: DensityLevel { DensityLevel.clamped(storedDensity) }

    // The modifier chain is split into named stages purely so the Swift type
    // checker can cope; a single chain this long makes it give up.

    var body: some View {
        NavigationStack {
            screen
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

    private var screen: some View {
        dialogs
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                newContactButton
                densityMenu
            }
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name or company"
            )
            .onChange(of: search) { rebuild() }
            // Levels 0/1/2 share identical sectioning — only level 3 regroups,
            // so most zoom steps need no rebuild at all.
            .onChange(of: density.groupsByCompany) { rebuild() }
            .onChange(of: favorites.ids) { rebuild() }
            // Opening a Spotlight result jumps straight to that person's card.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
                else { return }
                openCard(for: id)
            }
    }

    private var dialogs: some View {
        sheets
            .confirmationDialog(
                moreOptions?.displayName ?? "",
                isPresented: Binding(
                    get: { moreOptions != nil },
                    set: { if !$0 { moreOptions = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Contact…", role: .destructive) {
                    pendingDelete = moreOptions
                    moreOptions = nil
                }
                Button("Cancel", role: .cancel) { moreOptions = nil }
            }
            .confirmationDialog(
                pendingDelete.map { "Delete \($0.displayName)?" } ?? "",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Contact", role: .destructive) {
                    guard let person = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        if await repo.delete(id: person.id) { rebuild() }
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This removes them from your iPhone and can't be undone here.")
            }
            .alert(
                variantInfo?.company ?? "",
                isPresented: Binding(
                    get: { variantInfo != nil },
                    set: { if !$0 { variantInfo = nil } }
                ),
                presenting: variantInfo
            ) { _ in
                Button("OK", role: .cancel) { variantInfo = nil }
            } message: { info in
                Text("Grouped from these spellings:\n\n"
                     + info.spellings.joined(separator: "\n")
                     + "\n\nYour contacts are unchanged.")
            }
    }

    private var sheets: some View {
        content
            .sheet(isPresented: $creatingContact) {
                Task {
                    await repo.reload()
                    rebuild()
                }
            } content: {
                NewContactView { creatingContact = false }
                    .ignoresSafeArea()
            }
            .sheet(item: $card) {
                // Anything could have changed while the card was open — an
                // edit, or the contact being deleted outright.
                Task {
                    await repo.reload()
                    rebuild()
                }
            } content: { target in
                ContactCardView(contact: target.contact) { card = nil }
                    .ignoresSafeArea()
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
                        header(for: section)
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

    @ViewBuilder
    private func header(for section: ListSection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if section.spellings.count > 1 {
                Button {
                    variantInfo = VariantInfo(company: section.title, spellings: section.spellings)
                } label: {
                    Text("\(section.spellings.count) spellings")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .id(section.id)
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
                // Favourite is listed first, so it sits at the edge and is what
                // a full swipe triggers. Delete needs a deliberate pull past it.
                Button { favorites.toggle(person.id) } label: {
                    Label(
                        favorites.contains(person.id) ? "Unfavourite" : "Favourite",
                        systemImage: favorites.contains(person.id) ? "star.slash.fill" : "star.fill"
                    )
                }
                .tint(.orange)

                // Not Delete directly. SwiftUI can't stage a swipe reveal, so
                // deliberateness comes from a neutral "More" that opens the
                // menu — a mis-tap here costs nothing.
                Button { moreOptions = person } label: {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tint(.gray)
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

    private var newContactButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { creatingContact = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Contact")
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
        /// Distinct spellings of the company that were merged into this group.
        /// More than one means the heading is a normalisation of several.
        var spellings: [String] = []
    }

    struct VariantInfo: Identifiable {
        let company: String
        let spellings: [String]
        var id: String { company }
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
    /// Grouped by company, alphabetically, with everyone lacking a company
    /// collected under "Unknown" at the bottom.
    ///
    /// Grouping is by *normalised* name, so "Siemens", "SIEMENS" and
    /// "Siemens AG" form one section instead of three. Nothing is written back
    /// — the contacts keep whatever spelling they have.
    nonisolated private static func companySections(_ people: [Person]) -> [ListSection] {
        var groups: [String: [Person]] = [:]
        var spellings: [String: [String]] = [:]

        for person in people {
            let raw = person.companyGroup
            if raw.isEmpty {
                groups[unknownCompany, default: []].append(person)
            } else {
                let key = CompanyNormalizer.key(raw)
                groups[key, default: []].append(person)
                spellings[key, default: []].append(raw)
            }
        }

        // Sort by the spelling actually shown, not the normalised key.
        var titles: [String: String] = [:]
        for (key, variants) in spellings {
            titles[key] = CompanyNormalizer.preferredSpelling(from: variants)
        }

        var ordered = groups.keys
            .filter { $0 != unknownCompany }
            .sorted { (titles[$0] ?? $0).localizedStandardCompare(titles[$1] ?? $1) == .orderedAscending }
        if groups[unknownCompany] != nil { ordered.append(unknownCompany) }

        return ordered.map { key in
            let members = (groups[key] ?? []).sorted {
                $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
            }
            let isUnknown = key == unknownCompany
            let title = isUnknown ? unknownCompany : (titles[key] ?? key)
            let letter = isUnknown
                ? "#"
                : (title.first.map { String($0).uppercased() } ?? "#")
            let distinct = Array(Set(spellings[key] ?? [])).sorted()
            return ListSection(
                id: "¶\(key)",
                title: title,
                indexLetter: letter,
                people: members,
                spellings: distinct
            )
        }
    }
}
