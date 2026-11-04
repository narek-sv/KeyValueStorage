# KeyValueStorage 4.0 — Audit and Plan

## Rules that apply everywhere

1. **4.0.0 breaks compatibility, on purpose.** It's not backward compatible with 3.x, neither in its API nor in where
   values live, and the package has no real users yet: any public API can change, and nothing needs a migration path or
   has to wait for a later major version. 4.0.0 isn't released until every item in §1 is addressed, and the public API
   is refactored and polished until the maintainer is satisfied with it.
2. **An addressed item is removed from this file, not marked as done,** together with every reference to it; the items
   after it are renumbered.

---

What's left of the 4.0 refactor, and the audits it comes from: branch `4.0.0-experiments` at `4c12469` (2026-11-01) and
`145f535` (2026-11-02), every source file, the README, the CHANGELOG and the test suite. The open work is in §1, by
priority, with the details of each item; what only a device can settle is in §2; §3 assesses what's done. The
principles every change follows, and the decisions behind the design, are in [DESIGN.md](DESIGN.md). Check `git log`
first, as this file can lag it. Work on branch `4.0.0-experiments`.

Findings marked **confirmed** were reproduced with a probe built against the package (macOS); **verify** needs a real
device or Apple's confirmation. Severity: **high** (data loss or release blocker), **medium** (wrong behavior users or
maintainers will hit), **low** (rare, cosmetic or design).

---

## 0. How to work on this file

Every change follows the principles in [DESIGN.md](DESIGN.md), which also holds the decisions behind the design, such as
the deployment targets that stay (D27). The working rules and the commands are in [AGENTS.md](AGENTS.md).

---

## 1. Open work, by priority

Addressed from the top: the public API first, which can change freely (rule 1); then internals; then what needs a real
device; then what's optional, done or declined; the release comes last, once everything else is gone.

| # | Severity | Item |
| --- | --- | --- |
| 1 | Low, design | Observation sees only changes made through observable storages in this process |
| 2 | Low | `admitHolds()` depends on `removeAll(where:)`'s evaluation order |
| 3 | Low | The rest of the facade's cost, and one lock per instance |
| 4 | Medium, verify | Error cases the device checks may add |
| 5 | Medium, verify | tvOS on a device |
| 6 | Low, verify | Ubiquitous key limit on the oldest supported systems |
| 7 | Optional, design | Coding and observation layers as protocols with `open class Default…` implementations |
| 8 | Last | The release: every doc refined, the CHANGELOG's date, the coverage badge, the tag |

### Low

#### 1. Observation is narrow (low, design)

Only changes made in this process, through an `ObservableStorage` of the same storage type and scope, with the same value
type, are seen; delivery runs on the saving thread, inside the save. All of it is documented, including that a `sink` in
`@MainActor` code crashes in the Swift 6 language mode without `receive(on:)`.

To do, if it's wanted: feed observers Ubiquitous's `didChangeExternallyNotification` and UserDefaults'
`didChangeNotification`, for changes from other devices and other code.

#### 2. `admitHolds()` depends on `removeAll(where:)`'s evaluation order (low)

`admitHolds()` admits waiting moves and updates inside the predicate of `waitingHolds.removeAll { … }`: the predicate marks
each admitted hold's slots held and decrements their waiting counts, and later holds in the list see those marks. That's
correct only because `Array.removeAll(where:)` calls the predicate once per element, front to back. Today's standard
library does (`_halfStablePartition`), but it isn't part of the method's documented contract, and a change there would
break the core of `move` and `update` silently.

To do: an explicit loop that keeps the holds it doesn't admit, in order; the lock's mutation tests guard the change.

#### 3. The rest of the facade's cost, and one lock per instance (low)

- Over a storage that does nothing, a call costs ~0.9 µs through `UnifiedStorage` and 86 ns through the coding storage.
  The lock, the lookup and awaiting the created storage explain ~0.15 µs; the rest is probably generic code that isn't
  specialized across the module boundary, and the async calls between the layers.
- Every call takes the instance's lock twice, whatever its scope, so 8 tasks through one `UnifiedStorage` finish no faster
  than one task (0.93 µs vs 0.90 µs per call over a storage that does nothing).

