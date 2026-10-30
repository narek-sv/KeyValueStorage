# KeyValueStorage 4.0 — Refactor Plan

## 0. How to work on this plan

This file is the source of truth for the 4.0 refactor, written so that anyone, human or AI, can continue from it alone. The Status below can lag `git log`, so check the log first. Then read §S, which changes every storage and overrides what §4 and §5 say about scopes, keys and places. Work on branch `4.0.0-experiments`.

**Working rules** (the maintainer's):
- **Commits** only when the maintainer asks, one per step.
- **Pilot, then roll out:** plan a change fully, adopt it on one storage, stop for review, then apply the settled pattern to the other five. Audit errors and clashes along the way.
- **Simple, bulletproof, sound:** the simplest rule that holds for every input.
  - No logic in wrappers (E0): a default backing store is one system call per member.
  - All naming lives in the locators. No shared helper that a dependency only forwards to.
  - No parameters or properties for demonstration only.
  - Never swallow a "can't tell": throw instead.
- **Consistency:** a rule decided for one storage applies to all six, Keychain included. Keep the per-storage tables in this plan current.
- **Names** are exact bytes everywhere (§4.3, `ExactString` in §S). Encode, don't reject: any string is a valid key or namespace, and only system limits throw.
- **System and SDK gotchas** get a doc comment on the case they affect, not a workaround, unless they'd let two scopes reach each other's values (§S).
- **Comments** hold only essentials, gotchas and warnings, one line where possible, with no narration. API docs use `///`, `- Note:` and `- Warning:`.
- **Tests** use XCTest, with `// Given`, `// When`, `// Then` and mocks that record their calls. The gated files keep 100% region and line coverage (§11.1). Every behavior the docs state is either measured by a test or listed as "to verify" (§11.3, §13 item 7).
- **When asked whether anything is left open,** do one complete pass, and say "none" when nothing is.

**Commands:**
- macOS: `swift build --build-tests`, with no warnings, and `swift test`.
- iOS Simulator: `xcodebuild test -scheme KeyValueStorage -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- KeychainHost, for the real keychain on the Simulator: `xcodebuild test -project Tests/KeychainHost/KeychainHost.xcodeproj -scheme KeychainHost -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- Coverage: §11.4.
- Test runs take minutes, so run them in the background rather than with a short timeout.

## Status (2026-10-30)

- **Done: locators (§4.3).** Naming moved out of the storages into one locator per storage. Each step also applies the error contract (§4.4) and the clash rules (§4.5), and writes the storage's mock-based unit tests.
  - **Done, in review: FileStorage**, the pilot (§5.3). Its tests pass on macOS and the iOS Simulator. The gated files have 100% coverage, except the `#available(macOS 11)` fallback.
  - **Done: lossless file names.** File and SQLite name every file and folder with one encoding of the exact bytes (§5.3); only a name over 255 bytes fails, and `InvalidFileNameReason` is gone.
  - **Done: every storage has its locator.** All naming lives in `Storages/<Name>/Dependencies/<Name>Locator.swift`; `StorageDirectory`, `StorageDirectoryLookup` and `KeyNamespace` are gone. The other five moved their rules as they were; their steps still bring the clash fixes (§4.5), the error audit and the tests.
  - **Done: SQLite** (§5.6): locator and storage tests, integration tests against real SQLite, the error audit (no force unwraps left), and the 3.x tests ported and deleted. Gated files at 100%.
  - **Done: UserDefaults** (§5.4): only `Data` is a value (§4.6, now the rule for every storage), root keys escaped so `clear()` is exact, byte-exact keys, and the 3.x tests ported and deleted. Gated files at 100%.
  - **Done: Ubiquitous** (§5.7): the UserDefaults scheme and the only-`Data` rule, the 128-unit key limit on the stored key, and the escaping fix. Gated files at 100%; the default adapter needs a signed host with the iCloud entitlement.
  - **Done: Keychain** (§5.2): the root uses service `""` and App Group services carry the group, so no scope reaches another's items; only `Data` items are values; KeychainHost runs again, with real-keychain tests. Gated files at 100%.
  - **Done: InMemory** (§5.5): the default store keys buckets and values by bytes, so every storage keeps keys exact (§4.3); locator and storage tests. Gated files at 100%.
  - **Deferred: locked-device errors** (§13, item 7), which need a real iPhone and a device signing setup for KeychainHost.
  - **Decided: the sealed scopes** (§S, D21), which settle the clash audit (§4.5). To implement, with the planned items below.
  - **Done: Keychain without reads before its calls** (§5.2, 2026-10-30), so `delete` no longer fails while locked; an item without data is a value like any other.
  - **Planned: Keychain app-scope services that carry the app's identifier** (§5.2), so two apps' app scopes never meet.
  - **Planned: app-scope paths carry the app's identifier** (§4, D9).
  - **Planned: UserDefaults' app scope gets a suite of its own, and UserDefaults and Ubiquitous keys carry the library's mark** (§5.4, §5.7).
  - **Locators are done for all six storages.** What's left of `Tests/Legacy3x/` belongs to the coding, observation and unified layers.
- **Done: phases 0–6, the source side.** The synchronous `KeyValueDataStorage` with `init(scope:backingStore:)`, typed throws, scopes with namespaces, every storage on its backing store, the global actors removed, and `KeychainWrapper.swift` deleted.
- **Added: `UbiquitousStorage`** (§5.7), on the same pattern.
- **Tests:** the public API target and the coder tests are on the 4.0 API and pass. The 3.x unit tests live in `Tests/Legacy3x/` (not a target) as the porting reference; each storage's locator step ports and deletes its file.
- **Next: the sealed scopes** (§S, Appendix A, phase 6b). Pilot on FileStorage and stop for review, then SQLite, UserDefaults, Ubiquitous, Keychain and InMemory. Each step brings that storage's planned items (§5.2–5.7), its part of the error refactor (§4.4) and its test revisit (§11.3).
- **Then: phases 7–9**, the coding, isolation and facade layers. The observation and unified layers still emit isolated-conformance warnings on Swift 6.2+ compilers, because the storage protocol is no longer `Sendable`.

## S. Sealed scopes and keys (decided 2026-10-30; next, and it changes every storage)

Read this first. It replaces the scope, key and place rules that §4 and §5 describe for today's code: where they differ, this section wins. Phase 6b implements it (§12), and Appendix A holds the agreed enums and docs.

**Rule:** the user says what they mean, and the library picks the place and owns every name inside it. A scope says who sees the values, on which devices, how long the system keeps them and how they're protected. It never names a system location. Interop with other code's files, items or keys goes through a custom locator, which then owns the guarantees (§13, item 8; D21).

**Shared types** (`Layers/KeyValueDataStorage.swift`):
- `ExactString`: a string compared and hashed by its exact UTF-8 bytes (`String`'s `==` takes `"é"` and `"e\u{301}"` for one); `ExpressibleByStringInterpolation` and `CustomStringConvertible`. Every storage has `typealias Namespace = ExactString` and `typealias Key = ExactString`, so the layers (`UnifiedStorage`'s cache, observation) compare names the way the storages store them. One type for both is fine: it carries no meaning of its own.
- `KeyValueDataStorageScope` requires only `Hashable & Sendable` and `static var default`. `defaultNamespace` (`"KeyValueStorage"`) replaces `defaultName`. Scopes have no `namespace` property: locators read it from the cases.
- The protocol keeps `associatedtype Key: KeyValueDataStorageKey` (`Hashable & Sendable`) generic, so custom storages can bring their own key types. `KeyValueDataStorageNamespace` goes.

**Scopes.** The place comes first and the namespace last. Every namespace is required, never optional or defaulted, so there's no root.

```swift
// FileStorage, SQLiteStorage
case own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: Namespace)
case appGroup(id: String, protection: Protection = .inherited, namespace: Namespace)
// UserDefaultsStorage
case own(namespace: Namespace)
case appGroup(id: String, namespace: Namespace)
// KeychainStorage
case own(protection: Protection = .whileLocked, namespace: Namespace)
case appGroup(id: String, protection: Protection = .whileLocked, namespace: Namespace)
case iCloud(Owner, protection: SyncedProtection = .whileLocked, namespace: Namespace)   // Owner: .own, .appGroup(id:)
// InMemoryStorage
case own(namespace: Namespace)
// UbiquitousStorage
case iCloud(Owner, namespace: Namespace)   // Owner: .own
```

- **Who and where:** `own` is the running app's or extension's own, never its containing app's: they share only through `appGroup`. `appGroup` is the group's apps and extensions. `iCloud` syncs to the user's other devices, and its `Owner`, never optional, says which apps, spelled like the device cases.
- **Retention** (File, SQLite): `.persistent` (Application Support), `.cache` (Caches: the system can delete it when storage runs low) and `.temporary` (tmp: the system can delete it while the app isn't running). App Groups take none: `containerURL(forSecurityApplicationGroupIdentifier:)` gives one folder, with no defined caches, support or temporary folder, so a group's values live at its root.
- **Protection** is part of the place, like retention: scopes that differ only in protection never share values. One vocabulary for File, SQLite and Keychain, each listing its system's levels: `.inherited` and `.none` (File, SQLite), `.untilFirstUnlock`, `.whileLocked`, `.whileLockedUnlessOpen` (File, SQLite), and Keychain's `…ThisDeviceOnly` levels and `.whileLockedOrWithoutPasscode`. Keychain's `.iCloud` takes `SyncedProtection` (`.untilFirstUnlock`, `.whileLocked`), so a synced item with a device-only level can't be written. The defaults are each system's: `.inherited`, and Keychain's `.whileLocked`.
- **Keys are names only** in every storage: protection, accessibility and sync moved into the scopes. File's `Key` loses `protection`; Keychain's loses `accessibility` and `isSynchronizable`.

**Places** (the default locators):

| Scope | File, SQLite | UserDefaults | Keychain | InMemory | Ubiquitous |
|---|---|---|---|---|---|
| `.own` | `<Application Support, Caches or tmp>/<encoded bundle ID>/`, a folder per namespace and protection; SQLite's `.KeyValueStorage.sqlite` in it | suite `<encoded bundle ID>.KeyValueStorage` | service `<bundle ID>:<namespace>` with the protection, the default access group, local items | the process's bucket | — |
| `.appGroup(id)` | the group container's root, a folder per namespace and protection | the group's suite, `id` | service `<group>/<namespace>` with the protection, access group `id`, local items | — | — |
| `.iCloud(owner)` | — | — | the owner's service and group, synchronizable items | — | the store |

- The protection level goes into the folder, database file or service name in a form no namespace encodes to. The obvious `name!code` would collide with File's capital marker, where `!c` is `C`.
- **Every `.own` place carries the app's identifier** (D9), so two apps' `.own` scopes never meet, also on macOS without App Sandbox and when Keychain Sharing lists a shared group first (§5.2). InMemory needs none (per process); Ubiquitous's store is per app unless entitlements share it.
  - Where the identifier becomes a file name (File and SQLite paths, UserDefaults' suite), it's written in File's lossless encoding. Bundle IDs that differ only in case then never share a file on macOS, the process-name fallback needs no rules of its own, the folder never meets the conventional `Application Support/<bundle ID>` other code uses, and the suite name never starts with `group.`. Keychain services keep it as is, because the keychain compares exactly.
  - The one limit: a bundle ID longer than about 120 characters, with many capitals or dots, could pass 255 bytes once encoded, and the storage would throw. Real bundle IDs are far shorter.
- **Marks:** UserDefaults and Ubiquitous store keys as `<namespace>!/<key>`, because other code writes to App Group suites and to the store (§5.4, §5.7). File folders keep their `!`. Keychain needs none: its services start with the bundle ID or the group.
- **Rejected:** every `.appGroup`, and Keychain's `Owner.appGroup`, throws for an empty id. UserDefaults' `.appGroup` also throws for the global domain's names and for `.own`'s suite name (§4.5, item 1).
- **System and SDK gotchas are documented on the case they affect, not worked around**, unless they'd let two scopes reach each other's values, as with the rejection above. The docs cover `.own` belonging to the bundle ID (builds that share one share values, and unit tests hosted in an app use the app's, so tests take a namespace of their own); macOS without App Sandbox; File and SQLite paths longer than 1024 bytes in all, which the system refuses even when every name fits in 255; Keychain's default access group; keychain items outliving the app; unentitled App Groups (macOS gives any id a folder, UserDefaults stays in the app without an error, Keychain fails with `errSecMissingEntitlement`); macOS group ids that differ only in case; launch arguments and registered defaults; Ubiquitous's quota and its missing entitlement; iCloud being off or signed out; and the passcode level.

**Gone:** `AppScope`, `.documents`, `.directory(at:)` (a custom place goes through a locator), `.suite(named:)`, `.standard`, the root and its rules (root-key escaping, Keychain's service `""`, InMemory's unnamed bucket), and the per-storage namespace cases (`.directory(named:)`, `.keyPrefix(named:)`, `.service(named:)`, `.bucket(named:)`).

**Settles:** the §4.5 audit (items 2–5 by construction, item 1 by the rejection), URL aliasing, and the default suite that apps shared on macOS.

**Costs:** keys that need different protection or retention need a scope each; changing either later starts an empty set; a forgotten parameter reads another set and gets `nil`; a custom place, or interop, needs a custom locator.

**Reference:** Appendix A holds the full enums with their agreed doc comments. Implement from it.

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
| D6 | **Backing stores:** one protocol per storage that is a minimal, **location-free** interface to the system. The storage gets the location (URL, suite name, service, bucket) from its locator (D17) and passes it in. Default adapters are thin and as branch-free as possible. | The backing and the scope can't disagree. Scope resolution is reachable from tests. Adapters need only integration tests. |
| D7 | **Storages depend only on their backing store and their locator.** Every value read from the environment comes through the backing store: directories and App Group containers. | 100% coverage without the real system, including path and suite resolution. |
| D8 | The protocol requires `init(scope:)` and `init()`, with `init()` defaulting to `.default`. Each storage adds a public `init(scope:backingStore:locator:)` taking its `XBackingStore` and its `XLocator`, both required, and its `init(scope:)` passes a new `DefaultXBackingStoreWrapper` and `DefaultXLocator`. **`scope` is non-optional.** | Consistent API; the scope is always known; `nil` and `.default` can't become two different storages. |
| D9 | **App scopes include the app identifier** (bundle identifier, or process name for command-line tools) in paths and suite names; App Group scopes don't. | Same behaviour on every platform: on macOS without App Sandbox, `~/Library`, the temporary directory and `~/Documents` are shared by all apps. |
| D10 | **Synchronous `DataCoder`.** | JSON and PropertyList coding are synchronous; `async` only forced hops and blocked locking. |
| D11 | **Observation is built into `KeyValueCodingStorage`** and always available. Delete `KeyValueObservableStorage` and `ObservableUnifiedStorageFactory`. | An empty registry costs one dictionary lookup per write. It removes a subclass, a factory and the `publisher(...) -> nil` APIs. |
| D12 | `set(_:forKey:)` is a protocol extension, not a requirement. | It's the same five lines in every storage, and five copies to test. |
| D13 | Storages and layers are `final class`, with no `open`/`required`. The default backing stores and locators are `open` classes. | Extension points are protocols, backing stores and locators. Subclassing a default changes one operation or one naming rule without rewriting the rest. |
| D14 | Keep **Swift tools 6.0** and the Xcode 16 CI job. Don't mark types `nonisolated`: that needs Swift 6.1, and it's redundant without default `MainActor` isolation. | Toolchain support stays as it is. |
| D15 | Backing protocols are **not** `Sendable`. Only the shared default `DefaultInMemoryBackingStoreWrapper` is (`@unchecked Sendable` + lock). | Storages aren't `Sendable`, so a backing travels with its storage. Region isolation stops one backing from being shared by storages on different actors, and mocks don't need `@unchecked Sendable`. |
| D16 | **No iCloud Drive scope and no file coordination.** No `CoordinatedFileStorage`, and no `isCoordinated` key option. | **Coordination:** every write is an atomic replace, so readers in other processes never see a partial file, and no `NSFilePresenter` watches the package-owned folders; coordinating would only add a round trip to a daemon on every operation. A per-key option, or a second storage type over the same folder, would let uncoordinated writes slip in. Cross-process read-modify-write belongs to SQLite. **iCloud Drive:** files there may not be downloaded yet, conflict across devices, need `url(forUbiquityContainerIdentifier:)` (which must not run on the main thread) and require coordination. That breaks the synchronous, local-first contract. Synced data uses `UbiquitousStorage`, `KeychainStorage` with `isSynchronizable`, or CloudKit outside this library. If it's ever revisited, coordination goes into a `CoordinatedFileBackingStore` adapter, always on for that scope. |
| D17 | **Locators:** one public protocol per storage plus an `open` default, injected like the backing store, that owns all naming: scope → location, key → stored name with validation, and stored name → key (§4.3). Storages keep business logic only. | One place for every naming rule. The rules are tested without backing mocks. Apps can adopt 4.0 over data that already exists (3.x files, existing keychain services, unprefixed UserDefaults keys) with a custom locator. |
| D18 | **System limits are enforced in the locator only**, and the protocol documents them. A custom locator must uphold them. | All naming in one place; the same trust model as a custom backing store, which can already crash or write anywhere. |
| D19 | **Errors are typed end to end and carry what failed** (§4.4); invalid keys and namespaces carry the rule they break. | Errors are actionable without reading the code; no error is re-mapped or swallowed silently. |
| D20 | **Stored names are disjoint across scopes, and `clear()` is scope-exact** (§4.5). | Root values and namespaced values can share one folder, suite or store without one scope's `clear()` deleting another's values. |
| D21 | **Sealed scopes** (§S): a scope says who sees the values, on which devices, how long they're kept and how they're protected; the library picks the place and owns every name in it. | Every input is a valid name, no two scopes or keys clash, and the storages stay interchangeable. Interop is a custom locator's job. |

## 3. Target architecture

```
UnifiedStorage / IsolatedUnifiedStorage   facade: key → (storage type, scope) → one storage each
          │
IsolatedKeyValueStorage<Wrapped>          OPTIONAL actor, outermost; withStorage { … } + typed conveniences
          │
KeyValueCodingStorage<Storage>            sync, not Sendable: Value ↔ Data, atomic update, observation
          │
FileStorage · SQLiteStorage · KeychainStorage · UserDefaultsStorage · InMemoryStorage · UbiquitousStorage
          │                               sync, not Sendable: business logic (system calls, retries,
          │                               error mapping, clear semantics)
          ├── XxxLocator (protocol)       naming: scope → location, key ↔ stored name, validation
          │
XxxBackingStore (protocol)                the system and nothing else; default adapter + mocks in tests
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

`Sources/KeyValueStorage/Layers/KeyValueDataStorage.swift`

```swift
public protocol KeyValueDataStorage {
    associatedtype Key: KeyValueDataStorageKey             // Hashable & Sendable
    associatedtype Scope: KeyValueDataStorageScope         // Hashable & Sendable, Namespace, static var default
    associatedtype Error: KeyValueDataStorageError         // Error & Sendable

    var scope: Scope { get }

    init() throws(Error)
    init(scope: Scope) throws(Error)

    func fetch(forKey key: Key) throws(Error) -> Data?
    func save(_ value: Data, forKey key: Key) throws(Error)
    func delete(forKey key: Key) throws(Error)
    func clear() throws(Error)
}

public extension KeyValueDataStorage {
    init() throws(Error) {
        try self.init(scope: .default)
    }

    func set(_ value: Data?, forKey key: Key) throws(Error) {
        if let value { try save(value, forKey: key) } else { try delete(forKey: key) }
    }
}
```

- No `IsolatedKeyValueDataStorage` typealias, no `async` in requirements or initializers, no `Sendable` on the protocol.
- `KeyValueDataStorageScope.defaultName = "KeyValueStorage"`: every `default` scope's suite, directory, service, key prefix or bucket.
- Every scope has an optional `namespace` that separates sets of values within it: a folder (File, SQLite), a key prefix (UserDefaults, Ubiquitous), a service (Keychain) or a bucket (InMemory). `nil` is the scope's root.
  - **Planned:** every scope names a namespace, there's no root, and `defaultNamespace` replaces `defaultName` (§S).
- No app identifier in paths or suite names: the namespace separates apps' values where the system doesn't.
  - **Planned, reversing this for app scopes** (2026-10-30, D9): File and SQLite paths and Keychain services (§5.2) carry the app's identifier, because two apps that pick the same namespace would otherwise share values. UserDefaults' app scope moves to a suite of its own, `<encoded bundle ID>.KeyValueStorage` (§5.4). Paths and the suite name carry the identifier encoded (§S).
- Neither backing stores nor locators are part of the protocol. Each storage's `init(scope:backingStore:locator:)` takes existentials (`any FileBackingStore`, `any FileLocator`, …), so the storages stay non-generic.

### 4.2 System directories (File and SQLite)

Finding where a scope's values go is naming, so the default File and SQLite locators look up the system's directories themselves. There's no lookup protocol and no shared resolver; the backing stores only act on paths they're given.

```swift
open func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL?   // urls(for:in: .userDomainMask).first
open var temporaryDirectory: URL                                                   // FileManager.temporaryDirectory
open func groupDirectory(for groupId: String) -> URL?                              // containerURL(forSecurityApplicationGroupIdentifier:)
```

- Each is one `FileManager` call, with no logic, like a backing store's members (E0). A subclass changes where a directory is; the unit tests use one with fixed paths (`FixedDirectoriesFileLocator`).
- Each default locator turns its own scope into its folder in one switch, and throws its storage's errors (`.directoryNotFound`, `.groupDirectoryNotFound`, `.invalidDirectory`, `.invalidNamespace`). File and SQLite have separate scope and error types, so they repeat the switch rather than share a helper.
- The namespace's folder is named with the file name encoding (§5.3) plus a trailing `!`, so file and SQLite storages of one namespace share a folder. It's encoded first, so its one error, a name over 255 bytes (`.invalidNamespace`), doesn't depend on the system.

### 4.3 Locators

A locator translates the library's names (scope, namespace, key name) into the system's names (URL, file name, suite, stored key, service, account, bucket) and back. It never sees values or key attributes (protection, accessibility, synchronizable), and never acts on the system; its only system calls are the directory lookups of the File and SQLite defaults (§4.2).

- **Shape:** one public protocol per storage and an `open class Default<Name>Locator`, in `Storages/<Name>/Dependencies/<Name>Locator.swift`, next to the backing store. A shared generic protocol would need parameterized existentials (`any P<A>`), which need iOS 16 / macOS 13.
- **Stateless:** the same inputs give the same outputs, given the same system directories. The storage passes its `scope` to every call, so the two can't disagree.
- **Injected:** every storage's `init(scope:backingStore:locator:)` takes the locator; `init(scope:)` passes the defaults.
- **Key names, not keys:** it takes `String` names, never `Key` structs.
- **Exact keys:** every storage keeps a key's and a namespace's exact bytes, so `"é"` and `"e\u{301}"` are two keys, though Swift's `==` takes them for one. Verified in File, SQLite, UserDefaults, Keychain and InMemory; Ubiquitous keys are `NSString` dictionary keys like UserDefaults', and can't be checked without the entitlement.
- **Typed throws** in the storage's `Error`, only where the default can fail. Otherwise the method doesn't throw, so the Keychain, InMemory and Ubiquitous initializers stay non-throwing.
- **Inverse law:** where a reverse method exists, it maps every stored name a valid key produces back to that key, and returns `nil` for every other name. The default's reverse method calls `self`'s forward method, so a subclass that changes the forward rule stays consistent.
- **System limits** (D18): each protocol documents the limits a stored name must respect, and the locator enforces them.

| Protocol | Location (once, in init) | Key → stored name (each call) | Stored name → key (`clear()`) |
|---|---|---|---|
| `FileLocator` | `directory(for:) throws` | `fileName(forKey:in:) throws` | `key(forFileName:in:)` |
| `SQLiteLocator` | `databaseURL(for:) throws` | `storedKey(forKey:in:)` | — |
| `UserDefaultsLocator` | `suite(for:)` → `AppScope` (`.standard` / `.suite(named:)`) | `storedKey(forKey:in:)` | `key(forStoredKey:in:)` |
| `UbiquitousLocator` | — (one store) | `storedKey(forKey:in:) throws` | `key(forStoredKey:in:)` |
| `KeychainLocator` | `service(for:)`, `accessGroup(for:)` | `account(forKey:in:)` | — |
| `InMemoryLocator` | `bucket(for:)` | `storedKey(forKey:in:)` | — |

What stays in the storages: system calls and their retries (File's `createDirectory` on a missing folder), attribute mapping (protection → writing options or SQLite flags, keychain accessibility and sync), status and error mapping, value limits (Ubiquitous's 1 MB), and how `clear()` removes values.

### 4.4 Error contract

- **E1 Typed end to end.** A storage and its locator throw `<Storage>.Error`. An error is constructed once and never re-mapped, with no `as? <Storage>.Error` casts.
- **E0 No logic in wrappers.** A default backing store is one system call per member, with no catches, translations or path rewriting. Every rule, including what an error means, lives in the storage, where the unit tests reach it.
- **E2 Only backing-store calls are wrapped.** Their untyped errors map to specific cases where the meaning is known (`.protectedDataUnavailable`, `.sqlite(code:message:)`, `.os`), or else to `.other(underlying)`, which keeps the original error. A rule the storage checks before acting, such as File's `.pathOccupied`, is thrown by the storage itself, never read from an error code.
- **E3 Absence isn't an error, and nothing else is swallowed.** A missing value is `nil` on fetch and a no-op on delete and clear. Storages check what is there before acting; "nothing there" is the one error a check translates (File: `fileReadNoSuchFile` → `nil`), and every other error is thrown, so an unreadable location never passes for an empty one.
- **E4 Validation before side effects.** Invalid keys, namespaces and values throw before any backing-store call.
- **E5 Errors carry the failing input:** the key, namespace, group ID, directory, URL or size, and nothing derived from it.
- **E6 No traps:** no `try!`, no force unwraps of system results, no `fatalError`, and no reachable Objective-C exceptions.
- **E7 Every case is documented, and every throw site is tested.**
- **E8 Partial failure is documented:** `clear()` stops at the first failure, and a failed init leaves nothing open.
- **Planned: refactor the errors with the sealed scopes** (2026-10-30, §13 item 8), against E1–E8:
  - drop the cases the redesign removes: `.invalidDirectory` (no `.directory(at:)`), Keychain's `.keyOccupied` (gone already, §5.2);
  - one name for one meaning across storages: a group the app isn't in (`.groupDirectoryNotFound`, `.invalidSuiteName`, `.os(errSecMissingEntitlement)` today), an occupied place (`.pathOccupied`, `.keyOccupied`), and a locked device (`.protectedDataUnavailable` for File today; SQLite's and Keychain's locked results once the device test names them, §13 item 7);
  - cases carry `ExactString` keys and namespaces, the failing input as the caller passed it (E5);
  - every case documented and every throw site tested again (E7).

### 4.5 Key clashes and scope-exact `clear()`

**Invariant:** in one physical store, two different (namespace or root, key) pairs never get the same stored name. A scope's reverse mapping claims exactly the names its own keys can produce, so `clear()` removes exactly the scope's values: never another namespace's, never a namespace's from the root, and never the root's from a namespace.

- **Shared spaces** (a File folder, a UserDefaults suite, the Ubiquitous store): `clear()` lists the stored names and deletes only those the locator claims.
- **Exclusive locations** (an SQLite database file, an InMemory bucket, a Keychain service with its access group): `clear()` empties the location.
- **Root vs namespace:**
  - File and SQLite keep namespaces in folders. **Files are values and folders are namespaces:** a key's value is only ever a file, its name never contains `.`, and a folder is never read, replaced or removed as a value. Namespace folders end with `!`, which no key's file name does (a `!` is always followed by a letter), so a root key and a namespace with the same name coexist. `.pathOccupied` comes only from other code's items, and nothing is ever removed to make room.
  - UserDefaults and Ubiquitous percent-encode `%` and `/` in root keys, so a root stored key never contains `/` and can't equal a namespaced one (`<encoded namespace>/<key>`).
  - Keychain's root uses service `""`, so it no longer matches every service. An app scope's queries search every access group the app has, so App Group services are `<group>/<namespace>` (escaped): an app scope's service never contains `/`, and no two scopes share a service. Verified in KeychainHost, also when the app's default access group is the App Group.
- **Not fixable without marking stored names:** in a space shared with other code's entries (a folder the user picked, `UserDefaults.standard`), the root `clear()` also removes entries that a key could have produced, such as `notes` or `AppleLanguages`. A namespace never does. Each scope's docs say so.
- **Laws** run against every default locator: round trip; no collisions within a namespace (File: also case-insensitively and canonically, as on APFS, with keys compared by their exact scalars); no collisions across namespaces, including the root; and no claiming of names that another scope or no key produces.
- **Clashes outside the locators, settled by the sealed scopes (§S)** (audit of 2026-10-30, through the public API with the default locators). The storages' own names never clash: not within `.app`, not between `.app` and `.appGroup`, not between the root and namespaces, and not where File and SQLite share a folder. What does clash, most severe first:
  1. **UserDefaults suites that are the global domain.** `UserDefaults(suiteName:)` rejects `NSGlobalDomain`, but accepts `.GlobalPreferences`, `kCFPreferencesAnyApplication` and `Apple Global Domain`, and writes through them land in the global domain (measured on the Simulator). `.standard`, every suite and every App Group then fetch the value, and their `delete` and `clear()` most likely can't remove it (not measured). Fix: `.invalidSuiteName` for these names, and for the app scope's own suite name (§5.4). Documented on UserDefaults' group scope. It's the one system gotcha with a check, because it lets two scopes reach each other's values.
  2. **The layers merge names the storages keep apart.** Swift's `==` is canonical, so scopes or keys that differ only in Unicode form (`"é"`, `"e\u{301}"`) are one entry in `UnifiedStorage`'s storage cache and in the observation registry (measured). The scope used first gets both scopes' values, and an observer of `"é"` receives a value saved under `"e\u{301}"`. Fix: compare names by bytes in the layers too (§4.3). The `String` keys of SQLite, UserDefaults, Ubiquitous and InMemory can't change `==`, so either they become `Key` structs like File's and Keychain's, or the layers compare bytes themselves.
  3. **Observation misses changes between keys that reach one value:** File keys that differ in `protection`, Keychain keys that differ in `accessibility`, different value types (§6.3 already plans this one), and the scope pairs in items 4 and 5.
  4. **SQLite scopes that differ only in `protection` share one database.** Each `clear()` empties both, and each open re-applies its class, so opening the `.none` scope downgrades the `.complete` one's files. Fix: move protection out of the scope, into an init parameter, so a scope only names a place.
  5. **UserDefaults `.app(.suite(named: g))` is `.appGroup(groupId: g)`**, because the group's suite is the suite named after it. Fix: document it.

### 4.6 Only the storage's own values

One rule in every storage: the library never replaces or removes other code's data. In File, UserDefaults and Ubiquitous, an entry is a value only if it has the storage's value type, and anything else at a key's place is other code's: `fetch` returns `nil`, `delete` and `clear()` never remove it, and `save` throws the storage's "occupied" error instead of replacing it. Keychain needs no check (§5.2).

| Storage | A value is | Otherwise |
|---|---|---|
| File | a regular file, never a folder or a link | `.pathOccupied(URL)` |
| UserDefaults | a `Data` object; registered defaults count, process-wide | `.keyOccupied(storedKey)` |
| Ubiquitous | a `Data` object | `.keyOccupied(storedKey)` |
| Keychain | any generic password at the scope's service and account, one without data included (it fetches as `nil`) | — (§5.2: under the scope's own names, an item holds nothing of other code's to keep) |
| SQLite, InMemory | — | exclusive locations: the database file and the bucket are the scope's alone, and their values are typed (`BLOB`, `Data`), so there is no other code's entry to keep |

- **Done: Keychain has no check** (§5.2, 2026-10-30). The rule is "never destroy other code's data": File keeps protecting folders and links, and UserDefaults and Ubiquitous keep their type check, which reads memory, not encrypted data. Keychain's check decrypted the item, which fails while locked, and an item without data at the scope's names holds nothing to lose.

## 5. Storages

Common shape for every storage, matching `FileStorage` today:

```
Storages/<Name>/
  <Name>.swift                 final class, business logic only
  <Name>+Scope.swift           Namespace, AppScope, Scope
  <Name>+Error.swift
  <Name>+Key.swift
  Dependencies/                what the storage is given: injected, public, with open defaults
    <Name>BackingStore.swift   protocol + open Default<Name>BackingStoreWrapper
    <Name>Locator.swift        protocol + open Default<Name>Locator
```

**Backing vocabulary.** Backing protocols use short names that are the same across storages, instead of copying each system API. Each member's doc comment names the system call it maps to. Default adapters wrap system types rather than extending them, so the library adds no methods to `UserDefaults` and similar types.

| | read | write | remove | list | remove all |
|---|---|---|---|---|---|
| UserDefaults suite, Ubiquitous, SQLite database | `read(forKey:)` | `write(_:forKey:)` | `remove(forKey:)` | `keys()` (UserDefaults, Ubiquitous) | `removeAll()` (SQLite) |
| InMemory | `read(forKey:in:)` | `write(_:forKey:in:)` | `remove(forKey:in:)` | — | `removeAll(in:)` |
| File | `read(at:)` | `write(_:at:options:)` | `remove(at:)` | `itemNames(at:)` | — |
| Keychain (queries) | `read(_:)` | `add(_:)` / `update(_:with:)` | `remove(_:)` | — | — |

The setup members are `createDirectory(at:)` (always creates intermediate directories), SQLite's `open(at:protection:)`, and UserDefaults' `standard` and `suite(named:)`.

### 5.1 Scope → location (the default locators)

**Planned:** §S's places replace this table.

| Storage | Scope | Resolves to |
|---|---|---|
| File | `.app(.applicationSupport/.cache/.documents/.temporary/.directory(at: u), namespace: n)` | `<base or u>[/<n>]/<encoded key>` |
| File | `.appGroup(g, namespace: n)` | `<group container g>[/<n>]/<encoded key>` |
| SQLite | same as File, plus `protection:` (default `.inherited`) | `<folder>[/<n>]/.KeyValueStorage.sqlite` (+ `-wal`, `-shm`), opened in the scope's protection class |
| UserDefaults | `.app(.standard, namespace: n)` | `UserDefaults.standard` |
| UserDefaults | `.app(.suite(named: s), namespace: n)` | suite `s` |
| UserDefaults | `.appGroup(g, namespace: n)` | suite `g` |
| UserDefaults, Ubiquitous | `.keyPrefix(named: n)` | keys stored as `"<n with % → %25, / → %2F>/<key>"`; at the root (`nil`), keys stored with `%` → `%25` and `/` → `%2F` (§4.5) |
| Keychain | `.app(namespace: n)` | `kSecAttrService = n` (root `""`, empty `%`; `%` and `/` escaped), no access group: saves go to the app's default one, queries search them all |
| Keychain | `.appGroup(g, namespace: n)` | `kSecAttrService = <g>/<n>` (root `<g>/`), `kSecAttrAccessGroup = g` |
| InMemory | `.app(namespace: n)` | bucket `n` (`nil` is a bucket of its own) |
| Ubiquitous | `.shared(namespace: n)` | `NSUbiquitousKeyValueStore.default` (the store of the target's kvstore entitlement) |

Defaults: every `default` scope uses the namespace `"KeyValueStorage"`: File and SQLite `.app(.applicationSupport, namespace: .directory(named:))`, UserDefaults `.app(.suite(named: "KeyValueStorage"), namespace: .keyPrefix(named:))`, Keychain `.app(namespace: .service(named:))`, InMemory `.app(namespace: .bucket(named:))`, Ubiquitous `.shared(namespace: .keyPrefix(named:))`.

The root encodings (§4.5) and the Keychain services are done.

### 5.2 KeychainStorage (done)

**Backing store:** `KeychainBackingStore`, one Security call per member: `read` (`SecItemCopyMatching`), `add`, `update` and `remove` (`SecItemDelete`, every item the query matches), each taking a `KeychainQuery`. No call lists items, so `KeychainQuery` has no `returnAttributes` and its only match limit is `.one`.

**Locator:** `service(for:)` is the namespace, `""` at the root and `%` for an empty name; an App Group's is `<group>/<namespace>`, with `%` and `/` escaped byte by byte in both. `accessGroup(for:)` is `nil` for an app scope, so saves go to the app's default group, and the App Group's ID otherwise. `account(forKey:in:)` keeps the key's exact bytes.

**Storage:** no call reads an item first (done 2026-10-30). Reading decrypts the item, so a `.whenUnlocked` item couldn't even be deleted while the device was locked; and the read only told an item without data from a value. Anything at the scope's service and account is the scope's, and an item without data holds nothing to lose (§4.6).
  - `fetch` reads with `returnData` and `.one`; an item without data → `nil`;
  - `save` updates the item's data and accessibility, and adds the item if the update finds none. If another process adds it in between, the add's `errSecDuplicateItem` is thrown;
  - `delete` removes the key's item, and `clear()` every item of the scope's service and access group, synchronizable or not, in one call each; "not found" is no error;
  - the internal `Item` enum, its `.other` case and Keychain's `.keyOccupied` are gone. Any other status → `.os(status)`.
- **Planned: the app scope's service carries the app's identifier** (2026-10-30): `<identifier>:<namespace>`, where the identifier is the bundle ID, or the process name without one, escaped like the namespace, `:` included.
  - Why: saves without an access group go to the first Keychain Sharing entry. When a developer lists a shared group first, two apps' app-scope items land in one group, and the same namespace made them the same items. With the identifier in the service they stay apart, and an extension's are its own.
  - Bundle IDs have no `/`, and the namespace's is escaped, so app services still never contain `/`, unlike App Group services (§4.5).
  - Same rule as File and SQLite paths (D9): every app-scope place carries the app's identifier.
  - Remains: apps that share the default access group can read, change and delete the items with their own keychain code, never through the library's app scopes. That's the first Keychain Sharing group if the app lists any, otherwise the app's own identifier, which another app of the team can list on purpose. The docs of `.own` and of `.iCloud`'s `.own` say so.
- **Interop:** App Group items move to service `<group>/<namespace>`; an app scope's service changes only for a namespace with `%` or `/`; the root's queries now name service `""`, which items saved without a service also have. Reading items written before needs a custom locator. A CHANGELOG note.

**Measured in KeychainHost (iOS Simulator):**
- service `""` matches items saved with `""` or without a service, and no other service; a query without a service matches every service;
- the default access group is the first `keychain-access-groups` entry; a query without a group finds App Group items, and naming a group keeps others out;
- a group the app isn't entitled to → `errSecMissingEntitlement`;
- an item added without data reads as success with a `nil` result;
- a synchronizable and a non-synchronizable item with the same service and account are separate items;
- `kSecReturnData` with `kSecMatchLimitAll` lists every item, with data where it has some.

### 5.3 FileStorage (done: the locator pilot)

**Backing store:** `FileBackingStore`, one `FileManager` or `Data` call per member, with no logic (E0): `itemType(at:)` (`attributesOfItem(atPath:)[.type]`, which describes a link itself), `read(at:)`, `write(_:at:options:)`, `remove(at:)` (`removeItem`, which deletes a folder with everything inside, so the storage calls it only for a file), `createDirectory(at:)` (with intermediates) and `itemNames(at:)` (every name in the folder). Path-based on purpose: `URL.resourceValues` caches answers on the URL instance, and a cached answer survives the file's removal.

**Locator:** `FileLocator` / `DefaultFileLocator`, which owns all naming:
- `directory(for:)`: the scope's base directory, from the locator's own lookups (§4.2), or the namespace's subfolder in it, named with the same encoding as keys plus a trailing `!`. The namespace is encoded first (`.invalidNamespace` over 255 bytes, mark included).
- `fileName(forKey:in:)`: one lossless encoding of the key's exact UTF-8 bytes, so nothing is rejected but length (`.invalidKey` over 255 bytes):
  - `a`–`z`, `0`–`9`, `_` and `-` stay; a capital is `!` and its lowercase letter; every other byte is `%` and two lowercase hex digits; the empty key is `%`.
  - Every name is one ASCII word without capitals, `.` or whitespace: no extension, no dot file, nothing a volume rejects (FAT's `"*:<>?\|`, a trailing `.` or space), and no two names that a case-insensitive or normalizing volume sees as one. Verified on APFS (both cases), HFS+, exFAT and FAT32.
  - Each byte becomes one token, and the three token kinds start with different characters, so a name splits one way only: no collisions.
  - No normalization: keys are their exact bytes, as in UserDefaults, the keychain and SQLite, so `"é"` and `"e\u{301}"` are two keys. Foundation's `precomposedStringWithCanonicalMapping` maps some keys that Swift's `==` keeps apart to one string (`"\u{10410}\u{306}"` → `"Ӑ"`), and `removingPercentEncoding` drops a leading U+FEFF, so the locator uses neither.
  - Longest keys: 255 lowercase letters, digits, `_` or `-`; 127 capitals; 42 Cyrillic or accented letters; 28 CJK characters; 21 emoji.
- `key(forFileName:in:)`: decodes, and returns the key only if it encodes back to the same name, so it claims exactly the names the encoding writes.
- `key(forFileName:in:)`: the exact inverse of the default names.
- A subclass that changes names overrides both name methods and can call `super` in both.

**Storage (business logic only): files are values, folders are namespaces.** It checks what is at a path, then acts:
- **The check:** `itemType(at:)`; `fileReadNoSuchFile` means nothing is there, and every other error is thrown, so an unreadable path never passes for an empty one.
- **A value is a regular file in the scope's folder.** The folder is checked first, so a file in its place is never looked into. Without one, `fetch` returns `nil`, and `delete` and `clear()` do nothing.
- **Links are never followed:** a link is neither a value nor a folder, and is never read, written or removed. The scope's folder itself must not be a link (`AppScope.directory(at:)` says to resolve it first).
- **`save`** creates a missing folder, then writes atomically with the key's protection. Anything but a folder where the folder goes, such as another app's file → `.pathOccupied(folder)`. Anything but a file at the key's path, such as another app's folder or a link → `.pathOccupied(file)`. Nothing is ever replaced.
- **`delete`** removes the key's file; anything else at its path stays.
- **`clear()`** lists the folder and removes a name only if the locator maps it to a key *and* that key back to the same name, and a file is there. So neither a folder with a key's name nor a locator whose two methods disagree can make it remove anything else. It stops at the first failure.
- **Errors:** `.protectedDataUnavailable` for Cocoa no-permission with an underlying `EPERM` (from 3.x); every other system error is `.other(error)`, the original error. A failed check is an error, never "no value".
- **Races:** if another process changes a path between a check and the call, the call's error is thrown (such as a file removed meanwhile). The one destructive case: a file swapped for a folder between `delete`'s check and its removal makes `removeItem` delete that folder. It needs a delete and a create of the same name at the same instant, and is documented.

`writingOptions(for:)` has a `#available(macOS 11, *)` fallback that can't run on any CI host. It's the only uncovered region (open decision 1).

### 5.4 UserDefaultsStorage (done)

**Backing store:** `UserDefaultsBackingStore` (`standard`, `suite(named:)`) opens a `UserDefaultsSuite`, one call per member: `read(forKey:)` (`object(forKey:)`: any property-list value, registered defaults included), `write(_:forKey:)`, `remove(forKey:)` and `keys()` (`dictionaryRepresentation().keys`, the global domain's included).

**Locator:** `suite(for:)` is an app scope's suite, or the App Group's suite named after the group. `storedKey(forKey:in:)` is `<namespace>/<key>`, or the root key as is, with `%` → `%25` and `/` → `%2F` in the namespace and in root keys, so a root key never contains `/` and never equals a namespace's. It escapes byte by byte: Foundation's `replacingOccurrences` skips a `/` that carries a combining mark. `key(forStoredKey:in:)` is the exact inverse, compared by bytes.

**Storage:** only `Data` is a value (§4.6). `fetch` returns `nil` for anything else; `save` throws `.keyOccupied(storedKey)` instead of replacing it; `delete` and `clear()` never remove it. `clear()` removes the `Data` at every stored key the locator claims and maps back byte for byte. Keys are exact bytes: the suite keeps `"é"` and `"e\u{301}"` apart.
- Registered defaults are process-wide, so a registered non-`Data` default under a stored key makes `save` throw in every suite.
- `keys()` lists the global domain's keys too, but removing one only touches the suite's own domain, so a root `clear()` never changes the global domain.
- **Interop:** root keys containing `%` or `/` are stored escaped (`a/b` → `a%2Fb`); other keys are unchanged. A CHANGELOG note.
- **Planned with the sealed scopes** (2026-10-30, §13 item 8):
  - The app scope uses a suite of the library's own, `<encoded bundle ID>.KeyValueStorage` (the identifier in File's lossless encoding, §S), never `.standard`. Only the library writes there, so other code's keys never meet ours; the common reset call `UserDefaults.standard.removePersistentDomain(forName: bundleID)` can't wipe our values; and `.standard`, which loads at launch, stays small. A custom locator can still map a scope to `.standard`.
  - Stored keys are `<namespace>!/<key>`, the namespace escaped as today. The `!` marks the library's entries in App Group suites, which must be named after the group, so other code in the group writes there too. One format in every suite.
  - `.appGroup` rejects an empty id, the global domain's names and the app scope's suite name as group ids (§4.5, item 1).

### 5.5 InMemoryStorage (done)

**Backing store:** `InMemoryBackingStore` (`read`, `write`, `remove` and `removeAll`, each in a bucket). `DefaultInMemoryBackingStoreWrapper` is process-wide memory behind a lock; it keys buckets and values by their UTF-8 bytes, because Swift's `String` dictionaries take `"é"` and `"e\u{301}"` for one key.

**Locator:** `bucket(for:)` is the namespace's name, `nil` at the root; `storedKey(forKey:in:)` keeps the key as is. Both are non-throwing (`Error == Never`).

**Storage:** `clear()` empties the scope's bucket, which is the scope's alone (§4.5). Values are typed `Data`, so §4.6 has nothing to keep.

### 5.6 SQLiteStorage (done)

**Backing store:** `SQLiteBackingStore` (`createDirectory(at:)` with intermediates, `open(at:protection:)`) opens an `SQLiteDatabase` (`read`, `write`, `remove`, `removeAll`), whose errors are `SQLiteError(code:message:)`. `DefaultSQLiteDatabase` is the connection: `FULLMUTEX`, WAL, a 1 s busy timeout, one `WITHOUT ROWID` table, four prepared statements, NUL-safe key binding and `zeroblob` for empty values. The prepared statements make an instance unsafe to share between threads (D2); two instances have separate connections. A failed open closes what it opened, and nothing traps.

**Locator:** `databaseURL(for:)` is the scope's folder, named as `DefaultFileLocator` names it (§5.3, `!` mark included), so file and SQLite storages of one namespace share a folder, plus the hidden `.KeyValueStorage.sqlite`. `storedKey(forKey:in:)` keeps the key's exact bytes. The locator looks up its system directories itself (§4.2).

**Storage:** resolves the URL, creates its folder, and opens the database with the scope's protection. `clear()` empties the database, which is the scope's alone. `SQLiteError` → `.sqlite(code:message:)`, anything else → `.other`.
- Nothing that isn't the storage's is removed or replaced: a file where the folder goes → `.other` (the `createDirectory` error); a folder at the database path → `.sqlite(SQLITE_CANTOPEN)`; a corrupt file → `.sqlite(SQLITE_NOTADB)`; another app's `KeyValueStorage` view → `.sqlite(SQLITE_ERROR)`.
- **Links are followed**, unlike `FileStorage`: `SQLITE_OPEN_NOFOLLOW` rejects a link anywhere in the path, including `/var` → `/private/var` above every temporary and app-container path, so it can't be used.
- **Protection** (`SQLiteStorage.Protection`, part of the scope, default `.inherited`) is per database, because every key shares one file. It maps to a `SQLITE_OPEN_FILEPROTECTION_*` flag, which also covers `-wal` and `-shm`, and is re-applied on every open. Verified on macOS for `.complete`, `.completeUnlessOpen` and `.completeUntilFirstUserAuthentication`; macOS reports the default class for `.none`. Still to confirm on a locked iOS device (§13, item 7): the result code a `.complete` database fails with, which could map to a `.protectedDataUnavailable` like `FileStorage`'s.

### 5.7 UbiquitousStorage (done)

**Backing store:** `UbiquitousBackingStore`, one `NSUbiquitousKeyValueStore.default` call per member: `read(forKey:)` (`object(forKey:)`), `write(_:forKey:)`, `remove(forKey:)`, `keys()` (`dictionaryRepresentation.keys`) and `synchronize()`.

**Locator:** the same scheme as UserDefaults' (§5.4): `<namespace>/<key>` or the root key as is, `%` and `/` escaped byte by byte in the namespace and in root keys, and an exact, byte-compared inverse. `storedKey(forKey:in:)` also enforces the store's limit: a stored key, prefix and escapes included, of more than 128 UTF-16 code units throws `.invalidKey(key)`, because the store raises an Objective-C exception, a crash, for longer keys.

**Storage:** only `Data` is a value (§4.6): `fetch` returns `nil` for anything else, `save` throws `.keyOccupied(storedKey)` instead of replacing it, and `delete` and `clear()` never remove it. `clear()` removes the `Data` at every stored key the locator claims and maps back byte for byte. `save` checks the key, then the 1 MB value limit (`.valueTooLarge`), both before calling the store.

- **Availability:** `@available(watchOS 9.0, *)`, matching `NSUbiquitousKeyValueStore`; the package supports watchOS 6. Raising the watchOS minimum to 9 would remove the annotations (see Open decisions).
- **Store and sharing:** a process can reach exactly one store, `NSUbiquitousKeyValueStore.default`, chosen only by its signed `com.apple.developer.ubiquity-kvstore-identifier` entitlement and the Apple Account. There's no API to pick a store, App Groups have no effect on it, and on iOS the code can't read the entitlement. So the scope has one case, `.shared(namespace:)`. The docs explain the setup:
  - one app keeps Xcode's default identifier, `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`;
  - an app and its extensions, or apps of one team, set the same value in every target's entitlements;
  - an extension that keeps its default identifier silently gets its own store.
- **Limits it documents but can't enforce:** 1024 keys and 1 MB in total. Exceeding them fails silently and is reported only through `didChangeExternallyNotification` with `NSUbiquitousKeyValueStoreQuotaViolationChange`.
- **Planned with the sealed scopes:** stored keys are `<namespace>!/<key>`, as in UserDefaults (§5.4). The store is shared with the app's other code and its SDKs, and the `!` marks the library's entries; it counts toward the 128-unit limit.
- **Without the entitlement** (test bundles, unsigned builds) the store keeps nothing, lists nothing, never raises, and `synchronize()` returns `false`. So the default adapter has no integration tests; covering it needs a signed host app with the entitlement and an Apple Account.
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
  - Also not observed, with the sealed scopes (§S): changes from the user's other devices, which `.iCloud` scopes receive through sync; the system emptying `.cache` and `.temporary`; and the keychain deleting `.whileLockedOrWithoutPasscode` items when the passcode is removed. Observers keep showing values that are gone or stale until the next change made through the library.

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
- Direct `FileManager`/`Bundle` use inside storages and locators.
- `StorageDirectory`, `StorageDirectoryError` and `StorageDirectoryLookup`: the default File and SQLite locators look up their folders themselves (§4.2).
- `KeyNamespace`: the UserDefaults and Ubiquitous locators build their key prefixes.
- Stale leftovers: `Storages/Layers/` index entries (run `git add -A Sources` once the tree is consistent).

## 10. File layout

```
Sources/KeyValueStorage/
  Core/        KeyValueDataStorage.swift, KeyValueScopeProviding.swift
  Storages/    FileStorage/ SQLiteStorage/ KeychainStorage/ UserDefaultsStorage/ InMemoryStorage/
               (each: <Name>.swift, +Scope, +Error, +Key, Dependencies/ with BackingStore and Locator)
  Coding/      DataCoder.swift, JSONDataCoder.swift, PropertyListDataCoder.swift, RawDataCoder.swift,
               KeyValueCodingStorage.swift, KeyValueCodingStorageKey.swift,
               Observation/ObservationRegistry.swift, Observation/KeyValuePublisher.swift
  Isolation/   IsolatedKeyValueStorage.swift
  Unified/     UnifiedStorage.swift, IsolatedUnifiedStorage.swift, UnifiedStorageKey.swift,
               UnifiedStorageFactory.swift, Typealiases.swift
  Resources/   PrivacyInfo.xcprivacy
Tests/
  KeyValueStorageTests/              unit tests with mocks (@testable)
    Storages/<Name>StorageTests.swift, Coding/…, Isolation/…, Unified/…
    Mocks/<Name>BackingStoreMock.swift, <Name>LocatorStub.swift, FixedDirectoriesFileLocator.swift, DataCoderMock.swift, DataStorageMock.swift
    Support/                         typed assertThrows, locator law helpers
  KeyValueStorageIntegrationTests/   NEW target: default adapters against the real system
  KeyValueStoragePublicAPITests/     no @testable: what clients can reach, isolation contexts
  KeychainHost/                      app host for real-keychain integration tests
```

## 11. Testing strategy

### 11.1 Rules

- **Storage classes, the coding layer, the isolation layer and the facade: 100% coverage with mocks.** Every outcome of every `if`/`guard`/`switch`/`catch` has a test, and each test asserts both the result and the exact backing calls (arguments recorded by the mock).
- **Default locators:** tested directly (no backing mocks, system directories at fixed paths) against their inventory and the §4.5 laws, with 100% coverage.
- **Default adapters** (`Default*BackingStoreWrapper`, `DefaultUserDefaultsSuite`, `DefaultSQLiteDatabase`, `DefaultInMemoryBackingStoreWrapper`): integration tests against the real system. Failures the system won't produce on demand are documented as uncovered.
- **Mocks:** final classes conforming to the backing protocols. They record calls (in order, with arguments) and return or throw scripted results per call. No subclassing of Apple classes.
- **Measuring:** Swift's coverage data has line and region counters, not branch counters (llvm-cov's branch columns stay empty for Swift; verify on the CI toolchain). Each branch arm is its own region, so the gate is **100% region and line coverage** for the gated files, plus the outcome inventories below as the checklist.

### 11.2 Outcome inventories

**Scope → folder** (default File and SQLite locators, with fixed system directories): each case builds the right path, with and without a namespace. Application Support, Caches and Documents each return `nil` → `.directoryNotFound(directory)`. A `nil` group container → `.groupDirectoryNotFound(id)`. A URL that isn't a file URL → `.invalidDirectory`. The temporary directory never fails. Namespaces are encoded like keys, a name over 255 bytes throws before the lookups, and no two namespaces or the root share a folder, compared case-insensitively.

**DefaultKeychainLocator** (`DefaultKeychainLocatorTests`, no mocks)
- services for the root, a namespace, the empty name, escapes (also with a combining mark), App Groups with and without a namespace;
- no two scopes, app or App Group, share a service, over names that mimic each other's escapes and separators;
- access groups; accounts are the keys' exact bytes.

**KeychainStorage** (`KeychainStorageTests`; `KeychainBackingStoreMock`, an in-memory keychain with the real query rules, and `KeychainLocatorStub`)
- queries use exactly the locator's names; `scope` is the one given;
- the exact queries: `fetch` reads with `returnData` and `.one`; `save` updates with a query without accessibility and data, then adds with them; synchronizable keys are items of their own;
- no read before a call: `save` updates, then adds only if there's no item; `fetch`, `delete` and `clear()` are one call each;
- an item without data fetches as `nil`, and `save`, `delete` and `clear()` replace and remove it like a value;
- delete; `clear()` removes every item of the scope, synchronizable or not and without data included, and nothing else; without items it succeeds;
- every failing read, add, update and remove → `.os(status)`, and nothing changes; an item added between `save`'s update and add → `.os(errSecDuplicateItem)`;
- `set`; the root, an app namespace and App Groups (one of them the default access group) never reach each other's items.

**DefaultFileLocator** (`DefaultFileLocatorTests`, no mocks)
- **File names:**
  - `a`–`z`, `0`–`9`, `_` and `-` stay; capitals are `!` and their letter; `.`, whitespace, `/`, NUL, `!`, `%`, `~`, non-ASCII and emoji are `%xx`; the empty key is `%`;
  - the two spellings of `é` get two names;
  - exactly 255 bytes is valid; 256 lowercase letters, 128 capitals or 22 emoji → `.invalidKey(key)`.
- **Namespaces:** encoded like keys plus `!`; 254 bytes encoded is the longest; no key's file and namespace's folder share a name.
- **Reverse mapping**, not claimed: dot files, raw capitals, `.`, spaces or non-ASCII, a lone or misplaced `!`, `%%`, malformed escapes, uppercase or needless escapes (`%2E`, `%41`), escapes that aren't UTF-8, names over 255 bytes.
- **Subclassing:** a subclass calling `super` in both name methods keeps the laws.
- **Laws L1, L2 and L4** over every ASCII character and a case and Unicode corpus (including the pairs Foundation's NFC merges), with APFS's case-insensitive, canonical comparison and keys compared by exact scalars. L3: namespaces and the root never share a folder.
- **Exhaustive, once, outside the suite:** every Unicode scalar, every ASCII key of up to 3 characters, 2M pairs of case, combining, jamo and joiner scalars, and 1M random strings round-trip exactly with no collisions; of 813,615 names over a mixed alphabet, only the encoder's own are claimed.

**FileStorage** (`FileStorageTests`; `FileBackingStoreMock`, an in-memory file system with `FileManager`'s rules; the real locator, and `FileLocatorStub`)
- **Init:**
  - no file system calls;
  - the locator's error is thrown as is;
  - `scope` is the one given.
- **Locator use:**
  - the locator gets the scope and `key.name`, and its names are used verbatim;
  - its errors and invalid keys stop before any file system call.
- **Files are values, folders are namespaces**, over every no-value state (no folder, no file, a folder or a link at the file's path, a file or a link where the folder goes):
  - `fetch` returns `nil` without reading, and `delete` removes nothing;
  - a value where the folder goes is never looked into.
- **Save:**
  - options for each of the 5 protections (always `.atomic`);
  - creates the folder, and replaces the file;
  - never replaces what isn't the scope's: `.pathOccupied(file)` for a folder or a link, `.pathOccupied(folder)` for a file or a link where the folder goes.
- **Delete:** removes only the key's file.
- **Clear:**
  - only the files the locator claims, and whose key maps back to the same name; never SQLite's files, dot files, names no key produces, or a folder with a key's name;
  - no folder, or a file in its place → no-op;
  - it stops at the first failure.
- **Set:** saves a value and deletes `nil`.
- **Errors:** every call of every operation, failing in turn, is reported as `.other`, never taken for no value (only `fileReadNoSuchFile` from `itemType` means nothing is there); `EPERM` under a permission error is the only protected-data case (wrong code, domain, missing or non-Cocoa underlying error, or another POSIX code → `.other`).

**File integration** (`FileIntegrationTests`, real file system)
- **Adapter:**
  - `itemType` describes links themselves, and the listing has every name;
  - only a missing item throws `fileReadNoSuchFile`; a folder it may not look into and a path under a file throw other errors;
  - the default locator's lookups match `FileManager`.
- **Values:**
  - round trips, with case-only keys and the two spellings of `é` apart;
  - every key of up to two printable ASCII characters has a file of its own on the real volume, and `clear()` removes them all;
  - only saves create the folder;
  - instances that share a folder see each other's changes;
  - overwrites never expose a missing or partial value.
- **Clashes:**
  - a root key and a namespace with the same name coexist, and the root's `clear()` leaves the namespace;
  - another app's folder at a key's path is never a value and never removed;
  - a file where the folder goes is never a value and never removed;
  - `clear()` is exact across a root, a namespace and SQLite storages in one folder (only a key-producible foreign name is claimed, as documented).
- **Links:** a link to a file or a folder at a key's path is never a value and never touched, and `save` reports it; a link in the scope's folder's place is never followed.
- **Permissions:** a read-only folder reports `EACCES` and changes nothing; a folder that can't be looked into reports `EACCES` and is never taken for empty; an unreadable file reports `EACCES` and can still be deleted.

**DefaultUserDefaultsLocator** (`DefaultUserDefaultsLocatorTests`, no mocks)
- each scope's suite; an App Group's keys are prefixed like an app scope's;
- namespaced keys: `ns/key`, `/` and `%` in the namespace escaped (also with a combining mark), an empty namespace, a key with `/` and `%` kept as is;
- root keys escape only `%` and `/`;
- not claimed: a root `a/b`, `%41`, `%2f`, a lone or trailing `%`; for a namespace, its name alone, another namespace's keys, an escaped `/` or another case;
- laws within each scope, with bytes as the comparison; no two scopes, the root included, share or claim each other's stored keys.

**UserDefaultsStorage** (`UserDefaultsStorageTests`; `UserDefaultsBackingStoreMock`, `UserDefaultsLocatorStub`)
- init: the locator's suite, `standard` or named; a name `UserDefaults` rejects → `.invalidSuiteName`; `scope` is the one given;
- only `Data` is a value: a string, number, Boolean, date, array or dictionary under a key is never fetched, replaced or removed, and `save` throws `.keyOccupied`;
- `save` writes and replaces `Data`; `delete` removes it, and reads nothing else;
- `clear()` removes only the `Data` at claimed stored keys; it skips keys the locator maps to a key with another stored key, also when they differ only in how `é` is written;
- `set`.

**DefaultInMemoryLocator** (`DefaultInMemoryLocatorTests`): the bucket is the namespace's name (`nil` at the root, `""` kept); keys are stored as their exact scalars.

**InMemoryStorage** (`InMemoryStorageTests`; `InMemoryBackingStoreMock`, `InMemoryLocatorStub`): every operation uses exactly the locator's names; `clear()` empties only the scope's bucket; `set`; `scope` is the one given; with the default store, the root, the empty name, case variants and both spellings of `é` never reach each other's values, and keys are exact too.

**DefaultSQLiteLocator** (`DefaultSQLiteLocatorTests`, fixed system directories)
- each app scope and the App Group → `<folder>[/<namespace>!]/.KeyValueStorage.sqlite`; the default scope; protection doesn't change the path;
- missing directories → `.directoryNotFound(directory)`; a missing group container → `.groupDirectoryNotFound`; a URL that isn't a file URL → `.invalidDirectory`;
- namespace folders equal `DefaultFileLocator`'s over every ASCII character and Unicode names; 254 encoded bytes is the longest; the namespace is checked before the lookups;
- keys are stored as their exact scalars.

**SQLiteStorage** (`SQLiteStorageTests`; `SQLiteBackingStoreMock`, `SQLiteLocatorStub`)
- init: creates the folder of the locator's URL, then opens the URL; a locator error stops before any call; a folder that can't be created → `.other`, and nothing is opened; `open` → `.sqlite` for an `SQLiteError`, `.other` otherwise;
- protection: each of the 5 cases, for `.app` and `.appGroup`, reaches `open` as the matching `FileProtectionType?` (`.inherited` → `nil`);
- fetch, save, delete and clear use exactly the locator's stored keys; `set`; every operation reports an `SQLiteError` as `.sqlite` and anything else as `.other`;
- `scope` is the one given.

**DefaultUbiquitousLocator** (`DefaultUbiquitousLocatorTests`, no mocks)
- namespaced keys and root keys as in `DefaultUserDefaultsLocatorTests`, a `/` with a combining mark included;
- exactly 128 UTF-16 code units passes and one more throws `.invalidKey(key)`, for a root key, a namespaced key, escapes and emoji;
- not claimed: the UserDefaults cases, and a stored key over the limit;
- laws within each scope, by bytes; no two scopes share or claim each other's stored keys.

**UbiquitousStorage** (`UbiquitousStorageTests`; `UbiquitousBackingStoreMock`, `UbiquitousLocatorStub`)
- locator errors stop fetch, save and delete before the store; `scope` is the one given;
- only `Data` is a value: a string, number, Boolean, date, array or dictionary under a key is never fetched, replaced or removed, and `save` throws `.keyOccupied`;
- `save` writes and replaces `Data`; exactly 1 MB is stored, one byte more throws `.valueTooLarge` before the store; `delete` removes `Data`;
- `clear()` removes only the `Data` at claimed stored keys; it skips keys the locator maps to another stored key (also by how `é` is written) or to an invalid key;
- `set`; `synchronize()` returns the store's result.

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
- **SQLite** (`SQLiteIntegrationTests`, done):
  - the locator's lookups match `FileManager`; the database, `-wal` and `-shm` are hidden in the namespace's folder; each open applies the scope's protection to the database and its log;
  - persistence across instances; instances sharing a database see each other's changes; values round-trip exactly (empty, every byte, 1 MB); keys that differ in case, after a NUL, or in how `é` is written are separate rows;
  - a file where the folder goes → `.other`, kept; a folder at the database path → `SQLITE_CANTOPEN`; a corrupt database → `SQLITE_NOTADB`, kept; another app's view → `SQLITE_ERROR`;
  - a lock held by another connection → `SQLITE_BUSY` after the 1 s timeout, reads still working in WAL mode; a dropped table → `SQLITE_ERROR` until reopened.
  - Uncovered: `sqlite3_open_v2` returning no handle, which happens only out of memory.
- **UserDefaults** (`UserDefaultsIntegrationTests`, done; a suite of each test's own, removed in teardown):
  - values persist across instances; stored keys are the locator's exact bytes (`a%2Fb`, `ns/a/b`, both spellings of `é`, the empty key); `.standard` is `UserDefaults.standard`;
  - a value of another type is never replaced or removed; a registered non-`Data` default occupies its key;
  - `clear()` is exact across the root, two namespaces, other code's data and values of other types, and never changes the global domain;
  - `NSGlobalDomain` → `.invalidSuiteName`.
- **`DefaultInMemoryBackingStoreWrapper`** (`DefaultInMemoryBackingStoreWrapperTests`, unit target): concurrent access is serialized, and released values are freed after unlocking.
- **Keychain** (`KeychainIntegrationTests` in KeychainHost, done; the 3.x tests are ported and deleted):
  - values round-trip and persist; accessibility is set on add and on update; synchronizable keys are items of their own;
  - the root never reaches namespaced items; an app scope and App Groups, one of them the default group, never reach each other's items;
  - a group the app isn't entitled to → `.os(errSecMissingEntitlement)`;
  - an item without data fetches as `nil`, and `save`, `delete` and `clear()` replace and remove it; items without a service share the root, as documented.
- **End-to-end:** one save/fetch/clear per storage through `UnifiedStorage` with real backings in temporary scopes.
- **To add: the system behavior the scope docs state** (2026-10-30), so no comment rests on reasoning alone:
  - iOS Simulator: a UserDefaults suite named after an App Group the app isn't entitled to works and reports nothing, and its plist lands in the app's own container;
  - macOS: `containerURL(forSecurityApplicationGroupIdentifier:)` returns a path for any id, and two ids that differ only in case get paths that differ only in case, on a volume that ignores case. The test checks paths and the volume, without creating folders in `~/Library/Group Containers`;
  - macOS: whether two UserDefaults suites whose names differ only in case share values in the process, and on disk;
  - the docs are then worded after what these tests measure.
- **To add: a test for every behavior the plan or the docs assume without a measurement** (2026-10-30). Known so far, besides the system behavior above:
  - a NUL in UserDefaults, Ubiquitous and Keychain names: whether the system keeps the whole string. If one cuts at the NUL, two keys would merge, so that storage escapes NUL like `%` and `/`;
  - an empty key and an empty namespace in every storage, and an empty Keychain account in particular;
  - the encoded app identifier in paths and in UserDefaults' suite name, including bundle IDs that differ only in case;
  - an empty group id throwing in every storage.
- **To do with the sealed scopes: revisit every test suite** and cover every reachable edge case. That means each scope case and parameter, each retention and protection level, empty names, NUL, emoji, both spellings of `é`, maximum lengths (including a whole File or SQLite path at the system's 1024-byte limit), case-only differences, the marks, the rejected names, and two scopes or two storages that share a place. The gated files stay at 100%.
- **To fix: UserDefaults tests leave empty plists behind.** `removePersistentDomain(forName:)` empties a suite but keeps its file: 41 empty `UserDefaultsIntegrationTests-*.plist` were found in `~/Library/Preferences` (2026-10-30). Teardown also deletes the file.

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
| 1 | Core: new `KeyValueDataStorage`; remove global actors and `Sendable` from the protocol | Core tests 100% |
| 2 | **KeychainStorage** onto the new protocol + mock tests (pattern reference for the rest) | Keychain inventory covered |
| 3 | FileStorage: backing gets the resolver members; storage cleanup; mock tests | File inventory covered |
| 4 | UserDefaultsStorage: backing + `UserDefaultsSuite`; mock tests | UserDefaults inventory covered |
| 5 | InMemoryStorage: `DefaultInMemoryBackingStoreWrapper`; mock tests | InMemory inventory covered |
| 6 | SQLiteStorage: extract `DefaultSQLiteBackingStoreWrapper`/`DefaultSQLiteDatabase`; mock tests; move the SQLite integration tests | SQLite inventory covered |
| 6b | **Sealed scopes** (§S, Appendix A): `ExactString`, the new scopes, places and marks, the planned items of §5.2–5.7, the error refactor (§4.4) and the test revisit (§11.3). Pilot on File, then the other five | §S in all six storages; gated files 100%; macOS, iOS Simulator and KeychainHost green |
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
5. ~~**Typed throws** on the data layer.~~ Adopted: every storage, the locators and the coding layer throw typed errors, and they build for the iOS 13 / macOS 10.15 deployment targets.
6. **watchOS minimum 6 → 9.** That's what `UbiquitousStorage` needs; it would remove its `@available(watchOS 9.0, *)` annotations.
7. **Locked-device errors (deferred: needs a real iPhone).** `ProtectedDataTests` in KeychainHost records what SQLite (each protection class, on an open and on a new connection) and a `.complete` file do while the device is locked, and that both recover after unlocking. It skips on the Simulator and unless `KVS_LOCK_TEST=1`.
   - From its report: map SQLite's locked-database result code to a `.protectedDataUnavailable` case, like `FileStorage`'s, and confirm File's `EPERM` mapping on a device.
   - Also confirm, now that Keychain no longer reads before its calls (§5.2): that the keychain deletes a `.whenUnlocked` item while locked, and that saves at `.complete` and `.whenUnlocked` fail while locked.
   - And, for the sealed scopes (§S): what each protection level does while locked; whether the system deletes a database's files one at a time in `.cache` and `.temporary`; which file protection classes macOS enforces.
   - **Keychain `.iCloud(.appGroup(id:))` with an App Group id**, not a Keychain Sharing group: whether synced items in an App Group access group sync to the user's other devices.
   - **The same key written on two devices before they sync**, for Keychain's and Ubiquitous's `.iCloud` scopes: which value wins. Last writer is likely but not measured; the result becomes a doc line on each `.iCloud` case.
   - **Ubiquitous, in the same device-only run:** a signed host with the iCloud key-value store entitlement and an Apple Account, ideally with a second device to see values sync. Check the key-length limit (128 UTF-16 code units per Apple's docs, 64 UTF-8 bytes per older forum and blog posts), the default adapter's integration tests, the quota, signed-out behavior, and what an unentitled build does (keeps nothing, `synchronize()` returns `false`).
   - Blocker: KeychainHost is ad-hoc signed, and its entitlements hardcode a placeholder team (`ABCDE12345`). Running it on a device needs a signing setup that leaves the committed project alone, such as a local, git-ignored xcconfig with the team and bundle ID, and entitlements built from `$(AppIdentifierPrefix)`.
8. **Who owns the names: the library or the system.** Decided 2026-10-30: **sealed** (§S, D21). The user says what they mean, the library picks the place and owns every name inside it, and interop goes through a custom locator.
   - Rejected, **faithful:** names one to one with the system's, in its terms. Each system's rules would become key rules (`/`, `..`, case, length), the clashes would come back, and `clear()` couldn't tell the scope's entries from other code's.
   - Also rejected: places the user names (`.directory(at:)`, `.suite(named:)`). They make the guarantees depend on the input: URL aliases, global-domain suite names, folders other code writes to.

## 14. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `update` isn't atomic across processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension. This is already in the scope docs.
- **Observation across instances on different actors** has no ordering guarantee; in-process users should go through one facade.
- **Actor I/O on the concurrency pool**, see §7.

## Appendix A. Sealed scopes: the agreed enums and docs

The full public shape of §S, with the doc comments as agreed on 2026-10-30. Implement from this: the `Elsewhere` notes at its end are design notes, not code.

```swift
//
//  KeyValueStorageScopes.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

import Foundation

// MARK: - KeyValueDataStorageScope

/// - Warning: `.own` belongs to the bundle ID: builds that share one share values, and unit tests hosted in an app use the app's,
///   so a test's `clear()` empties the app's data on that device. Give tests a namespace of their own.
public protocol KeyValueDataStorageScope: Hashable, Sendable {
    static var `default`: Self { get }
}

public extension KeyValueDataStorageScope {
    /// Every `default` scope's namespace.
    /// - Warning: Shared by everything in the app that uses a `default` scope.
    static var defaultNamespace: ExactString {
        "KeyValueStorage"
    }
}

// MARK: - ExactString

/// A string compared by its exact UTF-8 bytes; `String`'s `==` takes `"é"` and `"e\u{301}"` for one.
public struct ExactString: Hashable, Sendable, ExpressibleByStringInterpolation, CustomStringConvertible {
    public let string: String

    public var description: String {
        string
    }

    public init(_ string: String) {
        self.string = string
    }

    public init(stringLiteral string: String) {
        self.init(string)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.string.utf8.elementsEqual(rhs.string.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Array(string.utf8))
    }
}

// MARK: - FileStorage

public extension FileStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    enum Retention: Hashable, Sendable {
        /// Kept until deleted.
        case persistent
        /// The system can delete it when storage runs low.
        case cache
        /// The system can delete it while the app isn't running.
        case temporary
    }

    /// Applies to every file the scope writes.
    /// - Note: Part of the place: scopes that differ only in protection never share values.
    enum Protection: Hashable, Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        /// Usable at any time, even before the first unlock after a restart (`none`).
        case none
        /// Usable once the user has unlocked the device after a restart, then also while locked (`completeUntilFirstUserAuthentication`).
        case untilFirstUnlock
        /// Usable only while the device is unlocked (`complete`).
        case whileLocked
        /// Saves work while locked; reads only while unlocked (`completeUnlessOpen`).
        case whileLockedUnlessOpen
    }

    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Note: An empty id throws.
        /// - Note: On macOS, every id gets a folder, even one the app isn't entitled to, and ids that differ only in case share one.
        case appGroup(id: String, protection: Protection = .inherited, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}

// MARK: - SQLiteStorage

public extension SQLiteStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    enum Retention: Hashable, Sendable {
        /// Kept until deleted.
        case persistent
        /// The system can delete it when storage runs low.
        case cache
        /// The system can delete it while the app isn't running.
        case temporary
    }

    /// Applies to the database and its `-wal` and `-shm` files.
    /// - Note: Part of the place: scopes that differ only in protection never share values.
    enum Protection: Hashable, Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        /// Usable at any time, even before the first unlock after a restart (`none`).
        case none
        /// Usable once the user has unlocked the device after a restart, then also while locked (`completeUntilFirstUserAuthentication`).
        case untilFirstUnlock
        /// Usable only while the device is unlocked, even by an open database (`complete`).
        case whileLocked
        /// While locked, usable only by a storage created before locking, which keeps the database open (`completeUnlessOpen`).
        case whileLockedUnlessOpen
    }

    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Note: An empty id throws.
        /// - Note: On macOS, every id gets a folder, even one the app isn't entitled to, and ids that differ only in case share one.
        case appGroup(id: String, protection: Protection = .inherited, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}

// MARK: - UserDefaultsStorage

public extension UserDefaultsStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    /// - Note: Launch arguments and registered defaults under a stored key's name read as that key's value, in every suite.
    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Note: A suite of the library's own, not `UserDefaults.standard`.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Warning: Without the App Group entitlement, values stay in this app, and nothing reports it.
        /// - Note: An empty id, the global domain's names (`NSGlobalDomain`, `.GlobalPreferences`, `kCFPreferencesAnyApplication`,
        ///   `Apple Global Domain`) and `.own`'s suite name throw `.invalidSuiteName`: every suite reads the global domain, and `.own`'s suite is `.own`'s alone.
        /// - Note: On macOS, ids that differ only in case share one suite.
        case appGroup(id: String, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}

// MARK: - KeychainStorage

public extension KeychainStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    /// Which apps see an iCloud scope's items.
    enum Owner: Hashable, Sendable {
        /// The running app or extension.
        /// - Warning: Items go to the app's default access group, its first Keychain Sharing group if it lists any; apps sharing that group can read, change and delete them.
        case own
        /// The group's apps and extensions: an App Group, or a Keychain Sharing group with its team ID prefix.
        /// - Note: An empty id throws; a group the app isn't entitled to fails with `errSecMissingEntitlement`.
        case appGroup(id: String)
    }

    /// When the scope's items are usable, and whether they may move to another device.
    /// - Note: Part of the place: scopes that differ only in protection never share items.
    enum Protection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`afterFirstUnlock`).
        case untilFirstUnlock
        /// As `untilFirstUnlock`, and never moves to another device (`afterFirstUnlockThisDeviceOnly`).
        case untilFirstUnlockThisDeviceOnly
        /// Usable only while the device is unlocked (`whenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whileLocked
        /// As `whileLocked`, and never moves to another device (`whenUnlockedThisDeviceOnly`).
        case whileLockedThisDeviceOnly
        /// As `whileLockedThisDeviceOnly`, and only while a passcode is set (`whenPasscodeSetThisDeviceOnly`).
        /// - Warning: Saving fails without a passcode, and removing the passcode deletes the items.
        case whileLockedOrWithoutPasscode
    }

    /// When the scope's items are usable; only the levels iCloud Keychain can sync.
    /// - Note: Part of the place: scopes that differ only in protection never share items.
    enum SyncedProtection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`afterFirstUnlock`).
        case untilFirstUnlock
        /// Usable only while the device is unlocked (`whenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whileLocked
    }

    /// - Warning: Items outlive the app: deleting it leaves them in the keychain, and a reinstall finds them.
    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: Items go to the app's default access group, its first Keychain Sharing group if it lists any; apps sharing that group can read, change and delete them.
        case own(protection: Protection = .whileLocked, namespace: Namespace)
        /// Shared by the group's apps and extensions: an App Group, or a Keychain Sharing group with its team ID prefix.
        /// - Note: An empty id throws; a group the app isn't entitled to fails with `errSecMissingEntitlement`.
        case appGroup(id: String, protection: Protection = .whileLocked, namespace: Namespace)
        /// Synced to the user's other devices through iCloud Keychain; separate from the `.own` and `.appGroup` items of the same namespace.
        /// - Note: Items stay on this device while iCloud Keychain is off. With `.own`, only the app with the same bundle ID sees them on the other devices.
        case iCloud(Owner, protection: SyncedProtection = .whileLocked, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}

// MARK: - InMemoryStorage

public extension InMemoryStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    /// Values live until the process exits.
    enum Scope: KeyValueDataStorageScope {
        /// This process's own memory.
        case own(namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}

// MARK: - UbiquitousStorage

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    typealias Namespace = ExactString
    typealias Key = ExactString

    /// Which apps see the values.
    enum Owner: Hashable, Sendable {
        /// The running app or extension.
        /// - Warning: Apps whose entitlements name the same key-value store can read, change and delete its values.
        case own
    }

    enum Scope: KeyValueDataStorageScope {
        /// Synced to the user's other devices through iCloud.
        /// - Note: Values stay on this device while the user is signed out of iCloud.
        /// - Note: The store holds at most 1 MB and 1024 keys in all.
        /// - Warning: Without the iCloud key-value store entitlement, the store keeps nothing, and nothing reports it.
        case iCloud(Owner, namespace: Namespace)

        public static var `default`: Self {
            .iCloud(.own, namespace: defaultNamespace)
        }
    }
}

// MARK: - Elsewhere

// - Locators read the namespace, retention and protection from the scope's cases; no scope has properties.
// - Retention and protection are part of the place. The locator puts protection into the place's name (the SQLite
//   database file, the File folder, the Keychain service) in a form no namespace encodes to, so scopes that differ
//   only in protection never share values.
// - UserDefaults, Ubiquitous and InMemory take no protection: the system sets it, and memory has none.
// - Each storage's default protection is its system's: `.inherited` for File and SQLite, `.whileLocked` for Keychain.
// - Keys are names only in every storage: protection, accessibility and sync moved into the scopes.
// - Every `.own` place carries the app's identifier, so two apps' `.own` scopes never meet. File and SQLite paths (D9) and
//   UserDefaults' suite (`<encoded bundle ID>.KeyValueStorage`) carry it in File's lossless encoding, so bundle IDs that differ
//   only in case never share a file on macOS. Keychain services (`<bundle ID>:<namespace>`) carry it as is: the keychain
//   compares exactly. InMemory is per process, and Ubiquitous's store is per app unless entitlements share it.
// - App Group values live at the root of the group's container, which has no defined caches or temporary folder, so groups
//   take no retention. Every `.appGroup` rejects an empty id.
// - UserDefaults and Ubiquitous store keys as `<namespace>!/<key>`: the `!` marks the library's entries where other code also
//   writes (App Group suites, the Ubiquitous store). Keychain services need no mark: they start with the bundle ID or the group.
// - One `ExactString` for namespaces and keys in the six storages. The protocol keeps `associatedtype Key: KeyValueDataStorageKey`
//   (`Hashable & Sendable`) generic, so custom storages can bring their own key types; `KeyValueDataStorageNamespace` goes.
// - Each storage's `Namespace` and `Key` are typealiases, so no top-level name clashes with SwiftUI's `Namespace`.
// - `KeyValueDataStorageScope.defaultName` becomes `defaultNamespace`.
// - Group ids stay `String`: they're the entitlements' ASCII identifiers.
// - System and SDK gotchas are documented on the case they affect, not worked around, unless they'd let two scopes reach
//   each other's values: UserDefaults rejects the global domain's names and `.own`'s suite name as group ids.
// - To verify on a device: what each protection level does while locked; whether the system deletes a database's files
//   one at a time in `.cache` and `.temporary`; which file protection classes macOS enforces.
```
