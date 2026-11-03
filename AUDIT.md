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
priority, with the details of each item; what only a device can settle is in §2; §3 assesses what's done. The finished
design, its decisions (D1–D28) and their rationale are in git: the full plan as of commit `0d557e4`. Check `git log`
first, as this file can lag it. Work on branch `4.0.0-experiments`.

Findings marked **confirmed** were reproduced with a probe built against the package (macOS); **verify** needs a real
device or Apple's confirmation. Severity: **high** (data loss or release blocker), **medium** (wrong behavior users or
maintainers will hit), **low** (rare, cosmetic or design).

---

## 0. How to work on this file

**Working rules** (the maintainer's):
- **Commits** only when the maintainer asks, one per step.
- **Simple, bulletproof, sound:** the simplest rule that holds for every input. No logic in default backing stores (one system call per member); all naming lives in the locators, with the byte-level encodings they share in `Helpers/String+UTF8.swift`; no parameters or properties for demonstration only; never swallow a "can't tell": throw instead.
- **Consistency:** a rule decided for one storage applies to all six.
- **Names** are exact bytes everywhere (`ExactString`). Encode, don't reject: any string is a valid key or namespace, and only system limits throw.
- **Errors** are typed end to end, carry the failing input as the caller passed it, are documented per case, and every throw site is tested.
- **System and SDK gotchas** get a doc comment on the case they affect, not a workaround, unless they'd let two scopes reach each other's values.
- **Comments** hold only essentials, gotchas and warnings, one line where possible, describing the current behavior, never its history. API docs use `///`, `- Note:` and `- Warning:`.
- **Tests** use XCTest, with `// Given`, `// When`, `// Then` and mocks that record their calls. Storages, layers and the facade keep 100% region and line coverage; default adapters get integration tests against the real system. Every behavior the docs state is either measured by a test or listed in §2 as to verify.
- **Members for tests only** are internal and read-only, and only where a test can't observe a state otherwise, such as `UnifiedStorage.Scopes.state(of:in:)`. Tests wait for a state with `waitUntil`, never for a fixed time.
- **Condition coverage, not just lines:** Swift's coverage counts a whole condition as one region, so every compound condition (`&&`, `||`, `if`/`guard` clause lists, `where`, `??`, ternaries, patterns) needs a test for each path that short-circuiting can tell apart: `a && b && c` needs `a` false, `b` false, `c` false and all true. Limits get a test on each side of the boundary.
- **When asked whether anything is left open,** do one complete pass, and say "none" when nothing is.

**Commands:**
- macOS: `swift build --build-tests`, with no warnings, and `swift test`.
- iOS Simulator: `xcodebuild test -scheme KeyValueStorage -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- KeychainHost, for the real keychain on the Simulator: `xcodebuild test -project Tests/KeychainHost/KeychainHost.xcodeproj -scheme KeychainHost -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- Coverage: `swift test --enable-code-coverage`, then read `.build/arm64-apple-macosx/debug/codecov/KeyValueStorage.json`; delete the `default.profraw` a run can leave in the repository's root.
- Test runs take minutes, so run them in the background rather than with a short timeout.

**Deployment targets stay** (2026-11-01): iOS 13, macOS 10.15, watchOS 6. So `FileStorage`'s `#available(macOS 11)` fallback stays uncovered, and `UbiquitousStorage` keeps its `@available(watchOS 9.0, *)` annotations.

---

## 1. Open work, by priority

Addressed from the top: the public API first, which can change freely (rule 1); then internals; then what needs a real
device; the release comes last, once everything else is gone.

| # | Severity | Item |
| --- | --- | --- |
| 1 | Low | Custom locators in `UnifiedStorage` take cast-heavy factory code |
| 2 | Low, design | No retention that persists but stays out of backups |
| 3 | Low | Code that must stay in sync across storages |
| 4 | Low, design | Observation sees only changes made through observable storages in this process |
| 5 | Low | `admitHolds()` depends on `removeAll(where:)`'s evaluation order |
| 6 | Low | The rest of the facade's cost, and one lock per instance |
| 7 | Medium, verify | Error cases the device checks may add |
| 8 | Medium, verify | tvOS on a device |
| 9 | Low, verify | Ubiquitous key limit on the oldest supported systems |
| 10 | Last | The release: README, DocC, the CHANGELOG's date, the coverage badge, the tag |

### Low

#### 1. Custom locators in `UnifiedStorage` take cast-heavy factory code (low)

Giving one storage type a custom locator or backing store takes a generic `dataStorage(for:)` that compares
`Storage.self` with the type, casts the scope and the storage, and bridges the typed error with `error as! Storage.Error`
(README "Custom Locators"; `TestStorageFactory` in `UnifiedIntegrationTests` is 40 lines for three storages). Checking the
scope's type alone isn't enough: `IsolatedDataStorage<FileStorage>` has `FileStorage`'s scopes, and a force cast of the
storage would crash.

To do: a helper on `UnifiedStorageFactory` that takes a builder per storage type and keeps the defaults for the rest, with
no casts at the call site.

#### 2. No retention that persists but stays out of backups (low, design)

`.persistent` is in Application Support, which iCloud and computer backups include; `.cache` and `.temporary` aren't backed
up, but the system can delete them. Apple's data storage guidelines ask apps to keep what they can download again out of
backups; data that must stay available offline, such as downloaded media or maps, has no scope that is both persistent
and excluded from backups (`URLResourceValues.isExcludedFromBackup`, which on a folder covers what's inside). The README
and `Retention.persistent` point data that can be downloaded again to `.cache`.

To do: decide: leave it out, as documented now, or add a retention, such as `.persistentExcludedFromBackup`, that sets the
flag on the scope's folder when the storage creates it.

#### 3. Code that must stay in sync (low)

- `DefaultFileLocator` and `DefaultSQLiteLocator` each implement the folder rules (base folders, app folder, namespace and
  protection folder names, group checks). SQLite relies on landing in File's folder; one test guards it, but the rule is
  written twice.
- `FileStorage` and `SQLiteStorage` have separate but identical `Retention`, `Protection` (cases) and `Scope` types.
- `DefaultUserDefaultsLocator` and `DefaultUbiquitousLocator` repeat the `<namespace>!/<key>` scheme.
- `CodingStorage` and `AsyncCodingStorage` are copies.

To do: one shared folder rule and one shared stored-key codec, so that "a rule decided for one storage applies to all six"
holds in code rather than by review. Since the public API can change (rule 1), File and SQLite could also share one
public `Retention`, `Protection` and `Scope`.

#### 4. Observation is narrow (low, design)

Only changes made in this process, through an `ObservableStorage` of the same storage type and scope, with the same value
type, are seen; delivery runs on the saving thread, inside the save. All of it is documented, including that a `sink` in
`@MainActor` code crashes in the Swift 6 language mode without `receive(on:)`.

To do, if it's wanted: feed observers Ubiquitous's `didChangeExternallyNotification` and UserDefaults'
`didChangeNotification`, for changes from other devices and other code.

#### 5. `admitHolds()` depends on `removeAll(where:)`'s evaluation order (low)

`admitHolds()` admits waiting moves and updates inside the predicate of `waitingHolds.removeAll { … }`: the predicate marks
each admitted hold's slots held and decrements their waiting counts, and later holds in the list see those marks. That's
correct only because `Array.removeAll(where:)` calls the predicate once per element, front to back. Today's standard
library does (`_halfStablePartition`), but it isn't part of the method's documented contract, and a change there would
break the core of `move` and `update` silently.

To do: an explicit loop that keeps the holds it doesn't admit, in order; the lock's mutation tests guard the change.

#### 6. The rest of the facade's cost, and one lock per instance (low)

- Over a storage that does nothing, a call costs ~0.9 µs through `UnifiedStorage` and 86 ns through the coding storage.
  The lock, the lookup and awaiting the created storage explain ~0.15 µs; the rest is probably generic code that isn't
  specialized across the module boundary, and the async calls between the layers.
- Every call takes the instance's lock twice, whatever its scope, so 8 tasks through one `UnifiedStorage` finish no faster
  than one task (0.93 µs vs 0.90 µs per call over a storage that does nothing).

### On a real device

#### 7. Error cases the device checks may add (medium, verify)

Two device checks in §2 end in a new error case: mapping SQLite's locked-database result to a `.protectedDataUnavailable`
case, as File and Keychain have, and a `valueTooLarge` check for User Defaults if `set` drops values once a suite reaches
4 MB on iOS (500 KB on tvOS, item 8). Until then, a SQLite database protected while the device is locked fails with
`.sqlite(code:message:)`, and User Defaults stays silent over its limit; both are documented.

Measured so far (a Mac with its screen locked, 2026-11-01): opening a `.complete` database fails with `SQLITE_CANTOPEN`,
which other open failures share, so a mapping may not be possible from the result code alone.

To do: run §2's lock test and User Defaults size test, and add `SQLiteStorage.Error.protectedDataUnavailable` and
`UserDefaultsStorage.Error.valueTooLarge` if they show the need.

#### 8. tvOS on a device (medium, verify)

Apple's App Programming Guide for tvOS: "your app can only access 500 KB of persistent storage that is local to the device
(using the NSUserDefaults class). Outside of this limited local storage, all other data must be purgeable by the operating
system when space is low." Cache data "is not deleted while the app is running."

The default File and SQLite scopes are `.own(.persistent)`, in Application Support. Unknown on a device:
- whether writes there fail, succeed and get purged, or work; an `EPERM` would surface as `.protectedDataUnavailable`,
  which an Apple TV never resolves, since it doesn't lock;
- what User Defaults does past 500 KB: drop the value, log, or terminate the app.

The README's Supported Platforms, `Retention.persistent` and the User Defaults notes say to use `.cache` for files and
SQLite on tvOS. CI builds for tvOS but runs no tvOS tests, and the Simulator doesn't enforce the device sandbox.

To do: §2's tvOS checks. If `.persistent` throws, decide whether it deserves an error of its own (with item 7), a
different default scope on tvOS, or a doc line.

#### 9. Ubiquitous key limit on older systems (low, verify)

`DefaultUbiquitousLocator` allows stored keys of up to 128 UTF-16 code units. Apple's current `NSUbiquitousKeyValueStore`
reference (checked 2026-11-02): "The maximum length for each key string is 128 characters using the UTF-16 encoding …
If a key string exceeds the maximum length, the system raises an exception." Older third-party write-ups give 64 bytes of
UTF-8, likely from Apple's earlier iCloud design guide. Nothing shows a supported system enforcing it, but if the oldest
ones (iOS 13, macOS 10.15, watchOS 9) did, keys between the two limits would crash there.

To do: §2's Ubiquitous check on the oldest supported systems; only if one crashes, check both limits.

### Last

#### 10. The release

Once every other item is addressed (rule 1):
- README: "Migrating from 2.x" points to the 3.0.0 CHANGELOG's migration code, which is written for the 3.x API.
- DocC rewrite: the scopes table, the isolation guide, observation limits.
- Date the CHANGELOG's 4.0.0 section, re-measure the coverage badge (96% of lines on 2026-11-02), and tag 4.0.0.

---

## 2. Real-device tests (deferred: need a real iPhone or Apple TV)

The lock test and the User Defaults size test below decide item 7; the tvOS checks decide item 8.

Keychain's `errSecInteractionNotAllowed` is mapped to `.protectedDataUnavailable` from Apple's docs; SQLite's code still needs the run. `ProtectedDataTests` in KeychainHost records what SQLite (each protection class, on an open and on a new connection) and a `.complete` file do while the device is locked, and that both recover after unlocking. It skips on the Simulator and unless `KVS_LOCK_TEST=1`.
- From its report: map SQLite's locked-database result code to a `.protectedDataUnavailable` case, like `FileStorage`'s, and confirm File's `EPERM` mapping on a device.
- Measured on a Mac with its screen locked (2026-11-01): a `.complete` file write fails with Cocoa 513 wrapping `EPERM`, which maps to `.protectedDataUnavailable`; opening a `.complete` SQLite database fails with `SQLITE_CANTOPEN`, which can't be told apart from other open failures. The other classes work. Confirm both on an iPhone.
- Confirm that the keychain deletes a `.whenUnlocked` item while locked, and that saves at `.complete` and `.whenUnlocked` fail while locked.
- What each protection level does while locked; whether the system deletes a database's files one at a time in `.cache` and `.temporary`; which file protection classes macOS enforces.
- **App Groups the app isn't entitled to:** `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` on a device (`FileIntegrationTests.testWhichGroupIdsTheSystemGivesAContainer` asserts it; the Simulator and macOS give any id a container), and a UserDefaults suite named after one stays in the app's own preferences.
- **Keychain `.iCloud(.appGroup(id:))` with an App Group id**, not a Keychain Sharing group: whether synced items in an App Group access group sync to the user's other devices.
- **The same key written on two devices before they sync**, for Keychain's and Ubiquitous's `.iCloud` scopes: which value wins. Last writer is likely but not measured; the result becomes a doc line on each `.iCloud` case.
- **Ubiquitous:** a signed host with the iCloud key-value store entitlement and an Apple Account, ideally with a second device to see values sync. Check the key-length limit on the oldest supported systems too (item 9), the default adapter's integration tests, the quota, signed-out behavior, what an unentitled build does (keeps nothing, `synchronize()` returns `false`), and that the store, like UserDefaults, drops keys with NUL (assumed; the locator escapes it).
- **UserDefaults before the first unlock after a restart:** fetches return `nil` (documented); whether saves made then last, or are replaced by the file's values once it's readable.
- **UserDefaults size:** whether `set` drops a value once its suite reaches 4 MB on iOS, or 500 KB on tvOS (with the tvOS checks below); if it does, a `valueTooLarge` check like Ubiquitous's.
- **App Group SQLite and suspension:** whether an idle connection, whose WAL index keeps a shared lock on its `-shm` file, gets a suspended app terminated (`0xdead10cc`); the scope warns about locks held while reading and writing. If it does, apps close those scopes with `close(storage:forScope:)` before they're suspended.
- **tvOS, on an Apple TV:** what `.persistent` File and SQLite scopes do (fail, and with which error, or work and get purged), whether `.cache` values survive while the app runs and relaunches, and what User Defaults does past 500 KB (drops the value, logs, or terminates the app).
- Blocker: KeychainHost is ad-hoc signed, and its entitlements hardcode a placeholder team (`ABCDE12345`). Running it on a device needs a signing setup that leaves the committed project alone, such as a local, git-ignored xcconfig with the team and bundle ID, and entitlements built from `$(AppIdentifierPrefix)`.

---

## 3. Assessment

The core is solid: scope isolation holds for all six storages, no data race was found, errors are typed end to end, and
the suite (428 tests, no warnings) covers every compound condition.

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
- **Factory with defaulted requirements:** a factory implements only what it changes.
- **Encodings:** `portableName` is lossless, ASCII-only and capital-free; `percentEscaping` is exactly invertible;
  every `clear()` re-encodes each name before removing it, so a locator's lenient decoder never claims foreign items.

Weak spots: items 1, 3 and 4.

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
floor: File makes one `lstat` per item and checks the folder once in `clear`, Keychain updates first and adds only when
missing, SQLite uses prepared statements, WAL and `synchronous = NORMAL`. The facade's cache is typed per storage type,
so its lookup doesn't box scopes, stays flat however many scopes are cached, and adds no allocations.

**Extreme cases:**
- **Large values** are saved and fetched whole, in memory (File reads the whole file; JSON adds copies for non-`Data`
  types), and an observed key keeps its latest change in memory, plus the value each publisher read. Documented.
- **Many scopes:** each SQLite scope keeps its database open until `close(storage:forScope:)`.
- **Contention:** one lock per `UnifiedStorage` instance (item 6), and one per SQLite connection, whose calls block their
  threads; blocking I/O runs on the cooperative pool, a trade-off taken on purpose.
- **Checked and fine:** a large SQLite value doesn't leave a large WAL behind. Apple's SQLite is built with
  `DEFAULT_JOURNAL_SIZE_LIMIT=32768`, so after a 50 MB save the `-wal` was 50 MB and dropped to 62 KB on the next write
  (measured).

Calling the async API from the main actor in a tight loop costs ~9 µs per call in executor hops; that's Swift's
`nonisolated async` semantics, not the library.

### 3.3 Scope isolation — verified

With the public API and the default locators, no two scopes reach each other's values:

- **File and SQLite:** `portableName` is injective, capital-free (safe on case-insensitive volumes), ASCII
  (normalization-insensitive volumes can't merge names), and never starts with `.` (never SQLite's or the system's
  files). Namespace folders end with `!`, which no portable name does; each protection is its own folder; `.own` lives
  under the app's identifier, `.appGroup` in the group container.
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

- **Crashes:** none in the library; the Ubiquitous key limit still needs a check on the oldest systems (item 9). A `sink`
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

Docs and comments: none open besides the release (item 10). Tests: none open. Every compound condition's paths are
covered, limits are tested on both sides, edge-case keys (`""`, NUL, `é`/`e\u{301}`, `..`, `/`) run against the real
systems, and the tests of `move`, `update` and `close` wait for the scope state they need through `UnifiedStorage.Scopes.state(of:in:)`,
so they neither depend on timing nor pass without checking. Every tried mutation of the lock's admission logic
and of `close` fails a test within seconds, none by hanging.

---

## 4. Uncovered by design

No test can reach these: `Lock`'s `NSLock` fallback (before macOS 13 / iOS 16), `FileStorage`'s `.atomic`-only writing options (before macOS 11), `OwnIdentity.identifier` without a bundle ID, `assert` failure arms, a call that has left a scope still holding its storage when a `close` releases it (the call consumes its reference before it leaves, but the window without that is a few instructions, which no test can time), SQLite's out-of-memory and empty-blob-pointer paths, and `SQLiteStorage.init()`, which would open a database in the real Application Support. The Keychain and Ubiquitous default adapters run in KeychainHost and on a device.

## 5. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `move` and `update` hold their scopes only against calls through the same `UnifiedStorage`, so neither is atomic across instances or processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension; the scope docs say so.
- **Observation** sees only changes made through an `ObservableStorage` of the same storage type and scope, and only of the observer's value type. Concurrent writers of one key may deliver out of order.
- **Blocking SQLite calls:** `DefaultSQLiteDatabase` locks each operation, so calls on one instance block while they wait. `IsolatedDataStorage` turns that into suspension when many tasks share one SQLite scope.
