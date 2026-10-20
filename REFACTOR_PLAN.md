# KeyValueStorage 4.0 — Refactor Plan

## Status (2026-10-17)

- **First up: name resolvers.** To be specified.
- **Done: phases 0–6, the source side.** The synchronous `KeyValueDataStorage` with `init(scope:backingStorage:)`, `StorageDirectoryResolving`, every storage on its backing storage, the global actors removed, and `KeychainWrapper.swift` deleted.
- **Added: `UbiquitousStorage`** (§5.7), on the same pattern.
- **Updated: the public API test target**, which now exercises Keychain and Ubiquitous through in-memory backing storages.
- **Open: the mock-based unit tests for phases 1–6.** `Tests/KeyValueStorageTests` is still on the 3.x API and doesn't compile.
- **Next: phases 7–9**, the coding, isolation and facade layers. The observation and unified layers still emit isolated-conformance warnings on Swift 6.2+ compilers, because the storage protocol is no longer `Sendable`.

## 1. Context

The library offers one consistent way to work with storages of very different nature (UserDefaults, Keychain, files, SQLite, memory). The 3.x design made every storage a global-actor-isolated, `@unchecked Sendable` class with `async` methods, and mixed system calls, scope resolution and storage logic in the same types. That made the storages hard to test (subclassed `FileManager`/`UserDefaults` mocks, real keychain needed) and forced `async` and actor hops on apps that are single-threaded anyway.

4.0 is a clean rewrite with **no backward compatibility** (the package has no external users yet). Goals:

1. **Consistency:** every storage has the same shape: same initializers, same scope model, same operations.
2. **Testability:** all storage logic sits behind injectable backing storages, so every storage class reaches 100% branch coverage with mocks.
3. **Modern concurrency:** storages are synchronous and not `Sendable`. A main-actor app uses them directly and the compiler keeps them there. Isolation is an explicit, opt-in actor wrapper.
4. **Composition over inheritance:** small layers that each do one thing, `final` types, no `open`/`required` hierarchies.

## 2. Decisions (and why)

| # | Decision | Rationale |
|---|---|---|
| D1 | No backward compatibility; ship as **4.0.0** | Paths, suite names, APIs and defaults all change; there are no users to migrate. |
| D2 | **Storages are synchronous, not `Sendable`, not isolated.** No global actors (`FileActor`, `SQLiteActor`, `KeychainActor`, `UserDefaultsActor`, `InMemoryActor`, `CodingStorageActor`). | Most apps are single-threaded, especially with Swift 6.2's default `MainActor` isolation. A non-`Sendable` value can't be sent to another actor or task unless it's disconnected, so single-threaded use is compiler-checked, not hoped for. Synchronous calls cost nothing. |
| D3 | **One opt-in isolation wrapper: `IsolatedKeyValueStorage<Wrapped>`, a generic actor.** No `LockedStorage`. | Synchronous access from many threads is a GCD-era need: sync use is covered by D2, shared use is `async` anyway. A lock blocks the caller (including the main thread) during I/O, needs a recursive lock for observers, and is a second way to do the same thing. The actor moves I/O off the caller and the compiler enforces ownership (`sending`). |
| D4 | **Isolation is the outermost layer**, wrapping the coding storage. | Coding must work without isolation (D2). With synchronous coders, encoding inside the actor costs microseconds next to the I/O. Change events emitted inside the isolated operation come out in commit order. |
| D5 | **Locks only inside building blocks**, never in the public API: the shared `DefaultInMemoryBackingStoreWrapper` backing, the observation registry, the isolated facade's cache. | These are process-wide states that several instances share, which the type system can't see. |
| D6 | **Backing storages:** one protocol per storage that is a minimal, **location-free** interface to the system. The storage resolves its scope and passes the resulting location (URL, suite name, query, container) in. Default adapters are thin and as branch-free as possible. | The backing and the scope can't disagree. Scope resolution (the main logic) is reachable from mocks. Adapters need only integration tests. |
| D7 | **Storages depend only on their backing.** Every value read from the environment comes through it: directories, App Group containers, the app identifier. | 100% mock coverage, including path and suite resolution. |
| D8 | The protocol requires `init(scope:)` and `init()`, with `init()` defaulting to `.default`. Each storage adds a public `init(scope:backingStorage:)` taking its `XBackingStore`, and its `init(scope:)` passes a new `DefaultXBackingStoreWrapper`. **`scope` is non-optional.** | Consistent API; the scope is always known; `nil` and `.default` can't become two different storages. |
| D9 | **App scopes include the app identifier** (bundle identifier, or process name for command-line tools) in paths and suite names; App Group scopes don't. | Same behaviour on every platform: on macOS without App Sandbox, `~/Library`, the temporary directory and `~/Documents` are shared by all apps. |
| D10 | **Synchronous `DataCoder`.** | JSON and PropertyList coding are synchronous; `async` only forced hops and blocked locking. |
| D11 | **Observation is built into `KeyValueCodingStorage`** and always available. Delete `KeyValueObservableStorage` and `ObservableUnifiedStorageFactory`. | An empty registry costs one dictionary lookup per write. It removes a subclass, a factory and the `publisher(...) -> nil` APIs. |
| D12 | `set(_:forKey:)` is a protocol extension, not a requirement. | It's the same five lines in every storage, and five copies to test. |
| D13 | Storages and layers are `final class`, with no `open`/`required`. | Extension points are protocols and backings, not subclassing. |
| D14 | Keep **Swift tools 6.0** and the Xcode 16 CI job. Don't mark types `nonisolated`: that needs Swift 6.1, and it's redundant without default `MainActor` isolation. | Toolchain support stays as it is. |
| D15 | Backing protocols are **not** `Sendable`. Only the shared default `DefaultInMemoryBackingStoreWrapper` is (`@unchecked Sendable` + lock). | Storages aren't `Sendable`, so a backing travels with its storage. Region isolation stops one backing from being shared by storages on different actors, and mocks don't need `@unchecked Sendable`. |
| D16 | **No iCloud Drive scope and no file coordination.** No `CoordinatedFileStorage`, and no `isCoordinated` key option. | **Coordination:** every write is an atomic replace, so readers in other processes never see a partial file, and no `NSFilePresenter` watches the package-owned folders; coordinating would only add a round trip to a daemon on every operation. A per-key option, or a second storage type over the same folder, would let uncoordinated writes slip in. Cross-process read-modify-write belongs to SQLite. **iCloud Drive:** files there may not be downloaded yet, conflict across devices, need `url(forUbiquityContainerIdentifier:)` (which must not run on the main thread) and require coordination. That breaks the synchronous, local-first contract. Synced data uses `UbiquitousStorage`, `KeychainStorage` with `isSynchronizable`, or CloudKit outside this library. If it's ever revisited, coordination goes into a `CoordinatedFileBackingStorage` adapter, always on for that scope. |

