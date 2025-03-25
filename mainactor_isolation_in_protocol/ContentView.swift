import SwiftUI

@main
struct MainActorProtocolDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Protocol with MainActor isolation
/// A protocol that requires its methods to be run on MainActor.
/// - Important: Simply marking the protocol itself with `@MainActor` does not guarantee
///   that all implementations are isolated.
///   The isolation will work for the **entire class** only if:
///   1) the class itself is marked `@MainActor`, or
///   2) the conformance to the protocol (e.g. `Store: MainActorIsolated`) is declared
///      **inside** the main body of the class, not in an extension.
///
/// If you declare conformance to `MainActorIsolated` in an extension, then **only** the protocol methods
/// will be isolated, while the rest of the class (properties, additional methods) will not.
/// This can be desired (partial isolation) or potentially risky (accidental data races).
@MainActor
protocol MainActorIsolated {
    func performUpdate(with date: Date) async
}

// MARK: - Basic implementation (Full class isolation)
/// `Store` demonstrates complete `MainActor` isolation:
/// - Conformance to `MainActorIsolated` is declared **within** the class.
/// - This means that all properties and methods of `Store` are isolated on `MainActor`.
/// - This is particularly useful for UI-oriented objects (for example, a SwiftUI View Model),
///   where any state modifications should happen on the main thread.
@Observable
final class Store: MainActorIsolated {
    var lastUpdate: Date = .now {
        didSet {
            logThread("DidSet triggered on:")
        }
    }
    
    func performUpdate(with date: Date) async {
        logThread("Update started on:")
        await executeInternalUpdate(with: date)
    }
    
    private func executeInternalUpdate(with date: Date) async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        logThread("Internal update executing on:")
        lastUpdate = date
    }
    
    private func logThread(_ message: String) {
        print("\(message): \(Thread.current)")
    }
}

// MARK: - Example of INcomplete isolation (via extension)
/// Explanations:
/// 1. With this approach, only the performUpdate method will be isolated on MainActor.
/// 2. The internal logic of executeInternalUpdate(with:) is not required to run on MainActor.
/// 3. Swift 6 will forbid such a call because of a potential data race if
///    executeInternalUpdate is not marked @MainActor.
/// 4. Such “partial isolation” can make sense if the class has
///    mixed responsibilities (UI + background operations). But you must carefully ensure
///    that the non-isolated parts do not access UI state while bypassing the main actor.
/*
 extension Store: MainActorIsolated {
 func performUpdate(with date: Date) async {
 logThread("Unsafe update started on:")
 await executeInternalUpdate(with: date)
 }
 }
 */

// MARK: - Test View
struct ContentView: View {
    @State private var store = Store()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Last update: \(store.lastUpdate.formatted())")
            
            Button("Trigger Update") {
                Task {
                    await store.performUpdate(with: .now)
                }
            }
        }
        .padding()
    }
}

// MARK: - Test results
/// Scenario 1: Conformance declared in the main class body (as in the current example)
/// - performUpdate: runs on MainActor
/// - executeInternalUpdate: runs on MainActor
/// - didSet: called on MainActor (safe for UI)
///
/// Scenario 2: Conformance via an extension
/// - performUpdate: runs on MainActor (because it’s a protocol method)
/// - executeInternalUpdate: may end up unisolated, i.e. on a background thread
/// - didSet: potentially on a background thread (unsafe for UI, because there's an Observation layer that may synchronize access)
///
/// Conclusion: If you need full compile-time control and convenience, declare:
/// 1. The class as `@MainActor`, or
/// 2. Conformance to the protocol within the class body,
/// so that all properties and methods are truly under the protection of the main actor.