### On a real device

#### 4. Error cases the device checks may add (medium, verify)

Two device checks in §2 end in a new error case: mapping SQLite's locked-database result to a `.protectedDataUnavailable`
case, as File and Keychain have, and a `valueTooLarge` check for User Defaults if `set` drops values once a suite reaches
4 MB on iOS (500 KB on tvOS, item 5). Until then, a SQLite database protected while the device is locked fails with
`.sqlite(code:message:)`, and User Defaults stays silent over its limit; both are documented.

Measured so far (a Mac with its screen locked, 2026-11-01): opening a `.complete` database fails with `SQLITE_CANTOPEN`,
which other open failures share, so a mapping may not be possible from the result code alone.

To do: run §2's lock test and User Defaults size test, and add `SQLiteStorage.Error.protectedDataUnavailable` and
`UserDefaultsStorage.Error.valueTooLarge` if they show the need.

#### 5. tvOS on a device (medium, verify)

Apple's App Programming Guide for tvOS: "your app can only access 500 KB of persistent storage that is local to the device
(using the NSUserDefaults class). Outside of this limited local storage, all other data must be purgeable by the operating
system when space is low." Cache data "is not deleted while the app is running."

The default File and SQLite scopes are `.own(.persistent)`, in Application Support, as `.persistentExcludedFromBackup`
scopes are. Unknown on a device:
- whether writes there fail, succeed and get purged, or work; an `EPERM` would surface as `.protectedDataUnavailable`,
  which an Apple TV never resolves, since it doesn't lock;
- what User Defaults does past 500 KB: drop the value, log, or terminate the app.

The README's Supported Platforms, both persistent retentions and the User Defaults notes say to use `.cache` for files
and SQLite on tvOS. CI builds for tvOS but runs no tvOS tests, and the Simulator doesn't enforce the device sandbox.

To do: §2's tvOS checks. If `.persistent` throws, decide whether it deserves an error of its own (with item 4), a
different default scope on tvOS, or a doc line.

#### 6. Ubiquitous key limit on older systems (low, verify)

`DefaultUbiquitousLocator` allows stored keys of up to 128 UTF-16 code units. Apple's current `NSUbiquitousKeyValueStore`
reference (checked 2026-11-02): "The maximum length for each key string is 128 characters using the UTF-16 encoding …
If a key string exceeds the maximum length, the system raises an exception." Older third-party write-ups give 64 bytes of
UTF-8, likely from Apple's earlier iCloud design guide. Nothing shows a supported system enforcing it, but if the oldest
ones (iOS 13, macOS 10.15, watchOS 9) did, keys between the two limits would crash there.

To do: §2's Ubiquitous check on the oldest supported systems; only if one crashes, check both limits.

### Optional

#### 7. Coding and observation layers as protocols with `open class Default…` implementations (optional, design)

Every other extension point is a protocol, with the library's own implementation as a concrete type: storages
(`DataStorage`, `AsyncDataStorage`), scopes (`DataStorageScope`), coders (`DataCoder`), factory modifiers
(`UnifiedStorage.Factory.Modifier`), and all twelve locators and backing stores, each a protocol and an
`open class Default…` (`FileLocator` and `DefaultFileLocator`, `FileBackingStore` and `DefaultFileBackingStoreWrapper`,
and so on for the other five storages). `CodingStorage`, `AsyncCodingStorage` and `ObservableStorage` are the only
exceptions: open classes, with open operations since `3331462`, and no protocol.

Compared on 2026-11-04: the better architecture and the more consistent one, at the costs below. The proposed shape:
- `public protocol CodingStorage<Storage>`, with `associatedtype Storage: DataStorage`: `scope`, and synchronous
  `fetch`, `save`, `set`, `delete` and `clear`, throwing `CodingStorageError<Storage>`. Its implementation is
  `open class DefaultCodingStorage<Storage: DataStorage>: CodingStorage`, today's class, `Sendable` when its storage is.
