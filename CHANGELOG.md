# Changelog

## 3.0.0

Version 3 fixes data loss, security and concurrency issues, which required changing where and how values are stored. **Values saved by 2.x are not migrated automatically**; see [Migrating from 2.x](#migrating-from-2x).

### Breaking changes

- **Keychain:** items without a domain are saved under the `KeyValueStorage` service instead of the bundle identifier, and items with a domain under `KeyValueStorage.<groupId>` or `Domain.service`.
- **Keychain:** a key without accessibility saves its items as `.whenUnlocked`, and every save applies the key's accessibility to the existing item.
- **Files:** values are stored in `Application Support/<bundle identifier>/KeyValueStorage` and `<group container>/KeyValueStorage`, instead of `Documents/<bundle identifier>` and `<group container>/<bundle identifier>`.
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

- `RawDataCoder(fallback:)`, the new default coder.
- `DefaultUnifiedStorageFactory(coder:)` and `ObservableUnifiedStorageFactory(coder:)`.
- `includingCurrentValue` for `publisher(forKey:)` and `stream(forKey:)`.
- `KeychainStorage.Domain(groupId:teamId:service:)`, `KeychainStorage.defaultService`, and a public `KeychainWrapper` to use custom services.
- `FileStorage.directoryName`.

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

// Files: 2.x stored them in Documents/<bundle identifier>
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let oldFiles = KeyValueCodingStorage(storage: await FileStorage(fileManager: .default, root: documents.appendingPathComponent(bundleIdentifier)),
                                     coder: JSONDataCoder())

// UserDefaults: the keys are the same, only String and Data values are encoded differently
let oldDefaults = UnifiedStorage(factory: DefaultUnifiedStorageFactory(coder: JSONDataCoder()))
```

Keychain items saved by 2.x on macOS are in the file-based keychain, which 3.0 doesn't read.
