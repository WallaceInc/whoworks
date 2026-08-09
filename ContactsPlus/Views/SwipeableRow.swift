import SwiftUI

/// Tracks which row is currently open.
///
/// Deliberately an `@Observable` object rather than parent `@State`: any `@State`
/// mutation invalidates the view that owns it, so opening a row re-ran the list's
/// body and re-diffed every contact. Only the rows read this, so only the rows
/// re-render.
@MainActor
@Observable
final class SwipeCoordinator {
    var openRowID: String?
}

/// Hand-rolled swipe actions.
///
/// `List`'s `.swipeActions` isn't available to us — the list is a
/// `ScrollView`/`LazyVStack` so that the pinch can hold its scroll position.
///
/// Swipe left: message and call. Swipe right: favourite.
///
/// Deliberately no `.contextMenu`: a `UIContextMenuInteraction` on every row
/// runs a long-press recogniser that delays touches reaching the scroll view
/// while it decides. That blocked vertical scrolling for around a second once
/// a sideways movement had started.
///
/// The layering here is the whole trick, and both halves are load-bearing:
///
/// * **The drag gesture sits on the outer container**, which never moves. Put it
///   inside `.offset` and the drag is measured in a coordinate space the drag is
///   itself shifting — the feedback makes tracking jitter.
/// * **`.contentShape` is applied to the content *before* `.offset`**, so the
///   row's tap area travels with it. Applied after, hit testing re-anchors to
///   the original rectangle and the row swallows taps meant for the buttons.
///
/// Getting one right while breaking the other is easy; they look unrelated.
struct SwipeableRow<Content: View>: View {
    let rowID: String
    let phoneNumber: String?
    let isFavorite: Bool
    let onCall: () -> Void
    let onMessage: () -> Void
    let onToggleFavorite: () -> Void
    let onTap: () -> Void
    let coordinator: SwipeCoordinator
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    /// Translation at the moment the swipe was recognised. Subtracting it keeps
    /// the row from jumping by the distance spent deciding.
    @State private var engageTranslation: CGFloat = 0
    @State private var engaged = false
    /// Direction is judged once per gesture, then locked. Re-judging on every
    /// update let a vertical scroll re-qualify as a swipe partway down.
    @State private var decided = false
    /// Kept true through the closing animation, so the buttons don't vanish
    /// while the row is still sliding back over them.
    @State private var actionsMounted = false
    /// Unlike `onEnded`, `@GestureState` resets even when a gesture is
    /// *cancelled* — which is what happens when the scroll view claims the
    /// touch. Without it the direction flags leaked into the next gesture.
    @GestureState private var dragging = false

    private let actionWidth: CGFloat = 78
    /// Below roughly 15pt the row's drag beats the scroll view to the touch and
    /// vertical scrolling stops working. This is a floor, not a responsiveness
    /// dial — `engageTranslation` absorbs the travel spent here.
    private let minimumDragDistance: CGFloat = 18
    private let decisionDistance: CGFloat = 20
    private let horizontalBias: CGFloat = 1.35

    /// No number means nothing to call or message, so there's nothing to reveal.
    private var maxTrailing: CGFloat { phoneNumber == nil ? 0 : actionWidth * 2 }
    private var maxLeading: CGFloat { actionWidth }

    var body: some View {
        ZStack {
            // Mounted only while in use — three buttons behind every closed row
            // is what made scrolling a large address book stutter.
            if actionsMounted {
                HStack(spacing: 0) {
                    actionButton(
                        symbol: isFavorite ? "star.slash.fill" : "star.fill",
                        tint: .orange
                    ) {
                        onToggleFavorite()
                        close()
                    }
                    .opacity(offset > 0 ? 1 : 0)

                    Spacer(minLength: 0)

                    if phoneNumber != nil {
                        actionButton(symbol: "message.fill", tint: .blue) {
                            onMessage()
                            close()
                        }
                        actionButton(symbol: "phone.fill", tint: .green) {
                            onCall()
                            close()
                        }
                    }
                }
            }

            content()
                .background(Color(uiColor: .systemBackground))
                .contentShape(.rect)
                .onTapGesture {
                    // An open row swallows the first tap, the way Mail does.
                    if offset != 0 { close() } else { onTap() }
                }
                .offset(x: offset)
        }
        .clipped()
        // `.simultaneousGesture`, not `.gesture`. With `.gesture` the scroll
        // view must wait for this drag to fail before it will scroll, which put
        // a fixed delay on the start of every vertical scroll — most obvious on
        // the first scroll after launch and immediately after a swipe closes.
        // Recognising simultaneously lets scrolling begin at once; the direction
        // lock below still keeps the row from moving during a vertical drag.
        .simultaneousGesture(drag)
        .onChange(of: dragging) { _, active in
            guard !active else { return }
            // Cancelled mid-swipe leaves the row stranded between positions.
            if engaged, offset != 0 {
                withAnimation(.snappy(duration: 0.2)) {
                    if offset > maxLeading / 2 { offset = maxLeading }
                    else if offset < -maxTrailing / 2 { offset = -maxTrailing }
                    else { offset = 0 }
                }
                unmountIfClosed()
            }
            decided = false
            engaged = false
        }
        .onChange(of: coordinator.openRowID) { _, newValue in
            if newValue != rowID, offset != 0 { close() }
        }
    }

    private func actionButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(tint)
        }
        .buttonStyle(.plain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: minimumDragDistance)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !decided {
                    guard max(abs(dx), abs(dy)) >= decisionDistance else { return }
                    decided = true
                    engaged = abs(dx) > abs(dy) * horizontalBias
                    guard engaged else { return }
                    startOffset = offset
                    engageTranslation = dx
                    actionsMounted = true
                    coordinator.openRowID = rowID
                }

                guard engaged else { return }
                offset = min(max(startOffset + (dx - engageTranslation), -maxTrailing), maxLeading)
            }
            .onEnded { value in
                defer {
                    decided = false
                    engaged = false
                }
                guard engaged else { return }

                // Resolve in the direction the row is *currently* displaced. Read
                // on its own, a flick meant swiping left to shut a right-opened
                // row threw it wide open the other way — no path back to centre.
                let flick = value.predictedEndTranslation.width - value.translation.width
                let target: CGFloat
                if offset > 0 {
                    target = (offset > maxLeading / 2 || (flick > 90 && offset > 20)) ? maxLeading : 0
                } else if offset < 0 {
                    target = (offset < -maxTrailing / 2 || (flick < -90 && offset < -20)) ? -maxTrailing : 0
                } else {
                    target = 0
                }

                withAnimation(.snappy(duration: 0.25)) { offset = target }
                unmountIfClosed()
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { offset = 0 }
        unmountIfClosed()
    }

    /// Waits for the slide-back to finish before tearing the buttons down.
    private func unmountIfClosed() {
        guard offset == 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if offset == 0 { actionsMounted = false }
        }
    }
}