- `public protocol AsyncCodingStorage<Storage>: Sendable`, with `associatedtype Storage: AsyncDataStorage & Sendable`:
  the same operations, `async`. Its implementation is `open class DefaultAsyncCodingStorage<Storage>`. The protocol
  requires `Sendable` because a protocol can't conform conditionally, as today's class does: a non-`Sendable`
  asynchronous storage loses the default coding storage, but it isn't safe to share anyway, and `UnifiedStorage` takes
  only `Sendable` storages.
- `public protocol ObservableStorage<Storage>: AsyncCodingStorage`, which adds
  `publisher(forKey:includingCurrentValue:)` and `stream(forKey:includingCurrentValue:bufferingPolicy:)`: an observable
  storage is a coding storage that also publishes. Its implementation is `open class DefaultObservableStorage<Storage>`,
  which wraps `any AsyncCodingStorage<Storage>` instead of the class, so it observes any coding storage.
- No defaults in protocol extensions: a conformance from scratch implements every requirement, which the compiler
  checks, and a refinement subclasses a `Default…` class, where `override` is checked and `super` reaches the library's
  behavior. A conformance whose method nearly matches a defaulted requirement compiles and is never called (measured
  2026-11-03 on `Modifier`: a concrete storage type, a one-letter label typo, `_` or another label, and `throws` without
  its error type, none with a warning).
- `CodingStorageKey` and `CodingStorageError` stay as they are.
- The value stays generic per call, as today: each operation is a generic method, such as
  `fetch<Value: CodingValue>(forKey:)`, as `DataCoder`'s `encode` and `Modifier`'s steps already are; only the storage,
  fixed per instance, is an associated type.
- Requirements can't declare default arguments, so `publisher`'s `includingCurrentValue: true`, and `stream`'s
  `includingCurrentValue: true` and `bufferingPolicy: .unbounded`, move to overloads in a protocol extension that
  forward to the requirement: `publisher(forKey:)`, `stream(forKey:)`, `stream(forKey:includingCurrentValue:)` and
  `stream(forKey:bufferingPolicy:)`. They add ways to call, not defaults of requirements, so they have no near-miss
  trap. The `Default…` classes keep their initializer's `coder: RawDataCoder()`.

Pros:
- One shape for every extension point: a protocol, and the library's `open class Default…`.
- Every way to customize: subclass a default to refine it; conform from scratch for a different implementation that
  doesn't inherit the default's storage and coder; or wrap any implementation, such as what the modifiers before make,
  with `Logging(base: await previous())` in a modifier's coding step, stacking any number deep. Today wrapping takes a
  subclass that forwards every call, and still initializes its superclass with a storage and coder it never uses.
- The layers depend on abstractions: `UnifiedStorage`, `ScopeStorage`, the factory and `DefaultObservableStorage` see
  protocols, not classes.
- Test doubles are small fakes instead of subclasses of the real classes, in the library's tests and in apps'.

Cons:
- Six types instead of three, and longer everyday names: `DefaultCodingStorage(storage:)` instead of
  `CodingStorage(storage:)`, and `DefaultObservableStorage(_:)` instead of `ObservableStorage(_:)`.
- Existential signatures: the factory's coding and observation steps and their closures, `Modifier`'s requirements and
  `ScopeStorage` take and return `any AsyncCodingStorage<Storage>` and `(any ObservableStorage<Storage>)?`. Calls
  through them dispatch through the witness table, negligible next to storage I/O; measure the facade's per-call cost
  (item 3) before and after.
- Breaking: renamed types and new protocols, so it's done or declined before 4.0.0 is tagged, or it waits for 5.0.
- **Deployment targets:** constrained existentials (`any P<T>`) need the Swift 5.7 runtime in generic code: macOS 13,
  iOS 16, tvOS 16 and watchOS 9. A probe at the package's targets (2026-11-03): `observable ?? coding`, on
  `(any AsyncCoding<Storage>)?`, fails with "runtime support for parameterized protocol types is only available in
  macOS 13.0.0 or newer". Stored properties of those types, the factory's chain, `Modifier`'s defaults, a stored
  per-type closure and the creation task compiled when written without `??`, so the library can avoid the problem;
  apps targeting older systems can't, once they write `await previous() ?? fallback` in a modifier, map such a value,
  keep them in an array or cast them. So either the deployment targets rise (they stay, decided 2026-11-01), or apps on
  older systems live with that restriction.

