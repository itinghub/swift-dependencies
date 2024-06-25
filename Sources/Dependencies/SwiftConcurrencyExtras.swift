import Foundation

///pick form
///https://github.com/pointfreeco/swift-concurrency-extras/blob/main/Sources/ConcurrencyExtras
///
///UncheckedSendable
///LockIsolated
///ActorIsolated



/// A generic wrapper for turning any non-`Sendable` type into a `Sendable` one, in an unchecked
/// manner.
///
/// Sometimes we need to use types that should be sendable but have not yet been audited for
/// sendability. If we feel confident that the type is truly sendable, and we don't want to blanket
/// disable concurrency warnings for a module via `@preconcurrency import`, then we can selectively
/// make that single type sendable by wrapping it in `UncheckedSendable`.
///
/// > Note: By wrapping something in `UncheckedSendable` you are asking the compiler to trust you
/// > that the type is safe to use from multiple threads, and the compiler cannot help you find
/// > potential race conditions in your code.
///
/// To synchronously isolate a value with a lock, see ``LockIsolated``.
#if swift(>=5.10)
  @available(iOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    macOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )@available(tvOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    watchOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )
#endif
@dynamicMemberLookup
@propertyWrapper
public struct UncheckedSendable<Value>: @unchecked Sendable {
  /// The unchecked value.
  public var value: Value

  /// Initializes unchecked sendability around a value.
  ///
  /// - Parameter value: A value to make sendable in an unchecked way.
  public init(_ value: Value) {
    self.value = value
  }

  public init(wrappedValue: Value) {
    self.value = wrappedValue
  }

  public var wrappedValue: Value {
    _read { yield self.value }
    _modify { yield &self.value }
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  public subscript<Subject>(dynamicMember keyPath: KeyPath<Value, Subject>) -> Subject {
    self.value[keyPath: keyPath]
  }

  public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Subject {
    _read { yield self.value[keyPath: keyPath] }
    _modify { yield &self.value[keyPath: keyPath] }
  }
}

#if swift(>=5.10)
  @available(iOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    macOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )@available(tvOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    watchOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )
#endif
extension UncheckedSendable: Equatable where Value: Equatable {}

#if swift(>=5.10)
  @available(iOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    macOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )@available(tvOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    watchOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )
#endif
extension UncheckedSendable: Hashable where Value: Hashable {}

#if swift(>=5.10)
  @available(iOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    macOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )@available(tvOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    watchOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )
#endif
extension UncheckedSendable: Decodable where Value: Decodable {
  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.singleValueContainer()
      self.init(wrappedValue: try container.decode(Value.self))
    } catch {
      self.init(wrappedValue: try Value(from: decoder))
    }
  }
}

#if swift(>=5.10)
  @available(iOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    macOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )@available(tvOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead.")@available(
    watchOS, deprecated: 9999, message: "Use 'nonisolated(unsafe) let', instead."
  )
#endif
extension UncheckedSendable: Encodable where Value: Encodable {
  public func encode(to encoder: Encoder) throws {
    do {
      var container = encoder.singleValueContainer()
      try container.encode(self.wrappedValue)
    } catch {
      try self.wrappedValue.encode(to: encoder)
    }
  }
}


/// A generic wrapper for isolating a mutable value with a lock.
///
/// If you trust the sendability of the underlying value, consider using ``UncheckedSendable``,
/// instead.
@dynamicMemberLookup
public final class LockIsolated<Value>: @unchecked Sendable {
  private var _value: Value
  private let lock = NSRecursiveLock()

  /// Initializes lock-isolated state around a value.
  ///
  /// - Parameter value: A value to isolate with a lock.
  public init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self._value = try value()
  }

  public subscript<Subject: Sendable>(dynamicMember keyPath: KeyPath<Value, Subject>) -> Subject {
    self.lock.sync {
      self._value[keyPath: keyPath]
    }
  }

  /// Perform an operation with isolated access to the underlying value.
  ///
  /// Useful for modifying a value in a single transaction.
  ///
  /// ```swift
  /// // Isolate an integer for concurrent read/write access:
  /// var count = LockIsolated(0)
  ///
  /// func increment() {
  ///   // Safely increment it:
  ///   self.count.withValue { $0 += 1 }
  /// }
  /// ```
  ///
  /// - Parameter operation: An operation to be performed on the the underlying value with a lock.
  /// - Returns: The result of the operation.
  public func withValue<T: Sendable>(
    _ operation: @Sendable (inout Value) throws -> T
  ) rethrows -> T {
    try self.lock.sync {
      var value = self._value
      defer { self._value = value }
      return try operation(&value)
    }
  }

  /// Overwrite the isolated value with a new value.
  ///
  /// ```swift
  /// // Isolate an integer for concurrent read/write access:
  /// var count = LockIsolated(0)
  ///
  /// func reset() {
  ///   // Reset it:
  ///   self.count.setValue(0)
  /// }
  /// ```
  ///
  /// > Tip: Use ``withValue(_:)`` instead of ``setValue(_:)`` if the value being set is derived
  /// > from the current value. That is, do this:
  /// >
  /// > ```swift
  /// > self.count.withValue { $0 += 1 }
  /// > ```
  /// >
  /// > ...and not this:
  /// >
  /// > ```swift
  /// > self.count.setValue(self.count + 1)
  /// > ```
  /// >
  /// > ``withValue(_:)`` isolates the entire transaction and avoids data races between reading and
  /// > writing the value.
  ///
  /// - Parameter newValue: The value to replace the current isolated value with.
  public func setValue(_ newValue: @autoclosure @Sendable () throws -> Value) rethrows {
    try self.lock.sync {
      self._value = try newValue()
    }
  }
}

