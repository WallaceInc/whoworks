import SwiftUI

/// One tick on the right-hand scrubber: a letter, and the section it jumps to.
/// When grouped by company, several companies share a letter — the entry points
/// at the first of them.
struct IndexEntry: Identifiable, Hashable {
    let letter: String
    let sectionID: String

    var id: String { sectionID }
}

/// The A–Z scrubber down the right edge. Hand-rolled because the list is a
/// `ScrollView`/`LazyVStack` rather than a `List` — which is what lets the
/// pinch gesture keep its place when row heights change.
struct SectionIndexBar: View {
    let entries: [IndexEntry]
    let onSelect: (IndexEntry) -> Void

    @State private var active: String?

    /// Fixed per-letter height keeps the bar sized to its contents and centred,
    /// rather than smeared down the full height of the scroll view.
    private let itemHeight: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                Text(entry.letter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: itemHeight)
            }
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !entries.isEmpty else { return }
                    let index = min(max(Int(value.location.y / itemHeight), 0), entries.count - 1)
                    let entry = entries[index]
                    guard entry.id != active else { return }
                    active = entry.id
                    onSelect(entry)
                }
                .onEnded { _ in active = nil }
        )
        .padding(.trailing, 4)
        .sensoryFeedback(.selection, trigger: active)
    }
}
