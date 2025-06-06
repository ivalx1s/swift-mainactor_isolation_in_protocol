## Approaches to `MainActor` Isolation with Protocols in Swift


[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-red?logo=swift)](https://swift.org/download/) [![Xcode 15+](https://img.shields.io/badge/Xcode-15+-blue?logo=xcode)](https://developer.apple.com/xcode/) [![Swift 6](https://img.shields.io/badge/Swift-6.0+-red?logo=swift)](https://swift.org/download/) [![Xcode 16+](https://img.shields.io/badge/Xcode-16+-blue?logo=xcode)](https://developer.apple.com/xcode/) [![RU](https://img.shields.io/badge/Translation-RU-green)](https://github.com/ivalx1s/swift-mainactor_isolation_in_protocol/blob/main/README-ru.md)

When working with main-thread–bound code—especially UI updates in SwiftUI or UIKit—concurrency issues can arise if your data is not properly isolated on MainActor. While it's common practice to restrict a whole class or its methods to the main actor using the @MainActor attribute, the nuanced approach of isolating methods through protocol extensions is less explored and not well-documented across online resources.
Here, we'll delve into two patterns of main actor isolation:

Whole class is @MainActor: A straightforward approach where the entire class becomes MainActor-isolated, providing clear and comprehensive thread safety.
Per-protocol isolation via extension: A more subtle technique where only the properties and methods defined in the protocol become MainActor-isolated, offering a more granular and flexible approach to concurrency management.

We'll examine code snippets that illustrate these approaches, explore scenarios where each method shines, and demonstrate how Swift 6 compiler checks can help catch potential concurrency mistakes.

---

### Example Setup

We deinfine MainActorIsolated protocol and apply @MainActor attribute to it.

```swift
@MainActor
protocol MainActorIsolated {
    func performUpdate(with date: Date) async
}
```

Basic class with some property for UI layer.

```swift
@Observable
final class Store {
    var lastUpdate: Date = .now {
        didSet {
            logThread("DidSet triggered on:")
        }
    }

    private func logThread(_ message: String) {
        print("\(message): \(Thread.current)")
    }

    func executeInternalUpdate(with date: Date) async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        logThread("Internal update executing on:")
        lastUpdate = date
    }
}
```

---

### 1. Whole Class Is Main-Actor Isolated

By declaring conformance to a protocol marked as `@MainActor` within the class body, the **entire class** becomes isolated to the main actor. This means **every** property and method is guaranteed to run on the main thread, providing strong safety for UI-related code. 

```swift
// Entire class becomes MainActor-isolated
@Observable
final class Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
        await executeInternalUpdate(with: date)
    }
}
```

In scenarios where you’re binding this `Store` to a SwiftUI view (or otherwise closely integrating with your UI), you generally want compile-time guarantees that **all** property accesses and mutations happen on the main actor. This approach makes accidental background mutations much harder.

---

### 2. Conformance in an Extension (Partial Isolation)

If you only want the protocol’s methods to be main-actor isolated—while leaving other parts of the class free to operate on different actors or threads—you can declare conformance in an `extension`. This pattern is especially helpful if your class has multiple responsibilities (hello **S**OLID, but whatever), and not all of them require main-thread isolation. 

```swift
// Only MainActorIsolated methods are main-actor isolated.
extension Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
        // Runs on the main actor context for the protocol requirement
        await executeInternalUpdate(with: date)
    }
}
```

Here, **only** the `performUpdate(with:)` requirement (and anything else explicitly required by `MainActorIsolated`) runs in a main-actor context. Other parts of `Store` remain unrestricted. This can be useful if you’re shadowing or extending the class with a protocol, letting you keep certain functionality non-isolated while respecting `MainActor` constraints for UI-critical actions.

> **Note:** This approach demands caution if you accidentally rely on main-thread access for properties or methods that aren’t explicitly covered by the protocol. **Make sure you truly want partial isolation**.

It's important to understand that when implementing protocol conformance in a class extension, the entire class does not inherit the isolation defined in the protocol. This can be counterintuitive, especially given Swift's common practice of implementing protocols in type extensions. If you follow this approach without a deep understanding of actor isolation mechanics, you might find yourself in a situation where you expect the class to be isolated, but it remains fully accessible across threads.

This is a logical behavior of the language, as an extension by definition cannot (and should not) alter the isolation of the entity it extends. However, it's a nuanced detail that developers should carefully consider when designing the concurrency architecture of their Swift code.

---

### When Partial Isolation Might Be Favorable

1. **Shadowing or multiple protocol conformances:** Suppose `Store` also needs to conform to another protocol that allows or requires background execution. By isolating just `MainActorIsolated` methods in an extension, you can keep other protocols’ methods from forcing a main-thread context unnecessarily.  
2. **Performance considerations:** Some logic might be CPU-intensive and better suited for a background actor or concurrent thread. Partial isolation ensures only the UI-bound or strictly main-thread-relevant code is protected by `@MainActor`.

---

### When Whole Class Isolation Is More Favorable

1. **UI-centric data objects:** Often, `Store` is closely bound to your views. Declaring the entire class as `@MainActor` or conforming within its body ensures every property and method is safely on the main thread.  
2. **Compile-time safety:** You get broader compiler checks that **all** class interactions remain main-thread–safe. In Swift 6, for instance, code that tries to mutate a main-actor–isolated property from a background context raises a compile-time error.

---

### Comparison Table

| Component                      | Whole Class Is MainActor                           | Partial Conformance via Extension                         |
|--------------------------------|----------------------------------------------------|------------------------------------------------------------|
| Actor Isolation Coverage       | Entire class (all properties & methods)           | Only methods in the `MainActorIsolated` protocol          |
| Typical Use Case               | UI-bound data, SwiftUI models, full safety needed | Mixed responsibilities, partial UI tasks, partial isolation|
| Compiler-Assisted Safety       | Strong guarantees                                  | Limited to the scope of protocol methods                   |
| Potential Data Races          | Very unlikely                                      | Possible if non-isolated parts incorrectly access UI data  |
| Ideal Scenarios               | AppState, View Models, user-facing data            | Shared modules, selective concurrency, partial UI updates  |

---

### Integration with Swift Observation

```swift
@Observable class Store {
    // Automatically syncs property changes (though the Main Thread Checker may not catch all concurrency)
    var value: Date = .now
}
```

It also seems like Swift's @Observable sends property change notifications on the main thread. However, this observation-based behavior is more of an empirical pattern noticed rather than a guaranteed thread-safety mechanism. Therefore, you should still explicitly use @MainActor or implement partial isolation approaches to ensure truly safe concurrency in your Swift code.

---

### Swift 6 Enforcement

With Swift 6, the compiler can help you spot nonisolated usage of main-actor–isolated properties or methods—especially if you accidentally make calls from outside the main actor context. For example:

```swift
extension Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
    // Sending main actor-isolated 'self.store' to nonisolated instance method 'performUpdate(with:)'
    // risks causing data races between nonisolated and main actor-isolated uses
        await executeInternalUpdate(with: date)
    }
}
```

or, if `performUpdate(with:)` is not isolated to main-actor through protocol or other means:

```swift
Button("Trigger Update") {
    Task {
    // Sending main actor-isolated 'self.store' to nonisolated instance method 'performUpdate(with:)'
    // risks causing data races between nonisolated and main actor-isolated uses
        await store.performUpdate(with: .now)
    }
}
```

---

When working with UI-related data in Swift, developers have compelling options for managing actor isolation. For classes primarily handling UI state, marking the entire class with @MainActor offers the most robust approach, providing strong compile-time safety and a straightforward mental model for concurrency management. When your class has more diverse responsibilities, partial isolation through protocol extensions becomes a valuable technique, allowing you to selectively constrain specific methods to the main actor while maintaining flexibility for other parts of your code.

The emerging Swift 6 compiler brings an additional layer of protection, with enhanced static analysis that can proactively identify potential concurrency issues before runtime. These intelligent checks help developers catch and resolve potential data races early in the development process.

Ultimately, mastering these actor isolation patterns is crucial for writing reliable, thread-safe Swift code. Whether you choose whole-class isolation or more granular approaches, understanding these mechanisms empowers developers to build more predictable and maintainable concurrent applications, significantly reducing the risk of unexpected threading complications.
