# KeyValueStorage — Design

Why KeyValueStorage is built the way it is: the principles every change follows, and the decisions behind its shape,
each with what it rules out. It's written for contributors and reviewers; how to use the package is in the
[README](README.md).

A decision is here when a careful reviewer would otherwise "fix" it or ask "why not …?". Reopening one takes new
evidence, such as a measurement, a change in a system's behavior or a new Swift version. A change that reverses or
extends a decision updates its entry in the same commit, and entries keep their numbers.

## Principles

- **Simple, bulletproof, sound:** the simplest rule that holds for every input. No logic in default backing stores (one
  system call per member); all naming lives in the locators, with the byte-level encodings they share in
  `Helpers/String+UTF8.swift`; no parameters or properties for demonstration only; never swallow a "can't tell": throw
  instead.
- **Sealed by default, open on every layer:** the built-in storages hide where and how they keep values behind scopes,
  each a sandbox the library simulates inside the system's shared places. A scope's values never meet another scope's,
  another library's or other code's, and clearing a scope removes only its own, so an app splits its data as it likes,
  such as a namespace per feature or per signed-in user, and clears or moves each part on its own. A few exceptions
  remain, all rare: D9 lists them, with how an app stays clear of them. For what the seal rules out, every layer is
  open: a storage takes its locator and backing store, and `UnifiedStorage` takes a factory that swaps any storage
  type's storage, coder, coding storage or observable storage. An app swaps in its own, or subclasses the library's:
  most classes are open, including all an adjustment needs, so a subclass changes one behavior and inherits the rest
  (D2, D22). What an app swaps in owns the guarantees it changes.
- **Consistency:** a rule decided for one storage applies to all six.
- **Isolation:** storages share no code, only the primitives in `Helpers/`: each keeps its own scope, error, locator and
  backing store types, even where they match another's, as File's and SQLite's do. File and SQLite share a scope's
  folder, so a test (`testEveryScopesDatabaseIsInTheFileStoragesFolderForTheSameScope`), not shared code, keeps their
  two folder rules in agreement. `CodingStorage` and `AsyncCodingStorage` stay copies too: what they could share is
  already in the coder.
- **Names** are exact bytes everywhere (`ExactString`), so `"é"` and `"e\u{301}"` are two keys. Encode, don't reject:
  any string is a valid key or namespace, and only system limits throw.
- **Only the storage's own values:** the library never replaces or removes other code's data. In File, User Defaults and
  Ubiquitous, anything at a key's place that isn't the storage's kind of value is other code's: `fetch` returns `nil`,
  `delete` and `clear()` leave it, and `save` throws `.pathOccupied` or `.keyOccupied` instead of replacing it.
- **Errors** are typed end to end, carry the failing input as the caller passed it, are documented per case, and every
  throw site is tested. Each storage throws its own `Error`, which `CodingStorageError` wraps, never translates. Absence
  isn't an error (`nil` from `fetch`, nothing to do for `delete` and `clear()`), and nothing else is swallowed, so an
  unreadable place never passes for an empty one. Invalid input throws before any side effect, and nothing traps: no
  `try!`, no force unwrap of a system result, no `fatalError`, no reachable Objective-C exception.
- **System and SDK gotchas** get a doc comment on the case they affect, not a workaround, unless they'd let two scopes
  reach each other's values.
- **Comments** hold only essentials, gotchas and warnings, one line where possible, describing the current behavior,
  never its history. API docs use `///`, `- Note:` and `- Warning:`.
- **Tests** use XCTest, with `// Given`, `// When`, `// Then` and mocks that record their calls. Storages, layers and
  `UnifiedStorage` keep 100% region and line coverage; default adapters get integration tests against the real system.
  Every behavior the docs state is either measured by a test or listed among the checks that need a device.
- **Condition coverage, not just lines:** Swift's coverage counts a whole condition as one region, so every compound
  condition (`&&`, `||`, `if`/`guard` clause lists, `where`, `??`, ternaries, patterns) needs a test for each path that
  short-circuiting can tell apart: `a && b && c` needs `a` false, `b` false, `c` false and all true. Limits get a test
  on each side of the boundary.
