# Snapshot addendum: Swift SIL, ownership SSA, ARC and copy-on-write (cluster `sil-arc`)

This addendum lists the files the `sil-arc` pass added to `docs/swift/`. Another pass
(cluster `tc`) stages type-checker documents into the same snapshot at the same pin;
the merge folds both lists into one `docs/swift/SNAPSHOT.md`.

- **Upstream:** `swiftlang/swift` on GitHub, https://github.com/swiftlang/swift.
- **Revision:** tag `swift-6.4.0-RELEASE`, a lightweight tag on commit
  `b8189d766d86ad7fc8106787d6ce9e402f38dd72`, the newest release tag on 2026-10-09
  (`git ls-remote --tags https://github.com/swiftlang/swift.git 'refs/tags/swift-6.4*'`).
- **Fetched:** 2026-10-09, by a shallow, blob-filtered, sparse clone at the tag (one new
  directory, nothing built or run):
  `git clone --depth 1 --branch swift-6.4.0-RELEASE --filter=blob:none --no-checkout --sparse https://github.com/swiftlang/swift.git`,
  then `git sparse-checkout set --no-cone '/docs/' ...`.
- **Paths:** relative to the repository root (so `docs/SIL/Ownership.md`).
- **Licence:** Apache-2.0 with the Runtime Library Exception (`LICENSE.txt` at the tag; each
  source file's header says so).
- **Files (13):**
  - `docs/SIL/SIL.md`: the SIL reference: stages (raw, canonical), lowered types,
    ownership kinds, lifetimes, borrow scopes, reborrow and guaranteed phis, lexical
    lifetimes, joint post-dominance and dead-end points, the copy-on-write
    representation, the stack discipline, memory lifetime, TBAA, runtime failure.
  - `docs/SIL/Ownership.md`: Ownership SSA in detail: the ownership-kind lattice, the
    value ownership kinds, operand constraints, forwarding, safe interior pointers,
    variable (lexical) lifetimes and deinit barriers, dead-end blocks, move-only wrapped
    types and the move checker.
  - `docs/SIL/ARCOptimization.md`: RC identity, `retain_value`, `is_unique` and
    `Builtin.isUnique`, ARC loop hoisting, the uniqueness-check hazard, the deinit model.
  - `docs/SIL/Instructions.md`: the instruction reference; the ownership-relevant entries
    are `begin_borrow`, `end_borrow`, `borrowed from`, `copy_value`, `move_value`,
    `destroy_value`, `end_lifetime`, `extend_lifetime`, `drop_deinit`, the
    `destructure_*`, `load [copy|take]`, `store [init|assign]`, `is_unique`,
    `begin_cow_mutation`, `end_cow_mutation`, `mark_dependence`, `partial_apply
    [on_stack]`, `alloc_ref [stack]`, `begin_access`, `return_borrow`,
    `mark_unresolved_non_copyable_value`, the move-only wrapper conversions and
    `Builtin.Borrow`.
  - `docs/SIL/SILFunctionConventions.md`: argument indexing across function types,
    definitions and applies.
  - `docs/SIL/SILMemoryAccess.md`: access base, storage and path; formal access markers.
  - `docs/SIL/SIL-Utilities.md`: the Swift-side optimizer utilities, ownership and borrow
    utilities, and the plan to classify instructions by protocol.
  - `docs/OwnershipManifesto.md`: the 2017 design of ownership: the Law of Exclusivity,
    shared values, `owned`/`shared`/`consuming`, `move`/`copy`/`endScope`, non-copyable
    types.
  - `docs/HighLevelSILOptimizations.rst`: `@_semantics` tags (`array.make_mutable` and the
    other array semantics, their guards and interference), `@_effects`.
  - `docs/proposals/InoutCOWOptimization.rst`: the `INOUT` header bit for in-place
    mutation of COW elements through accessors (a design document).
  - `docs/proposals/ValueSemantics.rst`: value against reference semantics; moves.
  - `docs/ReferenceGuides/LifetimeAnnotation.md`: `@_lifetime` dependencies of
    `~Escapable` values (`borrow`, `&`, `copy`, `immortal`, defaults, subtyping).
  - `userdocs/diagnostics/embedded-restrictions.md`: the `EmbeddedRestrictions`
    diagnostic group.

**Not taken, and why.** `docs/SIL/Types.md`, `docs/SIL/FunctionAttributes.md` and
`docs/SIL/SILInitializerConventions.md` (no ownership content beyond what `SIL.md` says);
`docs/Arrays.md` (2014, about Objective-C bridging); `docs/ExternalResources.md` (a link
list; its two SIL talks are recorded as links in the notes); `docs/EmbeddedSwift/*.md`
(seven one-line stubs at this tag: "Embedded Swift documentation has moved to" docs.swift.org;
the moved text is the `docs/swift-embedded-examples/` snapshot). The images and
`.graffle` files under `docs/` are not documentation text.

**How to fetch more.** Single files:
`https://raw.githubusercontent.com/swiftlang/swift/b8189d766d86ad7fc8106787d6ce9e402f38dd72/<path>`.
The tree: `https://api.github.com/repos/swiftlang/swift/git/trees/b8189d766d86ad7fc8106787d6ce9e402f38dd72?recursive=1`.
The runtime's retain entry points (`stdlib/public/runtime/HeapObject.cpp`) are already in
the library at `docs/swift-rc/`, at the older tag `swift-6.2-RELEASE`; this pass did not
re-take them.