## 3. Target architecture

```
UnifiedStorage / IsolatedUnifiedStorage   facade: key → (storage type, scope) → one storage each
          │
IsolatedKeyValueStorage<Wrapped>          OPTIONAL actor, outermost; withStorage { … } + typed conveniences
          │
KeyValueCodingStorage<Storage>            sync, not Sendable: Value ↔ Data, atomic update, observation
          │
FileStorage · SQLiteStorage · KeychainStorage · UserDefaultsStorage · InMemoryStorage
          │                               sync, not Sendable: ALL storage logic (scope → location,
          │                               key rules, error mapping, clear semantics)
XxxBackingStorage (protocol)              the system and nothing else; default adapter + mocks in tests
```

Usage:

```swift
// Main-actor app: synchronous, no isolation
let settings = try KeyValueCodingStorage(storage: FileStorage(scope: .default), coder: JSONDataCoder())
try settings.save(user, forKey: userKey)

// Shared across actors: I/O never runs on the caller, and no unisolated reference survives (`sending`)
let shared = IsolatedKeyValueStorage(try KeyValueCodingStorage(storage: SQLiteStorage(scope: .default)))
try await shared.save(user, forKey: userKey)
try await shared.withStorage { try $0.update(counterKey) { ($0 ?? 0) + 1 } }   // atomic read-modify-write

// Facade
let storage = UnifiedStorage()
try storage.save(token, forKey: KeychainKey<String>(key: .init(name: "token")))
```

## 4. Core: the data storage protocol

`Sources/KeyValueStorage/Core/KeyValueDataStorage.swift`

```swift
public protocol KeyValueDataStorage {
    associatedtype Key: KeyValueDataStorageKey             // Hashable & Sendable
    associatedtype Scope: KeyValueDataStorageScope         // Hashable & Sendable, static var default
    associatedtype Error: KeyValueDataStorageError         // Error & Sendable

    var scope: Scope { get }

    init() throws
    init(scope: Scope) throws

    func fetch(forKey key: Key) throws -> Data?
    func save(_ value: Data, forKey key: Key) throws
    func delete(forKey key: Key) throws
    func clear() throws
}

public extension KeyValueDataStorage {
    init() throws {
        try self.init(scope: .default)
    }

    func set(_ value: Data?, forKey key: Key) throws {
        if let value { try save(value, forKey: key) } else { try delete(forKey: key) }
    }
}
```

- Remove `IsolatedKeyValueDataStorage` typealias, `async` from all requirements and initializers, `Sendable` from the protocol.
- Keep `KeyValueDataStorageScope.defaultContainerName = "KeyValueStorage"`.
- Remove `KeyValueDataStorageScope.appIdentifier` (it reads `Bundle.main` directly). The app identifier comes from the backing (D7).
- Backing stores aren't part of the protocol. Each storage's `init(scope:backingStorage:)` takes the existential (`any FileBackingStore`, …), so the storages stay non-generic, and its `init(scope:)` passes `DefaultXBackingStoreWrapper()`.

### Shared directory resolution (File and SQLite)

`Sources/KeyValueStorage/Core/StorageDirectory.swift` (exists; change it to use a resolver instead of `FileManager`)

```swift
public protocol StorageDirectoryResolving {
    var appIdentifier: String { get }                                  // Bundle.main.bundleIdentifier ?? processName
    var temporaryDirectory: URL { get }                                      // FileManager.temporaryDirectory
    func directory(for directory: FileManager.SearchPathDirectory) -> URL?   // urls(for:in: .userDomainMask).first
    func groupDirectory(for groupId: String) -> URL?                         // containerURL(forSecurityApplicationGroupIdentifier:)
}

enum StorageDirectory {   // internal; unchanged cases
    func url(storageFolder: String, resolver: some StorageDirectoryResolving) throws -> URL   // throws Failure
}
```

