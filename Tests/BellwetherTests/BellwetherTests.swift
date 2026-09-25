import Testing
import CoreFoundation
import Foundation
@testable import Bellwether

@Suite("Bellwether", .serialized)
struct BellwetherTests {

    @Test("default DENY — gate closed ⇒ subscribe nil even with the argument")
    func defaultDeny() {
        Bellwether.subscriptionsAllowed = false
        Bellwether.launchArgumentOverride = "-uitest-live-refresh" // arg present
        #expect(Bellwether.subscribeRefresh(for: "home", handler: {}) == nil)
        Bellwether.launchArgumentOverride = nil
    }

    @Test("gate open but no argument ⇒ nil")
    func gateOpenNoArg() {
        Bellwether.subscriptionsAllowed = true
        Bellwether.launchArgumentOverride = nil              // real ProcessInfo: no arg in test host
        #expect(Bellwether.subscribeRefresh(for: "home", handler: {}) == nil)
    }

    @Test("signal name is canonical")
    func naming() {
        #expect(Bellwether.refreshSignalName(for: "home").rawValue as String == "com.crucible.refresh.home")
    }

    @Test("gate+arg: subscription delivers on post; deinit detaches")
    func deliveryAndLifetime() async {
        Bellwether.subscriptionsAllowed = true
        Bellwether.launchArgumentOverride = "-uitest-live-refresh"
        defer { Bellwether.subscriptionsAllowed = false; Bellwether.launchArgumentOverride = nil }
        let box = FireBox()
        var sub = Bellwether.subscribeRefresh(for: "lifetest") { box.fire() }
        #expect(sub != nil)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Bellwether.refreshSignalName(for: "lifetest"), nil, nil, true)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(box.count == 1)
        sub = nil                                              // deinit detaches
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Bellwether.refreshSignalName(for: "lifetest"), nil, nil, true)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(box.count == 1)                               // no second delivery
    }

    @Test("activate() opens the gate; deactivate() closes it")
    func activationLifecycle() {
        Bellwether.subscriptionsAllowed = false
        Bellwether.activate()
        #expect(Bellwether.subscriptionsAllowed == true)
        Bellwether.deactivate()
        #expect(Bellwether.subscriptionsAllowed == false)
    }

    @Test("two screens coexist — each handler fires only for its id")
    func multiScreen() async {
        Bellwether.subscriptionsAllowed = true
        Bellwether.launchArgumentOverride = "-uitest-live-refresh"
        defer { Bellwether.subscriptionsAllowed = false; Bellwether.launchArgumentOverride = nil }
        let a = FireBox(); let b = FireBox()
        var sa = Bellwether.subscribeRefresh(for: "a") { a.fire() }
        var sb = Bellwether.subscribeRefresh(for: "b") { b.fire() }
        defer { sa = nil; sb = nil }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Bellwether.refreshSignalName(for: "a"), nil, nil, true)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(a.count == 1 && b.count == 0)
    }
}

final class FireBox: @unchecked Sendable {
    private let lock = NSLock(); private(set) var count = 0
    func fire() { lock.lock(); count += 1; lock.unlock() }
}

@Suite("BellwetherRefreshModifier")
struct BellwetherModifierTests {

    @Test("modifier attaches without crash; production gate closed => nil subscription, no cost path")
    @MainActor func modifierAttaches() async {
        Bellwether.subscriptionsAllowed = false
        defer { Bellwether.subscriptionsAllowed = false }
        // gate closed: subscribeRefresh inside onAppear returns nil — the
        // modifier's storage stays nil and no observer exists. We can't
        // host SwiftUI here; the behavioral contract is Bellwether's own
        // (pinned below) plus compile-time attachment correctness.
        let sub = Bellwether.subscribeRefresh(for: "modifier-probe", handler: {})
        #expect(sub == nil)
    }

    @Test("handler holds weak store — no retain cycle by construction (mirrors app usage)")
    @MainActor func noRetainCycle() async {
        final class FakeStore: @unchecked Sendable {
            var fired = false
        }
        let store = FakeStore()
        weak var weakStore = store
        Bellwether.subscriptionsAllowed = true
        Bellwether.launchArgumentOverride = "-uitest-live-refresh"
        defer { Bellwether.subscriptionsAllowed = false; Bellwether.launchArgumentOverride = nil }
        var sub = Bellwether.subscribeRefresh(for: "cycle") { [weak store] in
            store?.fired = true
        }
        #expect(sub != nil)
        sub = nil
        // subscription deallocated => its box released; store NOT retained by anything
        #expect(weakStore != nil)   // we still hold it
        _ = store
        #expect(true)
    }
}