- **Members for tests only** are internal and read-only, and only where a test can't observe a state otherwise, such as
  `UnifiedStorage.Scopes.state(of:in:)`. Tests wait for a state with `waitUntil`, never for a fixed time.

## Decisions

### Shape

#### D1. Each storage is three parts: the storage, its locator and its backing store

The storage holds the logic: what it checks before acting, what each system error means, and how `clear()` removes
values. The locator owns every name: scope to place, key to stored name and back, and the system's limits on them. The
backing store is the system and nothing else: one call per member, no logic, acting only on the places it's given.

- **Why:** every rule, including what an error means, sits where unit tests reach it with mocks, so the storages are
  fully covered without the real systems, and the default adapters need only integration tests.
- **Instead of:** storages that call the systems themselves, which takes subclassed `FileManager` or `UserDefaults`
  mocks, and the real keychain, to test.

#### D2. Extension points are protocols with `open class Default…` implementations; the storages are `final`

Each storage's backing store and locator is a protocol with an `open` default, passed to
`init(scope:backingStore:locator:)`, which defaults both to what `init(scope:)` uses. `CodingStorage`,
`AsyncCodingStorage` and `ObservableStorage` are open classes with open operations. The six storages and
`UnifiedStorage` are `final`.

- **Why:** a subclass of a default changes one operation or one naming rule and reaches the rest through `super`; a
  storage changes through what it's given, so its own logic stays whole.
- **Cost:** the open classes are `@unchecked Sendable`, and warn that a subclass's own state must be thread-safe too.

#### D3. Synchronous storages stay synchronous

`DataStorage` refines `AsyncDataStorage` and redeclares its operations as synchronous, so a storage implements each
operation once, and code that uses a synchronous storage directly never needs `await`.

- **Why:** most apps work on the main actor, and a storage backed by a server or CloudKit can still be an
  `AsyncDataStorage` without making the built-in ones, or the code that uses them, asynchronous.
- **Constraints:** `AsyncDataStorage` has no extension members, since an `async` member wins over a synchronous one of
  the same name in async code, and synchronous storages would need `await`. For the same reason, its `set` has no
  default (D25), and no protocol requires `init()`: an async default would win over the built-in storages' own
  synchronous `init()`, and a synchronous one needs `init(scope:)` redeclared as synchronous, which crashes Swift 6.3 in
  generic calls. `DataStorageScope.default` stays, since generic default arguments need it.

#### D4. Small layers that each do one thing

Coding (`CodingStorage`, `AsyncCodingStorage`), observation (`ObservableStorage`) and isolation (`IsolatedDataStorage`)
each wrap the layer below, and `UnifiedStorage` puts them together per storage type and scope. Isolation wraps the data
storage, so coding stays outside it.

- **Why:** a coding storage knows nothing about observation, and an unobserved storage pays nothing for it. Encoding
  runs in parallel on the callers' tasks, while `IsolatedDataStorage` serializes only the storage's calls.
- **Instead of:** observation built into every coding storage, with a registry that's always there and publishers that
  return `nil`.

#### D5. Coders are synchronous, and `RawDataCoder` is the default

`DataCoder` is synchronous. `RawDataCoder` keeps `Data` as is and `String` as UTF-8, and encodes every other type with
its fallback, `JSONDataCoder` unless given another.

- **Why:** JSON and property-list coding are synchronous, so async coders would only add hops. Raw bytes skip encoding,
  which makes large values faster and smaller than base64 or quoted text, and reads values other code saved raw, such
  as an existing token in the keychain.

### Concurrency

#### D6. The built-in storages are thread-safe and `Sendable`; the storage protocols aren't

The six storages are `Sendable`: their systems are thread-safe, and SQLite's connection takes a lock per operation.
`AsyncDataStorage` and `DataStorage` don't require `Sendable`, so a simple storage of an app's own needs nothing more.
`UnifiedStorage` takes only `Sendable` storages (`UnifiedStorable`), and `IsolatedDataStorage`, an actor, makes any
synchronous storage shareable.

- **Why:** five storages were thread-safe through their systems already; only SQLite's prepared statements needed a
  lock. An actor around each built-in storage would serialize each scope, with no parallel file I/O, and still leave
  other instances and processes racing. `Sendable` is a marker protocol, so the choice can't be made at runtime: the
  type states it once, and the compiler checks it.