`FileBackingStore` and `SQLiteBackingStore` both refine `StorageDirectoryResolving`.

## 5. Storages

Common shape for every storage, matching `FileStorage` today:

```
Storages/<Name>/
  <Name>.swift                 final class, logic only
  <Name>+Scope.swift           Container typealias, AppScope, Scope (docs as today)
  <Name>+Error.swift
  <Name>+Key.swift
  BackingStorage/<Name>BackingStorage.swift   protocol + Default adapter (internal)
```

**Backing vocabulary.** Backing protocols use short names that are the same across storages, instead of copying each system API. Each member's doc comment names the system call it maps to. Default adapters wrap system types rather than extending them, so the library adds no methods to `UserDefaults` and similar types.

| | read | write | remove | list | remove all |
|---|---|---|---|---|---|
| UserDefaults suite, Ubiquitous, SQLite database | `read(forKey:)` | `write(_:forKey:)` | `remove(forKey:)` | `keys()` (UserDefaults, Ubiquitous) | `removeAll()` (SQLite) |
| InMemory | `read(forKey:in:)` | `write(_:forKey:in:)` | `remove(forKey:in:)` | — | `removeAll(in:)` |
| File | `read(at:)` | `write(_:at:options:)` | `remove(at:)` | `contents(at:)` | — |
| Keychain (queries) | `read(_:)` | `add(_:)` / `update(_:with:)` | `remove(_:)` | — | — |

The setup members are `directory(for:)`, `groupDirectory(for:)`, `appIdentifier` and `temporaryDirectory` (directory lookups), `createDirectory(at:)` (always creates intermediate directories), SQLite's `open(at:)`, and UserDefaults' `standard` and `suite(named:)`.

### 5.1 Scope → location (unchanged from the current docs)

