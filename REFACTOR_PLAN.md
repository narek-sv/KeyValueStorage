# KeyValueStorage 4.0 — Refactor Plan

## Status (2026-10-28)

- **In progress: locators (§4.3).** Naming moves out of the storages into one locator per storage. Each step also applies the error contract (§4.4) and the clash rules (§4.5), and writes the storage's mock-based unit tests.
  - **Done, in review: FileStorage**, the pilot (§5.3). Its tests pass on macOS and the iOS Simulator. The gated files have 100% coverage, except the `#available(macOS 11)` fallback.
  - **Done: lossless file names.** File and SQLite name every file and folder with one encoding of the exact bytes (§5.3); only a name over 255 bytes fails, and `InvalidFileNameReason` is gone.
  - **Done: every storage has its locator.** All naming lives in `Storages/<Name>/Dependencies/<Name>Locator.swift`; `StorageDirectory`, `StorageDirectoryLookup` and `KeyNamespace` are gone. The other five moved their rules as they were; their steps still bring the clash fixes (§4.5), the error audit and the tests.
  - **Next:** SQLite, UserDefaults, Ubiquitous, Keychain, InMemory, on the pattern the review settles.
- **Done: phases 0–6, the source side.** The synchronous `KeyValueDataStorage` with `init(scope:backingStore:)`, typed throws, scopes with namespaces, every storage on its backing store, the global actors removed, and `KeychainWrapper.swift` deleted.
- **Added: `UbiquitousStorage`** (§5.7), on the same pattern.
- **Tests:** the public API target and the coder tests are on the 4.0 API and pass. The 3.x unit tests live in `Tests/Legacy3x/` (not a target) as the porting reference; each storage's locator step ports and deletes its file.
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
- No app identifier in paths or suite names: the namespace separates apps' values where the system doesn't.
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

### 4.5 Key clashes and scope-exact `clear()`

**Invariant:** in one physical store, two different (namespace or root, key) pairs never get the same stored name. A scope's reverse mapping claims exactly the names its own keys can produce, so `clear()` removes exactly the scope's values: never another namespace's, never a namespace's from the root, and never the root's from a namespace.

- **Shared spaces** (a File folder, a UserDefaults suite, the Ubiquitous store): `clear()` lists the stored names and deletes only those the locator claims.
- **Exclusive locations** (an SQLite database file, an InMemory bucket, a Keychain service with its access group): `clear()` empties the location.
- **Root vs namespace:**
  - File and SQLite keep namespaces in folders. **Files are values and folders are namespaces:** a key's value is only ever a file, its name never contains `.`, and a folder is never read, replaced or removed as a value. Namespace folders end with `!`, which no key's file name does (a `!` is always followed by a letter), so a root key and a namespace with the same name coexist. `.pathOccupied` comes only from other code's items, and nothing is ever removed to make room.
  - UserDefaults and Ubiquitous percent-encode `%` and `/` in root keys, so a root stored key never contains `/` and can't equal a namespaced one (`<encoded namespace>/<key>`).
  - Keychain's root uses service `""`, and `.app` scopes use the app's default access group (verified in KeychainHost), so neither reaches another scope's items.
- **Not fixable without marking stored names:** in a space shared with other code's entries (a folder the user picked, `UserDefaults.standard`), the root `clear()` also removes entries that a key could have produced, such as `notes` or `AppleLanguages`. A namespace never does. Each scope's docs say so.
- **Laws** run against every default locator: round trip; no collisions within a namespace (File: also case-insensitively and canonically, as on APFS, with keys compared by their exact scalars); no collisions across namespaces, including the root; and no claiming of names that another scope or no key produces.

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

| Storage | Scope | Resolves to |
|---|---|---|
| File | `.app(.applicationSupport/.cache/.documents/.temporary/.directory(at: u), namespace: n)` | `<base or u>[/<n>]/<encoded key>` |
| File | `.appGroup(g, namespace: n)` | `<group container g>[/<n>]/<encoded key>` |
| SQLite | same as File, plus `protection:` (default `.inherited`) | `<folder>[/<n>]/.KeyValueStorage.sqlite` (+ `-wal`, `-shm`), opened in the scope's protection class |
| UserDefaults | `.app(.standard, namespace: n)` | `UserDefaults.standard` |
| UserDefaults | `.app(.suite(named: s), namespace: n)` | suite `s` |
| UserDefaults | `.appGroup(g, namespace: n)` | suite `g` |
| UserDefaults, Ubiquitous | `.keyPrefix(named: n)` | keys stored as `"<n with % → %25, / → %2F>/<key>"`; at the root (`nil`), keys stored with `%` → `%25` and `/` → `%2F` (§4.5) |
| Keychain | `.app(namespace: n)` | `kSecAttrService = n` (root: `""`, §4.5), the app's default access group |
| Keychain | `.appGroup(g, namespace: n)` | `kSecAttrService = n` (root: `""`), `kSecAttrAccessGroup = g` |
| InMemory | `.app(namespace: n)` | bucket `n` (`nil` is a bucket of its own) |
| Ubiquitous | `.shared(namespace: n)` | `NSUbiquitousKeyValueStore.default` (the store of the target's kvstore entitlement) |

Defaults: every `default` scope uses the namespace `"KeyValueStorage"`: File and SQLite `.app(.applicationSupport, namespace: .directory(named:))`, UserDefaults `.app(.suite(named: "KeyValueStorage"), namespace: .keyPrefix(named:))`, Keychain `.app(namespace: .service(named:))`, InMemory `.app(namespace: .bucket(named:))`, Ubiquitous `.shared(namespace: .keyPrefix(named:))`.

The root encoding (§4.5), the Keychain root service `""` and the `.app` access group land with their locator steps.

### 5.2 KeychainStorage (backing already exists; start here)

Backing (exists): `KeychainBackingStore` with `read`, `add`, `update` and `remove`, each taking a `KeychainQuery` and returning a `KeychainOperationStatus`; the default is `DefaultKeychainBackingStoreWrapper`.

Changes:
- `final class KeychainStorage: KeyValueDataStorage`, `init(scope:backingStorage:)`, and `convenience init(scope:)` passing `DefaultKeychainBackingStoreWrapper()`.
- Remove `nonisolated` on the type, `@unchecked Sendable`, `required convenience init()`, and the `set` implementation.
- Drop `: Sendable` from `KeychainBackingStore` (D15). Make `KeychainOperationStatus` `Sendable`.
- **Delete `Helpers/KeychainWrapper.swift`** (no longer referenced).
- Extract the repeated query construction into a private `baseQuery(for key:)` / `serviceQuery()` helper.

Logic owned by the storage (all mock-tested): query fields per scope, synchronizable mapping, accessibility on add and update, status → result/error mapping.

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
public protocol SQLiteBackingStore {
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
- **Scope:** so the scope has one case, `.shared(container:)`. The container is a key namespace (escaped like UserDefaults', each in its own locator), and `nil` means raw keys. The docs explain the setup:
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
| 1 | Core: new `KeyValueDataStorage`; remove global actors and `Sendable` from the protocol | Core tests 100% |
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
5. ~~**Typed throws** on the data layer.~~ Adopted: every storage, the locators and the coding layer throw typed errors, and they build for the iOS 13 / macOS 10.15 deployment targets.
6. **watchOS minimum 6 → 9.** That's what `UbiquitousStorage` needs; it would remove its `@available(watchOS 9.0, *)` annotations.

## 14. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `update` isn't atomic across processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension. This is already in the scope docs.
- **Observation across instances on different actors** has no ordering guarantee; in-process users should go through one facade.
- **Actor I/O on the concurrency pool**, see §7.