- **Cost:** calls on one SQLite storage block their threads while they wait, also on Swift's cooperative thread pool,
  where an actor would suspend them; `IsolatedDataStorage` gives that when it matters. Two check-then-act races are
  tolerated: a file removed between a check and its removal counts as deleted, and a keychain save stays correct when
  another call adds or removes the item in between, so the last save wins.
- **Instead of:** a global actor per storage, as in 3.x, which forced `async` and an actor hop on every call.

#### D7. Locks only inside building blocks

Locks guard state that several instances share and the type system can't see: the observation registry, the in-memory
store, each SQLite connection and `UnifiedStorage`'s table of scopes. None is held across an `await`, and the public API
has none.

- **Instead of:** a lock wrapper for synchronous storages, which would block the caller, the main thread included,
  during I/O, need a recursive lock for observers, and be a second way to do what `IsolatedDataStorage` does.

#### D8. Observation is opt-in, and delivered inside the save

`ObservableStorage` publishes the changes made through it to the observers of the same storage type, scope, key and
value type, through any instance in the process. It delivers each change synchronously, on the saving thread, before the
save returns. A factory modifier turns it on for every storage type or for one.

- **Why:** no actor hop per write, and releasing an observation is synchronous. Storages that nobody observes don't pay
  for it.
- **Cost, documented:** only changes made through observable storages in this process are published, not those of
  other processes, other devices, direct system writes or the system purging caches. Concurrent saves of one key may
  deliver out of order, and a `sink` in `@MainActor` code crashes in the Swift 6 language mode without `receive(on:)`.

### Scopes and names

#### D9. Sealed scopes: the library picks the place and owns every name in it

A scope says who sees the values, on which devices, how long they're kept and how they're protected; it never names a
system location. Every scope names a namespace, and there's no root. Interop with other code's files, items or keys goes
through a custom locator, which then owns the guarantees.

- **Why:** every input is a valid name, no two scopes or keys clash, `clear()` removes exactly its scope's values, and
  the storages stay interchangeable.
- **Instead of:** names one to one with the system's, whose rules would become key rules (`/`, `..`, case, length),
  bring the clashes back, and leave `clear()` unable to tell the scope's entries from other code's; or places the app
  names (`.directory(at:)`, `.suite(named:)`), whose guarantees would depend on the input: URL aliases, the global
  domain's suite names, folders other code writes to.
- **Cost:** keys that need a different protection or retention need a scope each, and changing either later starts an
  empty set.
- **Exceptions an app avoids,** by the rule after each:
  - **One namespace in two parts:** features, modules or libraries that use one namespace in one place share its
    values, and each one's `clear()` removes the others'. Every built-in storage's `default` scope uses
    `"KeyValueStorage"`, so it's shared by everything in the app that uses one. Give each library, and each part the
    app clears on its own, a namespace of its own.
  - **One bundle ID in two builds** (D11): builds that share one share `.own` values, unit tests hosted in an app use
    the app's, and on macOS `swift test` runs every package's tests as `com.apple.dt.xctest.tool`. Give tests a
    namespace of their own.
  - **App Group ids that differ only in case,** on macOS: File and SQLite give them one folder, so a `move` between them
    deletes the value, and User Defaults writes one file but reads two suites, which loses or mixes values. Write each
    id as the capability shows it.
  - **Two storage types over one place,** such as `FileStorage` and `IsolatedDataStorage<FileStorage>`, share values
    but not holds, closes or observers (D21). Reach each scope through one storage type.
  - **A custom locator** that maps two scopes or keys to one name shares their values, and one that decodes names it
    didn't encode lets `clear()` remove other code's; observers are shared by storage type and scope, whatever the
    locator. Follow the rules its protocol lists.
  - **Code that removes a whole place,** such as every keychain item of the app, its Caches folder or an App Group's
    suite, removes the library's values with the rest. Make the app's resets remove only their own items.