| Storage | Scope | Resolves to |
|---|---|---|
| File | `.app(.applicationSupport/.cache/.documents/.temporary(c))` | `<base>/<appId>/<c>/Files/<encoded key>` |
| File | `.appGroup(g, c)` | `<group container g>/<c>/Files/<encoded key>` |
| SQLite | same as File, plus `protection:` (default `.inherited`) | `…/<c>/SQLite/KeyValueStorage.sqlite` (+ `-wal`, `-shm`), opened in the scope's protection class |
| UserDefaults | `.app(.standard)` | `UserDefaults.standard` |
| UserDefaults | `.app(.suite(c))` | suite `"<appId>.<c>"` |
| UserDefaults | `.appGroup(g, c)` | suite `g`, keys stored as `"<c with % → %25, / → %2F>/<key>"` |
| Keychain | `.app(c)` | `kSecAttrService = c` (`nil` → no service filter), no access group |
| Keychain | `.appGroup(g, c)` | `kSecAttrService = c`, `kSecAttrAccessGroup = g` |
| InMemory | `.app(c)` | container `c` in the backing |
| Ubiquitous | `.shared(c)` | `NSUbiquitousKeyValueStore.default` (the store of the target's kvstore entitlement), keys stored as `"<c, escaped like UserDefaults>/<key>"` (`nil` → keys as is) |

Defaults: File/SQLite `.app(.applicationSupport(container: "KeyValueStorage"))`, UserDefaults `.app(.suite(container: "KeyValueStorage"))`, Keychain and InMemory `.app(container: "KeyValueStorage")`, Ubiquitous `.shared(container: "KeyValueStorage")`.

### 5.2 KeychainStorage (backing already exists; start here)

Backing (exists): `KeychainBackingStore` with `read`, `add`, `update` and `remove`, each taking a `KeychainQuery` and returning a `KeychainOperationStatus`; the default is `DefaultKeychainBackingStoreWrapper`.

Changes:
- `final class KeychainStorage: KeyValueDataStorage`, `init(scope:backingStorage:)`, and `convenience init(scope:)` passing `DefaultKeychainBackingStoreWrapper()`.
- Remove `nonisolated` on the type, `@unchecked Sendable`, `required convenience init()`, and the `set` implementation.
- Drop `: Sendable` from `KeychainBackingStore` (D15). Make `KeychainOperationStatus` `Sendable`.
- **Delete `Helpers/KeychainWrapper.swift`** (no longer referenced).
- Extract the repeated query construction into a private `baseQuery(for key:)` / `serviceQuery()` helper.

Logic owned by the storage (all mock-tested): query fields per scope, synchronizable mapping, accessibility on add and update, status → result/error mapping.

### 5.3 FileStorage

Backing (exists, extend): `FileBackingStore: StorageDirectoryResolving` + `read(at:)`, `write(_:at:options:)`, `remove(at:)`, `createDirectory(at:)` and `contents(at:)`. The default adapter adds the four resolver members.

Changes:
- `final class`, remove `@FileActor` and `@unchecked Sendable`, `init(scope:backingStorage:)`.
- `root(for:)` uses `StorageDirectory.url(storageFolder:resolver: backingStorage)`; no `FileManager.default` in the storage.
- Keep: key validation, file name encoding, protection → writing options, lazy directory creation, `isProtectedDataUnavailable` mapping.
- `writingOptions(for:)` has a `#available(macOS 11, *)` branch that can't run on any CI host. **Proposal: raise the macOS minimum to 11** (see Open decisions), which removes the only untestable branch.

### 5.4 UserDefaultsStorage

New backing:

```swift
public protocol UserDefaultsBackingStore {
    var appIdentifier: String { get }
    var standard: any UserDefaultsSuite { get }                     // UserDefaults.standard
    func suite(named name: String) -> (any UserDefaultsSuite)?      // UserDefaults(suiteName:)
}

public protocol UserDefaultsSuite: AnyObject {
    func read(forKey key: String) -> Data?          // UserDefaults.data(forKey:)
    func write(_ data: Data, forKey key: String)    // UserDefaults.set(_:forKey:)
    func remove(forKey key: String)                 // UserDefaults.removeObject(forKey:)
    func keys() -> [String]                         // UserDefaults.dictionaryRepresentation().keys
}

final class DefaultUserDefaultsSuite: UserDefaultsSuite { /* wraps a UserDefaults */ }
```

`standard` and `suite(named:)` are separate so the adapter has no branch. The storage keeps suite naming, the App Group key namespace and prefix-scoped `clear()`.

### 5.5 InMemoryStorage

New backing:

```swift
public protocol InMemoryBackingStore {
    func read(forKey key: String, in container: String) -> Data?
    func write(_ data: Data, forKey key: String, in container: String)
    func remove(forKey key: String, in container: String)
    func removeAll(in container: String)
}

public final class DefaultInMemoryBackingStoreWrapper: InMemoryBackingStore, @unchecked Sendable {
    public static let shared = DefaultInMemoryBackingStoreWrapper()   // default backing; NSLock-protected dictionary
}
```

This removes `nonisolated(unsafe) static var container`, fixes the race between instances on different actors (D5), and lets tests inject a fresh backing instead of resetting global state.

### 5.6 SQLiteStorage

New backing and wrapper. All SQLite handling moves out of the storage:

```swift
public protocol SQLiteBackingStore: StorageDirectoryResolving {
    func createDirectory(at url: URL) throws                     // withIntermediateDirectories: true
    func open(at url: URL, protection: FileProtectionType?) throws -> any SQLiteDatabase   // nil: default class
}

public protocol SQLiteDatabase: AnyObject {                     // closes when released
    func read(forKey key: String) throws -> Data?
    func write(_ data: Data, forKey key: String) throws
    func remove(forKey key: String) throws
    func removeAll() throws
}

public struct SQLiteError: Error, Sendable, Equatable { public let code: Int32; public let message: String }
```

- `DefaultSQLiteBackingStoreWrapper` (internal, default backing): directory resolution via `FileManager`; `open(at:)` returns a `DefaultSQLiteDatabase`. Both live in `SQLiteBackingStore.swift`, mirroring `DefaultUserDefaultsBackingStoreWrapper` and `DefaultUserDefaultsSuite`: an entry object without state that opens a handle for one location.
- `DefaultSQLiteDatabase` (internal): today's `Connection`: `sqlite3_open_v2` with `FULLMUTEX`, WAL, a 1 s busy timeout, the table, four prepared statements, NUL-safe key binding, `zeroblob` for empty data, and `run`/`reset`.
- `SQLiteStorage`: resolves the URL, creates the directory, opens the database, and maps `SQLiteError` → `.sqlite(code:message:)` and other errors → `.other`.
- The prepared statements make an instance unsafe to share between threads, which matches D2. Two instances have separate connections.
- **Protection:** `SQLiteStorage.Protection` (a separate enum, mirroring `FileStorage.Key.Protection`) is part of the scope: `.app(_, protection:)` and `.appGroup(_, _, protection:)`, defaulting to `.inherited`. It's per database, not per key, because every key shares one file. The storage maps it to `FileProtectionType?`, and `DefaultSQLiteDatabase` turns that into a `SQLITE_OPEN_FILEPROTECTION_*` flag, which covers the `-wal` and `-shm` files too. Verified on macOS (arm64): reopening with another flag changes an existing database's class, so protection is re-applied on every open, like `FileStorage` re-applies it on every save. `.complete` makes even an open database fail while the device is locked. Still to confirm on a locked iOS device: which result code such failures produce, which could map to a `.protectedDataUnavailable` error like `FileStorage`'s.

### 5.7 UbiquitousStorage (new)

Backing: `UbiquitousBackingStore` with `read(forKey:)`, `write(_:forKey:)`, `remove(forKey:)`, `keys()` and `synchronize()`. The default adapter, `DefaultUbiquitousBackingStoreWrapper`, calls `NSUbiquitousKeyValueStore.default`.

- **Availability:** `@available(watchOS 9.0, *)`, matching `NSUbiquitousKeyValueStore`; the package supports watchOS 6. Raising the watchOS minimum to 9 would remove the annotations (see Open decisions).
- **Store and sharing:** a process can reach exactly one store, `NSUbiquitousKeyValueStore.default`, chosen only by its signed `com.apple.developer.ubiquity-kvstore-identifier` entitlement and the Apple Account. There's no API to pick a store, App Groups have no effect on it, and on iOS the code can't read the entitlement.
- **Scope:** so the scope has one case, `.shared(container:)`. The container is a key namespace (the escaping is shared with UserDefaults through `KeyNamespace`), and `nil` means raw keys. The docs explain the setup:
  - one app keeps Xcode's default identifier, `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`;
  - an app and its extensions, or apps of one team, set the same value in every target's entitlements;
  - an extension that keeps its default identifier silently gets its own store.
- **Limits the storage enforces**, all before calling the store:
  - the stored key, prefix included, must be at most 128 UTF-16 units, or it throws `.invalidKey`. The store would raise an Objective-C exception, which crashes the app.
  - a value must be at most 1 MB, or it throws `.valueTooLarge`.
- **Limits it documents but can't enforce:** 1024 keys and 1 MB in total. Exceeding them fails silently and is reported only through `didChangeExternallyNotification` with `NSUbiquitousKeyValueStoreQuotaViolationChange`.
- **`synchronize()`** is exposed as a passthrough and returns `false` when the app lacks the entitlement.
- **Not observed yet:** external changes, `didChangeExternallyNotification`, aren't published to observers. That's a candidate for the observation work in §6.3.

## 6. Coding layer

`Sources/KeyValueStorage/Coding/`

### 6.1 Coders

```swift
public protocol DataCoder: Sendable {
    func encode<Value: Encodable>(_ value: Value) throws -> Data
    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value
}
```

`JSONDataCoder`, `PropertyListDataCoder` and `RawDataCoder` become synchronous. Passing the type explicitly removes the `as Value` workaround in `fetch`.

### 6.2 KeyValueCodingStorage

```swift
public final class KeyValueCodingStorage<Storage: KeyValueDataStorage> {
    public var scope: Storage.Scope { get }
    public init(storage: Storage, coder: DataCoder = RawDataCoder())

    public func fetch<V: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, V>) throws -> V?
    public func save<V: CodingValue>(_ value: V, forKey key: KeyValueCodingStorageKey<Storage, V>) throws
    public func set<V: CodingValue>(_ value: V?, forKey key: KeyValueCodingStorageKey<Storage, V>) throws
    public func delete<V: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, V>) throws
    public func clear() throws
    @discardableResult
    public func update<V: CodingValue>(_ key: KeyValueCodingStorageKey<Storage, V>, _ transform: (V?) throws -> V?) throws -> V?

    public func publisher<V: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, V>, includingCurrentValue: Bool = true) throws -> KeyValuePublisher<V?>
    public func stream<V: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, V>, includingCurrentValue: Bool = true) throws -> AsyncStream<V?>
}
```

`update` reads, transforms and writes in one call. It's atomic when the storage is used from one isolation domain, or inside `IsolatedKeyValueStorage`. If `transform` returns `nil`, the key is deleted.

### 6.3 Observation (replaces `KeyValueObservableStorage`)

- **Registry:** an internal `ObservationRegistry` keyed by (storage type, scope, storage key), shared across the process and protected by a lock (D5). Changes made through any `KeyValueCodingStorage` instance in the process are published, as today.
- **Events:** a change to key K reaches every observer of K, whatever value type it was written with. An event carries the new `Data?` (and the original value as a fast path); each observer decodes into its own type.
- **Delivery:** synchronous, on the thread or actor that made the write, after the write succeeds. Observers are snapshotted under the registry lock and called **outside** it, so a callback can write to the storage without deadlocking. Inside `IsolatedKeyValueStorage`, delivery runs on the actor in commit order.
- **Current value:** register first, then read synchronously, then emit the value read unless a change came in meanwhile. Keep one version counter for writes from other instances. Most of today's async seeding complexity goes away.
- **API:** keep `KeyValuePublisher` (a `Sendable` wrapper, needed when returning from the actor) and `AsyncStream`.
- **Limits** (document them): changes from other processes (extensions), or written directly to the system (UserDefaults, keychain, files), aren't observed. Ordering across *different* instances on *different* actors isn't guaranteed.

## 7. Isolation layer

`Sources/KeyValueStorage/Isolation/IsolatedKeyValueStorage.swift`

```swift
public protocol KeyValueScopeProviding {            // KeyValueDataStorage and KeyValueCodingStorage conform
    associatedtype Scope: KeyValueDataStorageScope
    var scope: Scope { get }
}

public actor IsolatedKeyValueStorage<Wrapped: KeyValueScopeProviding> {
    public nonisolated let scope: Wrapped.Scope
    private let wrapped: Wrapped

    public init(_ wrapped: sending Wrapped)
    public func withStorage<T: Sendable>(_ body: @Sendable (Wrapped) throws -> T) throws -> T
}

// Typed conveniences: fetch/save/set/delete/clear/update/publisher/stream
extension IsolatedKeyValueStorage {
    public func fetch<S, V: CodingValue>(forKey key: KeyValueCodingStorageKey<S, V>) throws -> V?
        where Wrapped == KeyValueCodingStorage<S>
    // …
}
// Byte-level conveniences where Wrapped: KeyValueDataStorage
```

- `sending` (Swift 6.0) makes sure the caller gives up the storage.
- Methods never suspend inside, so every operation is atomic and actor reentrancy can't interleave them.
- **Document:** the actor runs blocking I/O on a thread of the Swift concurrency pool. That's fine for milliseconds of file, SQLite or keychain work. If keychain access control with user presence (biometric prompts) is ever added, use a custom executor on a serial `DispatchQueue` (iOS 17+).
- **README escape hatch:** for synchronous use from several threads, a user writes their own lock wrapper around a storage and takes responsibility for it.

## 8. Facade

`Sources/KeyValueStorage/Unified/`

- `UnifiedStorageKey<Storage, Value>`: `key`, `scope` (non-optional, defaults to `.default`), value type. Keep the typealiases `FileKey`, `SQLiteKey`, `KeychainKey`, `UserDefaultsKey`, `InMemoryKey`.
- `UnifiedStorageFactory` (protocol; tests use it to inject backings):

  ```swift
  public protocol UnifiedStorageFactory: Sendable {
      func dataStorage<S: KeyValueDataStorage>(_ type: S.Type, scope: S.Scope) throws -> S   // default: S(scope:)
  }
  ```

- **`UnifiedStorage`** (`final class`, not `Sendable`): a synchronous API (`fetch`, `save`, `set`, `delete`, `update`, `clear(storage:forScope: = .default)`, `publisher`, `stream`). It creates one `KeyValueCodingStorage` per (storage type, scope) on first use. Creation is synchronous, so the `Task`-caching logic goes away, and a failed creation isn't cached.
- **`IsolatedUnifiedStorage`** (`final class`, `Sendable`): the same API, `async`. Its cache is lock-protected (D5), and each (type, scope) gets its own `IsolatedKeyValueStorage<KeyValueCodingStorage<S>>`, so unrelated storages never wait for each other. Users who prefer a single actor can wrap a `UnifiedStorage` in an actor themselves.
- `coder` is set on the facade initializer, defaulting to `RawDataCoder()`.

## 9. Removals checklist

- Global actors: `FileActor`, `SQLiteActor`, `KeychainActor`, `UserDefaultsActor`, `InMemoryActor`, `CodingStorageActor`.
- `@unchecked Sendable` on storages and layers; `open`/`required`; `nonisolated` on type declarations.
- `async` on `KeyValueDataStorage`, `DataCoder` and `KeyValueCodingStorage`.
- `KeyValueObservableStorage`, `ObservableUnifiedStorageFactory`, `DefaultUnifiedStorageFactory` (replaced by the protocol default).
- `IsolatedKeyValueDataStorage` typealias, `KeyValueDataStorageScope.appIdentifier`.
- `Helpers/KeychainWrapper.swift`.
- `InMemoryStorage.container` static.
- Direct `FileManager`/`Bundle` use inside storages and `StorageDirectory`.
- Stale leftovers: `Storages/Layers/` index entries (run `git add -A Sources` once the tree is consistent).

## 10. File layout

```
Sources/KeyValueStorage/
  Core/        KeyValueDataStorage.swift, KeyValueScopeProviding.swift, StorageDirectory.swift
  Storages/    FileStorage/ SQLiteStorage/ KeychainStorage/ UserDefaultsStorage/ InMemoryStorage/
               (each: <Name>.swift, +Scope, +Error, +Key, BackingStorage/)
  Coding/      DataCoder.swift, JSONDataCoder.swift, PropertyListDataCoder.swift, RawDataCoder.swift,
               KeyValueCodingStorage.swift, KeyValueCodingStorageKey.swift,
               Observation/ObservationRegistry.swift, Observation/KeyValuePublisher.swift
  Isolation/   IsolatedKeyValueStorage.swift
  Unified/     UnifiedStorage.swift, IsolatedUnifiedStorage.swift, UnifiedStorageKey.swift,
               UnifiedStorageFactory.swift, Typealiases.swift
  Resources/   PrivacyInfo.xcprivacy
Tests/
  KeyValueStorageTests/              unit tests with mocks (@testable)
    Storages/<Name>StorageTests.swift, Core/StorageDirectoryTests.swift, Coding/…, Isolation/…, Unified/…
    Mocks/<Name>BackingStorageMock.swift, StorageDirectoryResolverMock.swift, DataCoderMock.swift, DataStorageMock.swift
  KeyValueStorageIntegrationTests/   NEW target: default adapters against the real system
  KeyValueStoragePublicAPITests/     no @testable: what clients can reach, isolation contexts
  KeychainHost/                      app host for real-keychain integration tests
```

## 11. Testing strategy

### 11.1 Rules

- **Storage classes, `StorageDirectory`, the coding layer, the isolation layer and the facade: 100% coverage with mocks.** Every outcome of every `if`/`guard`/`switch`/`catch` has a test, and each test asserts both the result and the exact backing calls (arguments recorded by the mock).
- **Default adapters** (`Default*BackingStorage`, `DefaultUserDefaultsSuite`, `DefaultSQLiteDatabase`, `DefaultInMemoryBackingStoreWrapper`): integration tests against the real system. Failures the system won't produce on demand are documented as uncovered.
- **Mocks:** final classes conforming to the backing protocols. They record calls (in order, with arguments) and return or throw scripted results per call. No subclassing of Apple classes.
- **Measuring:** Swift's coverage data has line and region counters, not branch counters (llvm-cov's branch columns stay empty for Swift; verify on the CI toolchain). Each branch arm is its own region, so the gate is **100% region and line coverage** for the gated files, plus the outcome inventories below as the checklist.

