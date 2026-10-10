# Snapshot addendum: Swift Evolution vision for Embedded Swift (cluster `sil-arc`)

Cluster `tc` stages proposals into `docs/swift-evolution/proposals/` at the same pin; the
merge folds this addendum into one `docs/swift-evolution/SNAPSHOT.md`.

- **Upstream:** `swiftlang/swift-evolution`, https://github.com/swiftlang/swift-evolution.
- **Revision:** `main` at `01180b65b4b9c1122d4a349170059d299a03a5f8`
  (`git ls-remote https://github.com/swiftlang/swift-evolution.git HEAD`, 2026-10-09).
- **Fetched:** 2026-10-09 from
  `https://raw.githubusercontent.com/swiftlang/swift-evolution/01180b65b4b9c1122d4a349170059d299a03a5f8/visions/embedded-swift.md`.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 with the Runtime Library Exception (`LICENSE.txt` at the pin).
- **File (1):** `visions/embedded-swift.md`: "A Vision for Embedded Swift": goals (a
  subset, not a dialect; dynamic features cost only where used; no implicit heavyweight
  runtime calls), the language subset, mandatory specialization with library bodies
  serialized to clients, metadata only where a feature needs it, the platform entry
  points (`_swift_allocate`, `_swift_deallocate`), and its revision history (the 2023
  version forbade metadata and existentials outright).

**Not taken.** `visions/resources/embedded-swift-footprint.png` (an image the vision
references); the other visions (`memory-safety.md`, `using-c++-from-swift.md` and the
rest; not in this cluster).

**Cross-links (staged by cluster `tc`, not duplicated here):** SE-0366 (`consume`),
SE-0377 (`borrowing`/`consuming` parameters), SE-0390 (noncopyable structs and enums),
SE-0427 (noncopyable generics), SE-0432 (noncopyable `switch`), SE-0446 (`~Escapable`),
SE-0414 (region-based isolation), SE-0430 (`sending`).