- **Exceptions the system makes,** which no library can seal, since the seal keeps names apart, not code: whatever
  reaches a place through the system reaches the values in it.
  - **Keychain:** `.own` items go to the app's default access group, its first Keychain Sharing group if it lists any,
    where every app in that group reaches them. List a group of the app's own first.
  - **iCloud key-value store:** every app whose entitlements name the same store reaches its values, and the app's
    other code counts toward its limits of 1 MB and 1024 keys.
  - **User Defaults:** launch arguments, the global domain and registered defaults under a stored key's name read as
    its value in every suite, and one that isn't `Data` makes `save` throw `.keyOccupied`. Stored keys hold `!/`, so
    only a name chosen on purpose meets one.
  - **macOS without App Sandbox:** the user's other apps can read `.own` files, databases and suites. Keep secrets in
    the keychain.

#### D10. Retention and protection are part of the place

File and SQLite scopes take a retention (`.persistent`, `.cache` or `.temporary`), and File, SQLite and Keychain scopes
a protection. Scopes that differ in either never share values: each protection level gets a folder of its own, named
with one letter, or a keychain service of its own.

- **Why:** if two protections shared a place, each SQLite open would re-apply its class to the other's files, and each
  `clear()` would empty both. One letter, because every byte counts toward the system's 1024-byte limit on a whole path.

#### D11. `.own` places carry the app's identifier

File and SQLite paths, the User Defaults suite and keychain services carry the bundle ID, or the process name without
one; App Group places don't. Where it becomes a file or suite name, it's encoded as names are (D12).

- **Why:** on macOS without App Sandbox, `~/Library` and the temporary directory are shared by every app, and keychain
  saves without an access group go to the first Keychain Sharing group, where two apps' items would meet. Encoded,
  bundle IDs that differ only in case never share a folder, and the folder never meets the
  `Application Support/<bundle ID>` folder other code uses.
- **Cost, documented:** builds that share a bundle ID share values, and unit tests hosted in an app use the app's, so
  tests take a namespace of their own.

#### D12. Names are encoded losslessly, and never normalized

File and SQLite names keep `a`–`z`, `0`–`9`, `_` and `-`, write a capital as `!` and its lowercase letter, any other
byte as `%` and two hex digits, and the empty name as `%`; namespace folders end with `!`, which no encoded name does.
User Defaults and Ubiquitous store `<namespace>!/<key>`, with `%` and NUL escaped in both and `/` in the namespace.
Keychain services are `<app>:<namespace>:<protection>` or `<group>/<namespace>/<protection>`, with `%`, `:` and `/`
escaped in every part. Every decoding is the strict inverse of its encoding.

- **Why:** any string is a valid key. File names never have capitals, `.` or whitespace, so a case-insensitive or
  normalizing volume can't merge two, and no key's file is a dot file. NUL never reaches a suite's file, where its value
  would be lost on relaunch. Strict inverses claim only the names their scope writes, so `clear()` never removes another
  scope's values.
- **Instead of:** normalizing, since Foundation's canonical mapping merges keys that Swift keeps apart, and
  `removingPercentEncoding` drops a leading U+FEFF; or rejecting the characters a system can't take.

### Storages

#### D13. No iCloud Drive scope, and no file coordination

- **Why:** every file write is an atomic replace, so readers in other processes never see a partial file, and
  coordinating would add a round trip to a system daemon on every operation; a per-key option, or a second storage type
  over the same folder, would let uncoordinated writes slip in. Read-modify-write across processes belongs to SQLite.
  Files in iCloud Drive may not be downloaded yet, conflict across devices, need `url(forUbiquityContainerIdentifier:)`
  off the main thread and require coordination, which breaks the synchronous, local-first contract.
- **Instead:** synced values use `UbiquitousStorage`, Keychain's `.iCloud` scopes, or CloudKit outside the library. If
  this is ever revisited, coordination goes into a backing store of its own, always on for its scope.

#### D14. Files: one file per value, written atomically, links never followed

Each value is a regular file in its scope's folder, saved and fetched whole and written with an atomic replace. Links
are never followed, read, written or removed. `clear()` tries every value and throws `.clearIncomplete` with each one it
couldn't remove.

- **Why:** reading a value never loads the others, and a damaged file affects only its own value. A link could lead out
  of the scope. A `clear()` that stopped at its first failure would leave the rest untried, and the caller unsure what's
  gone.
- **Cost, documented:** a value is held in memory whole.