extension LockIsolated where Value: Sendable {
  /// The lock-isolated value.
  public var value: Value {
    self.lock.sync {
      self._value
    }
  }
}

@available(*, deprecated, message: "Lock isolated values should not be equatable")
extension LockIsolated: Equatable where Value: Equatable {
  public static func == (lhs: LockIsolated, rhs: LockIsolated) -> Bool {
    lhs.value == rhs.value
  }
}

@available(*, deprecated, message: "Lock isolated values should not be hashable")
extension LockIsolated: Hashable where Value: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.value)
  }
}

extension NSRecursiveLock {
  @inlinable @discardableResult
  @_spi(Internals) public func sync<R>(work: () throws -> R) rethrows -> R {
    self.lock()
    defer { self.unlock() }
    return try work()
  }
}


/// A generic wrapper for isolating a mutable value to an actor.
///
/// This type is most useful when writing tests for when you want to inspect what happens inside an
/// async operation.
///
/// For example, suppose you have a feature such that when a button is tapped you track some
/// analytics:
///
/// ```swift
/// struct AnalyticsClient {
///   var track: (String) async -> Void
/// }
///
/// class FeatureModel: ObservableObject {
///   let analytics: AnalyticsClient
///   // ...
///   func buttonTapped() {
///     // ...
///     await self.analytics.track("Button tapped")
///   }
/// }
/// ```
///
/// Then, in tests we can construct an analytics client that appends events to a mutable array
/// rather than actually sending events to an analytics server. However, in order to do this in a
/// safe way we should use an actor, and `ActorIsolated` makes this easy:
///
/// ```swift
/// func testAnalytics() async {
///   let events = ActorIsolated<[String]>([])
///   let analytics = AnalyticsClient(
///     track: { event in await events.withValue { $0.append(event) } }
///   )
///   let model = FeatureModel(analytics: analytics)
///   model.buttonTapped()
///   await events.withValue {
///     XCTAssertEqual($0, ["Button tapped"])
///   }
/// }
/// ```
///
/// To synchronously isolate a value, see ``LockIsolated``.
@available(*, deprecated, message: "Use 'LockIsolated' instead.")
public final actor ActorIsolated<Value> {
  /// The actor-isolated value.
  public var value: Value

  /// Initializes actor-isolated state around a value.
  ///
  /// - Parameter value: A value to isolate in an actor.
  public init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
    self.value = try value()
  }

  /// Perform an operation with isolated access to the underlying value.
  ///
  /// Useful for modifying a value in a single transaction.
  ///
  /// ```swift
  /// // Isolate an integer for concurrent read/write access:
  /// let count = ActorIsolated(0)
  ///
  /// func increment() async {
  ///   // Safely increment it:
  ///   await self.count.withValue { $0 += 1 }
  /// }
  /// ```
  ///
  /// > Tip: Because XCTest assertions don't play nicely with Swift concurrency, `withValue` also
  /// > provides a handy interface to peek at an actor-isolated value and assert against it:
  /// >
  /// > ```swift
  /// > let didOpenSettings = ActorIsolated(false)
  /// > let model = withDependencies {
  /// >   $0.openSettings = { await didOpenSettings.setValue(true) }
  /// > } operation: {
  /// >   FeatureModel()
  /// > }
  /// > await model.settingsButtonTapped()
  /// > await didOpenSettings.withValue { XCTAssertTrue($0) }
  /// > ```
  ///
  /// - Parameter operation: An operation to be performed on the actor with the underlying value.
  /// - Returns: The result of the operation.
  public func withValue<T>(
    _ operation: @Sendable (inout Value) throws -> T
  ) rethrows -> T {
    var value = self.value
    defer { self.value = value }
    return try operation(&value)
  }

  /// Overwrite the isolated value with a new value.
  ///
  /// ```swift
  /// // Isolate an integer for concurrent read/write access:
  /// let count = ActorIsolated(0)
  ///
  /// func reset() async {
  ///   // Reset it:
  ///   await self.count.setValue(0)
  /// }
  /// ```
  ///
  /// > Tip: Use ``withValue(_:)`` instead of `setValue` if the value being set is derived from the
  /// > current value. This isolates the entire transaction and avoids data races between reading
  /// > and writing the value.
  ///
  /// - Parameter newValue: The value to replace the current isolated value with.
  public func setValue(_ newValue: @autoclosure @Sendable () throws -> Value) rethrows {
    self.value = try newValue()
  }
}