To do, if it's wanted:
1. Turn `CodingStorage`, `AsyncCodingStorage` and `ObservableStorage` into the protocols above, and their classes into
   `DefaultCodingStorage`, `DefaultAsyncCodingStorage` and `DefaultObservableStorage`, each in a file of its own.
2. `DefaultObservableStorage` wraps `any AsyncCodingStorage<Storage>`; `ScopeStorage` holds
   `any AsyncCodingStorage<Storage>` and `(any ObservableStorage<Storage>)?`.
3. `UnifiedStorage.Factory`: the coding and observation steps, `Modifier`'s requirements, `codingStorage(for:_:)`,
   `observableStorage(for:_:)`, and the per-type modifiers' casts, now between existentials.
4. Tests: fakes for the protocols; the subclass tests in `PublicAPITests` subclass the `Default…` classes; a public test
   for a modifier that wraps what `previous()` made.
5. README: the Factory table, Coding, Observation, and every `CodingStorage(storage:)` and `ObservableStorage(_:)`
   example. CHANGELOG: Breaking changes and Added.
6. Verify: `swift build --build-tests` with no warnings, the full suite, 100% coverage of the layers, the factory's
   mutation run, and the iOS build; the lock's mutation run (about 25 minutes) only if `UnifiedStorage+Scopes.swift`
   changes beyond `ScopeStorage`'s types.

If it's declined, remove this item (rule 2).

### Last

#### 8. The release

Once every other item is addressed (rule 1):
- **Every doc refined as a set,** from the README to DESIGN.md and the CHANGELOG: each as compact as it can be without
  losing context, and as clear to agents as to people.
  - **README:** shorter, leading with the library's benefits, then short examples of the everyday tasks; the rest moves
    to the docs below, linked. "Migrating from 2.x" points to the 3.0.0 CHANGELOG's migration code, which is written
    for the 3.x API.
  - **A doc per storage,** in detail: its scopes and where each keeps values, its key and namespace encodings and
    limits, setup, errors, locator and backing store (their rules, and how to replace or subclass them), and nuances,
    such as durability, cross-process behavior and system gotchas.
  - **SQLite for many values, not only medium ones:** the comparison, the quick guide and SQLite's doc say so, and why:
    each value is a row of one table, indexed by its key. Measured on an M3 Max on 2026-11-05, with 100,000 values of
    100 bytes, against `FileStorage`: a save takes 15.5 µs against 174 µs, a fetch 3.6 µs against 25.5 µs, `clear()`
    3.5 ms against 11 s, and the values take 13 MB on disk against 391 MB, since every file takes a 4 KB block.
  - **A doc on the layers:** the data storages, coding and its coders, observation, isolation, and `UnifiedStorage`
    with its factory: what each is for, how they compose, and how to use one on its own, replace it or subclass it.
  - **A doc on the factory and its modifiers:** what a modifier is, how to use the factory and the built-in modifiers,
    how to write your own, and what `previous` is: what the modifiers before it make, made anew on each call, so a
    modifier calls it at most once.
  - **Links and consistency:** wherever a doc mentions something that has a doc or section of its own, it links there,
    and every link and anchor resolves; the docs agree with each other and with the API's doc comments.
  - **AGENTS.md:** whatever is missing, such as the docs' layout, which docs a change updates, and any principle or
    working rule not written down yet.
  - **Where the docs live,** to decide: Markdown files, which GitHub renders and agents read as they are, or a DocC
    catalog, which Xcode and the Swift Package Index render and whose symbol links `docc` checks. The DocC rewrite
    planned here, with the scopes table, the isolation guide and the observation limits, becomes part of it.
- Date the CHANGELOG's 4.0.0 section, re-measure the coverage badge (96% of lines on 2026-11-02), and tag 4.0.0.

---

## 2. Real-device tests (deferred: need a real iPhone or Apple TV)

The lock test and the User Defaults size test below decide item 4; the tvOS checks decide item 5.