#### D15. SQLite: a database per scope, WAL, `synchronous = NORMAL` and a lock per operation

Each scope has a database of its own, `.KeyValueStorage.sqlite` in File's folder for the scope, so `clear()` empties it
whole. The connection runs in WAL mode with `synchronous = NORMAL`, set explicitly, and a 1-second busy timeout, and
each operation holds its lock. Links in the path are followed.

- **Why:** WAL lets readers and a writer work at once, also across processes. NORMAL is Apple's default: a save
  survives an app crash, and a power loss can lose the last saves but never corrupts the database, as the README says.
  The connection's prepared statements serve one call at a time. `SQLITE_OPEN_NOFOLLOW` would reject any link in the
  path, and `/var` is a link to `/private/var` above every app container.
- **Cost:** calls on one storage block their threads while they wait (D6).

#### D16. Keychain: no read before a write

`save` updates the item and adds it only when the update finds none; `delete` and `clear()` remove in one call each.
Nothing reads an item first.

- **Why:** reading decrypts the item, which fails while the device is locked, so a `.whenUnlocked` item couldn't even be
  deleted then. Anything at the scope's service and account is the scope's, so there's nothing to check.

#### D17. User Defaults: the `.own` suite is the library's own

`.own` scopes use the suite `<app>.KeyValueStorage`, never `UserDefaults.standard`. `.appGroup` throws
`.invalidSuiteName` for the global domain's names and for the `.own` suite's name.

- **Why:** only the library writes to its suite, so other code's keys never meet its own, the common reset
  `UserDefaults.standard.removePersistentDomain(forName:)` can't wipe its values, and `.standard`, which loads at
  launch, stays small. Writes through a global-domain name reach every suite, so that's the one system gotcha with a
  check.
- **Note:** App Group suites must be named after the group, so other code writes there too; the `!` in stored keys
  marks the library's.

#### D18. Ubiquitous: one scope, and its limits checked before the call

`UbiquitousStorage` has one scope case, `.iCloud(.own, namespace:)`. Every call checks the stored key's length, 128
UTF-16 code units, and a save also checks the value's size, 1,000,000 bytes, before calling the store.

- **Why:** a process reaches exactly one store, chosen by its entitlement and the Apple Account; App Groups don't affect
  it. A longer key makes the store raise an Objective-C exception, a crash. Apple's limit is "1 megabyte" per value:
  read as 1 MiB, values just under it would pass the check and be silently refused, while 1,000,000 bytes holds under
  either reading.

### UnifiedStorage

#### D19. `UnifiedStorage` adds no isolation of its own

It keeps one storage per storage type and scope, made by its factory on first use and kept until
`close(storage:forScope:)` or until it's deallocated; concurrent first calls share one creation, and a failed one isn't
kept. A call finds its storage under the instance's lock, never held across an `await`, and then awaits the storage
itself, so calls on different storage types or scopes never wait for each other.

- **Why:** the storages are thread-safe themselves (D6). An actor would serialize only the lookup, yet make every call
  hop onto it and then onto the storage: two hops and one choke point, as in 3.x.

#### D20. `move`, `update` and `close` hold their scopes against calls through the same instance

While one of them runs, calls through the same `UnifiedStorage` on its scopes wait, and it waits for the calls already
running. Other instances, app extensions and other processes aren't held; the docs say so, and say to use one instance
per app.

- **Why:** a read-modify-write is atomic only against writers that take the same lock, and only the instance's own calls
  can take it; a lock in every storage still wouldn't cover other instances or processes. `update`'s closure can't
  `await` or throw, so it never waits on the storage it holds.
- **Instead of:** `IsolatedDataStorage.withStorage`, atomic only against calls through its own instance, never against
  `UnifiedStorage`'s storage of the scope.
- **Semantics:** `move` saves at the destination unless a value is there already, then removes the source, and moving an
  entry onto itself does nothing. `close` lets go of a scope's storage, such as a SQLite database per account;
  recovering a damaged database is documented, not automated.

#### D21. One storage type per scope: documented, not enforced

`FileStorage` and `IsolatedDataStorage<FileStorage>` are two storages over the same files: a `move` or an `update`
through one doesn't hold the other's calls, a `close` closes only its own, and observers see only the changes made
through their own.

