# Changelog

## 4.0.0 - Unreleased

Version 4 rebuilds the library around scopes, synchronous thread-safe storages and typed errors, and adds the iCloud key-value store. **It isn't backward compatible with 3.x, neither in its API nor in where it stores values: 4.x doesn't read or migrate the values 3.x saved.** See [Upgrading from 3.x](README.md#upgrading-from-3x) for where 3.x kept them.

### Breaking changes

- **Scopes replace domains:** an entry, `UnifiedStorage.Entry(key:scope:)`, takes a scope instead of an optional domain, and `clear(storage:forScope:)` replaces `clear(storage:forDomain:)`. A storage's `Scope` is where its values live: `.own` for the running app or extension, `.appGroup(id:)` for a group, `.iCloud` for synced keychain items and the iCloud key-value store, each with a `namespace`; Keychain, File and SQLite scopes also have a protection level. Every storage has a `.default` scope.
- **Entries replace `UnifiedStorage`'s keys:** `UnifiedStorageKey` is `UnifiedStorage.Entry`, a value's storage type, scope and key, and every storage `UnifiedStorage` takes names its own, your own storages included: `FileStorage.Entry<Value>` replaces `FileKey<Value>`, and so on for `KeychainKey`, `UserDefaultsKey`, `InMemoryKey` and `SQLiteKey`. `UnifiedStorage`'s methods take the entry: `fetch(_:)`, `save(_:to:)`, `set(_:to:)`, `delete(_:)`, `publisher(for:)` and `stream(for:)` replace `fetch(forKey:)`, `save(_:forKey:)`, `set(_:forKey:)`, `delete(forKey:)`, `publisher(forKey:)` and `stream(forKey:)`, and `UnifiedStorage.Key` is removed.
- **Where values live:** User Defaults' `.own` scopes use the suite `<app>.KeyValueStorage` instead of `UserDefaults.standard`, under `<namespace>!/<key>`; keychain services are `<app>:<namespace>:<protection>` or `<group>/<namespace>/<protection>`; files are in `<Application Support, Caches or tmp>/<app>/<namespace>!/<protection>` or the group container, named so that `Key` is `!key`; the SQLite database is `.KeyValueStorage.sqlite` in the files' folder of the same scope. See [App Groups](README.md#app-groups).
- **Exact keys:** the built-in storages' keys and namespaces are `ExactString`, compared by their exact UTF-8 bytes, so `"é"` and `"e\u{301}"` are two keys in every storage, files included.
- **Keychain protection is part of the scope:** an entry whose protection changes finds none of the items saved with the old one, instead of changing their accessibility on the next save. Move them with `UnifiedStorage.move(_:to:)`.
- **Only the library's values:** User Defaults and the iCloud key-value store take only `Data` under a stored key for a value: anything else fetches as `nil`, is never replaced or removed, and makes `save` throw `.keyOccupied`.
- **Typed errors:** every storage throws its own `Error`, with new cases, and `UnifiedStorage`, `CodingStorage` and `AsyncCodingStorage` throw `CodingStorageError<Storage>`, `.storage` or `.coding`. See [Error handling](README.md#error-handling).
- **Renamed and split protocols:** `KeyValueDataStorage` is `AsyncDataStorage`, refined by the synchronous `DataStorage`; `KeyValueCodingStorage` is `AsyncCodingStorage`, next to the synchronous `CodingStorage`; `KeyValueObservableStorage` is `ObservableStorage`, which wraps a coding storage instead of subclassing it; `KeyValueCodingStorageKey` is `CodingStorageKey`, and `KeyValuePublisher` is `ValuePublisher`.
- **`set(_:forKey:)` is a storage requirement:** `AsyncDataStorage` and `DataStorage` require it, so a storage can save a value, or delete it for `nil`, in one operation of its own, and every layer calls it instead of `save` or `delete`: `CodingStorage`, `AsyncCodingStorage`, `ObservableStorage`, `IsolatedDataStorage`, and `UnifiedStorage`'s `set(_:to:)` and `update(_:_:)`. A synchronous storage gets `save` or `delete` by default; an asynchronous one implements it. An `ObservableStorage` subclass that changes `save` or `delete` changes `set` too.
- **Synchronous, `Sendable`, `final` storages:** the built-in storages' operations don't need `await` and run on the caller's thread. They take a backing store and a locator instead of a `FileManager` and root folder, a `UserDefaults` or a `KeychainWrapper`. `KeychainWrapper`, `KeychainWrapperError`, `KeychainAccessibility`, `KeychainStorage.Domain`, `KeychainStorage.defaultService`, the storages' `directoryName` and the global actors (`CodingStorageActor`, `FileActor`, `KeychainActor`, `UserDefaultsActor`, `InMemoryActor`, `SQLiteActor`) are removed.
- **`UnifiedStorage` is a class instead of an actor,** and takes only `Sendable` storages (`UnifiedStorable`): wrap any other synchronous storage in `IsolatedDataStorage`.
- **Factories:** `UnifiedStorageFactory` has four requirements, each with a default: `dataStorage(for:)`, `coder(for:)`, `codingStorage(for:)` and `observableStorage(for:)`. `DefaultUnifiedStorageFactory` and `ObservableUnifiedStorageFactory` are structs without a `coder` parameter: pick coders in your factory's `coder(for:)`.
- **Observation:** a factory makes a storage observable through `observableStorage(for:)`, and `UnifiedStorage(observable: true)` makes all of them observable. Changes are delivered on the thread that saves them, instead of on `CodingStorageActor`.
- **Coders are synchronous:** `DataCoder`'s `encode` and `decode` aren't `async`.

### Fixed

- Clearing a User Defaults storage removed every value of its suite, including your app's own and other libraries'. It removes only the values the library saved in the scope's namespace now.

### Added

- `UbiquitousStorage`, for the iCloud key-value store (watchOS 9.0 or later).
- `UnifiedStorage.move(_:to:)`, which moves an entry's value to another entry, scope or key, such as after its protection changes or its key is renamed, without losing it.
- `UnifiedStorage.update(_:_:)`, which reads and writes a value as one step.
- `UnifiedStorage.close(storage:forScope:)`, which lets go of a scope's storage, such as to close the database of a SQLite scope the app is done with.
- `UnifiedStorage.Entry(key:scope:)`, `CodingStorageKey(key:)` and every scope case with a namespace take a `String` too, for keys and namespaces named at runtime.
- `UnifiedStorage(observable:)`.
- Retention for files and SQLite, `.persistent`, `.cache` or `.temporary`, and protection levels for both.
- `DataStorage`, for synchronous custom storages, which need no `await` through `CodingStorage`; `AsyncDataStorage`, for asynchronous ones; and `IsolatedDataStorage`, an actor that makes any synchronous storage shareable.
- A locator and a backing store for every built-in storage: a custom locator changes where values live, and a custom backing store replaces the system calls, for example in tests. See [Custom Locators](README.md#custom-locators).
- `bufferingPolicy` for `stream(for:)`.
- `ExactString` and `OwnIdentity`.
- The privacy manifest also declares file timestamps, with the reason `C617.1`, for the file storage's `lstat`.

### Performance

- The built-in storages run on the caller's thread instead of each on a global actor of its own, and `UnifiedStorage` isn't an actor, so calls on different storages and scopes run in parallel.

## 3.0.0 - 2026-10-15

Version 3 fixes data loss, security and concurrency issues, which required changing where and how values are stored. **Values saved by 2.x are not migrated automatically**; see [Migrating from 2.x](#migrating-from-2x).

### Breaking changes

- **Installation:** CocoaPods is no longer supported. Add the package with Swift Package Manager.
- **Installation:** Swift 6.0 (Xcode 16) or later is required, and the library is compiled in the Swift 6 language mode.
- **Keychain:** items without a domain are saved under the `KeyValueStorage` service instead of the bundle identifier, and items with a domain under `KeyValueStorage.<access group>` or `Domain.service`.
- **Keychain:** a key without accessibility saves its items as `.whenUnlocked`, and every save applies the key's accessibility to the existing item.
- **Files:** values are stored in `Application Support/<bundle identifier>/KeyValueStorage/Files` and `<group container>/KeyValueStorage/Files`, instead of `Documents/<bundle identifier>` and `<group container>/<bundle identifier>`.
- **Files:** `%` and characters that change with case, such as uppercase letters, are percent-encoded in file names, so `Key` is stored as `%4Bey`, and keys that differ only in case are separate values on every platform.
- **Files:** invalid keys throw `FileStorage.Error.invalidKey`. `failedToSave` is removed, failures are reported as `.other`, and `failedToFindDocumentsDirectory` is renamed to `failedToFindApplicationSupportDirectory`.
- **Coding:** the default coder is `RawDataCoder`, which stores `Data` as is and `String` as UTF-8 instead of JSON.
- **Coding:** `XMLDataCoder` is renamed to `PropertyListDataCoder` and stores every value as the only element of an array.
- **Coding:** `JSONDataCoder` and `PropertyListDataCoder` are structs instead of actors.
- **Coding:** fetched values are decoded as the key's value type instead of its optional, so a stored JSON `null` for a non-optional key throws instead of returning `nil`.
- **UnifiedStorage:** `clear()` and `clear(storage:)` are removed. Use `clear(storage:forDomain:)`, or delete the keys.
- **Observation:** publishers and streams start with the current value. Pass `includingCurrentValue: false` for the previous behavior.
- **Observation:** `publisher(forKey:)` returns `KeyValuePublisher` instead of `AnyPublisher`, and `KeyValueObservableStorage`'s `publisher(forKey:)` and `stream(forKey:)` are `async throws`.
- **Concurrency:** `KeyValueCodingStorage` is no longer isolated to `CodingStorageActor`, so creating it doesn't need `await`.
- **Concurrency:** the library no longer declares `UserDefaults`, `AnyPublisher`, `AsyncPublisher` and `AnyCancellable` as `@unchecked Sendable` for your whole app.

### Fixed

- `DefaultUnifiedStorageFactory` and `ObservableUnifiedStorageFactory` couldn't be created or subclassed outside the module, so observation couldn't be enabled.
- App extensions couldn't read keychain items and files that the app saved to a shared domain.
- Changing a keychain key's accessibility made its item unreadable and every later save fail.
- Clearing the keychain left iCloud-synchronizable items, and on macOS searched a different keychain than the one items are saved to.
- An empty file key deleted every stored file and broke the storage, `../` keys wrote outside the storage directory, and keys with `/` failed silently.
- Saving a file wasn't atomic, read errors were returned as missing values, and clearing reported success when the directory couldn't be read.
- Clearing a `UserDefaultsStorage` created with an injected `UserDefaults` wiped the standard domain instead of the injected one.
- Concurrent first accesses to a storage through `UnifiedStorage` created one storage per caller.
- `PropertyListDataCoder` couldn't encode single values such as `String` or `Int`.
- Observations were never released, even after all subscribers were gone.

### Added

- `SQLiteStorage` and `SQLiteKey`, which keep all values of a domain in one SQLite database that an app and its extensions can use at the same time.
- `RawDataCoder(fallback:)`, the new default coder.
- `DefaultUnifiedStorageFactory(coder:)` and `ObservableUnifiedStorageFactory(coder:)`.
- `includingCurrentValue` for `publisher(forKey:)` and `stream(forKey:)`.
- `KeychainStorage.Domain(accessGroup:service:)`, which also accepts an App Group as the keychain access group, `Domain(groupId:teamId:service:)` for Keychain Sharing groups, `KeychainStorage.defaultService`, and a public `KeychainWrapper` to use custom services.
- `FileStorage.directoryName` and `SQLiteStorage.directoryName`, the names of their folders in `KeyValueStorage`.
- The storages' `domain` can be read without `await`.
- visionOS 1.0 or later is a supported platform.

### Performance

- Fetching and saving through `UnifiedStorage` is about 23% faster, because key types are hashed with `ObjectIdentifier` instead of their names.
- Coding no longer runs on shared actors: 8 tasks saving and fetching 50 KB values finish 3.6x faster than sequentially, instead of taking the same time.
- Saving and fetching a 100 KB `Data` value is about 350x faster, and a 10 KB string about 11x faster.

### Migrating from 2.x

Read the values from their 2.x locations with `JSONDataCoder`, save them with 3.0, and remove the old ones:

```swift
let storage = UnifiedStorage()
let bundleIdentifier = Bundle.main.bundleIdentifier!

// Keychain (iOS): 2.x used the bundle identifier as the service
let oldKeychain = KeyValueCodingStorage(storage: await KeychainStorage(keychain: KeychainWrapper(serviceName: bundleIdentifier)),
                                        coder: JSONDataCoder())
let oldTokenKey = KeyValueCodingStorageKey<KeychainStorage, String>(key: .init(name: "token"))
if let token = try await oldKeychain.fetch(forKey: oldTokenKey) {
    try await storage.save(token, forKey: KeychainKey<String>(key: .init(name: "token")))
    try await oldKeychain.delete(forKey: oldTokenKey)
}

// Files: 2.x stored them in Documents/<bundle identifier>, named exactly like the key
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let oldAvatar = documents.appendingPathComponent(bundleIdentifier).appendingPathComponent("avatar")
if let data = try? Data(contentsOf: oldAvatar) {
    let avatar: Data = try JSONDataCoder().decode(data)
    try await storage.save(avatar, forKey: FileKey<Data>(key: "avatar"))
    try FileManager.default.removeItem(at: oldAvatar)
}

// UserDefaults: the keys are the same, only String and Data values are encoded differently
let oldDefaults = UnifiedStorage(factory: DefaultUnifiedStorageFactory(coder: JSONDataCoder()))
```

Keychain items saved by 2.x on macOS are in the file-based keychain, which 3.0 doesn't read.