Keychain's `errSecInteractionNotAllowed` is mapped to `.protectedDataUnavailable` from Apple's docs; SQLite's code still needs the run. `ProtectedDataTests` in KeychainHost records what SQLite (each protection class, on an open and on a new connection) and a `.complete` file do while the device is locked, and that both recover after unlocking. It skips on the Simulator and unless `KVS_LOCK_TEST=1`.
- From its report: map SQLite's locked-database result code to a `.protectedDataUnavailable` case, like `FileStorage`'s, and confirm File's `EPERM` mapping on a device.
- Measured on a Mac with its screen locked (2026-11-01): a `.complete` file write fails with Cocoa 513 wrapping `EPERM`, which maps to `.protectedDataUnavailable`; opening a `.complete` SQLite database fails with `SQLITE_CANTOPEN`, which can't be told apart from other open failures. The other classes work. Confirm both on an iPhone.
- Confirm that the keychain deletes a `.whenUnlocked` item while locked, and that saves at `.complete` and `.whenUnlocked` fail while locked.
- What each protection level does while locked; whether the system deletes a database's files one at a time in `.cache` and `.temporary`; which file protection classes macOS enforces.
- **App Groups the app isn't entitled to:** `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` on a device (`FileIntegrationTests.testWhichGroupIdsTheSystemGivesAContainer` asserts it; the Simulator and macOS give any id a container), and a UserDefaults suite named after one stays in the app's own preferences.
- **Keychain `.iCloud(.appGroup(id:))` with an App Group id**, not a Keychain Sharing group: whether synced items in an App Group access group sync to the user's other devices.
- **The same key written on two devices before they sync**, for Keychain's and Ubiquitous's `.iCloud` scopes: which value wins. Last writer is likely but not measured; the result becomes a doc line on each `.iCloud` case.
- **Ubiquitous:** a signed host with the iCloud key-value store entitlement and an Apple Account, ideally with a second device to see values sync. Check the key-length limit on the oldest supported systems too (item 6), the default adapter's integration tests, the quota, signed-out behavior, what an unentitled build does (keeps nothing, `synchronize()` returns `false`), and that the store, like UserDefaults, drops keys with NUL (assumed; the locator escapes it).
- **Backups:** that iCloud and computer backups leave out `.persistentExcludedFromBackup` File and SQLite scopes, which Apple calls guidance, not a guarantee: the app's backup size in Settings, and a restore to another device, which starts without their values. Also whether a Quick Start transfer from device to device carries them.
- **Clearing files:** where `itemReplacementDirectory` puts the folder `clear()` moves out of an App Group scope, and that the system removes it when the app quits before the background deletion ends.
- **UserDefaults before the first unlock after a restart:** fetches return `nil` (documented); whether saves made then last, or are replaced by the file's values once it's readable.
- **UserDefaults size:** whether `set` drops a value once its suite reaches 4 MB on iOS, or 500 KB on tvOS (with the tvOS checks below); if it does, a `valueTooLarge` check like Ubiquitous's.
- **App Group SQLite and suspension:** whether an idle connection, whose WAL index keeps a shared lock on its `-shm` file, gets a suspended app terminated (`0xdead10cc`); the scope warns about locks held while reading and writing. If it does, apps close those scopes with `close(storage:forScope:)` before they're suspended.
- **tvOS, on an Apple TV:** what `.persistent` and `.persistentExcludedFromBackup` File and SQLite scopes do (fail, and with which error, or work and get purged), whether `.cache` values survive while the app runs and relaunches, and what User Defaults does past 500 KB (drops the value, logs, or terminates the app).
- Blocker: KeychainHost is ad-hoc signed, and its entitlements hardcode a placeholder team (`ABCDE12345`). Running it on a device needs a signing setup that leaves the committed project alone, such as a local, git-ignored xcconfig with the team and bundle ID, and entitlements built from `$(AppIdentifierPrefix)`.

---

## 3. Assessment

The core is solid: scope isolation holds for all six storages, no data race was found, errors are typed end to end, and
the suite (463 tests, no warnings) covers every compound condition.

### 3.1 Architecture — A−

- **Clean layering:** data storage → coding → observation → `UnifiedStorage` facade, assembled by a factory; every layer
  works on its own.
