# Bellwether

**The test-harness signal channel for iOS.** *The bellwether wears the bell for the flock — it hears the signal so your business logic doesn't have to.*

One line per screen gives an app under UI test an in-place refresh listener. The harness (e.g. [Crucible](https://github.com/MainActorDev/Crucible)) posts a Darwin notification into the simulator; Bellwether's subscriber refetches — no navigation, no pull-to-refresh, no relaunch.

## Adoption

```swift
// 1. Open the gate — YOUR source code, so it follows YOUR app configuration.
#if DEBUG
Bellwether.subscriptionsAllowed = true
#endif

// 2. Subscribe a screen (where its store lives):
self.refreshSignal = Bellwether.subscribeRefresh(for: "home") { [weak store] in
    store?.dispatch(.loadData)
}
```

Production launches register nothing: the subscription is `nil` unless **both** the gate is open **and** the launch argument `-uitest-live-refresh` is present. The returned `RefreshSubscription`'s lifetime is the observer's lifetime — store it in the owning adapter; deallocation detaches cleanly.

## The contract (single source of truth)

| Piece | Value |
|---|---|
| Launch argument | `-uitest-live-refresh` |
| Refresh signal | `com.crucible.refresh.<screenId>` (Darwin notification) |
| Gate | `Bellwether.subscriptionsAllowed` — **default `false`**; the consumer opts in |

The gate is runtime and default-deny because this library ships as a prebuilt XCFramework: compile conditions bake at prebuild time, not per app configuration. "Debug only by default" therefore lives in the consumer's `#if DEBUG`, where it actually follows the app's build.

## Requirements

iOS 16+. Swift 6. No dependencies.

## License

MIT
