# KeyValueStorage

![Build & Test](https://github.com/narek-sv/KeyValueStorage/actions/workflows/swift.yml/badge.svg)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-success.svg)](https://github.com/apple/swift-package-manager)
[![CocoaPods compatible](https://img.shields.io/cocoapods/v/KeyValueStorageSwift)](https://cocoapods.org/pods/KeyValueStorageSwift)

---

An elegant, thread-safe, multipurpose key-value storage, compatible with all Apple platforms.

---
## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Swift Package Manager is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. 

Once you have your Swift package set up, adding KeyValueStorage as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/narek-sv/KeyValueStorage.git", .upToNextMajor(from: "1.0.1"))
]
```

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
## Usage

First, initialize the storage:
```swift
let storage = KeyValueStorage()
```

then declare the key by specifing the key name and the type of the item:

```swift
let key = KeyValueStorageKey<Int>(name: "myAge")
```

after which you can save:
```swift
// Saves the item and associates it with the key or overrides the value if there is already such item. 

let myAge = 21
storage.save(myAge, forKey: key)
```

fetch:
```swift
// Fetches and returns the item associated with the key or returns nil if there is no such item.

let fetchedAge = storage.fetch(forKey: key) 
```

delete:
```swift
// Deletes the item associated with the key or does nothing if there is no such item.

storage.delete(forKey: key)
```

set:
```swift
// Sets the item identified by the key to the provided value.

let newAge = 24
storage.set(newAge, forKey: key) // save

storage.set(nil, forKey: key) // delete
```

or clear the whole storage content:
```swift
storage.clear()
```

The KeyValueStorage supports 3 storage types
* `In-memory` (This storage type persists the items only within an app session.)
* `User-Defaults` (This storage type persists the items within the whole app lifetime.)
* `Keychain` (This storage type keeps the items in secure storage and persists even app re-installations. Supports iCloud synchronization.)

You specify the storage type when declaring the key:
```swift
let key1 = KeyValueStorageKey<Int>(name: "id", storage: .inMemory)
let key2 = KeyValueStorageKey<Date>(name: "birthday", storage: .userDefaults)
let key3 = KeyValueStorageKey<String>(name: "password", storage: .keychain())
```
If you don't specify a storage type `.userDefaults` will be used.

To get the advantages of the Xcode autocompletion it is recommended to declare all your keys in the extension of the `KeyValueStorageKey` like so:
```swift
extension KeyValueStorageKey {
    static var key1: KeyValueStorageKey<Int> {
        .init(name: "id", storage: .inMemory)
    }
    
    static var key2: KeyValueStorageKey<Date> {
        .init(name: "birthday", storage: .userDefaults)
    }
    
    static var key3: KeyValueStorageKey<String> {
        .init(name: "password", storage: .keychain())
    }
}
```

then Xcode will suggest all the keys specified in the extension when you put a dot:
<img width="567" alt="Screen Shot 2022-08-20 at 18 04 02" src="https://user-images.githubusercontent.com/23353201/185749955-91558762-513d-46ef-83de-b836808fbb2e.png">

---
## License

See [License.md](https://github.com/narek-sv/KeyValueStorage/blob/main/LICENSE) for more information.
