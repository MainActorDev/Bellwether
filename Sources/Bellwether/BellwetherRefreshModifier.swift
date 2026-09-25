import Bellwether
import SwiftUI

/// UI-test seam attachment: subscribe this screen to its Bellwether
/// refresh signal (`com.crucible.refresh.<screenId>`).
///
/// No-op in production — the gate is closed, `subscribeRefresh` returns
/// nil, and the only cost is a nil-check per screen appearance. Under the
/// harness (Debug build + `-uitest-live-refresh`), the handler fires on
/// each posted signal.
///
/// Attach at the SCREEN ROOT (the composition site), not inside lazy
/// containers — `onAppear` must actually fire for the subscription to
/// exist.
///
/// Lifetime: the subscription lives in `@State`, so SwiftUI owns it; the
/// observer detaches when SwiftUI drops the storage. The handler should
/// capture its store weakly — there is no retain cycle by construction.
@available(iOS 16.0, *)
public struct BellwetherRefreshModifier: ViewModifier {

    let screenId: String
    let handler: @MainActor () -> Void
    @State private var subscription: RefreshSubscription?

    public init(screenId: String, handler: @escaping @MainActor () -> Void) {
        self.screenId = screenId
        self.handler = handler
    }

    public func body(content: Content) -> some View {
        content.onAppear {
            if subscription == nil {
                subscription = Bellwether.subscribeRefresh(for: screenId, handler: handler)
            }
        }
    }
}

@available(iOS 16.0, *)
extension View {

    /// Subscribe this screen to its Bellwether refresh signal. The ONE
    /// line a screen adds to join the UI-test seam; nothing else in the
    /// app needs to know Bellwether exists.
    public func bellwetherRefresh(
        screenId: String,
        handler: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(BellwetherRefreshModifier(screenId: screenId, handler: handler))
    }
}
