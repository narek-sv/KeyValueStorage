# KeyValueStorage 4.0 — Audit

Audit of branch `4.0.0-experiments` at commit `4c12469` (2026-11-01): every source file, the README, the CHANGELOG,
`REFACTOR_PLAN.md` and the test suite. Two findings were confirmed with a probe app built against the package (release
build, macOS). Items marked **verify** need a real device or Apple's confirmation before acting.

Severity: **high** (data loss or release blocker), **medium** (wrong behavior users will hit), **low** (rare or cosmetic).

---

## Summary

The core is solid. Scope isolation holds for all six storages with the default locators, errors are typed end to end,
the naming encodings are injective and safe on case- and normalization-insensitive volumes, and the test suite is
unusually thorough. What stands between the branch and a release:

1. Changing a scope's protection in an app update hides every existing value (§4a).
2. `IsolatedDataStorage.withStorage` is atomic only within one instance, but the README calls it an atomic step (§4b).

---

## 1. Architecture — grade A−

### Strengths

- **Clean layering:** data storage → coding → observation → `UnifiedStorage` facade, assembled by a factory.
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

### Weak spots

1. **Protection names read backwards (medium, API).** `.whileLocked` means "usable only while *unlocked*";
   `.whileLockedUnlessOpen` and `.whileLockedOrWithoutPasscode` are hard to parse. The case names describe when the
   protection applies, while the doc comments describe when the value is usable. Apple's vocabulary (`whenUnlocked`,
   `afterFirstUnlock`, `completeUnlessOpen`) would be read correctly by most developers. The most visible
   intuitiveness problem in the public API.
2. **No atomic read-modify-write in the facade (medium).** `UnifiedStorage` creates its storages through the factory and
   never exposes them, so an `IsolatedDataStorage.withStorage` block can't exclude writes made through `UnifiedStorage`
   to the same scope. Counters, appends and toggles lose updates. Suggested: `UnifiedStorage.update(forKey:_:)`, or
   access to the scope's storage.
3. **Duplicated code that must stay in sync (low).**
   - `DefaultFileLocator` and `DefaultSQLiteLocator` each implement the folder rules (base folders, app folder,
     namespace and protection folder names, group checks). SQLite relies on landing in File's folder; one test guards
     it, but the rule is written twice.
   - `FileStorage` and `SQLiteStorage` have separate but identical `Retention`, `Protection` (cases) and `Scope` types.
   - `DefaultUserDefaultsLocator` and `DefaultUbiquitousLocator` repeat the `<namespace>!/<key>` scheme.
   - `CodingStorage` and `AsyncCodingStorage` are copies.
   One shared folder rule and one shared stored-key codec would enforce "a rule decided for one storage applies to all
   six" in code rather than by review.
4. **Observation is narrow (low, design).** Only changes made in this process, through the same storage type and scope,
   with the same value type, are seen. Ubiquitous's `didChangeExternallyNotification` and UserDefaults'
   `didChangeNotification` could feed it.
5. **Protection is part of a scope's identity.** Defensible, since it rules out two scopes rewriting each other's
   accessibility, but it causes §4a.

---

## 2. Performance

Measured per call, in-memory storage, release build:

| Path | Time |
| --- | --- |
| `InMemoryStorage.fetch` (sync) | 0.12 µs |
| `AsyncCodingStorage.fetch` (String) | 0.28 µs |
| `UnifiedStorage.fetch` (String) | 1.27 µs |
| `UnifiedStorage.save` (Int, JSON) | 1.66 µs |
| `UnifiedStorage(observable: true).save` (Int) | 1.96 µs |

Breakdown of the facade's lookup: boxing `UnderlyingStorageKey` into `AnyHashable` and looking it up costs ~0.38 µs;
the lock, the `as?` cast and awaiting the finished task add ~0.07 µs.

1. **Facade cache key (low–medium).** ~1 µs per call over the coding storage, ~4.5×. A typed two-level cache,
   `[ObjectIdentifier: TypedCache<Storage>]` with `[Storage.Scope: CreationTask]` inside, removes the `AnyHashable`
   boxing. Matters only for InMemory and UserDefaults; the other storages' I/O dwarfs it.
2. **SQLite copies every blob (low).** `bind` uses `SQLITE_TRANSIENT`, so SQLite copies the whole value before
   stepping. Binding with `SQLITE_STATIC` and stepping inside `value.withUnsafeBytes` avoids a copy of multi-MB values.
   Keep `utf8CString` for the key: `withUTF8` can give a nil pointer for an empty string, which binds NULL.
   `sqlite3_clear_bindings` is redundant, since every call rebinds every parameter.
3. **`ExactString.==` (low).** Compare `utf8.count` first, or `memcmp` through `withUTF8`, instead of `elementsEqual`.
4. **Already good:** File (one `lstat` per item, one folder check in `clear`), Keychain (update first, add only when
   missing), SQLite (prepared statements, WAL, `synchronous = NORMAL`).

Note: calling the async API from the main actor in a tight loop costs ~9 µs per call in executor hops; that's Swift's
`nonisolated async` semantics, not the library.

---

## 3. Bugs

### 3.1 Ubiquitous key limit on older systems (low, verify)

`DefaultUbiquitousLocator` allows stored keys of up to 128 UTF-16 code units, the limit Apple's
`NSUbiquitousKeyValueStore` reference documents, and the store raises an exception (a crash) for longer keys. Older
third-party write-ups give 64 bytes of UTF-8, likely from Apple's earlier iCloud design guide. Nothing shows a supported
system enforcing it, but if the oldest ones (iOS 13, macOS 10.15, watchOS 9) did, keys between the two limits would
crash there. Verify on the oldest supported systems (`REFACTOR_PLAN §2`); only if one crashes, check both limits.

