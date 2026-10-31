# KeyValueStorage 4.0 — Refactor Plan

## 0. How to work on this plan

This file lists only what's left of the 4.0 refactor. The finished design, its decisions (D1–D28) and their rationale are in git: the full plan as of commit `0d557e4`. Check `git log` first, as this file can lag it. Work on branch `4.0.0-experiments`.

**Working rules** (the maintainer's):
- **Commits** only when the maintainer asks, one per step.
- **Simple, bulletproof, sound:** the simplest rule that holds for every input. No logic in default backing stores (one system call per member); all naming lives in the locators, with the byte-level encodings they share in `Helpers/String+UTF8.swift`; no parameters or properties for demonstration only; never swallow a "can't tell": throw instead.
- **Consistency:** a rule decided for one storage applies to all six.
- **Names** are exact bytes everywhere (`ExactString`). Encode, don't reject: any string is a valid key or namespace, and only system limits throw.
- **Errors** are typed end to end, carry the failing input as the caller passed it, are documented per case, and every throw site is tested.
- **System and SDK gotchas** get a doc comment on the case they affect, not a workaround, unless they'd let two scopes reach each other's values.
- **Comments** hold only essentials, gotchas and warnings, one line where possible, describing the current behavior, never its history. API docs use `///`, `- Note:` and `- Warning:`.
- **Tests** use XCTest, with `// Given`, `// When`, `// Then` and mocks that record their calls. Storages, layers and the facade keep 100% region and line coverage; default adapters get integration tests against the real system. Every behavior the docs state is either measured by a test or listed below as to verify.
- **Condition coverage, not just lines:** Swift's coverage counts a whole condition as one region, so every compound condition (`&&`, `||`, `if`/`guard` clause lists, `where`, `??`, ternaries, patterns) needs a test for each path that short-circuiting can tell apart: `a && b && c` needs `a` false, `b` false, `c` false and all true. Limits get a test on each side of the boundary.
- **When asked whether anything is left open,** do one complete pass, and say "none" when nothing is.

**Commands:**
- macOS: `swift build --build-tests`, with no warnings, and `swift test`.
- iOS Simulator: `xcodebuild test -scheme KeyValueStorage -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- KeychainHost, for the real keychain on the Simulator: `xcodebuild test -project Tests/KeychainHost/KeychainHost.xcodeproj -scheme KeychainHost -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- Test runs take minutes, so run them in the background rather than with a short timeout.

**Deployment targets stay** (2026-11-01): iOS 13, macOS 10.15, watchOS 6. So `FileStorage`'s `#available(macOS 11)` fallback stays uncovered, and `UbiquitousStorage` keeps its `@available(watchOS 9.0, *)` annotations.

## 1. Tests

1. **The system behavior the scope docs state**, so no comment rests on reasoning alone:
   - iOS Simulator: a UserDefaults suite named after an App Group the app isn't entitled to works and reports nothing, and its plist lands in the app's own container;
   - macOS: `containerURL(forSecurityApplicationGroupIdentifier:)` returns a path for any id, and two ids that differ only in case get paths that differ only in case, on a volume that ignores case. The test checks paths and the volume, without creating folders in `~/Library/Group Containers`;
   - macOS: whether two UserDefaults suites whose names differ only in case share values in the process, and on disk;
   - the docs are then worded after what these tests measure.
2. **Uncovered by design** (no test can reach them): `Lock`'s `NSLock` fallback (before macOS 13 / iOS 16), `FileStorage`'s `.atomic`-only writing options (before macOS 11), `OwnIdentity.identifier` without a bundle ID, `assert` failure arms, the `.unknown` arm of an observation's state, SQLite's out-of-memory and empty-blob-pointer paths, and `SQLiteStorage.init()`, which would open a database in the real Application Support. The Keychain and Ubiquitous default adapters run in KeychainHost and on a device.

## 2. Real-device tests (deferred: need a real iPhone)

Keychain's `errSecInteractionNotAllowed` is mapped to `.protectedDataUnavailable` from Apple's docs; SQLite's code still needs the run. `ProtectedDataTests` in KeychainHost records what SQLite (each protection class, on an open and on a new connection) and a `.complete` file do while the device is locked, and that both recover after unlocking. It skips on the Simulator and unless `KVS_LOCK_TEST=1`.
- From its report: map SQLite's locked-database result code to a `.protectedDataUnavailable` case, like `FileStorage`'s, and confirm File's `EPERM` mapping on a device.
- Confirm that the keychain deletes a `.whenUnlocked` item while locked, and that saves at `.complete` and `.whenUnlocked` fail while locked.
- What each protection level does while locked; whether the system deletes a database's files one at a time in `.cache` and `.temporary`; which file protection classes macOS enforces.
- **Keychain `.iCloud(.appGroup(id:))` with an App Group id**, not a Keychain Sharing group: whether synced items in an App Group access group sync to the user's other devices.
- **The same key written on two devices before they sync**, for Keychain's and Ubiquitous's `.iCloud` scopes: which value wins. Last writer is likely but not measured; the result becomes a doc line on each `.iCloud` case.
- **Ubiquitous:** a signed host with the iCloud key-value store entitlement and an Apple Account, ideally with a second device to see values sync. Check the key-length limit (128 UTF-16 code units per Apple's docs, 64 UTF-8 bytes per older forum and blog posts), the default adapter's integration tests, the quota, signed-out behavior, what an unentitled build does (keeps nothing, `synchronize()` returns `false`), and that the store, like UserDefaults, drops keys with NUL (assumed; the locator escapes it).
- Blocker: KeychainHost is ad-hoc signed, and its entitlements hardcode a placeholder team (`ABCDE12345`). Running it on a device needs a signing setup that leaves the committed project alone, such as a local, git-ignored xcconfig with the team and bundle ID, and entitlements built from `$(AppIdentifierPrefix)`.

## 3. CI

Add a coverage job (macOS, latest Xcode); `swift.yml` has none yet:

```sh
swift test --enable-code-coverage
PROF=$(swift test --show-codecov-path)          # JSON export path; profdata is next to it
xcrun llvm-cov report <test binary> -instr-profile .build/debug/codecov/default.profdata \
    -ignore-filename-regex '(Tests|\.build)/'
```

A small script fails the job if region or line coverage is below 100% for `Storages/*/<Name>.swift`, `Layers/` and the locators. Adapter files are excluded from the gate, and so is `FileStorage`'s `#available(macOS 11)` fallback. (Verify the binary path per toolchain.) Keep the existing matrix (Xcode 16 → 26.x), the iOS Simulator job, the KeychainHost job, and the tvOS, watchOS and visionOS builds.

## 4. Open decisions

1. **Name:** keep `KeyValueCodingStorage`, or shorten it to `CodingStorage`.

## 5. Release

- README: the Installation version (`from: "3.0.0"`) and "Migrating from 2.x".
- DocC rewrite: the scopes table, the isolation guide, observation limits.
- `CHANGELOG`; tag 4.0.0.

## 6. Risks and notes

- **Cross-process consistency:** isolation is per instance and per process. The app and an extension writing the same scope are only protected by the system itself (SQLite transactions and WAL, atomic file replace, UserDefaults and keychain internals). `withStorage` isn't atomic across processes.
- **iOS group containers:** the system terminates a suspended app that holds a file lock in a group container (`0xdead10cc`). SQLite in an App Group scope should finish its work before suspension; the scope docs say so.
- **Observation** sees only changes made through an `ObservableKeyValueStorage` of the same storage type and scope, and only of the observer's value type. Concurrent writers of one key may deliver out of order.
- **Blocking SQLite calls:** `DefaultSQLiteDatabase` locks each operation, so calls on one instance block while they wait. `IsolatedKeyValueDataStorage` turns that into suspension when many tasks share one SQLite scope.
