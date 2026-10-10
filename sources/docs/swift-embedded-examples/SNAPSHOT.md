# Snapshot: Embedded Swift documentation (DocC catalog)

The Embedded Swift user documentation moved out of `swiftlang/swift` (where
`docs/EmbeddedSwift/*.md` are one-line stubs at `swift-6.4.0-RELEASE`) to the DocC catalog
published at https://docs.swift.org/embedded/documentation/embedded, whose source is this
repository.

- **Upstream:** `swiftlang/swift-embedded-examples`,
  https://github.com/swiftlang/swift-embedded-examples.
- **Revision:** `main` at `119b29f83550efb39546e2359ad8368d5e6b6fd2`
  (`git ls-remote https://github.com/swiftlang/swift-embedded-examples.git HEAD`, 2026-10-09).
- **Fetched:** 2026-10-09 from
  `https://raw.githubusercontent.com/swiftlang/swift-embedded-examples/119b29f83550efb39546e2359ad8368d5e6b6fd2/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 with the Runtime Library Exception (`LICENSE.txt` at the pin;
  the GitHub API reports Apache-2.0).
- **Threads:** D (memory), cross-cutting (specialization).
- **Files (8)**, under `Sources/EmbeddedSwift/EmbeddedSwift.docc/`:
  - `EmbeddedSwift.md`: the catalog's root page.
  - `GettingStarted/Introduction.md`: how Embedded Swift differs (no runtime metadata
    where avoidable, no reflection, mandatory specialization, a compiler that behaves like
    a C compiler's object-file model).
  - `GettingStarted/LanguageSubset.md`: what is left out by design (reflection, generic
    calls on existentials, non-final generic class methods, weak and unowned references,
    library evolution, Objective-C, non-WMO builds).
  - `UsingEmbeddedSwift/Existentials.md`, `UsingEmbeddedSwift/NonFinalGenericMethods.md`:
    why monomorphization forbids generic calls whose type cannot flow from caller to
    callee, and the alternatives (generics, `#if` and type aliases, an enum).
  - `UsingEmbeddedSwift/Libraries.md`: libraries ship as serialized `.swiftmodule` only;
    all machine code is produced in the client's build, standard library included.
  - `CompilerDetails/ABI.md`: `$e` mangling, the reduced class metadata and witness-table
    layouts, the heap object (isa at offset 0, inline refcount at offset 1).
  - `CompilerDetails/Status.md`: the feature and standard-library support tables.

**Not taken.** The `Examples/` board guides, `SDKSupport/` pages, `InstallEmbeddedSwift.md`,
`Basics.md`, `Strings.md`, `ConditionalCompilation.md`, `ExternalDependencies.md` (build
and board how-tos, no compilation-model content), and the example projects themselves
(code we would never build).

**How to fetch more.** The catalog's tree:
`https://api.github.com/repos/swiftlang/swift-embedded-examples/git/trees/119b29f83550efb39546e2359ad8368d5e6b6fd2?recursive=1`.