### 11.2 Outcome inventories

**StorageDirectory** (mock resolver): each of the 5 cases builds the right path, with the app identifier only for app cases. Application Support, Caches and Documents each return `nil` → `.directoryNotFound(name)`. A `nil` group container → `.groupNotFound(id)`. The temporary directory never fails.

**KeychainStorage**
- init: `.app(nil)`, `.app(c)`, `.appGroup(g, nil)`, `.appGroup(g, c)` → service and access group in every query.
- fetch:
  - `.success` with `Data` → the data; `.success` with a non-`Data` result → `nil`; `.notFound` → `nil`.
  - each other status (`.duplicate`, `.interactionNotAllowed`, `.missingEntitlement`, `.otherError`) → `.os(status)`.
  - synchronizable true/false; query has `returnData` and `.one`.
- save:
  - add `.success` → done, no update.
  - add `.duplicate` → update `.success` → done; add `.duplicate` → update failure → `.os`.
  - add other status → `.os`, no update.
  - accessibility present in the add attributes and in the update attributes; the update query has no value or accessibility.
- delete: `.success`, `.notFound` → ok; other → `.os`.
- clear: `.success`, `.notFound` → ok; other → `.os`; the query has `.any` synchronizable and no account.

**FileStorage**
- init: 5 scope cases → root; the directory-not-found and group-not-found failures mapped to `.failedToFindDirectory` / `.failedToFindGroupDirectory`; no backing call until the first operation.
- key validation, each a separate case → `.invalidKey` with no backing call: empty, `.`, `..`, contains `/`, contains `\0`, encoded name over 255 bytes; exactly 255 is valid.
- file name: `%` encoded, case-changing characters encoded, other characters kept, canonically equivalent keys map to one name, multi-byte encoding.
- fetch: data; `fileReadNoSuchFile` → `nil`; protected-data error → `.protectedDataUnavailable`; other → `.other`.
- save:
  - write succeeds on the first try.
  - `fileNoSuchFile` → create directory → write succeeds.
  - create directory throws → mapped error; the second write throws → mapped error; the first write throws another error → mapped, no directory created.
  - options for each of the 5 protections (always `.atomic`).
