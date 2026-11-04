# KeyValueStorage

![Build & Test](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml/badge.svg)
[![Coverage](https://img.shields.io/badge/coverage-96%25-brightgreen)](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-success.svg)](https://github.com/apple/swift-package-manager)

---

A typed key-value storage for Apple platforms, with one API over the storages the system comes with: User Defaults, the Keychain, files, SQLite, the iCloud key-value store and memory. Each value is reached through its entry, which names its storage, its value type, its scope, the place where it lives, and its key, so values are type-checked at compile time, each scope keeps its values apart, and an App Group scope shares them with your extensions and other apps. The built-in storages are thread-safe and throw typed errors, code that uses a synchronous storage directly never needs `await`, and you can add your own storages and encodings.

**No dependencies.** `KeyValueStorage` works on its own: it uses only frameworks that come with the system, Foundation, Security, Combine and SQLite, so adding it brings no other packages into your project.


---
## Supported Platforms

| | | | | | |
| --- | --- | --- | --- | --- | --- |
| **iOS** | **macOS** | **watchOS** | **tvOS** | **visionOS** | **Swift** |
| 13.0+ | 10.15+ | 6.0+ | 13.0+ | 1.0+ | 6.0+ (Xcode 16+) |

`UbiquitousStorage` needs watchOS 9.0+, like `NSUbiquitousKeyValueStore`.

On tvOS, Apple limits an app's persistent local storage to 500 KB of User Defaults, and everything else must be purgeable: use `.cache` scopes for files and SQLite there, whose values the system can delete when storage runs low while the app isn't running.

## Choosing a Storage

Every storage works through the same API: declare a typed entry, then save, fetch, delete and observe its value with `UnifiedStorage`. Six storages are built in: In Memory, User Defaults, Keychain, File System, SQLite and iCloud Key-Value Store. You can add your own storage, synchronous or asynchronous, by conforming to `DataStorage` or `AsyncDataStorage` (see [Custom Storages](#custom-storages)), and your own encoding by conforming to `DataCoder` (see [Coding](#coding)). Values can be shared with your app's extensions and your other apps (see [Setup](#setup)), and observed for changes (see [Observation](#observation)).

Here's how the built-in storages compare:

| | In Memory | User Defaults | Keychain | File System | SQLite | iCloud Key-Value Store |
| --- | --- | --- | --- | --- | --- | --- |
| **Survives app restart** | ❌ | ✅ | ✅ (usually reinstalls too) | ✅ | ✅ | ✅ |
| **Suitable for secrets** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Shared with your other apps and extensions** | ❌ | ✅ App Group | ✅ App Group or Keychain Sharing group | ✅ App Group | ✅ App Group | ✅ Same store identifier |
| **Syncs across the user's devices** | ❌ | ❌ | ✅ iCloud Keychain (`.iCloud` scope) | ❌ | ❌ | ✅ iCloud |
| **Best value size** | Any | Small | Small | Large | Small to medium | Small, 1 MB in all |
| **Speed** | Fastest | Very fast | Slowest | Slow for small values, fastest for large ones | Fast for small values | Very fast locally, syncs in the background |
| **Across processes** | – | Last write wins per key | Last write wins per item | Atomic replace per file | Transaction per operation | Last write wins per key, also across devices |

**In Memory** - temporary state, caches and tests.
* The fastest storage: no disk access at all.
* Values are lost when the app quits, and are never shared with other processes.

**User Defaults** - settings, flags and other small values.
* Very fast reads from an in-memory cache, while writes reach the disk asynchronously.
* Shared with extensions through an App Group suite.
* Not for sensitive data: the values are stored unencrypted. Keep it small, since the whole suite is loaded into memory: the system logs an error for a suite of 4 MB or more on iOS, and tvOS allows 500 KB in all.
* Until the user first unlocks the device after a restart, such as in a background launch, every fetch returns `nil`, with no error.
* Values are `Data` under keys of the library's own, `<namespace>!/<key>`, and the `.own` scopes use a suite of the library's own, so `@AppStorage`, Settings bundles and `UserDefaults.standard` don't see them. Any string is a valid key: `%` and NUL are written as `%25` and `%00`, because the system never writes a key with NUL to disk, and `/` in a namespace as `%2F`.
* Clearing removes only the values saved through `KeyValueStorage` in the scope's namespace.

**Keychain** - tokens, passwords and other secrets.
* Encrypted by the system, with the scope's `protection` controlling when the items can be read, for example only while the device is unlocked.
* Can sync through iCloud Keychain (the `.iCloud` scope) and be shared with other apps and extensions through an App Group or a Keychain Sharing group.
* Every call goes through a system service, so it's the slowest storage. Use it for small secrets only.
* Items usually survive an app reinstall, and may be unreadable while the device is locked.

**File System** - large values, such as images, videos or cached responses.
* The fastest storage for large values: every value is written once, directly into its own file.
* Deleting a value frees its disk space right away.
* Every value is a separate file, so reading one value never loads the others into memory, and a damaged file affects only its own value. A value itself is saved and fetched whole, in memory, so keep each one to what the app can hold in memory at once.
* The default `.persistent` scope is in Application Support, which the device's backups include. Keep what you can download again out of them: in a `.cache` scope, such as cached responses, which the system can delete when storage runs low, or in a `.persistentExcludedFromBackup` scope, such as media for offline use, which stays until you delete it.
* Files are replaced atomically, so a crash never leaves a value half-written. A save survives an app crash; a power loss or system crash right after it can lose it, since files aren't flushed to the disk on every save.
* Slow for small values, since every save writes and renames a file.
* Any string is a valid key, up to a 255-byte file name, and keys that differ only in case are separate values on every platform. The name keeps `a`–`z`, `0`–`9`, `_` and `-`, writes a capital as `!` and its lowercase letter, so `Key` is saved as `!key`, and every other byte as `%` and two hex digits. Such bytes take three, so a key in Cyrillic fits about 42 characters and one in Chinese 28: hash longer keys, such as URLs with long query strings.

**SQLite** - many small and medium values, especially when an app and its extensions write the same data.
* All values of a scope live in one database, which your app and its extensions can use at the same time. It's much faster than separate files for small values; for large values, separate files are faster.
* Any string is a valid key.
* Every operation is a transaction across all processes, the strongest guarantee of all storages. A save survives an app crash; a power loss or system crash right after it can lose the last saves, but never corrupts the database.
* A fetch followed by a save isn't atomic across processes, and a write fails if another process keeps the database busy for over a second.
* Large values are written twice, first to the database's log and then into the database, so they briefly need about twice their size on disk.
* Deleted values free space inside the database for reuse, but the database file itself doesn't shrink.
* A scope's database stays open while `UnifiedStorage` keeps its storage: close the scopes the app is done with, see [Closing storages](#closing-storages).
* A single value can't exceed SQLite's size limit, so very large values belong in files.
* Its scopes take the same retentions as files', so a database you can download again stays out of the backups in a `.cache` or `.persistentExcludedFromBackup` scope.

**iCloud Key-Value Store** - small preferences and state that follow the user to their other devices.
* Synced through iCloud by the system, with a local copy that's read and written without waiting for the network.
* The whole store holds at most 1 MB of values and 1024 keys. A value over 1 MB (1,000,000 bytes) throws `valueTooLarge`, and a stored key over 128 UTF-16 code units, namespace included, throws `invalidKey`, but going over the store's total limits fails silently.
* Values are stored under `<namespace>!/<key>`. Any string is a valid key: `%` and NUL are written as `%25` and `%00`, and `/` in a namespace as `%2F`.
* Values stay on the device while the user is signed out of iCloud, and sync once they sign in.
* Not for sensitive data, and needs the iCloud capability (see [iCloud Key-Value Store](#icloud-key-value-store)): without it, the store silently keeps nothing.
* Changes that arrive from the user's other devices aren't published to observers.
* Clearing removes only the values saved through `KeyValueStorage` in the scope's namespace.

Quick guide:
* Secrets → `KeychainStorage`
* Settings and flags → `UserDefaultsStorage`
* Large values, such as images or videos → `FileStorage`, in a `.cache` scope if you can download them again, or `.persistentExcludedFromBackup` if they must stay for offline use
* Many small and medium values, such as records → `SQLiteStorage`
* Data written by both the app and its extensions → `SQLiteStorage`
* Temporary state and tests → `InMemoryStorage`
* Small preferences that follow the user across devices → `UbiquitousStorage`

---
## Setup

`KeyValueStorage` works out of the box: entries with the default scope need no setup, except for the keychain on macOS and the iCloud key-value store. If you want to share values among your apps and extensions, you need a little setup in Xcode first. Here's what each setup is for:

* [App Groups](#app-groups) - share values of any storage with your extensions and your other apps.
* [Keychain Sharing](#keychain-sharing) - share keychain items through a keychain access group instead of an App Group.
* [iCloud Keychain](#icloud-keychain) - sync keychain items across the user's devices.
* [iCloud Key-Value Store](#icloud-key-value-store) - sync small values across the user's devices, and share them with your extensions and other apps.
* [macOS](#macos) - use the keychain storage in a macOS app.
* [Privacy Manifest](#privacy-manifest) - nothing to do: what the library declares for the App Store review.

### App Groups

You need this when your app and its extensions, or several of your apps, read and write the same values. An App Group gives them a shared container for User Defaults, files and SQLite databases, and a shared keychain access group.

1. In Xcode, select your app target, open **Signing & Capabilities**, click **+ Capability** and add **App Groups**.
2. Add a group, for example `group.com.company.app`. On macOS, use the group exactly as the capability shows it.
3. Add the capability to every extension and app that shares the values, and select the same group.
4. Use the group in the entries' `.appGroup` scope:

```swift
let onboarded = UserDefaultsStorage.Entry<Bool>(key: "onboarded", scope: .appGroup(id: "group.com.company.app", namespace: "settings"))
let token = KeychainStorage.Entry<String>(key: "token", scope: .appGroup(id: "group.com.company.app", namespace: "auth"))
```

A target without the group doesn't see the shared values: User Defaults quietly keeps its own values, File and SQLite throw `groupDirectoryNotFound` on a device but get a folder of their own on macOS and in the Simulator, and the keychain throws `.keychain(status: errSecMissingEntitlement)`.

Every scope names a `namespace`, which keeps sets of values apart within the same place; the default scope uses `"KeyValueStorage"`. Here is where each built-in storage keeps a scope's values:

| Storage | `.own` scope | `.appGroup` scope |
| --- | --- | --- |
| `UserDefaultsStorage` | The app's own suite, `<app>.KeyValueStorage`, keys `<namespace>!/<key>` | The group's suite, keys `<namespace>!/<key>` |
| `FileStorage` | `<Application Support, Caches or tmp>/<app>/<namespace>!/<protection>`, with `x/` after `<app>` for `.persistentExcludedFromBackup` | `<group container>/<namespace>!/<protection>` |
| `SQLiteStorage` | `<Application Support, Caches or tmp>/<app>/<namespace>+/<protection>.sqlite`, with `x/` after `<app>` for `.persistentExcludedFromBackup` | `<group container>/<namespace>+/<protection>.sqlite` |
| `KeychainStorage` | The app's default access group, service `<app>:<namespace>:<protection>` | The group, service `<group>/<namespace>/<protection>` |
| `InMemoryStorage` | A bucket per namespace in the current process | — |
| `UbiquitousStorage` | — (`.iCloud(.own, namespace:)`) | App Groups have no effect; see [iCloud Key-Value Store](#icloud-key-value-store) |

`<app>` is the bundle identifier, or the process name without one, so every app and extension has its own `.own` values; only `.appGroup` and `.iCloud` scopes are shared. Scopes that differ only in protection never share values.

### Keychain Sharing

You need this only to share keychain items through a keychain access group instead of an App Group, for example because some of the apps that share the items don't belong to the same App Group.

1. Add the **Keychain Sharing** capability to every app and extension that shares the items.
2. Add the same group to each of them, for example `com.company.shared`. Xcode prefixes it with your team ID.
3. Use the group, prefixed with your team ID, as the scope: `.appGroup(id: "ABCDE12345.com.company.shared", namespace: "auth")`. Your team ID is in the membership details of your Apple Developer account.

### iCloud Keychain

You need this to make keychain items available on all the user's devices. Use the `.iCloud` scope, with `.own` or an `.appGroup(id:)` owner. There's no capability to add, but:
* Items sync only for users who turned on iCloud Keychain on their devices.
* `.iCloud` takes a `SyncedProtection`, `.afterFirstUnlock` or `.whenUnlocked`: the levels that stay on one device can't sync.
* `.iCloud` items are separate from the `.own` and `.appGroup` items of the same namespace.
* Deleting a synced item, or clearing the scope, removes it from all the user's devices.

```swift
let token = KeychainStorage.Entry<String>(key: "token", scope: .iCloud(.own, namespace: "auth"))
```

### iCloud Key-Value Store

You need this to use `UbiquitousStorage`. Without it, the store keeps nothing, and nothing reports it.

1. Add the **iCloud** capability to your app target and select **Key-value storage**. Xcode names the app's store `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` in the `com.apple.developer.ubiquity-kvstore-identifier` entitlement.
2. To share the store with your extensions or your other apps of the same team, add the capability to each of them and set the entitlement to the same identifier in every target. An extension that keeps its default identifier silently gets a store of its own.

```swift
let theme = UbiquitousStorage.Entry<String>(key: "theme")
// or in a namespace of its own
let layout = UbiquitousStorage.Entry<String>(key: "layout", scope: .iCloud(.own, namespace: "editor"))
```

Every app that names the same store can read, change and delete its values.

### macOS

You need this to use the keychain storage in a macOS app. The keychain storage uses the data protection keychain, like on iOS, which needs your app to be signed with a development team: select a team under **Signing & Capabilities**. Command-line tools, and apps that aren't signed with a team, get `errSecMissingEntitlement`.

### Privacy Manifest

There's nothing to set up. `KeyValueStorage` includes a privacy manifest that declares the two APIs it uses that Apple asks a reason for:
* User Defaults, with the reason `C56D.1`, which covers a library that reads and writes User Defaults only when your app asks it to.
* File timestamps, with the reason `C617.1`: the file storage looks up the type of its own files, in your app's or App Group's container, with `lstat`, which Apple lists among the APIs that return file timestamps.

Declare your app's own use of these APIs in your app's privacy manifest.

---
## Usage

The framework is capable of working with any type that conforms to `Codable` and `Sendable`.
The concept here is that first you declare the value's entry. It contains every piece of information about how and where the value is stored.

***NOTE***! If your target uses `MainActor` as its default actor isolation, which new Xcode 26 projects do, the `Codable` conformances of your types belong to the main actor. `KeyValueStorage` encodes and decodes values off the main actor, so using such a type as a value fails to compile with `main actor-isolated conformance of 'User' to 'Decodable' cannot satisfy conformance requirement for a 'Sendable' type parameter`. Mark the type, or only its conformance, as `nonisolated`:

```swift
nonisolated struct User: Codable { ... }

// or
struct User: nonisolated Codable { ... }
```

First, declare the entry, with the `Entry` of one of the built-in storages:

* `UserDefaultsStorage.Entry`
* `KeychainStorage.Entry`
* `InMemoryStorage.Entry`
* `FileStorage.Entry`
* `SQLiteStorage.Entry`
* `UbiquitousStorage.Entry`

or of your own storage, which has one too. [See how to define one](#custom-storages)

```swift
import KeyValueStorage

let name = UserDefaultsStorage.Entry<String>(key: "name")
// or alternatively provide the scope
let sharedName = UserDefaultsStorage.Entry<String>(key: "name", scope: .appGroup(id: "group.com.company.app", namespace: "settings"))
```

As you can see, the entry holds all the necessary information about the value:
* The key - `"name"`
* The storage type - `UserDefaultsStorage`
* The value type - `String`
* The scope (*optional*) - who sees the value and where it lives; `.default` when omitted

A key and a scope's namespace can be any string, a literal or one made at runtime, and are compared by their exact bytes, so `"é"` and `"e\u{301}"` are two keys:

```swift
let token = KeychainStorage.Entry<String>(key: accountID)
let draft = FileStorage.Entry<String>(key: "draft", scope: .own(namespace: userID))
```

Now all that is left is to instantiate the storage and use it:

```swift
// Instantiate the storage
let storage = UnifiedStorage()

// Saves the entry's value, or replaces the one already there
try await storage.save("Alice", to: name)

// Returns the entry's value, or nil if there is none
let value = try await storage.fetch(name)

// Deletes the entry's value, or does nothing if there is none
try await storage.delete(name)

// Saves the value, or deletes the entry's value for nil
try await storage.set("Bob", to: name) // save
try await storage.set(nil, to: name) // delete

// Reads the value and saves what the closure makes of it as one step, or deletes it for nil
let launches = SQLiteStorage.Entry<Int>(key: "launches")
try await storage.update(launches) { ($0 ?? 0) + 1 }

// Removes every value of the storage's scope, `.default` when omitted,
// including the values saved in previous launches
try await storage.clear(storage: KeychainStorage.self, forScope: .own(namespace: "auth"))
```

Clearing removes only the values the library saved in that scope. Other code's values in the same suite, folder or store are never touched.

`update` starts from `nil` when the storage reads no value, and User Defaults reads none before the device's first unlock after a restart, such as in a background launch: don't update User Defaults values then, or the result can replace the value it couldn't read.

Each scope keeps its values apart from other scopes' and other code's, so you can split your data into parts that you clear or move on their own, such as a namespace per feature or per signed-in user. To keep them apart:
* Give each library, and each part your app clears on its own, a namespace of its own. The `.default` scope of every built-in storage uses the namespace `"KeyValueStorage"`, so it's shared by everything in the app that uses it.
* Give tests a namespace of their own. Unit tests hosted in your app use the app's `.own` values, so a test's `clear()` empties the app's data on that device, and on macOS, `swift test` runs every package's tests as `com.apple.dt.xctest.tool`.
* Remove only your own items. Code that removes a whole place, such as every keychain item of your app, its Caches folder or an App Group's User Defaults suite, removes the library's values too.

[DESIGN.md](DESIGN.md#d9-sealed-scopes-the-library-picks-the-place-and-owns-every-name-in-it) lists every case where values can meet.

### Moving values

A value lives at its entry's scope and key, so an entry whose scope changes, such as its protection or namespace in an app update, or whose key is renamed, finds none of the values saved before. Move each value to its new place, for example at launch: to another scope, another key, or both at once with another entry:

```swift
// An app update that reads the token while the device is locked changes its protection from the default `.whenUnlocked`
let token = KeychainStorage.Entry<String>(key: "token", scope: .own(protection: .whenUnlocked, namespace: "auth"))
try await storage.move(token, to: .own(protection: .afterFirstUnlock, namespace: "auth"))

// A key renamed, in the same scope
try await storage.move(UserDefaultsStorage.Entry<Bool>(key: "onboarding"), to: "onboarded")

// Both at once
let draft = FileStorage.Entry<String>(key: "draft", scope: .own(namespace: "notes"))
try await storage.move(draft, to: FileStorage.Entry<String>(key: "note", scope: .own(.cache, namespace: "notes")))
```

`move` saves the value at the destination, unless a value is there already, and only then removes it from the entry, so the value is never lost; a failed or interrupted move is finished by calling it again, and moving an entry onto itself does nothing. Calls through the same `UnifiedStorage` in either scope wait until the move is done. Other `UnifiedStorage` instances, storages used directly and other processes don't wait, so move values before they use them.

A move between scopes needs two places: between scopes that resolve to one, such as File or SQLite App Group ids that differ only in case on macOS, it takes the value for one already at the destination, and deletes it.

### Closing storages

`UnifiedStorage` creates a scope's storage on first use and keeps it, so a SQLite scope keeps its database open until the app quits. Close a scope the app is done with, such as a chat the user left. Its values stay, and the next call opens it again:

```swift
await storage.close(storage: SQLiteStorage.self, forScope: .own(namespace: "chat-42"))
```

A damaged SQLite database fails every call, and clearing it fails too. Close its scope, delete the database's files, and the next call creates an empty database:

```swift
await storage.close(storage: SQLiteStorage.self, forScope: scope)
let database = try DefaultSQLiteLocator().databaseURL(for: scope)
for suffix in ["", "-wal", "-shm"] {
    try? FileManager.default.removeItem(atPath: database.path + suffix)
}
```

`close` waits for the calls running in the scope, and calls through the same `UnifiedStorage` wait for it. Your app extensions, other `UnifiedStorage` instances and storages you use directly keep their own connections, so don't delete a database while they may have it open. A factory that keeps its own reference to a storage keeps it open too.

---
## Type Inference

The framework leverages the full capabilities of ***Swift Generics***, so it can infer the types of values based on the entry at compile time, eliminating the need for extra checks or type casting.

```swift
struct MyType: Codable, Sendable { ... }

let entry = UserDefaultsStorage.Entry<MyType>(key: "myKey")
let value = try await storage.fetch(entry) // inferred type for value is MyType
try await storage.save(/* accepts only MyType*/, to: entry)
```

---
## Factory

`UnifiedStorage` creates each storage type and scope's storage through its factory, on first use, and again after a [close](#closing-storages) or a failed creation. The default factory, `.default`, does it in four steps:
1. Creates the storage with its `init(scope:)`.
2. Picks its coder, `RawDataCoder`.
3. Wraps both in an `AsyncCodingStorage`.
4. Doesn't observe it.

To change a step, add a modifier, for every storage type or for one. Each modifier returns a new factory, so they chain:

```swift
let storage = UnifiedStorage(factory: .default
    .observable()                                           // Every storage publishes its changes,
    .observable(false, for: KeychainStorage.self)           // but the keychain's
    .coder(JSONDataCoder())                                 // Every storage codes with JSON,
    .coder(PropertyListDataCoder(), for: FileStorage.self)  // but files with property lists
    .dataStorage(for: FileStorage.self) { scope throws(FileStorage.Error) in
        try FileStorage(scope: scope, locator: FolderFileLocator(folder: folder)) // in a folder of yours
    })
```

| Step | For every storage type | For one storage type |
| --- | --- | --- |
| Create the storage | | `dataStorage(for:_:)`, such as with a [custom locator](#custom-locators) or [more than its scope](#custom-storages) |
| Pick its coder | `coder(_:)` | `coder(_:for:)` |
| Wrap it for coding | | `codingStorage(for:_:)`, such as for [your own subclass](#coding) |
| Observe it | `observable(_:)` | `observable(_:for:)`, or `observableStorage(for:_:)` for [your own subclass](#observation) |

**The last modifier decides.** Each one gets what the modifiers before it make, and returns it as is, changed or replaced. So add the modifiers for every storage type first, and the ones for a type after them: with `.coder(PropertyListDataCoder(), for: FileStorage.self).coder(JSONDataCoder())`, files are coded with JSON too.

**A modifier for a type changes only that exact type.** `IsolatedDataStorage<FileStorage>` has the same scopes as `FileStorage`, but it's a type of its own, which `FileStorage`'s modifiers don't change.

`UnifiedStorage()` uses `.default`, and `UnifiedStorage(observable: true)` uses `.default.observable()`.

***NOTE***! Swift doesn't infer a closure's typed `throws`: spell out the storage's error type in `dataStorage(for:_:)`'s closure, as in `{ scope throws(FileStorage.Error) in … }`, even if the closure can't fail.

### Your own modifiers

For a change to every storage type that the modifiers above don't make, such as logging each creation or observing every storage through your own `ObservableStorage` subclass, write a modifier of your own: conform to `UnifiedStorage.Factory.Modifier` and add it with `modifier(_:)`. It has a method for each step, generic over the storage type:
* `dataStorage(for:previous:)` creates the storage.
* `coder(for:previous:)` picks its coder.
* `codingStorage(for:coder:previous:)` wraps both for coding.
* `observableStorage(for:previous:)` observes it, or returns `nil` for none.

Implement only the steps you change. Each gets `previous`, what the modifiers before it make, and returns it as is, changed or replaced; the steps you don't implement return it:

```swift
/// Logs each storage it creates
struct LogCreations: UnifiedStorage.Factory.Modifier {
    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        let storage = try await previous()
        print("Created \(Storage.self) for \(scope)")
        return storage
    }
}

/// Observes every storage through `LoggingObservableStorage`, see Observation
struct LogChanges: UnifiedStorage.Factory.Modifier {
    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        LoggingObservableStorage(coding)
    }
}

let storage = UnifiedStorage(factory: .default.modifier(LogCreations()).modifier(LogChanges()))
```

Let Xcode complete each method: one that differs in any way, even in an argument label, compiles but is never called. Each call to `previous` makes anew what the modifiers before it make, such as another database connection, so call it at most once.

---
## Custom Storages

You can define your own storage, synchronous or asynchronous, and it works with `UnifiedStorage` and the coding storages out of the box:
* A storage whose operations never suspend conforms to `DataStorage`. Code that uses it directly never needs `await`, and neither does `CodingStorage` on top of it.
* A storage whose operations suspend, such as one backed by a server, conforms to `AsyncDataStorage` and is used through `AsyncCodingStorage` or `UnifiedStorage`. Every `DataStorage` is an `AsyncDataStorage` too.

Each storage implements every operation once, synchronous or `async`. Declare its `Key` and `Error` types: Swift doesn't infer them from typed throws. `set`, which saves a value or deletes it for `nil`, is `save` or `delete` by default for a synchronous storage, and an asynchronous one implements it too. Every layer calls the storage's own `set`, so a storage that does either in one operation, such as one request, can implement its own.

```swift
// Synchronous
final class NewStorage: DataStorage {
    typealias Key = String
    typealias Error = NewStorageError

    let scope: NewStorageScope
    init(scope: NewStorageScope) throws(NewStorageError) { ... }
    func fetch(forKey key: String) throws(NewStorageError) -> Data? { ... }
    // save, delete and clear
}

// Asynchronous
actor RemoteStorage: AsyncDataStorage {
    typealias Key = String
    typealias Error = URLError

    nonisolated let scope: RemoteScope
    init(scope: RemoteScope) async throws(URLError) { ... }
    func fetch(forKey key: String) async throws(URLError) -> Data? { ... }
    // save, set, delete and clear
}
```

Then use it like the built-in storages, through its `Entry`. `UnifiedStorage` shares its storages between tasks, so it takes only `Sendable` ones, `UnifiedStorable` for short, and the compiler enforces it (see [Thread Safety](#thread-safety)):
* a synchronous or asynchronous storage that's `Sendable`, such as an actor or a storage behind a lock, as is;
* any other synchronous storage wrapped in `IsolatedDataStorage`.

```swift
let id = RemoteStorage.Entry<UUID>(key: "id")
try await storage.save(UUID(), to: id)

// A storage that isn't `Sendable`, through `IsolatedDataStorage`
let draft = IsolatedDataStorage<NewStorage>.Entry<String>(key: "draft")
try await storage.save("Hello", to: draft)

// A synchronous storage needs no `await`, also through its coding storage
let coding = CodingStorage(storage: try NewStorage(scope: .default))
try coding.save(UUID(), forKey: CodingStorageKey<NewStorage, UUID>(key: "id"))
```

`UnifiedStorage` creates each storage with its `init(scope:)`. To give yours more, such as a token, create it in the factory's `dataStorage(for:_:)` (see [Factory](#factory)); its error reaches the calls as your storage's own:

```swift
let storage = UnifiedStorage(factory: .default.dataStorage(for: RemoteStorage.self) { scope throws(URLError) in
    try await RemoteStorage(scope: scope, token: session.token)
})
```

***NOTE***! In `async` generic code, calls on a `DataStorage` resolve to the `async` requirements and need `await`; synchronous generic code calls the synchronous ones. Outside `UnifiedStorage`, your storage's thread safety is up to you.

### Custom Locators

Each built-in storage takes its names from a locator: the folder and file names, the suite and its keys, the keychain service and account, or the database's file. To change some of them, such as to keep a test's files in a folder of its own, subclass the default locator and pass it to the storage. For `UnifiedStorage`, create that storage type with your locator in the factory's `dataStorage(for:_:)` (see [Factory](#factory)); every other storage type is created as before:

```swift
/// Keeps every file scope in a folder of your choice, such as a test's own
final class FolderFileLocator: DefaultFileLocator, @unchecked Sendable {
    private let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    // A folder for each system directory, so scopes that differ only in retention stay apart
    override func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        folder.appendingPathComponent(String(directory.rawValue), isDirectory: true)
    }

    override var temporaryDirectory: URL {
        folder.appendingPathComponent("tmp", isDirectory: true)
    }
}

let storage = UnifiedStorage(factory: .default.dataStorage(for: FileStorage.self) { scope throws(FileStorage.Error) in
    try FileStorage(scope: scope, locator: FolderFileLocator(folder: testFolder))
})
```

Each storage's `init(scope:backingStore:locator:)` defaults both, so pass only the one you change. A custom backing store, which replaces the system calls, such as in tests, goes in the same way, as `backingStore:`.

A locator must give every scope and key names of their own, and decode exactly the names it encodes, or values get shared, or `clear()` leaves them behind; each locator protocol lists its rules. A subclass of a default locator or backing store restates `@unchecked Sendable`, and its own state must be thread-safe too.

---
## Xcode autocompletion 

To get the advantages of Xcode autocompletion, it is recommended to declare all your entries in an extension of `UnifiedStorage.Entry`, like this:

```swift
extension UnifiedStorage.Entry {
    static var launches: UserDefaultsStorage.Entry<Int> {
        .init(key: "launches")
    }
    
    static var lastSync: InMemoryStorage.Entry<Date> {
        .init(key: "lastSync", scope: .own(namespace: "session"))
    }
    
    static var balance: KeychainStorage.Entry<Double> {
        .init(key: "balance", scope: .iCloud(.appGroup(id: "ABCDE12345.com.company.shared"), protection: .afterFirstUnlock, namespace: "auth"))
    }
    
    static var avatarID: FileStorage.Entry<UUID> {
        .init(key: "avatarID", scope: .appGroup(id: "group.com.company.app", namespace: "cache"))
    }
}

let launches = try await storage.fetch(.launches)
```

Xcode then suggests every entry of the extension when you put a dot, as in `fetch(.launches)` above.

---
## Keychain

The scope's `protection` sets when its items can be read. By default `.whenUnlocked` is used: the items can be read only while the device is unlocked, one of the most restrictive options with good data protection.

Use `.afterFirstUnlock` if your app needs the items while in the background. Note that it is less secure than `.whenUnlocked`. Changing an existing entry's protection moves it to a new place, so move its items with `move(_:to:)` (see [Moving values](#moving-values)), or users lose them, such as a signed-in session.

Here are all the protection levels:
* `afterFirstUnlock` (`kSecAttrAccessibleAfterFirstUnlock`)
* `afterFirstUnlockThisDeviceOnly` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
* `whenUnlocked` (`kSecAttrAccessibleWhenUnlocked`)
* `whenUnlockedThisDeviceOnly` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
* `whenPasscodeSetThisDeviceOnly` (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`): saving fails without a passcode, and removing the passcode deletes the items.

The protection is part of the scope, so scopes that differ only in protection keep separate items.

```swift
let token = KeychainStorage.Entry<String>(key: "token", scope: .own(protection: .afterFirstUnlock, namespace: "auth"))
```

To share items with your other apps and extensions, use an App Group they all belong to, or a Keychain Sharing group with your team ID prefix. Set up the capability first, see [Setup](#setup):

```swift
// An App Group, written as in the App Groups capability
let token = KeychainStorage.Entry<String>(key: "token", scope: .appGroup(id: "group.com.company.app", namespace: "auth"))

// A Keychain Sharing group, prefixed with your team ID
let sharedToken = KeychainStorage.Entry<String>(key: "token", scope: .appGroup(id: "ABCDE12345.com.company.shared", namespace: "auth"))
```

To sync items through iCloud Keychain, use the `.iCloud` scope, see [iCloud Keychain](#icloud-keychain). To read items that other code saved under its own service, use a custom `KeychainLocator` (see [Custom Locators](#custom-locators)).

---
## Coding

Values are encoded with `RawDataCoder` by default. It stores `Data` as is and `String` as UTF-8, which keeps large values fast and compact, and lets you read raw values saved by other code. Every other type is encoded with its fallback coder, `JSONDataCoder` unless you provide another one.

There are 3 built-in coders:
* `RawDataCoder(fallback:)` - Raw `Data` and `String`, the fallback coder for the rest.
* `JSONDataCoder` - JSON for every type.
* `PropertyListDataCoder` - Binary property lists for every type. Pass a `PropertyListEncoder` with the `.xml` output format to get XML.

Coders are synchronous. Pass the coder to a coding storage, or conform your own type to `DataCoder`. For `UnifiedStorage`, the factory picks each storage's coder (see [Factory](#factory)), so different storages can use different coders:

```swift
// JSON for every storage, and property lists for files
let storage = UnifiedStorage(factory: .default
    .coder(JSONDataCoder())
    .coder(PropertyListDataCoder(), for: FileStorage.self))
```

`CodingStorage` and `AsyncCodingStorage` are `open` classes, so a subclass can change how they fetch, save, set, delete or clear, and call `super` for the rest. For `UnifiedStorage`, the factory's `codingStorage(for:_:)` codes a storage type through yours:

```swift
/// Logs each fetch, then fetches as `AsyncCodingStorage` does
final class LoggingCodingStorage<Storage: AsyncDataStorage>: AsyncCodingStorage<Storage>, @unchecked Sendable {
    override func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        print("Fetching \(key.key)")
        return try await super.fetch(forKey: key)
    }
}

let storage = UnifiedStorage(factory: .default.codingStorage(for: SQLiteStorage.self) { storage, coder in
    LoggingCodingStorage(storage: storage, coder: coder)
})
```

Their `set`, which saves a value or deletes it for `nil`, doesn't call `save` or `delete`, so a subclass that changes those changes `set` too; the same goes for `ObservableStorage`.

***NOTE***! The value type comes from the entry, it isn't saved with the value. Changing the value type of an existing entry can make its stored value undecodable, or, for `Data` and `String`, be read without an error.

---
## Observation

Observation is opt-in, through the factory (see [Factory](#factory)). `UnifiedStorage(observable: true)` makes every storage observable, and so does the factory's `observable()`, which you can follow with `observable(_:for:)` to decide for a storage type:

```swift
let storage = UnifiedStorage(observable: true)

// Every storage but the keychain's
let storage = UnifiedStorage(factory: .default
    .observable()
    .observable(false, for: KeychainStorage.self))
```

`ObservableStorage` is an `open` class, so a subclass can change how it saves, deletes or publishes, and call `super` for the rest. Observe a storage type through yours with the factory's `observableStorage(for:_:)`, whose closure can also return `nil` for none, or every storage type with [a modifier of your own](#your-own-modifiers):

```swift
/// Logs each save, then saves and publishes as `ObservableStorage` does
final class LoggingObservableStorage<Storage: UnifiedStorable>: ObservableStorage<Storage>, @unchecked Sendable {
    override func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        print("Saving \(key.key)")
        try await super.save(value, forKey: key)
    }
}

let storage = UnifiedStorage(factory: .default.observableStorage(for: FileStorage.self) { coding in
    LoggingObservableStorage(coding)
})
```

Publishers and streams start with the stored value, or `nil` if there's none, followed by every change. Each call to `publisher(for:)` or `stream(for:)` reads the value itself, so it's current even if it was changed in a way observers don't see; a change published after the read wins over it. Pass `includingCurrentValue: false` to get only the changes.

Combine style publishers:
```swift
let status = InMemoryStorage.Entry<String>(key: "status")
guard let publisher = try await storage.publisher(for: status) else {
    // The factory doesn't make this storage observable
    return
}

let subscription = publisher
    .receive(on: DispatchQueue.main)
    .sink { value in
        print(value) // String?
    }
```

Concurrency style async streams:
```swift
guard let stream = try await storage.stream(for: status) else {
    // The factory doesn't make this storage observable
    return
}

for await value in stream {
    print(value) // String?
}
```

A stream keeps every change its consumer hasn't read yet, so a consumer slower than the changes falls behind and holds them all in memory. To get only the current value, keep only the latest:

```swift
let latest = try await storage.stream(for: status, bufferingPolicy: .bufferingNewest(1))
```

Without `UnifiedStorage`, wrap a coding storage in `ObservableStorage`, which saves, fetches and deletes like it and adds `publisher` and `stream`:

```swift
let settings = ObservableStorage(AsyncCodingStorage(storage: try FileStorage(scope: .default)))
for await theme in try await settings.stream(forKey: CodingStorageKey<FileStorage, String>(key: "theme")) {
    apply(theme)
}
```

Changes are delivered on the thread that makes them, right after the write succeeds, so move to the main thread before updating the UI. Subscribers run inside the save, and other saves of the same key wait for them: keep them short, and move slow work off with `receive(on:)` or a stream. Streams resume on the executor of the task that iterates them. An observer sees only the values saved with its own value type. While a key is observed, its latest change stays in memory, and each publisher keeps the value it read, so mind large values.

***NOTE***! In the Swift 6 language mode, a closure written in `@MainActor` code, such as in a view model, or anywhere in a target whose default actor isolation is `MainActor`, crashes the app when it's called off the main thread, as a `sink` is for every save made outside the main actor. Put `receive(on: DispatchQueue.main)` before such a `sink`, as above, or iterate a stream from the main actor.

However, it's important to note that only the changes made through observable storages of the current process are published, from any instance of the same storage type and scope. Changes made by other processes (for example, App Extensions), on the user's other devices, by storages without observation, or written directly to `UserDefaults`, the keychain or files aren't. Two calls that save one key at the same moment may deliver their values out of order. When a clear throws, no observer is told, even about the values it removed before failing, such as those a file storage's `.clearIncomplete` doesn't list.

---
## Error handling

`UnifiedStorage`, `CodingStorage` and `AsyncCodingStorage` throw `CodingStorageError<Storage>`:
* `.storage(error)` - the storage failed; `error` is the storage's own `Error`, listed below.
* `.coding(error)` - the coder couldn't encode or decode the value, for example a `DecodingError` after a value's type changed.

Even with a correct setup, some errors can't be avoided and are worth handling:
* `.protectedDataUnavailable` (`FileStorage`, `KeychainStorage`) - the value is protected while the device is locked; try again once it's unlocked. `FileStorage` also throws it when the sandbox denies access, which unlocking doesn't fix, so don't retry it forever.
* `KeychainStorage.Error.keychain(status:)` - any other Security framework status, such as `errSecMissingEntitlement` when the scope's access group isn't in the app's entitlements.
* `SQLiteStorage.Error.sqlite(code:message:)` - the database is damaged, or another process kept it busy for longer than a second. A database protected while the device is locked fails here too, with SQLite's own code.

Setup mistakes:
* `.groupDirectoryNotFound(id)` (`FileStorage`, `SQLiteStorage`) - the system has no container for the App Group, usually because the target isn't in the group, or the id is empty.
* `.directoryNotFound(directory)` (`FileStorage`, `SQLiteStorage`) - the system has no Application Support or Caches directory for the user.
* `UserDefaultsStorage.Error.invalidSuiteName(name)` - the App Group id is empty, the global domain or your app's own suite, or `UserDefaults` rejects it.

Keys, namespaces and values over a storage's limits:
* `.invalidKey(key)` - `FileStorage`: its encoded file name is over 255 bytes; `UbiquitousStorage`: its stored key, with the namespace, is over 128 UTF-16 code units.
* `.invalidNamespace(namespace)` (`FileStorage`, `SQLiteStorage`) - its encoded folder name is over 255 bytes.
* `UbiquitousStorage.Error.valueTooLarge(key:size:)` - the value is over 1 MB (1,000,000 bytes).

Something that isn't a value where a value goes. It's never replaced or removed:
* `FileStorage.Error.pathOccupied(url)` - for example a folder at a key's file, or a file where the scope's folder goes.
* `.keyOccupied(key)` (`UserDefaultsStorage`, `UbiquitousStorage`) - a value that isn't `Data` is under the key's stored key. In `UserDefaults`, registered defaults count.

Clearing a scope that only partly succeeds:
* `FileStorage.Error.clearIncomplete(errors)` - `clear()` removes a scope's values one file at a time, and doesn't stop at the first failure: it tries every value, then throws each one it couldn't remove, by key, with its error. The other values are gone. The other storages clear a scope in one step, or can't fail.

`FileStorage` and `SQLiteStorage` wrap any other failure in `.other(error)`, keeping the original error; a failed file lookup is a `FileItemError` with the system's code. `InMemoryStorage` never throws.

---
## Thread Safety

**The built-in storages are thread-safe.** Each one is `Sendable`, so an instance can be used from any thread or task, and the compiler lets you share it. A *sequence* of operations, such as a fetch followed by a save, isn't atomic: another task or process can change the value in between.

```swift
let storage = try FileStorage(scope: .default)
Task.detached { try storage.save(data, forKey: "avatar") }   // fine: FileStorage is Sendable
```

**`UnifiedStorage` takes only `Sendable` storages.** It's safe to call from any thread, task or actor, and calls on storages of different types or scopes, such as a User Defaults fetch and a file write, never wait for each other. Only `move(_:to:)`, `update(_:_:)` and `close(storage:forScope:)` hold their scopes: calls in them wait until they're done, and they wait for those already running. For your own storages, thread safety is your responsibility: one that's `Sendable`, such as an actor or a class behind a lock, works as it is, and one that isn't doesn't compile in an entry.

**Use one `UnifiedStorage` for your app.** An instance coordinates only its own calls: `move(_:to:)`, `update(_:_:)` and `close(storage:forScope:)` hold their scopes against calls through the same instance, not through another. Several instances never break a value, since every storage they create is thread-safe, but a call through one can see another's move or update half done. So:
* Create one `UnifiedStorage` and share it, for example as a static property or through dependency injection.
* If you need more than one, such as one with observation and one without, give each its own scopes.
* Reach each scope through one storage type: `FileStorage` and `IsolatedDataStorage<FileStorage>` are two storages over the same files, so a move or an update through one doesn't hold the other's calls, a close closes only its own, and each one's observers get only the changes made through it.
* Nothing coordinates with your app extensions, other processes, or storages you use directly: move values before they use them, for example at launch, and don't count on `update` against their writes.
* Don't call a `UnifiedStorage` from inside its own storages, coders, factory or `ObservableStorage` subclasses: such a call can wait for a move or an update that waits for the call it's made in, and never return.

Even through one instance, a sequence of calls, such as a fetch followed by a save, isn't atomic: another task can save in between. Use `update(_:_:)` to read and write a value as one step.

**`IsolatedDataStorage` makes the rest easy.** It's an actor around any synchronous storage, `Sendable` and an `AsyncDataStorage` itself, that runs the storage's operations one at a time:

```swift
// Make your own storage usable in UnifiedStorage, however simple it is
let draft = IsolatedDataStorage<NotesStorage>.Entry<String>(key: "draft")
```

***NOTE***! Calls on one `SQLiteStorage` wait for each other behind its lock, blocking their threads meanwhile. An app that drives one SQLite scope from many tasks at once can wrap it in `IsolatedDataStorage`, in every entry of that scope, so that waiting callers suspend instead of blocking their threads; the call that runs still blocks one.

---
## Tests

* **Unit tests** check every storage, layer and `UnifiedStorage` against mocks that record their calls, including every path of every compound condition and both sides of every limit.
* **Integration tests** run the default adapters against the real systems: files, SQLite and User Defaults with `swift test`, and the keychain in `Tests/KeychainHost`, a host app with the keychain entitlements, on the iOS Simulator.
* **Public API tests** call the API as an app does, without `@testable`, from the main actor, other actors and nonisolated code.
* CI builds and tests with every Swift version from 6.0 to 6.3 on macOS, tests on the iOS Simulator, and builds for tvOS, watchOS and visionOS.

`swift test` covers 96% of the lines on macOS. The rest is the keychain and iCloud key-value store adapters, which need entitlements, fallbacks for older systems, and paths no test can reach, such as SQLite running out of memory.

```sh
swift test
xcodebuild test -scheme KeyValueStorage -destination "platform=iOS Simulator,name=<an installed iPhone>"
xcodebuild test -project Tests/KeychainHost/KeychainHost.xcodeproj -scheme KeychainHost -destination "platform=iOS Simulator,name=<an installed iPhone>"
```

---
## Design

[DESIGN.md](DESIGN.md) explains why the package is built the way it is: the principles every change follows, and the decisions behind its shape, with the alternatives each one rules out.

---
## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Once you have your Swift package set up, adding KeyValueStorage as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/narek-sv/KeyValueStorage.git", .upToNextMajor(from: "4.0.0"))
]
```

or

* In Xcode select *File > Add Packages*.
* Enter the project's URL: https://github.com/narek-sv/KeyValueStorage.git

In any file you'd like to use the package in, don't forget to
import the framework:

```swift
import KeyValueStorage
```

---
## Upgrading from 3.x

***NOTE***! Version 4 isn't backward compatible with 3.x, neither in its API nor in where it stores values. 4.x doesn't read the values that 3.x saved and doesn't migrate them, so an app that updates finds every storage empty: for example, its users are signed out and their settings are reset. The old values stay where 3.x saved them:

| Storage | Where 3.x saved values |
| --- | --- |
| Keychain | Service `KeyValueStorage`, or `KeyValueStorage.<access group>` for a domain |
| File System | `Application Support/<bundle identifier>/KeyValueStorage/Files`, or `<group container>/KeyValueStorage/Files` for a domain |
| SQLite | `KeyValueStorage.sqlite` in `Application Support/<bundle identifier>/KeyValueStorage/SQLite`, or `<group container>/KeyValueStorage/SQLite` for a domain |
| User Defaults | `UserDefaults.standard`, or the domain's suite, under the key itself |

To keep them, read each value from its 3.x location before using 4.x for it, save it with 4.x, and remove the old one.

---
## Migrating from 2.x

Version 3 stores keychain items, files and some values differently, and doesn't migrate the values saved by 2.x. See the [Changelog](CHANGELOG.md) for the breaking changes and how to move your values.

---
## License

See [License.md](https://github.com/narek-sv/KeyValueStorage/blob/main/LICENSE) for more information.
