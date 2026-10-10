# Snapshot: Swift.org blog posts on Embedded Swift

- **Upstream:** `swiftlang/swift-org-website`, https://github.com/swiftlang/swift-org-website
  (rendered at https://www.swift.org/blog/).
- **Revision:** `main` at `b896a120b78d8334fdc44b4234dc1840759c844b`
  (`git ls-remote https://github.com/swiftlang/swift-org-website.git HEAD`, 2026-10-09).
- **Fetched:** 2026-10-09 from
  `https://raw.githubusercontent.com/swiftlang/swift-org-website/b896a120b78d8334fdc44b4234dc1840759c844b/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** CC-BY-4.0. The repository's `LICENSE.md` says the site is "Licensed under
  Apache 2.0 (License.txt), with the exception of content in _posts which is licensed
  under the Creative Commons Attribution 4.0 International License (CC-BY-4.0.txt)".
  Attribution: the authors named in each post's front matter, swift.org.
- **Threads:** cross-cutting (specialization, compilation model).
- **Files (2):**
  - `_posts/2025-11-17-embedded-swift-improvements-coming-in-swift-6.3.md` (front-matter authors `doug_gregor`,
    `rauhul`): `EmbeddedRestrictions` diagnostics, `@c` (SE-0495), `@section`/`@used`
    (SE-0492), weak definitions for symbols of imported modules (the diamond-dependency
    duplicate-symbol fix), `@export(implementation|interface)` (SE-0497), DWARF as the
    only type-layout record for the debugger.
  - `_posts/2026-08-20-embedded-swift-improvements-coming-in-swift-6.4.md` (front-matter author `doug_gregor`):
    all `any` types, untyped throws and metatypes now in the subset, costed only where
    used and flagged by the `PerformanceHints` diagnostic group.

**Not taken.** `_posts/2024-04-03-embedded-swift-examples.md` (an announcement of the
examples repository, no technical content); every other post.
