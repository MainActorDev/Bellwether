import CoreFoundation
import Foundation

/// Bellwether — the test-harness signal channel.
///
/// One line per screen gives an app under UI test an in-place refresh
/// listener: the harness posts `com.crucible.refresh.<screenId>` into the
/// simulator; Bellwether's subscriber refetches.
///
/// Philosophy: the bellwether wears the bell for the flock — it hears the
/// signal so the business logic doesn't have to.
///
/// GATE (default DENY): this library is prebuilt once and linked into every
/// app configuration — compile conditions bake at Scipio time, so "Debug
/// only" cannot live here. The CONSUMER sets `subscriptionsAllowed` at
/// startup (typically inside its own `#if DEBUG`); a Release build that
/// wants the seam (QA drill builds) may opt in deliberately.
public enum Bellwether {

    // MARK: - Configuration

    /// The launch argument the harness passes (contract: `-uitest-live-refresh`).
    public static let liveRefreshArgument = "-uitest-live-refresh"

    /// Runtime gate, DEFAULT DENY. The consumer enables it at launch.
    /// Set once at startup, before any subscription — `nonisolated(unsafe)`
    /// because Swift 6 forbids mutable globals; the set-once discipline is
    /// the operator's contract (documented in the README).
    nonisolated(unsafe) public static var subscriptionsAllowed = false

    /// The sanctioned consumer entry: call ONCE at app launch, from the app
    /// target, inside its Debug (or deliberate QA-build) compilation region.
    /// Sets-once semantics: an app that never calls it stays denied.
    public static func activate() {
        subscriptionsAllowed = true
    }

    /// Symmetric off-switch (tests / teardown).
    public static func deactivate() {
        subscriptionsAllowed = false
    }

    /// The full seam condition: gate AND launch argument.
    public static var isLiveRefreshEnabled: Bool {
        subscriptionsAllowed && argumentPresent
    }

    /// Test override for the argument half ONLY — the gate stays explicit
    /// so tests exercise it. Non-nil ⇒ argument considered present.
    nonisolated(unsafe) public static var launchArgumentOverride: String?

    static var argumentPresent: Bool {
        if launchArgumentOverride != nil { return true }
        return ProcessInfo.processInfo.arguments.contains(liveRefreshArgument)
    }

    // MARK: - Signal naming

    /// Canonical notification name for a screen's refresh signal.
    public static func refreshSignalName(for screenId: String) -> CFNotificationName {
        CFNotificationName("com.crucible.refresh.\(screenId)" as CFString)
    }

    // MARK: - Subscription

    /// Subscribe a screen to its refresh signal. Non-nil ONLY when the
    /// gate is open AND the harness argument is present — production
    /// launches get nil, store nothing, no observer ever exists.
    ///
    /// The returned subscription's lifetime is the observer's lifetime:
    /// store it in the owning adapter; `deinit` detaches.
    @discardableResult
    public static func subscribeRefresh(
        for screenId: String,
        handler: @escaping @MainActor () -> Void
    ) -> RefreshSubscription? {
        guard subscriptionsAllowed, argumentPresent else { return nil }
        let box = HandlerBox(screenId: screenId, handler: handler)
        box.register()
        return RefreshSubscription(box: box)
    }
}

/// An owned refresh listener. Deallocation detaches the observer —
/// no static handler hop, no manual cancellation required.
public final class RefreshSubscription: @unchecked Sendable {
    private let box: HandlerBox
    fileprivate init(box: HandlerBox) { self.box = box }
    deinit { box.unregister() }   // weak registry ⇒ deinit actually runs
}

/// The observer object itself. The Darwin center IGNORES the `object`
/// and `suspensionBehavior` AddObserver arguments (SDK CFNotificationCenter.h:52)
/// and hands the callback the OBSERVER pointer — so the box registers AS
/// the observer and the callback casts it back. CF does not retain the
/// pointer: the subscription's strong box ref is the retain.
final class HandlerBox: @unchecked Sendable {
    private let screenId: String
    private let handler: @MainActor () -> Void
    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private let name: CFNotificationName

    init(screenId: String, handler: @escaping @MainActor () -> Void) {
        self.screenId = screenId
        self.handler = handler
        self.name = Bellwether.refreshSignalName(for: screenId)
    }

    fileprivate func register() {
        let observer = Unmanaged.passRetained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let box = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue()
            box.fire()
        }, name.rawValue, nil, .deliverImmediately)
        Registry.shared.register(self, for: screenId)   // weak entry
    }

    fileprivate func unregister() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, name, nil)
        Registry.shared.unregister(screenId: screenId)
        Unmanaged.passUnretained(self).release()        // balance register's retain
    }

    fileprivate func fire() { Task { @MainActor in handler() } }
}

/// Weak per-screen registry — one LIVE subscription per id (last-wins
/// simply replaces the weak entry), but never OWNS one (strong storage
/// would keep deinit from firing).
private final class Registry: @unchecked Sendable {
    static let shared = Registry()
    private let lock = NSLock()
    private var live: [String: WeakBox] = [:]
    private final class WeakBox {
        weak var value: HandlerBox?
        init(value: HandlerBox?) { self.value = value }
    }

    func register(_ box: HandlerBox, for screenId: String) {
        lock.lock(); defer { lock.unlock() }
        live[screenId] = WeakBox(value: box)
    }
    func unregister(screenId: String) {
        lock.lock(); defer { lock.unlock() }
        live.removeValue(forKey: screenId)
    }
}
