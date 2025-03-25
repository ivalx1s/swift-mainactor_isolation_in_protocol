Swift Actor Isolation Inheritance Demo

Sample app demonstrating non-intuitive behavior of global actor isolation inheritance when conforming classes to protocols with global actor (e.g. @MainActor) isolation attributes. Reveals subtle threading issues that can occur with different conformance patterns. Aslo demostrates how these issues are automatically solved in Swift 6 concurrency model.
