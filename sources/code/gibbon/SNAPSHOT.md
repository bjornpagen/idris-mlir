# Snapshot: Gibbon compiler and runtime, the passes for packed data

- **Upstream:** `gibbon-compiler/gibbon` on GitHub (formerly `iu-parfunc/gibbon`; the old name
  redirects, GitHub repository id 58642617).
- **Revision:** `main` at `41e650f14f2a815bcc78ec466a05bae6a33a7a11` (`git ls-remote` of both
  names, 2026-10-09; last push 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/gibbon-compiler/gibbon/41e650f14f2a815bcc78ec466a05bae6a33a7a11/<path>`;
  file list from `https://api.github.com/repositories/58642617/git/trees/41e650f14f2a815bcc78ec466a05bae6a33a7a11?recursive=1`.
- **Paths:** relative to the repository root (so `gibbon-compiler/src/Gibbon/Passes/Cursorize.hs`).
- **Files:** 28.
- **Licence:** none stated (verify). The repository has no licence file at its root, the GitHub
  API reports no licence, and `gibbon-compiler/gibbon.cabal` has its `license:` and
  `license-file:` fields commented out while stating "Copyright 2016-2022 Ryan Newton and
  contributors". The only licence file in the tree is a BSD-3-Clause stub under
  `archived/ToyTree/`, which covers that archived subproject only. Default copyright applies:
  confirm with the authors before redistributing these excerpts.
- **Threads:** flat (packed-trees), D.

**What is here.** The passes that infer locations and regions and compile traversals over
packed buffers, in the order `gibbon-compiler/src/Gibbon/Compiler.hs` runs them for the packed
backend (lines 690–848 of that file at this revision):

- Pipeline and IRs: `gibbon-compiler/src/Gibbon/Compiler.hs` (the pass order, including the
  Gibbon1 dummy-traversal path and the Gibbon2 random-access path, and `addRedirectionCon`),
  `README.md`, `gibbon-compiler/README.md`, `gibbon-compiler/src/Gibbon/L2/README.md`,
  `L2/Syntax.hs` (LoCal as implemented: `LetRegionE`, `LetParRegionE`, `LetLocE` with
  `StartOfRegionLE`/`AfterConstantLE`/`AfterVariableLE`/`InRegionLE`/`FromEndLE`, `RetE`,
  `IndirectionE`, `BoundsCheck`, region multiplicities, the `Traverse` effect, `LRM`
  location–region–modality triples, and the structure-of-arrays region `SoAR`),
  `L2/Typecheck.hs` (the location type checker run between passes), `NewL2/Syntax.hs` and
  `NewL2/FromOldL2.hs` (L2 with explicit region/end-of-region arguments), `L3/Syntax.hs`
  (the cursor language), `LocExp.hs`.
- Location and region inference: `Passes/InferLocations.hs` (L1 to L2: fixed versus fresh
  locations, constraints discharged as the recursion unwinds, copy insertion as repair, `fixRANs`),
  `Passes/RegionsInwards.hs` (moves `letregion` bindings inwards), `Passes/InferRegionScope.hs`
  (global versus dynamic regions by escape; all regions "infinite").
- Traversals and random access: `Passes/InferEffects.hs` (traversal effects by a fixpoint that
  starts at the maximum and shrinks), `Passes/AddTraversals.hs` (Gibbon1 dummy traversals),
  `Passes/AddRAN.hs` (Gibbon2 random-access nodes added to the L1 program, then location
  inference rerun; `needsRAN`), `Passes/RemoveCopies.hs` (copy calls become indirection nodes),
  `Passes/FindWitnesses.hs` (reorders bindings to bring end witnesses into scope),
  `Passes/RouteEnds.hs` (end witnesses as extra returns), `Passes/FollowPtrs.hs` (indirection and
  redirection branches in case expressions).
- Parallelism and runtime regions: `Passes/ParAlloc.hs` (after-locations of spawned values become
  fresh regions tied back with pointers), `Passes/ThreadRegions2.hs` (threads region and
  end-of-chunk cursors through calls for bounds checks and refcounts),
  `Passes/InferFunAllocs.hs` (which functions can trigger GC).
- Cursor insertion: `Passes/Cursorize.hs` (L2 to L3: the dilated `(start,end)` representation,
  read/write cursors, end-of-read returns).
- Runtime: `gibbon-rts/rts-c/gibbon_rts.h` and `gibbon_rts.c` (reserved tags for
  redirection/indirection and the collector, 16-bit tags in the high bits of 48-bit pointers,
  chunks, the nursery, region info, old-generation footers, chunk-size constants),
  `gibbon-rts/rts-ng/src/gc.rs` and `notes.md` (the Rust generational collector of
  `koparkar-2024-mostly-serialized-gc`: burning, forwarding, left-to-right evacuation, finding
  region metadata from a pointer).

**Not included.** The front ends (`HaskellFrontend.hs`, `SExpFrontend.hs`), L0 specialisation,
`Passes/Codegen.hs`, `Lower.hs`, `Fusion2.hs`, `ThreadRegions.hs` (superseded by
`ThreadRegions2.hs` and no longer run), `CalculateBounds.hs` (not imported by the pipeline),
benchmarks and examples, including the Marmoset layout benchmarks under
`gibbon-compiler/examples/layout_benchmarks/`.