- **One shape for every storage:** `+Error`, `+Key`, `+Namespace`, `+Scope`, a backing store that only makes system calls,
  and a locator that owns all naming. Reading one storage teaches the other five.
- **`DataStorage` refines `AsyncDataStorage`:** synchronous storages satisfy the async API with no wrapper, and
  synchronous code never needs `await`.
- **Typed throws end to end**, with each storage's own error type and `CodingStorageError` wrapping, never translating.
- **`Sendable` discipline:** `UnifiedStorable` makes the compiler reject non-`Sendable` storages; `IsolatedDataStorage`
  makes any synchronous storage shareable.
- **A factory of modifiers:** each changes one step of making a storage, for every storage type or for one, with no
  casts at the call site, and the last one decides; a modifier of the app's own implements only the steps it changes.
- **Encodings:** `portableName` is lossless, ASCII-only and capital-free; `percentEscaping` is exactly invertible;
  a suite's or store's `clear()` re-encodes each name before removing it, so a locator's lenient decoder never claims
  foreign items, and a file scope's `clear()` moves its own folder out in one rename.

Weak spots: item 1, and the optional item 7.

### 3.2 Performance — real-life use A, extreme cases B

Measured per call on an M3 Max, release build, median of 7 runs:

| Path | Time | Allocations |
| --- | --- | --- |
| `InMemoryStorage.fetch` (sync) | 0.10 µs | 0 |
| `AsyncCodingStorage.fetch` (String) | 0.24 µs | 0 |
| `UnifiedStorage.fetch` (String) | 1.05 µs | 0 |
| `UnifiedStorage.save` (Int, JSON) | 1.44 µs | 2 |
| `UnifiedStorage(observable: true).save` (Int) | 1.72 µs | 2 |

**Real-life use:** the facade's ~1 µs disappears behind any persistent storage, and each storage is near its system's
floor: File makes one `lstat` per item, deletes with one `unlink` and clears with one `rename`, Keychain updates first
and adds only when missing, SQLite uses prepared statements, WAL and `synchronous = NORMAL`. The facade's cache is typed
per storage type, so its lookup doesn't box scopes, stays flat however many scopes are cached, and adds no allocations.

**Extreme cases:**
- **Large values** are saved and fetched whole, in memory (File reads the whole file; JSON adds copies for non-`Data`
  types), and an observed key keeps its latest change in memory, plus the value each publisher read. Documented.
- **Many scopes:** each SQLite scope keeps its database open until `close(storage:forScope:)`.
- **Contention:** one lock per `UnifiedStorage` instance (item 3), and one per SQLite connection, whose calls block their
  threads; blocking I/O runs on the cooperative pool, a trade-off taken on purpose.
- **Checked and fine:** a large SQLite value doesn't leave a large WAL behind. Apple's SQLite is built with
  `DEFAULT_JOURNAL_SIZE_LIMIT=32768`, so after a 50 MB save the `-wal` was 50 MB and dropped to 62 KB on the next write
  (measured).

Calling the async API from the main actor in a tight loop costs ~9 µs per call in executor hops; that's Swift's
`nonisolated async` semantics, not the library.

### 3.3 Scope isolation — verified

With the public API and the default locators, no two scopes reach each other's values:

- **File and SQLite:** `portableName` is injective, capital-free (safe on case-insensitive volumes), ASCII
  (normalization-insensitive volumes can't merge names), and never starts with `.` (never the system's files).
  Namespace folders end with `!` for files and `+` for databases, which no portable name does, so a database never
  shares a folder with files; each protection is its own folder or database; `.own` lives under the app's identifier,
  `.persistentExcludedFromBackup` in that folder's `x`, which no namespace folder is, and `.appGroup` in the group
  container.
- **Keychain:** `.own` services are `:`-separated and `.appGroup` services `/`-separated, with `%`, `:` and `/` escaped
  in every part, so they never match even though `.own` queries reach every access group the app has. `.iCloud` items
  are separated by `kSecAttrSynchronizable`; protection is part of the service.
- **UserDefaults and Ubiquitous:** the escaped namespace has no `/`, so `<namespace>!/` is unambiguous; `clear()`
  re-encodes each key before removing it; `.appGroup` rejects the global domain and `.own`'s suite.
