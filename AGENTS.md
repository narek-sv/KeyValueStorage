# Agents

Instructions for coding agents and AI reviewers working on KeyValueStorage.

- **Read [DESIGN.md](DESIGN.md) first.** Its principles apply to every change, and its decisions were made on purpose:
  don't propose reversing one, or report what it decides as a problem, without new evidence, such as a measurement, a
  change in a system's behavior or a new Swift version. A change that reverses or extends a decision updates its entry
  in the same commit.
- **Open work** for 4.0 is in [AUDIT.md](AUDIT.md), by priority. An addressed item is removed, not marked as done.
- **Commit** only when the maintainer asks, one commit per step.
- **When asked whether anything is left open,** do one complete pass, and say "none" when nothing is.

## Commands

- Build: `swift build --build-tests`, with no warnings.
- Test: `swift test`. A run takes minutes, so run it in the background rather than with a short timeout. Never run two
  at once, here or in another worktree: they share real User Defaults suites, folders and databases, and fail each other.
- iOS Simulator: `xcodebuild test -scheme KeyValueStorage -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- KeychainHost, for the real keychain on the Simulator:
  `xcodebuild test -project Tests/KeychainHost/KeychainHost.xcodeproj -scheme KeychainHost -destination "platform=iOS Simulator,name=<an installed iPhone>"`.
- Coverage: `swift test --enable-code-coverage`, then read `.build/arm64-apple-macosx/debug/codecov/KeyValueStorage.json`;
  delete the `default.profraw` a run can leave in the repository's root.