---

## 4. Business-logic gaps and data-loss risks

### 4a. Changing a scope's protection hides its values (high, docs)

Protection is part of the place, so an update that changes `.own(protection: .whileLocked)` to `.untilFirstUnlock`
finds nothing. The README recommends exactly that change ("Use `.untilFirstUnlock` if your app needs the items while in
the background"). The rule is documented; the consequence and a migration recipe are not. Same for any namespace change.

### 4b. `withStorage` is atomic only per instance (medium, docs)

README: "Several operations as one atomic step, on any storage." It excludes only calls through the same
`IsolatedDataStorage` instance: not `UnifiedStorage`'s own storage of the scope, other instances, or other processes.
Read-modify-write written from the README example loses updates. See §1.2.

### 4c. UserDefaults before first unlock (medium, verify)

During prewarming or before the first unlock after a reboot, the preferences file is unreadable and UserDefaults returns
`nil` for every key. File and Keychain throw `.protectedDataUnavailable` in the same situation; UserDefaults can't tell.
Apps will take it for a first launch. Writes in that window may not persist, or may replace the real values once the
file is readable. At least a `- Warning:` on the storage.

### 4d. Large UserDefaults values (low–medium, verify)

CFPreferences logs values of 4 MiB or more as invalid on iOS, and tvOS's limit is much lower. `set` reports nothing,
so a value can be dropped silently. `UbiquitousStorage` checks value size; `UserDefaultsStorage` doesn't. Document, and
consider a `valueTooLarge` check like Ubiquitous's.

### 4e. App Group SQLite and suspension (medium, docs, verify)

`REFACTOR_PLAN §4` says "the scope docs say so" about `0xdead10cc`, but no scope doc mentions it. An open WAL connection
keeps a shared lock on the `-shm` file, and the system terminates an app suspended while holding a lock in a shared
container. Document on `SQLiteStorage.Scope.appGroup`; confirm on a device whether an idle connection triggers it.

### 4f. Minor

- FileStorage's durability on power loss isn't stated (SQLite's is): `Data.write(.atomic)` doesn't `fsync`.
- Interrupted atomic writes leave hidden temp files (`.dat.nosync…`) that `clear()` never removes: disk space, not values.
- Unit tests run by `swift test` on macOS share `.own` scopes with every other package's tests, through
  `com.apple.dt.xctest.tool`.

---

## 5. Docs, comments and tests

### Docs and comments

- `REFACTOR_PLAN §4` claims the App Group scope docs warn about suspension; they don't (§4e).
- README `withStorage`: needs "only against calls through this instance" (§4b).
- README Thread Safety note: "so that waiting calls suspend instead" — callers suspend, but the actor's thread still
  blocks for the whole call.
- `UserDefaultsStorage.Scope`: lists launch arguments and registered defaults, not the global domain, which every suite
  also reads.
- `AsyncCodingStorage`: "wrap a synchronous storage in `IsolatedDataStorage` to share it" — the built-in synchronous
  storages are already `Sendable`; it means non-`Sendable` ones.
- Release leftovers: Installation `from: "3.0.0"`; the coverage badge says ≥98% while the plan says 100%; the README
  "Tests" section says nothing concrete.

### Test gaps

- Observation: `AsyncStream` buffering under a slow consumer.
- `UnifiedStorage`: caller cancellation during creation.
- iOS: a 255-byte file name through a real atomic write (checked on macOS: works).

Otherwise excellent: every compound condition's paths are covered, limits are tested on both sides, and edge-case keys
(`""`, NUL, `é`/`e\u{301}`, `..`, `/`) run against the real systems.

---

## 6. Scope isolation — verified

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

Clashes that exist are documented: App Group ids that differ only in case on macOS; unentitled groups getting a folder
on macOS and the Simulator; unentitled UserDefaults groups staying in the app; launch arguments and registered defaults.
Undocumented, only with custom locators: two instances of one storage type and scope, but different locators, receive
each other's observation events.

---

## 7. Leaks, hangs and crashes

- **Cooperative pool blocking (medium).** Synchronous storages run Keychain, file and SQLite calls on Swift's
  cooperative threads. SQLite waits up to 1 s for another process (`busy_timeout`). A burst of contention, such as the
  app and an extension writing one database, can occupy every cooperative thread and stall all async work in the app.
  Fix: run blocking storages on their own executor or dispatch queue (a custom executor for `IsolatedDataStorage`).
- **Unbounded `AsyncStream` (low).** `bufferingPolicy: .unbounded`: a slow consumer of a frequently written key grows
  memory without limit. `.bufferingNewest(1)` fits state observation.
- **Delivery under the observation's lock (low).** A slow subscriber blocks every writer of that key; a subscriber that
  waits synchronously for another thread saving the same key deadlocks.
- **No eviction in `UnifiedStorage` (low).** With a namespace per account, SQLite connections and their file
  descriptors accumulate for the instance's lifetime.
- **Creation ignores cancellation (low).** Awaiting the creation task ignores the caller's cancellation; a custom async
  storage whose `init` hangs blocks its scope forever.
- **Crashes:** none found; the Ubiquitous key limit still needs a check on the oldest systems (§3.1). Lock re-entry (the registry is never re-entered from an observation's release),
  statement lifetimes and every error path check out.

---

## 8. Thread safety

No data races found:

- All mutable state is behind a lock: the facade's cache, the observation registry and its reference counts, each SQLite
  connection, the in-memory buckets.
- Locks are taken in one order (observation, then registry).
- Creation is deduplicated without a race, and failures aren't cached.
- The observation's version check lets a change win over a concurrent read.

The remaining races are logical: observation delivery order (documented) and per-instance atomicity (§4b).