- **InMemory:** one bucket per namespace, compared by exact bytes.
- **Facade and observation:** keys and caches include the storage type; scopes compare exactly.

Clashes that exist are documented: App Group ids that differ only in case on macOS, between which a `move` deletes the
value; unentitled groups getting a folder on macOS and the Simulator; unentitled UserDefaults groups staying in the app;
launch arguments and registered defaults; storages of one type and scope with different locators sharing observers.

### 3.4 Leaks, hangs and crashes

- **Crashes:** none in the library; the Ubiquitous key limit still needs a check on the oldest systems (item 6). A `sink`
  written in `@MainActor` code crashes in the Swift 6 language mode when a save off the main actor calls it (confirmed
  with a probe); that's the documented delivery thread meeting the language's isolation checks, warned about in
  `ObservableStorage`, `UnifiedStorage.publisher` and the README. Lock reentrancy (the registry is never re-entered from an
  observation's release), statement lifetimes and every error path check out.
- **Hangs:** none in the library. Calling a `UnifiedStorage` from inside its own storages, coders, factory or
  `ObservableStorage` subclasses can wait forever for a move or update that waits for the outer call, and a subscriber
  that waits for another save of its key never returns; both are documented.
- **Leaks:** none. Storages live until `close(storage:forScope:)` or until their `UnifiedStorage` is deallocated, and
  observed values stay in memory while observed (documented).

### 3.5 Thread safety

No data races found:

- All mutable state is behind a lock: the facade's cache, the observation registry and its reference counts, each SQLite
  connection, the in-memory buckets.
- No lock is held across an `await`; every continuation is resumed exactly once, outside the lock, and every waiting call
  and hold is let in once its scope frees up.
- Locks are taken in one order (observation, then registry).
- Creation is deduplicated without a race, and failures aren't cached.
- `close` releases a scope's storage outside the lock and before calls come back in, and a call lets go of its storage
  before it leaves the scope, so a scope never has two storages at once.
- The observation's version check lets a change win over a concurrent read.
- The keychain's update, add, update sequence stays correct when another call adds or removes the item in between.

The remaining races are logical: observation delivery order (documented), and other instances or processes writing
between the steps of a `move` or an `update`, which only calls through the same `UnifiedStorage` wait for (documented).

### 3.6 Docs and tests

Docs and comments: none open besides the release (item 8). Tests: none open. Every compound condition's paths are
covered, limits are tested on both sides, edge-case keys (`""`, NUL, `é`/`e\u{301}`, `..`, `/`) run against the real
systems, and the tests of `move`, `update` and `close` wait for the scope state they need through `UnifiedStorage.Scopes.state(of:in:)`,
so they neither depend on timing nor pass without checking. Every tried mutation of the lock's admission logic
and of `close` fails a test within seconds, none by hanging.

---

## 4. Uncovered by design

No test can reach these: `Lock`'s `NSLock` fallback (before macOS 13 / iOS 16), `FileStorage`'s `.atomic`-only writing options (before macOS 11), `DefaultFileBackingStoreWrapper`'s `EINVAL` for a URL without a file system path, which `withUnsafeFileSystemRepresentation` never gives (even `https://example.com` gives `""`), `OwnIdentity.identifier` without a bundle ID, `assert` failure arms, a call that has left a scope still holding its storage when a `close` releases it (the call consumes its reference before it leaves, but the window without that is a few instructions, which no test can time), SQLite's out-of-memory and empty-blob-pointer paths, and `SQLiteStorage.init()`, which would open a database in the real Application Support. The Keychain and Ubiquitous default adapters run in KeychainHost and on a device.

## 5. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `move` and `update` hold their scopes only against calls through the same `UnifiedStorage`, so neither is atomic across instances or processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension; the scope docs say so.
- **Observation** sees only changes made through an `ObservableStorage` of the same storage type and scope, and only of the observer's value type. Concurrent writers of one key may deliver out of order.
- **Blocking SQLite calls:** `DefaultSQLiteDatabase` locks each operation, so calls on one instance block while they wait. `IsolatedDataStorage` turns that into suspension when many tasks share one SQLite scope.
