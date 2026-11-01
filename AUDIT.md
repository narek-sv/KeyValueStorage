# KeyValueStorage 4.0 — Audit

Audit of branch `4.0.0-experiments` at commit `4c12469` (2026-11-01): every source file, the README, the CHANGELOG,
`REFACTOR_PLAN.md` and the test suite. Two findings were confirmed with a probe app built against the package (release
build, macOS). Items marked **verify** need a real device or Apple's confirmation before acting.

Severity: **high** (data loss or release blocker), **medium** (wrong behavior users will hit), **low** (rare or cosmetic).

---

## Summary

The core is solid. Scope isolation holds for all six storages with the default locators, errors are typed end to end,
the naming encodings are injective and safe on case- and normalization-insensitive volumes, and the test suite is
unusually thorough. No finding blocks a release on its own. What's left: checks that need a device (§3.1 and
`REFACTOR_PLAN §2`), release leftovers in the docs (§5), and design and performance improvements (§1, §2).

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

1. **Duplicated code that must stay in sync (low).**
   - `DefaultFileLocator` and `DefaultSQLiteLocator` each implement the folder rules (base folders, app folder,
     namespace and protection folder names, group checks). SQLite relies on landing in File's folder; one test guards
     it, but the rule is written twice.
   - `FileStorage` and `SQLiteStorage` have separate but identical `Retention`, `Protection` (cases) and `Scope` types.
   - `DefaultUserDefaultsLocator` and `DefaultUbiquitousLocator` repeat the `<namespace>!/<key>` scheme.
   - `CodingStorage` and `AsyncCodingStorage` are copies.
   One shared folder rule and one shared stored-key codec would enforce "a rule decided for one storage applies to all
   six" in code rather than by review.
2. **Observation is narrow (low, design).** Only changes made in this process, through the same storage type and scope,
   with the same value type, are seen. Ubiquitous's `didChangeExternallyNotification` and UserDefaults'
   `didChangeNotification` could feed it.

---

## 2. Performance

Measured per call on an M3 Max, release build, median of 7 runs:

| Path | Time | Allocations |
| --- | --- | --- |
| `InMemoryStorage.fetch` (sync) | 0.10 µs | 0 |
| `AsyncCodingStorage.fetch` (String) | 0.24 µs | 0 |
| `UnifiedStorage.fetch` (String) | 1.05 µs | 0 |
| `UnifiedStorage.save` (Int, JSON) | 1.44 µs | 2 |
| `UnifiedStorage(observable: true).save` (Int) | 1.72 µs | 2 |

The facade's cache is typed per storage type, so its lookup no longer boxes scopes, stays flat however many scopes are
cached, and adds no allocations to any storage.

1. **The rest of the facade (low).** Over a storage that does nothing, a call costs ~0.9 µs through `UnifiedStorage` and
   86 ns through the coding storage. The lock, the lookup and awaiting the created storage explain ~0.15 µs; the rest is
   probably generic code that isn't specialized across the module boundary, and the async calls between the layers.
2. **One lock per instance (low).** Every call takes the instance's lock twice, whatever its scope, so 8 tasks through
   one `UnifiedStorage` finish no faster than one task (0.93 µs vs 0.90 µs per call over a storage that does nothing).
3. **Already good:** File (one `lstat` per item, one folder check in `clear`), Keychain (update first, add only when
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

None open: the gaps found are documented, and what only a device can settle is listed in `REFACTOR_PLAN §2`.

---

## 5. Docs, comments and tests

### Docs and comments

- Release leftovers: Installation `from: "3.0.0"`; the coverage badge says ≥98% while the plan says 100%; the README
  "Tests" section says nothing concrete.

### Test gaps

None open. The suite is excellent: every compound condition's paths are covered, limits are tested on both sides, and edge-case keys
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

The remaining races are logical: observation delivery order (documented), and other instances or processes writing between the steps of a `move` or an `update`, which only calls through the same `UnifiedStorage` wait for (documented).