- delete: success; `fileNoSuchFile` ignored; other → mapped.
- clear: `fileReadNoSuchFile` → no-op; listing throws another error → mapped; empty list; several files each removed; a file that vanished meanwhile is ignored; a remove failure → mapped (and stops).
- `isProtectedDataUnavailable`: wrong domain; wrong code; no underlying error; non-POSIX underlying; POSIX but not `EPERM`; read + `EPERM` → true; write + `EPERM` → true.

**UserDefaultsStorage**
- init: `.standard` → `standard`, no prefix; `.suite(c)` → `suite(named: "<appId>.<c>")`, and `nil` → `.invalidSuiteName`; `.appGroup(g, c)` → `suite(named: g)` + prefix, and `nil` → error.
- prefix encoding: plain, `/`, `%`, both, empty container; containers `a` + key `b/c` and `a/b` + key `c` never collide.
- fetch, save, delete: with and without prefix (exact key passed to the suite).
- clear: no prefix removes every key; with a prefix, only prefixed keys (others and foreign values stay); empty suite.

**InMemoryStorage:** fetch hit and miss; save; delete; clear; two containers stay apart; default container; exact container passed to the backing.

**SQLiteStorage**
- init: 5 scope cases → database URL; resolution failures mapped; `createDirectory` throws → `.other`; `open` throws `SQLiteError` → `.sqlite`, or another error → `.other`.
- fetch, save, delete, clear: success; `SQLiteError` → `.sqlite(code:message:)`; another error → `.other`.
- protection: each of the 5 `Protection` cases, for `.app` and `.appGroup`, reaches `open` as the matching `FileProtectionType?` (`.inherited` → `nil`); an omitted protection is `.inherited`.

