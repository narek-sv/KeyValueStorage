# KeyValueStorage

![Build & Test](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml/badge.svg)
[![Coverage](https://img.shields.io/badge/coverage->=98%25-brightgreen)](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-success.svg)](https://github.com/apple/swift-package-manager)

---

Enhance your development with the state-of-the-art key-value storage framework, meticulously designed for speed, safety, and simplicity. Leveraging Swift's advanced error handling and concurrency features, the framework ensures thread-safe interactions, bolstered by a robust, modular, and protocol-oriented architecture. Unique to the solution, types of values are encoded within the keys, enabling compile-time type inference and eliminating the need for unnecessary casting. It is designed with App Groups in mind, facilitating seamless data sharing between your apps and extensions. Experience a testable, easily integrated storage solution that redefines efficiency and ease of use.

**No dependencies.** `KeyValueStorage` works on its own: it uses only frameworks that come with the system, Foundation, Security, Combine and SQLite, so adding it brings no other packages into your project.


---
## Supported Platforms

| | | | | | |
| --- | --- | --- | --- | --- | --- |
| **iOS** | **macOS** | **watchOS** | **tvOS** | **visionOS** | **Swift** |
| 13.0+ | 10.15+ | 6.0+ | 13.0+ | 1.0+ | 6.0+ (Xcode 16+) |

## Choosing a Storage

Every storage works through the same API: declare a typed key, then save, fetch, delete and observe its value with `UnifiedStorage`. Five storages are built in: In Memory, User Defaults, Keychain, File System and SQLite. You can add your own storage by conforming to `KeyValueDataStorage` (see [Custom Storages](#custom-storages)), and your own encoding by conforming to `DataCoder` (see [Coding](#coding)). Values can be shared with your app's extensions and your other apps (see [Setup](#setup)), and observed for changes (see [Observation](#observation)).

Here's how the built-in storages compare:

| | In Memory | User Defaults | Keychain | File System | SQLite |
| --- | --- | --- | --- | --- | --- |
| **Survives app restart** | ❌ | ✅ | ✅ (usually reinstalls too) | ✅ | ✅ |
| **Suitable for secrets** | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Shared with your other apps and extensions** | ❌ | ✅ App Group | ✅ App Group or Keychain Sharing group | ✅ App Group | ✅ App Group |
| **Syncs across the user's devices** | ❌ | ❌ | ✅ iCloud Keychain (`isSynchronizable`) | ❌ | ❌ |
| **Best value size** | Any | Small | Small | Large | Small to medium |
| **Speed** | Fastest | Very fast | Slowest | Slow for small values, fastest for large ones | Fast for small values |
| **Across processes** | – | Last write wins per key | Last write wins per item | Atomic replace per file | Transaction per operation |

**In Memory** - temporary state, caches and tests.
* The fastest storage: no disk access at all.
* Values are lost when the app quits, and are never shared with other processes.

**User Defaults** - settings, flags and other small values.
* Very fast reads from an in-memory cache, while writes reach the disk asynchronously.
* Shared with extensions through an App Group suite.
* Not for sensitive data: the values are stored unencrypted. Keep it small, since the whole domain is loaded into memory.
* Clearing removes every value of the domain, including the ones that weren't saved through `KeyValueStorage`.

**Keychain** - tokens, passwords and other secrets.
* Encrypted by the system, with `accessibility` controlling when the items can be read, for example only while the device is unlocked.
* Can sync through iCloud Keychain (`isSynchronizable`) and be shared with other apps and extensions through an App Group or a Keychain Sharing group.
* Every call goes through a system service, so it's the slowest storage. Use it for small secrets only.
* Items usually survive an app reinstall, and may be unreadable while the device is locked.

**File System** - large values, such as images, videos or cached responses.
* The fastest storage for large values: every value is written once, directly into its own file.
* Deleting a value frees its disk space right away.
* A value can be as large as the free disk space allows.
* Every value is a separate file, so reading one value never loads the others into memory, and a damaged file affects only its own value.
* Files are replaced atomically, so a crash never leaves a value half-written.
* Slow for small values, since every save writes and renames a file.
* Keys must be valid file names, and keys that differ only in case are separate values on every platform.

**SQLite** - many small and medium values, especially when an app and its extensions write the same data.
* All values of a domain live in one database, which is much faster than separate files for small values. For large values, separate files are faster.
* Any string is a valid key.
* Every operation is a transaction across all processes, the strongest guarantee of all storages.
* A fetch followed by a save isn't atomic across processes, and a write fails if another process keeps the database busy for over a second.
* Large values are written twice, first to the database's log and then into the database, so they briefly need about twice their size on disk.
* Deleted values free space inside the database for reuse, but the database file itself doesn't shrink.
* A single value can't exceed SQLite's size limit, so very large values belong in files.

Quick guide:
* Secrets → `KeychainKey`
* Settings and flags → `UserDefaultsKey`
* Large values, such as images or videos → `FileKey`
* Many small and medium values, such as records → `SQLiteKey`
* Data written by both the app and its extensions → `SQLiteKey`
* Temporary state and tests → `InMemoryKey`

---
## Setup

`KeyValueStorage` works out of the box: keys without a domain need no setup, except for the keychain on macOS. If you want to share values among your apps and extensions, you need a little setup in Xcode first. Here's what each setup is for:

* [App Groups](#app-groups) - share values of any storage with your extensions and your other apps.
* [Keychain Sharing](#keychain-sharing) - share keychain items through a keychain access group instead of an App Group.
* [iCloud Keychain](#icloud-keychain) - sync keychain items across the user's devices.
* [macOS](#macos) - use the keychain storage in a macOS app.
* [Privacy Manifest](#privacy-manifest) - nothing to do: what the library declares for the App Store review.

### App Groups

You need this when your app and its extensions, or several of your apps, read and write the same values. An App Group gives them a shared container for User Defaults, files and SQLite databases, and a shared keychain access group.

1. In Xcode, select your app target, open **Signing & Capabilities**, click **+ Capability** and add **App Groups**.
2. Add a group, for example `group.com.company.app`. On macOS, use the group exactly as the capability shows it.
3. Add the capability to every extension and app that shares the values, and select the same group.
4. Use the group as the domain of the keys:

```swift
let onboarded = UserDefaultsKey<Bool>(key: "onboarded", domain: "group.com.company.app")
let token = KeychainKey<String>(key: .init(name: "token"), domain: .init(accessGroup: "group.com.company.app"))
```

A target without the group doesn't see the shared values: User Defaults quietly keeps its own values, and the keychain throws `errSecMissingEntitlement`.

Here is what a `domain` means for each built-in storage:

| Storage | Domain | Where the values live |
| --- | --- | --- |
| `UserDefaultsKey` | App Group ID, e.g. `"group.com.company.app"` | `UserDefaults(suiteName:)` of that group |
| `FileKey` | App Group ID | `<group container>/KeyValueStorage/Files` |
| `SQLiteKey` | App Group ID | `<group container>/KeyValueStorage/SQLite/KeyValueStorage.sqlite` |
| `KeychainKey` | `.init(accessGroup: "group.com.company.app")` for an App Group, or `.init(groupId: "com.company.shared", teamId: "ABCDE12345")` for a Keychain Sharing group | That access group, with the service `KeyValueStorage.<access group>` |
| `InMemoryKey` | Any string | A separate namespace in the current process |

None of these locations depend on the bundle identifier, so your app and its extensions read and write the same values. File and SQLite storage each use their own folder in `KeyValueStorage`, so clearing one never touches the other's data.

### Keychain Sharing

You need this only to share keychain items through a keychain access group instead of an App Group, for example because some of the apps that share the items don't belong to the same App Group.

1. Add the **Keychain Sharing** capability to every app and extension that shares the items.
2. Add the same group to each of them, for example `com.company.shared`. Xcode prefixes it with your team ID.
3. Use the group and your team ID as the domain: `.init(groupId: "com.company.shared", teamId: "ABCDE12345")`. Your team ID is in the membership details of your Apple Developer account.

### iCloud Keychain

You need this to make keychain items available on all the user's devices. Create their keys with `isSynchronizable: true`. There's no capability to add, but:
* Items sync only for users who turned on iCloud Keychain on their devices.
* Synchronizable items can't use the accessibility options that end in `ThisDeviceOnly`.
* Deleting a synchronizable item, or clearing the storage, removes it from all the user's devices.

### macOS

You need this to use the keychain storage in a macOS app. The keychain storage uses the data protection keychain, like on iOS, which needs your app to be signed with a development team: select a team under **Signing & Capabilities**. Command-line tools, and apps that aren't signed with a team, get `errSecMissingEntitlement`.

### Privacy Manifest

There's nothing to set up. `KeyValueStorage` includes a privacy manifest that declares its use of the User Defaults API with the reason `C56D.1`, which covers a library that reads and writes User Defaults only when your app asks it to. Declare your app's own use of the API in your app's privacy manifest.

---
## Usage

The framework is capable of working with any type that conforms to `Codable` and `Sendable`.
The concept here is that first you need to declare the key. It contains every piece of information about how and where the value is stored.

***NOTE***! If your target uses `MainActor` as its default actor isolation, which new Xcode 26 projects do, the `Codable` conformances of your types belong to the main actor. `KeyValueStorage` encodes and decodes values off the main actor, so using such a type as a value fails to compile with `main actor-isolated conformance of 'User' to 'Decodable' cannot satisfy conformance requirement for a 'Sendable' type parameter`. Mark the type, or only its conformance, as `nonisolated`:

```swift
nonisolated struct User: Codable { ... }

// or
struct User: nonisolated Codable { ... }
```

First, you need to declare the key. You can use one of the built-in types:

* `UserDefaultsKey`
* `KeychainKey`
* `InMemoryKey`
* `FileKey`
* `SQLiteKey`

or you can define your own ones. [See how to do that](#custom-storages)

```swift
import KeyValueStorage

let key = UserDefaultsKey<String>(key: "myKey")
// or alternatively provide the domain
let otherKey = UserDefaultsKey<String>(key: "myKey", domain: "sharedContainer")
```

As you can see, the key holds all the necessary information about the value:
* The key name - `"myKey"`
* The storage type - `UserDefaults`
* The value type - `String`
* The domain (*optional*) - `"sharedContainer"`


Now all that is left is to instantiate the storage and use it:

```swift
// Instantiate the storage
let storage = UnifiedStorage()

// Saves the item and associates it with the key, 
// or overrides the value if there is already such an item
try await storage.save("Alice", forKey: key)

// Returns the item associated with the key or returns nil if there is no such item
let value = try await storage.fetch(forKey: key) 

// Deletes the item associated with the key or does nothing if there is no such item
try await storage.delete(forKey: key)

// Sets the item identified by the key to the provided value
try await storage.set("Bob", forKey: key) // save
try await storage.set(nil, forKey: key) // delete

// Removes everything stored in the specified storage and domain,
// including the values saved in previous launches
try await storage.clear(storage: KeychainStorage.self, forDomain: nil)
```

***NOTE***! Clearing `UserDefaultsStorage` removes ***every*** value of its domain, including the values that weren't saved through `KeyValueStorage`.

---
## Type Inference

The framework leverages the full capabilities of ***Swift Generics***, so it can infer the types of values based on the key compile-time, eliminating the need for extra checks or type casting.

```swift
struct MyType: Codable, Sendable { ... }

let key = UserDefaultsKey<MyType>(key: "myKey")
let value = try await storage.fetch(forKey: key) // inferred type for value is MyType
try await storage.save(/* accepts only MyType*/, forKey: key)
```

---
## Custom Storages

`UnifiedStorage` has 5 built-in storage types:
* `In-memory` - This storage type persists the items only within an app session.
* `User-Defaults` - This storage type persists the items within the app's lifetime.
* `File-System` -  This storage saves every value as a separate file in `Application Support/<bundle identifier>/KeyValueStorage/Files`, or in the App Group container. The file is replaced atomically, so a crash never leaves a value half-written or missing. Since the key is used as the file name, it must be a single path component: an empty key, `.`, `..` and keys containing `/` throw `FileStorage.Error.invalidKey`. Uppercase letters, other characters that change with case, and `%` are percent-encoded in the file name, so `Key` is saved as `%4Bey` and never shares a file with `key`, even on a case-insensitive disk. A file name can be at most 255 bytes, and an encoded character takes three bytes for each of its UTF-8 bytes, so longer keys throw `invalidKey` too.
* `Keychain` - This storage type keeps the items in secure storage and persists even after app re-installations. Supports `iCloud` synchronization.
* `SQLite` - This storage keeps all values of a domain in one SQLite database, `Application Support/<bundle identifier>/KeyValueStorage/SQLite/KeyValueStorage.sqlite`, or in the App Group container. Any string is a valid key, and all storages of a domain, in your app and its extensions, share the same database at the same time. Each operation is atomic across processes, but a fetch followed by a save is not: another process can save in between.

You can also define your own storage, and it will work with it seamlessly with `UnifiedStorage` out of the box.
All you need to do is:
1. Define your own type that conforms to the `KeyValueDataStorage` protocol:
```swift
class NewStorage: KeyValueDataStorage { ... }
```
2. Define the new key type (optional, for ease of use):
```swift
typealias NewStorageKey<Value: CodingValue> = UnifiedStorageKey<NewStorage, Value>
```

That's it. You can use it now as the built-in storages:

```swift
let key = NewStorageKey<UUID>(key: customKey)
try await storage.save(UUID(), forKey: key)
```

***NOTE***! You need to handle the thread safety of your storage on your own.

---
## Xcode autocompletion 

To get the advantages of Xcode autocompletion, it is recommended to declare all your keys in the extension of the `UnifiedStorageKey`, like this:

```swift
extension UnifiedStorageKey {
    static var key1: UserDefaultsKey<Int> {
        .init(key: "key1", domain: nil)
    }
    
    static var key2: InMemoryKey<Date> {
        .init(key: "key2", domain: "sharedContainer")
    }
    
    static var key3: KeychainKey<Double> {
        .init(key: .init(name: "key3", accessibility: .afterFirstUnlock, isSynchronizable: true), 
              domain: .init(groupId: "groupId", teamId: "teamId"))
    }
    
    static var key4: FileKey<UUID> {
        .init(key: "key4", domain: "otherContainer")
    }
}
```

then Xcode will suggest all the keys specified in the extension when you put a dot:
<img width="620" alt="Screenshot 2024-03-03 at 13 43 39" src="https://github.com/narek-sv/KeyValueStorage/assets/23353201/992873cd-1030-4c95-87cb-e3788c09e5cc">

---
## Keychain

Use `accessibility` parameter to specify the security level of the keychain storage.
By default the `.whenUnlocked` option is used. It is one of the most restrictive options and provides good data protection.

You can use `.afterFirstUnlock` if you need your app to access the keychain item while in the background. Note that it is less secure than the `.whenUnlocked` option.

Here are all the supported accessibility types:
* `afterFirstUnlock`
* `afterFirstUnlockThisDeviceOnly`
* `whenPasscodeSetThisDeviceOnly`
* `whenUnlocked`
* `whenUnlockedThisDeviceOnly`

The accessibility is applied every time a value is saved, so changing it for an existing key takes effect on the next save.

Set `isSynchronizable` to `true` to sync the item across the user's devices through iCloud Keychain. See [iCloud Keychain](#icloud-keychain) for what it requires.

```swift
let key = KeychainKey<String>(key: .init(name: "key", accessibility: .afterFirstUnlock, isSynchronizable: true),
                              domain: .init(groupId: "groupId", teamId: "teamId"))
```

To share items with your other apps and extensions, use an App Group they all belong to, or a Keychain Sharing group. Set up the capability first, see [Setup](#setup):

```swift
// An App Group, written as in the App Groups capability, without a team prefix
let key = KeychainKey<String>(key: .init(name: "token"), domain: .init(accessGroup: "group.com.company.app"))

// A Keychain Sharing group, which the access group prefixes with your team ID
let otherKey = KeychainKey<String>(key: .init(name: "token"), domain: .init(groupId: "com.company.shared", teamId: "ABCDE12345"))
```

Items without a domain are saved under the `KeyValueStorage` service. Items with a domain use `KeyValueStorage.<access group>` by default, or the `service` you provide, for example to read the items that other code already saved:

```swift
let key = KeychainKey<String>(key: .init(name: "authToken"),
                              domain: .init(groupId: "groupId", teamId: "teamId", service: "com.company.auth"))
```

Clearing the keychain storage removes the synchronizable items too.

---
## Coding

Values are encoded with `RawDataCoder` by default. It stores `Data` as is and `String` as UTF-8, which keeps large values fast and compact, and lets you read raw values saved by other code. Every other type is encoded with its fallback coder, `JSONDataCoder` unless you provide another one.

There are 3 built-in coders:
* `RawDataCoder(fallback:)` - Raw `Data` and `String`, the fallback coder for the rest.
* `JSONDataCoder` - JSON for every type.
* `PropertyListDataCoder` - Binary property lists for every type. Pass a `PropertyListEncoder` with the `.xml` output format to get XML.

Pass the coder to the factory, or conform your own type to `DataCoder`:

```swift
let storage = UnifiedStorage(factory: DefaultUnifiedStorageFactory(coder: PropertyListDataCoder()))
```

***NOTE***! The value type comes from the key, it isn't saved with the value. Changing the value type of an existing key can make its stored value undecodable, or, for `Data` and `String`, be read without an error.

---
## Observation

The `UnifiedStorage` initializer takes a `factory` parameter that conforms to the `UnifiedStorageFactory` protocol, enabling customized storage instantiation and configuration. This feature is particularly valuable for mocking storage in tests or substituting default implementations with custom ones.

By default, this parameter is set to `DefaultUnifiedStorageFactory`, which omits observation capabilities to avoid excessive class burden. However, supplying an `ObservableUnifiedStorageFactory` instance as the parameter activates observation of all underlying storages for changes.

```swift
let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
```

Publishers and streams start with the currently stored value, or `nil` if there's none, followed by every change. Pass `includingCurrentValue: false` to get only the changes.

Combine style publishers:
```swift
let key = InMemoryKey<String>(key: "key")
guard let publisher = try await storage.publisher(forKey: key) else {
    // The storage is not properly configured
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
guard let stream = try await storage.stream(forKey: key) else {
    // The storage is not properly configured
    return
}

for await value in stream {
    print(value) // String?
}
```

Changes are delivered on a background executor, so move to the main thread before updating the UI. Streams resume on the executor of the task that iterates them.

However, it's important to note that only the changes made through observable storages of the current process are published. Changes made by other processes (for example, App Extensions), by storages without observation, or written directly to `UserDefaults`, the keychain or files aren't.

---
## Error handling

All the methods of the `UnifiedStorage` are throwing. Even with a correct setup, some errors can't be avoided and are worth handling:
* `KeychainStorage.Error.os` - for example, `errSecInteractionNotAllowed` while the device is locked and the item is only accessible `.whenUnlocked`, or `errSecMissingEntitlement` when the domain's access group isn't in the app's entitlements.
* `FileStorage.Error` - an invalid key, missing permissions, or a file that is protected while the device is locked.
* `SQLiteStorage.Error.sqlite` - the database file is damaged, or another process kept it busy for longer than a second.
* `DecodingError` - the stored data doesn't match the key's value type, for example after changing the type of an existing key.
* `FileStorage.Error.failedToInitSharedDirectory` and `SQLiteStorage.Error.failedToInitSharedDirectory` - the system has no container for the App Group, for example when the target isn't in the group.
* `UserDefaultsStorage.Error` - the domain is a name `UserDefaults` doesn't allow: your app's own bundle identifier, or `NSGlobalDomain`.

---
## Thread Safety

All built-in storages and `UnifiedStorage` are thread-safe: you can call them from any thread, task or actor at the same time, without data races, and every operation is atomic. A *sequence* of operations, such as a fetch followed by a save, isn't atomic: another task or process can change the value in between. If you extend the storage with your own ones, it is your responsibility to make them thread-safe.

---
## Tests

The whole framework is thoroughly validated with high-quality unit tests. 
Additionally, it serves as an excellent demonstration of how to use the framework as intended.

---
## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Once you have your Swift package set up, adding KeyValueStorage as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/narek-sv/KeyValueStorage.git", .upToNextMajor(from: "3.0.0"))
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
## Migrating from 2.x

Version 3 stores keychain items, files and some values differently, and doesn't migrate the values saved by 2.x. See the [Changelog](CHANGELOG.md) for the breaking changes and how to move your values.

---
## License

See [License.md](https://github.com/narek-sv/KeyValueStorage/blob/main/LICENSE) for more information.
