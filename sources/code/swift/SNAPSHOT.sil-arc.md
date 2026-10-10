# Snapshot addendum: Swift ownership verifier, semantic ARC and COW sources (cluster `sil-arc`)

This addendum lists the files the `sil-arc` pass added to `code/swift/`. Cluster `tc`
stages region-isolation sources (`RegionAnalysis.h`, `PartitionUtils.h`,
`PartitionOpError.def`) into the same snapshot at the same pin; the merge folds both
lists into one `code/swift/SNAPSHOT.md`.

- **Upstream:** `swiftlang/swift`, https://github.com/swiftlang/swift.
- **Revision:** tag `swift-6.4.0-RELEASE` = commit `b8189d766d86ad7fc8106787d6ce9e402f38dd72`
  (lightweight tag).
- **Fetched:** 2026-10-09, from the same sparse clone as `docs/swift/SNAPSHOT.sil-arc.md`
  (sparse patterns `/lib/SILOptimizer/SemanticARC/`, `/lib/SIL/Verifier/`,
  `/lib/SILOptimizer/ARC/`, `/include/swift/SIL/SILValue.h`,
  `/include/swift/SILOptimizer/Utils/OSSACanonicalizeOwned.h`,
  `/lib/SILOptimizer/Mandatory/OwnershipModelEliminator.cpp`,
  `/lib/SILOptimizer/Mandatory/MoveOnly*`, `/stdlib/public/core/...`). Nothing built or run.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 with the Runtime Library Exception (file headers).
- **Files (26):**
  - `lib/SILOptimizer/SemanticARC/` (all 15 files at the tag): the semantic ARC optimizer
    on OSSA: the driver (`SemanticARCOpts.cpp`, `.h`), the worklist visitor
    (`SemanticARCOptVisitor.cpp`, `.h`), the per-function context (`Context.cpp`, `.h`),
    copy elimination and live-range joining (`CopyValueOpts.cpp`), the owned live range
    (`OwnershipLiveRange.cpp`, `.h`), owned-to-guaranteed phi conversion
    (`OwnedToGuaranteedPhiOpt.cpp`, `OwnershipPhiOperand.h`, `Transforms.h`),
    `OwnershipConversionElimination.cpp`, `RedundantMoveValueElimination.cpp`,
    `CMakeLists.txt`.
  - `lib/SIL/Verifier/SILOwnershipVerifier.cpp`, `lib/SIL/Verifier/LinearLifetimeChecker.cpp`,
    `lib/SIL/Verifier/LinearLifetimeCheckerPrivate.h`: the OSSA verifier and the linear
    lifetime dataflow it runs per value.
  - `include/swift/SIL/SILValue.h`: `OwnershipKind` (the lattice), `ValueOwnershipKind`,
    `OwnershipConstraint`, `OperandOwnership` (the closed classification of every use)
    and `Operand`.
  - `include/swift/SILOptimizer/Utils/OSSACanonicalizeOwned.h`: the interface and design
    comment of OSSA lifetime canonicalization (rewrite all copies and destroys of one
    owned def from its pruned liveness).
  - `lib/SILOptimizer/Mandatory/OwnershipModelEliminator.cpp`: lowering OSSA to plain SSA
    (copy to retain, destroy to release, borrows erased, destructures split).
  - `lib/SILOptimizer/Mandatory/MoveOnlyChecker.cpp`: the move-only checker's driver.
  - `lib/SILOptimizer/ARC/RCStateTransition.def`, `lib/SILOptimizer/ARC/RefCountState.h`:
    the pre-OSSA ARC sequence optimizer's state machine (retain/release pairing by
    bottom-up and top-down lattices), kept as the design OSSA replaces.
  - `stdlib/public/core/ManagedBuffer.swift`: `ManagedBuffer`, `ManagedBufferPointer`,
    `isKnownUniquelyReferenced`.
  - `stdlib/public/core/ContiguousArrayBuffer.swift`: the native array buffer:
    `beginCOWMutation`/`endCOWMutation`, `_consumeAndCreateNew`, the static empty-array
    singleton.

**Not taken, and why.** `lib/SIL/Verifier/SILVerifier.cpp` (346 KB; the ownership rules
it delegates are in the two verifier files above); `GuaranteedPhiVerifier*`,
`MemoryLifetimeVerifier.cpp`, `FlowSensitiveVerifier.*` (not read); the rest of
`lib/SILOptimizer/ARC/` (the sequence dataflow implementation; the state machine is
enough to show the design); the other `MoveOnly*` checker utilities (165 KB of address
checking); `stdlib/public/core/Array.swift` and `ArrayBuffer.swift` (read only at their
mutation entry points; pointers below); `OSSACanonicalizeGuaranteed.h`;
`SwiftCompilerSources/Sources/Optimizer/Utilities/OwnershipLiveness.swift` and
`LifetimeCompletion.swift` (the Swift-side liveness utilities; not read).

**Pointers, read at the pin, not stored.**
- `stdlib/public/core/Array.swift` lines 350-378: `_makeMutableAndUnique` is
  `@_semantics("array.make_mutable")` and calls `_buffer.beginCOWMutation()`, replacing
  the buffer by `_consumeAndCreateNew()` when it is not unique; `_endMutation` is
  `@_semantics("array.end_mutation")` and calls `endCOWMutation()`. Lines 1080-1150:
  `reserveCapacity`, `_createNewBuffer(bufferIsUnique:...)` (moves elements when the old
  buffer is unique, copies otherwise).
- `stdlib/public/core/ArrayBuffer.swift` lines 104-166: the Objective-C-bridging buffer's
  `isUniquelyReferenced`, `beginCOWMutation` (a non-native buffer is never unique) and
  `endCOWMutation`.

**How to fetch more.** `https://raw.githubusercontent.com/swiftlang/swift/b8189d766d86ad7fc8106787d6ce9e402f38dd72/<path>`.