**UbiquitousStorage**
- init: a container → `<escaped>/` prefix (plain, `/`, `%`); a `nil` container → keys as is.
- key length: exactly 128 UTF-16 units with the prefix → passes; 129 → `.invalidKey` from fetch, save and delete, without calling the store.
- save: exactly 1 MB → stored; one byte more → `.valueTooLarge(key:size:)`, without calling the store.
- fetch hit and miss; delete.
- clear: with a container, only prefixed keys (other containers and foreign keys stay); with `nil`, every key.
- `synchronize()` returns the backing's result.

**Protocol extension:** `set(nil)` → delete; `set(value)` → save (tested once, with a `DataStorageMock`).

**KeyValueCodingStorage** (mock data storage and mock coder)
- fetch: `nil`; decode success; decode throws; storage throws.
- save: encode throws (no write); write throws (no event); success (event).
- delete, clear: success emits events (clear notifies every observed key of the scope); failure emits nothing.
- update: `nil` → value; value → `nil` (delete); value → value; transform throws; decode, encode or storage throws.
- observation:
  - with and without the current value; reading the current value throws.
  - a different key isn't notified; a different scope isn't notified; another instance on the same scope is notified.
  - observers of different value types; a callback writing to the storage (no deadlock).
  - a released publisher or a cancelled stream removes the observation.

**IsolatedKeyValueStorage:**
- forwards every operation and error;
- `scope` is readable without `await`;
- `withStorage` is atomic: 1000 concurrent `update` increments end at 1000;
- a mock storage records overlapping entries and must record none;
- callable from every isolation context (public API target).

