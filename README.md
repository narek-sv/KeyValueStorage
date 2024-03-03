# KeyValueStorage

![Build & Test](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml/badge.svg)
[![Coverage](https://img.shields.io/badge/coverage->=90%25-brightgreen)](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-success.svg)](https://github.com/apple/swift-package-manager)
[![CocoaPods compatible](https://img.shields.io/cocoapods/v/KeyValueStorageSwift)](https://cocoapods.org/pods/KeyValueStorageSwift)

---

Enhance your development with the state-of-the-art key-value storage framework, meticulously designed for speed, safety, and simplicity. Leveraging Swift's advanced error handling and concurrency features, the framework ensures thread-safe interactions, bolstered by a robust, modular, and protocol-oriented architecture. Unique to the solution, types of values are encoded within the keys, enabling compile-time type inference and eliminating the need for unnecessary casting. It is designed with App Groups in mind, facilitating seamless data sharing between your apps and extensions. Experience a testable, easily integrated storage solution that redefines efficiency and ease of use.


---
## Supported Platforms

| | | | |
| --- | --- | --- | --- |
| **iOS** | **macOS** | **watchOS** | **tvOS** |
| 13.0+ | 10.15+ | 6.0+ | 13.0+ |

## Built-in Storage Types

|  |
| --- |
| **In Memory** |
| **User Defaults** |
| **Keychain** |
| **File System** |

---
## App Groups

`KeyValueStorage` also supports working with shared containers, which allows you to share your items among different **App Extensions** or **your other Apps**. To do so, first, you need to configure your app by following the steps described in [this](https://developer.apple.com/documentation/security/keychain_services/keychain_items/sharing_access_to_keychain_items_among_a_collection_of_apps) article.

By providing corresponding `domain`s to each type of storage, you can enable the sharing of storage spaces. Alternatively, by doing so, you can also keep the containers isolated.

---
## Usage

The framework is capable of working with any type that conforms to `Codable` and `Sendable`.
The concept here is that first you need to declare the key. It contains every information about how and where the value stores.

First declare the key. You can use one of the built-in types

* `UserDefaultsKey`
* `KeychainKey`
* `InMemoryKey`
* `FileKey`

or you can define your own ones. [See here](#custom-storages)
```swift
import KeyValueStorage

let key = UserDefaultsKey<String>(key: "myKey")
// or alternatively provide the domain
let otherKey = UserDefaultsKey<String>(key: "myKey", domain: "sharedContainer")
```

As you can see the key holds all the necessary info about the value:
* The key name - `"myKey"`
* The storgae type - `UserDefaults`
* The value type - `String`
* The domain (optionally) - `"sharedContainer"`

now all the left is to instantiate the storage and use it.
```swift
// Instantiate the storage
let storage = UnifiedStorage()

// Saves the item and associates it with the key 
// or overrides the value if there is already such item. 

try await storage.save("Alice", forKey: key)

// Fetches and returns the item associated with the key or returns nil if there is no such item.
let value = try await storage.fetch(forKey: key) 

// Deletes the item associated with the key or does nothing if there is no such item.
try await storage.delete(forKey: key)

// Sets the item identified by the key to the provided value.
try await storage.set("Bob", forKey: key) // save
try await storage.set(nil, forKey: key) // delete

// or clear the whole storage content
storage.clear()
```

---
## Type Inference

The framework leverages the full capabilities of Swift Generics, so it can infer the types of values based on the key compile- time, eliminating the need for extra checks or type casting.

```swift
struct MyType: Codable, Sendable { ... }

let key = UserDefaultsKey<MyType>(key: "myKey")
let value = try await storage.fetch(forKey: key) // inferred type for value is MyType
try await storage.save(/* accepts only MyType*/, forKey: key)
```

---
## Custom Storages

The KeyValueStorage has 4 built-in storage types
* `In-memory` - This storage type persists the items only within an app session.
* `User-Defaults` - This storage type persists the items within the whole app lifetime.
* `File-System` - This storage saves your key-values as separate file in your file system.
* `Keychain` - This storage type keeps the items in secure storage and persists even app re-installations. Supports `iCloud` synchronization.

You can also define your own storages and `UnifiedStorage` will work with it seamlessly out of the box.
To do so just need to 
1. Define your own type which conforms to `KeyValueDataStorage` protocol.
```swift
class NewStorage: KeyValueDataStorage { ... }
```
2. Define the new key type (for ease of use)
```swift
typealias NewStorageKey<Value: CodingValue> = UnifiedStorageKey<NewStorage, Value>
```

Now you are readt to go, use it as the built-in storages

```swift
let key = NewStorageKey<UUID>(key: customKey)
try await storage.save(UUID(), forKey: key)
```

**NOTE**! You need to handle the thread safety of your storage on your own.

---
## Xcode autocompletion 

To get the advantages of the Xcode autocompletion it is recommended to declare all your keys in the extension of the `UnifiedStorageKey` like so:
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
<img width="567" alt="Screen Shot 2022-08-20 at 18 04 02" src="https://user-images.githubusercontent.com/23353201/185749955-91558762-513d-46ef-83de-b836808fbb2e.png">

---
## Keychain

Use `accessibility` parameter to specify the security level of the keychain storage.
By default the `.whenUnlocked` option is used. It is one of the most restrictive options and provides good data protection.

You can use `.afterFirstUnlock` if you need your app to access the keychain item while in the background. Note that it is less secure than the `.whenUnlocked` option.

Here are all the supported accessibility types:
* *afterFirstUnlock*
* *afterFirstUnlockThisDeviceOnly*
* *whenPasscodeSetThisDeviceOnly*
* *whenUnlocked*
* *whenUnlockedThisDeviceOnly*

Set `synchronizable` property to `true` to enable keychain items synchronization across user's multiple devices. The synchronization will work for users who have the **Keychain** enabled in the *iCloud* settings on their devices. Deleting a synchronizable item will remove it from all devices.

```swift
let key = KeychainKey<String>(key: .init(name: "key3", accessibility: .afterFirstUnlock, isSynchronizable: true),
                                  domain: .init(groupId: "groupId", teamId: "teamId"))
```

---
## Observation

You can also observe each key-value modification within the storage. All you need is to register for the change by specifying the appropriate:

To do so first you need to explicitly inform the `UnifiedStorage` that you need to observe key-value changes.

TODO: -


---
## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Once you have your Swift package set up, adding KeyValueStorage as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/narek-sv/KeyValueStorage.git", .upToNextMajor(from: "2.0.0"))
]
```

or

* In Xcode select *File > Add Packages*.
* Enter this project's URL: https://github.com/narek-sv/KeyValueStorage.git

In any file you'd like to use KeyValueStorage in, don't forget to
import the framework with `import KeyValueStorage`.

### [CocoaPods](https://cocoapods.org)

CocoaPods is a dependency manager for Cocoa projects. For usage and installation instructions, visit their website. To integrate KeyValueStorage into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
pod 'KeyValueStorageSwift'
```

Then run `pod install`.

In any file you'd like to use KeyValueStorage in, don't forget to
import the framework with `import KeyValueStorageSwift`.


---
## License

See [License.md](https://github.com/narek-sv/KeyValueStorage/blob/main/LICENSE) for more information.