- **Why not enforced:** Swift can't reject the pair at compile time, and the library can't tell which of an app's own
  types share data. The README and `UnifiedStorage`'s docs state the rule.

#### D22. The factory is a value of modifiers, and the last one decides

`UnifiedStorage.Factory` is a `Sendable` struct holding modifiers in order. Each changes a step of making a scope's
storages (create the storage, pick its coder, wrap it for coding, observe it), for every storage type or for one, and
gets what the modifiers before it make, `previous`. A modifier for one type matches that exact type
(`IsolatedDataStorage<FileStorage>` isn't `FileStorage`) and casts inside, so call sites have no casts.

- **Why:** one mechanism and one precedence rule for the built-in modifiers and an app's own. Each call returns a new
  factory, as SwiftUI's modifiers do. A closure can't be generic, so logic for every type, such as logging, is a
  `Modifier` with generic methods.
- **Named Factory, not Builder:** a builder assembles one product and hands it over with `build()`; this makes a family
  of storages per storage type and scope, on demand, many times. The chain is a fluent interface.
- **Instead of:** a factory protocol, where changing one storage type took `Storage.self ==` checks and force casts in
  the app; a class to subclass, which either shares mutable state between chains or loses a subclass's stored state when
  copied; or closures beside protocol methods, two mechanisms with unclear precedence.

#### D23. `Modifier`'s steps have public defaults, despite near misses

Each of `Modifier`'s four steps returns `previous()` by default, so a modifier implements only what it changes. Swift
6.3 doesn't warn about a method that nearly matches a defaulted generic requirement, such as one with a concrete storage
type, another argument label, or `throws` without its error type: it compiles and is never called. The docs say to let
Xcode complete each method.

- **Why:** apps write modifiers with autocompletion, and required steps would make every modifier spell out the ones it
  doesn't change.
- **Instead of:** defaults visible only inside the module, which turn every near miss into a compile error but make
  every app's modifier implement all four steps.

#### D24. Closures spell out their typed throws

`dataStorage(for:_:)`'s closure is written `{ scope throws(FileStorage.Error) in … }`, and the docs say so.

- **Why:** Swift never infers a closure's typed `throws` from its context: a closure with `try` infers `any Error`, and
  even one that doesn't throw fails to convert to `throws(Storage.Error)` when the type is a generic's member.
- **Instead of:** a second, non-throwing overload, which is ambiguous for storages whose `Error` is `Never`.

#### D25. `set` is a requirement of every storage

`AsyncDataStorage` and `DataStorage` require `set(_:forKey:)`, which saves a value or deletes for `nil`, and every layer
passes it down. `DataStorage` defaults it to `save` or `delete`; `AsyncDataStorage` has no default.

- **Why:** as an extension method, generic code never reached a storage's own `set`, so a storage that writes or removes
  in one operation of its own, such as one request, couldn't use it. An async default would win over a synchronous
  storage's own `set` in async code (D3). `set` writes; `update` is the read-modify-write (D20).

### Platforms and compatibility

#### D26. 4.0 isn't backward compatible with 3.x

Paths, suite names, keychain services, APIs and defaults all changed, and 4.x neither reads nor migrates what 3.x saved.
The README lists where 3.x kept its values, for apps that move them themselves.

- **Why:** 4.0 is a rewrite whose places come from sealed scopes (D9), and the package had no users to migrate.

#### D27. The deployment targets stay

iOS 13, macOS 10.15, tvOS 13, watchOS 6 and visionOS 1, with Swift 6.0 (Xcode 16) and later; CI builds with every Swift
from 6.0 to 6.3.

- **Weighed:** macOS 11 would remove one fallback no CI host can run, `FileStorage`'s `.atomic`-only writing options,
  and watchOS 9 the `@available(watchOS 9.0, *)` annotations on `UbiquitousStorage`.
- **Cost:** `Lock` falls back to `NSLock` before macOS 13 and iOS 16. Generic code avoids constrained existentials
  (`any P<T>`), whose runtime support needs macOS 13 and iOS 16. Newer Swift features, such as `nonisolated` types
  (6.1) and `SendableMetatype` (6.2), wait.