**UnifiedStorage / IsolatedUnifiedStorage:**
- one storage per (type, scope); `.default` and an omitted scope share it;
- the factory is called once, and a failed creation is retried;
- `clear(storage:forScope:)`;
- observation works through the facade;
- the isolated facade gives different scopes different actors.

### 11.3 Integration tests (new target)

- **`DefaultFileBackingStoreWrapper`** in a temp directory:
  - read, write, remove, create and list.
  - the real `CocoaError` codes for a missing file or directory, a directory where a file is expected, `chmod` 000 / 555 (skipped as root).
  - resolver members return real paths.
- **`DefaultSQLiteBackingStoreWrapper`/`DefaultSQLiteDatabase`** (move today's SQLite tests here):
  - round trips (empty, 1 MB, keys containing NUL);
  - a corrupt database → `SQLITE_NOTADB`; a directory at the database path → `SQLITE_CANTOPEN`;
  - a lock held by another connection → `SQLITE_BUSY` after the timeout, reads still working in WAL mode;
  - a dropped table → `SQLITE_ERROR`, recreated on reopen; persistence across instances.
- **`UserDefaults` adapter:** a unique suite name per test, removed in teardown; `standard` is the same object as `UserDefaults.standard`.
- **`DefaultInMemoryBackingStoreWrapper`:** concurrent access from many tasks.
- **Keychain:** `DefaultKeychainBackingStoreWrapper` in KeychainHost (entitlements): add, match, update, delete, `.duplicate`/`.notFound`, `.missingEntitlement` for a group it isn't entitled to.
- **End-to-end:** one save/fetch/clear per storage through `UnifiedStorage` with real backings in temporary scopes.

### 11.4 CI

- Add a coverage job (macOS, latest Xcode):

  ```sh
  swift test --enable-code-coverage
  PROF=$(swift test --show-codecov-path)          # JSON export path; profdata is next to it
  xcrun llvm-cov report <test binary> -instr-profile .build/debug/codecov/default.profdata \
      -ignore-filename-regex '(Tests|\.build)/'
  ```

  A small script fails the job if region or line coverage is below 100% for `Storages/*/<Name>.swift`, `Core/`, `Coding/`, `Isolation/` and `Unified/`. Adapter files are excluded from the gate. (Verify the binary path per toolchain.)
- Keep the existing matrix (Xcode 16 → 26.x), the iOS simulator job, the KeychainHost job (integration tests now), and the tvOS, watchOS and visionOS builds.

## 12. Execution phases

Each phase ends with: the library builds on every CI toolchain, the phase's tests pass, and its gated files have 100% coverage.

| Phase | Work | Done when |
|---|---|---|
| 0 | Fix the git index (`git add -A Sources`), delete `KeychainWrapper.swift`, settle the Open decisions below | Clean tree, decisions recorded here |
| 1 | Core: new `KeyValueDataStorage`, `StorageDirectoryResolving`, `StorageDirectory` + tests; remove global actors and `Sendable` from the protocol | `StorageDirectoryTests` 100% |
| 2 | **KeychainStorage** onto the new protocol + mock tests (pattern reference for the rest) | Keychain inventory covered |
| 3 | FileStorage: backing gets the resolver members; storage cleanup; mock tests | File inventory covered |
| 4 | UserDefaultsStorage: backing + `UserDefaultsSuite`; mock tests | UserDefaults inventory covered |
| 5 | InMemoryStorage: `DefaultInMemoryBackingStoreWrapper`; mock tests | InMemory inventory covered |
| 6 | SQLiteStorage: extract `DefaultSQLiteBackingStoreWrapper`/`DefaultSQLiteDatabase`; mock tests; move the SQLite integration tests | SQLite inventory covered |
| 7 | Synchronous coders; `KeyValueCodingStorage` with `update` and built-in observation; delete `KeyValueObservableStorage` | Coding inventory covered |
| 8 | `IsolatedKeyValueStorage` + tests | Isolation inventory covered |
| 9 | `UnifiedStorage`, `IsolatedUnifiedStorage`, factory protocol + tests | Facade inventory covered |
| 10 | Integration test target, KeychainHost update, public API and isolation tests rewritten | All targets green on CI |
| 11 | Coverage gate in CI; README and DocC rewrite (scopes table, isolation guide, lock escape hatch, observation limits); `CHANGELOG`; tag 4.0.0 | Release |

## 13. Open decisions

1. **macOS minimum 10.15 → 11.** Removes the untestable `#available` branch in `FileStorage.writingOptions` and simplifies the protection options. Recommended.
2. **Names:** `IsolatedKeyValueStorage` vs `ActorKeyValueStorage`; keep `KeyValueCodingStorage` or shorten it to `CodingStorage`.
3. **Isolated facade:** one actor per (type, scope) (recommended, §8) vs a single actor around `UnifiedStorage`.
4. **Observation always on** (recommended, D11) vs opt-in.
5. **Typed throws** (`throws(Error)`) on the data layer: nicer error types, but check back-deployment to iOS 13 for generic contexts before adopting.
6. **watchOS minimum 6 → 9.** That's what `UbiquitousStorage` needs; it would remove its `@available(watchOS 9.0, *)` annotations.

## 14. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `update` isn't atomic across processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension. This is already in the scope docs.
- **Observation across instances on different actors** has no ordering guarantee; in-process users should go through one facade.
- **Actor I/O on the concurrency pool**, see §7.
