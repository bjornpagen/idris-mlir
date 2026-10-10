# Whole-program compilation at scale: summaries, sharded backends, deterministic caches

Notes of the sharded-compilation cluster, 2026-10-10, for proposal 0011
(`proposals/0011-sharded-whole-program-compiler.md`). Paths starting `docs/`, `code/` or
`papers/` are already stored in this library. Everything else was **read online on
2026-10-10 and is not stored**, except the items of §10, fetched the same day after the
owner's approval. A claim is marked **measured** (a published number with its
machine), **read** (what the text or code says) or **unverified** (found only in secondary
sources, or the primary was unreachable).

Contents: 1 ThinLTO; 2 GCC WHOPR and LTO partitioning; 3 MLton; 4 rustc; 5 MLIR and LLVM
threading; 6 build systems and content-addressed caches; 7 Zig, Carbon, Unison; 8 Swift and
GHC; 9 what transfers; 10 snapshots fetched.

## 1. ThinLTO

Johnson, Amini, Li, "ThinLTO: Scalable and Incremental LTO", CGO 2017, pp. 111–121.
https://research.google/pubs/thinlto-scalable-and-incremental-lto/ (PDF 2.2 MB, 11 pp.).
LLVM blog, June 2016; clang docs https://clang.llvm.org/docs/ThinLTO.html.

- **read** Three phases: compile with a per-module summary, a thin link, parallel backends.
  The thin link is the only serial step and reads no IR.
- **read** A summary holds per function linkage, instruction count, optional hotness, flags,
  and every reference and call, so the thin link has the full call and reference graph.
  **measured** Summaries add about 0.8% to IR size.
- **read** Imports are decided at the thin link by walking call chains: threshold 100
  instructions with decay 0.7 per level; hot edges 300 with decay 1.0. **measured** Halving
  the threshold cost 5% (povray) and 6.7% (milc).
- **read** Other global facts at the thin link: internalization, prevailing copies,
  indirect-call promotion, promotion and renaming of locals by appending the SHA-1 of the
  defining module, so every backend agrees on a name without coordinating. **measured**
  Internalization alone kept about 90% of the gain on astar.
- **read** Backend cache key (`computeLTOCacheKey`, `llvm/lib/LTO/LTO.cpp`): SHA-1 over
  compiler version, codegen configuration, module hash, the *sorted* export list, the import
  list sorted by module hash then GUID, resolved linkage, flags, imported summaries, type-id
  resolutions, profile. Sorting is what makes the key schedule-independent.
- **measured** (16-core/32-thread Xeon) Chromium: ThinLTO 3m18s total of which the thin link
  is 30 s at about 1.3 GB; full LTO 28m18s; GCC WPA+LTRANS 8m21s. Clang incremental after
  editing one rarely called function: full LTO 17m11s, ThinLTO 25 s, no LTO 4 s.
- **read** Limits named by the authors: module-level hashing is coarse; distributed builds
  ship each backend only its index slice.

## 2. GCC WHOPR and LTO partitioning

Glek, Hubička, "Optimizing real-world applications with GCC Link Time Optimization", GCC
Summit 2010, arXiv:1010.2196 (PDF 182 KB). GCC manual, Optimize-Options. `gcc/lto/lto-partition.cc`.

- **read** LGEN (parallel), WPA (serial), LTRANS (parallel). WPA partitions the call graph
  into partitions of about equal size, minimizing cross-partition references.
- **read** Every IPA pass is split into seven hooks: generate, write and read summary;
  execute (with no access to function bodies); write and read optimization summary;
  transform. Passes communicate through **virtual clones**: bodiless call-graph nodes that
  describe how to derive a body, so later analyses compose over decisions, not rewritten IR.
- **measured** (24-core AMD) GCC: serial WPA 19 s, of which 42% is streaming and 9% analysis.
  Firefox: WPA 4m24s, of which type and declaration reading 24%, merging 20%, streaming 28%,
  analysis 8%. WPA peaks at about 4 GB on Firefox; LTRANS stays under 400 MB. **The serial
  stage is dominated by I/O of types and declarations, not by analysis.**
- **read** Balanced partitioning takes nodes in topological order toward
  `max(total_size / lto_partitions, min_partition_size)`, grows a partition past 3/4 of the
  target up to 2×, then rolls back to the best boundary-to-internal-call ratio. A `cache`
  partitioner keeps related symbols together for incremental LTO; `-flto-incremental`
  arrived in GCC 15. **read** (Jireš, FOSDEM 2025) The main incremental work was removing
  sources of partition divergence under small edits. The default of 128 partitions is
  **unverified**.
- WHOPR's origin paper (Briggs, Novillo et al., 2007) was not located: **unverified**.

## 3. MLton

`docs/mlton/` (WholeProgramOptimization, ClosureConvert, Contify, Flatten, Useless,
CompilerOverview), `code/mlton/`. Weeks, "Whole-Program Compilation in MLton", ML Workshop
2006 (slides, 209 KB, online). Cejtin, Jagannathan, Weeks, ESOP 2000, is link-only in INDEX.md
and its PDF was unreachable: paper-level details are **unverified**.

- **read** Defunctorize, monomorphise, defunctionalize, then a first-order SSA optimizer.
  A function is "a tagged record of free variables"; a call dispatches on the tag.
- **measured** Monomorphisation growth at most 30% in practice; it terminates because SML has
  no polymorphic recursion (Idris needs the explicit bound and refusal it already has).
- **measured** 0CFA over all of MLton in under 2 s, by type-based preprocessing, hash-consed
  sets with cached operations, and union-find for equality constraints.
- **measured** Self-compile SSA: 26.2k functions and 719k statements before optimization,
  1.8k and 365k after. Goal: a self-compile under 5 minutes. **read** No parallelism.

## 4. rustc

`docs/rustc-parallel/` (blog and dev-guide chapter, stored). Online: the dev guide's query,
incremental and monomorphization chapters; `compiler/rustc_monomorphize/src/partitioning.rs`.

- **read** Red-green incremental compilation: each query result gets a 128-bit stable hash;
  `try_mark_green` validates a cached result when all its dependencies are green.
  "Projection queries" are firewalls: a monolithic unhashed query feeds small hashed
  projections that can stay green.
- **read** Codegen units: one stable and one volatile CGU per source module; `#[inline]`
  items copied into each CGU that reaches them; merging by largest inlined-item overlap.
  Inputs and outputs are sorted by name and the code `bug!`s on unsorted output. Defaults: 16
  CGUs, 256 incremental.
- **measured** Parallel front end (8 threads): Cargo's front end 10.2 s → 5.9 s; real
  workloads up to 50% faster, up to 35% more memory, 0–2% slower single-threaded. The serial
  MIR-to-LLVM translation caps backend concurrency (the "staircase").
- **read** Binary identity across serial and parallel front ends is a stated invariant.
- **read** Salsa: a global revision; "backdating" keeps an unchanged output's revision (early
  cutoff); durability levels skip verification.

## 5. MLIR and LLVM threading

`docs/mlir/docs/PassManagement.md` (threading rules, lines 20–55; anchoring, 355ff),
`docs/mlir/docs/Rationale/Rationale.md` ("Multithreading the compiler", line 1033).

- **read** A pass may not inspect siblings, may not modify outside its op, holds no mutable
  global state. Pass managers anchor only on `IsolatedFromAbove` ops; nested pipelines run
  in parallel per op. Dialects must be loaded before a multithreaded pipeline starts.
- **read** MLIR can thread where LLVM cannot because types and attributes are immutable,
  uniqued and immortal, and functions are symbols, not SSA values.
- **read** `mlir/IR/Threading.h` orders *diagnostics* by element position; it does not make
  results deterministic. That stays the pass's job.
- **read** LLVM `SplitModule` partitions a module by name hash or round-robin. `ParallelCG.h`
  was unreachable: **unverified**.
- **measured** lld (20-core Xeon): clang debug link 104 s with GNU ld, 5.3 s with lld.

## 6. Build systems and content-addressed caches

Mokhov, Mitchell, Peyton Jones, "Build Systems à la Carte", ICFP 2018 (PDF about 1 MB);
Bazel remote caching; Nix RFC 0062.

- **read** A build system is a scheduler (topological, restarting, suspending) composed with a
  rebuilder (dirty bit, verifying, constructive or deep constructive traces). **Early
  cutoff**: an unchanged result stops its dependents. Constructive traces store values, which
  is what makes shared (cloud) caches possible. Deep constructive traces lose early cutoff and
  require deterministic tasks.
- **read** Bazel: an action cache keyed by action hash plus a content-addressed store; reuse
  across machines is safe only if builds are reproducible.
- **read** Nix content-addressed derivations: output paths from output content; resolving
  inputs to realized paths gives early cutoff.

## 7. Zig, Carbon, Unison

- **measured** Zig 0.14 `-fincremental` (experimental): 14 s initial check, 63 ms
  re-analysis after an edit on half a million lines. Separate codegen thread: self-build
  12.8 s → 8.6 s. 2025 devlog: many codegen threads, one Sema thread, one linker thread; the
  self-hosted x86 backend cut the compiler build 75 s → 20 s.
- **read** `code/zig/src/InternPool.zig`: per-thread `locals`, power-of-two `shards`, and
  interned indices carry the creating thread's id in their high bits. **Such indices are
  schedule-dependent and must never reach output, ordering or hashes** in a byte-identical
  design.
- **read** Carbon: data in vectors, flyweights passed around; parsing without semantic
  context; separate and parallel compilation as goals. The 10M lines/s lex+parse and 1M
  lines/s semantics targets are **unverified** (talk only).
- **read** Unison: a definition is identified by the hash of its syntax tree; names are
  metadata. How mutually recursive groups hash is **unverified**.

## 8. Swift and GHC

- **read** `docs/swift/docs/CompilerPerformance.md`: primary-file mode is quadratic in
  parsing; batch mode fixes it; whole-module mode rebuilds everything and runs AST and SIL
  phases single-threaded, only IRGen and LLVM in parallel. **read** (Swift blog 2016) After
  SIL the module is split for parallel LLVM; unchanged parts are not reprocessed.
- **read** `docs/ghc/users_guide/`: interface files carry unfoldings under a size threshold
  (750) as cross-module summaries; the recompilation checker compares per-declaration
  fingerprints because changes propagate through inlinings; byte determinism needs
  `-fobject-determinism`. **measured** `-jsem`: lens 152 s → 118 s, pandoc 788 s → 556 s.

## 9. What transfers to idris-mlir

1. **Summaries, a small serial global phase, sharded backends** (ThinLTO, WHOPR) is proven
   at Chromium scale. The guarantee-bearing facts idris-mlir needs (instance sets, closure
   sums, exclusivity, layouts) are the same kind of fact as ThinLTO's imports and
   internalization: small, global, computed without bodies.
2. **Ship each unit only its slice of the global facts**; its cache key is its own content
   hash plus its slice hash, every list sorted (`computeLTOCacheKey`).
3. **Virtual clones** (GCC) fit specialization and defunctionalization: a decision is a
   descriptor the owning unit materializes.
4. **The global phase is cheap if the representation is right** (MLton's 0CFA under 2 s) and
   expensive if it streams types and declarations (GCC's WPA). Keep summaries flat and tiny.
5. **Early cutoff at projections** (rustc firewalls, salsa backdating, Nix CA): a monolithic
   global fact feeds small hashed per-unit projections.
6. **Determinism is designed in, not tested in**: sort at every hand-off (rustc), remove
   partition drift (GCC 15), never let thread-tagged ids escape (Zig), order results, not
   just diagnostics (MLIR).
7. **Partition stability under edits** decides cache hit rates (GCC `cache`, rustc stable
   and volatile CGUs).

## 10. Snapshots (fetched 2026-10-10)

Approved by the owner and fetched on 2026-10-10; provenance in each folder's `README.md` or
`SNAPSHOT.md` and in `sources/README.md` (access record, "Sharded-compilation pass").

| Folder | Source | Size | Status |
| --- | --- | --- | --- |
| `papers/johnson-2017-thinlto/` | https://storage.googleapis.com/gweb-research2023-media/pubtools/4743.pdf | 2.2 MB | stored: PDF, `papers/johnson-2017-thinlto/paper.pdf` |
| `papers/glek-2010-gcc-lto/` | arXiv 1010.2196 (TeX e-print preferred) | 182 KB PDF | stored: TeX (arXiv e-print), `papers/glek-2010-gcc-lto/` |
| `papers/mokhov-2018-build-systems/` | https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems-a-la-carte.pdf | about 1 MB | stored: PDF, `papers/mokhov-2018-build-systems/paper.pdf` |
| `papers/weeks-2006-mlton-whole-program/` | MLton repository, `doc/guide/src/References.attachments/060916-mlton.pdf` | 209 KB | stored: PDF slides at the library's MLton pin `aa2fd1ad`, `papers/weeks-2006-mlton-whole-program/slides.pdf` |
| `docs/rustc-dev-guide/` (addendum) | query, incremental-in-detail, backend/monomorph chapters | small | stored as a new snapshot, not an addendum (`docs/rustc-parallel/` records no revision): `docs/rustc-dev-guide/` at `20a4fdd7`, 4 chapters |
| `docs/llvm/` (addendum) | clang `ThinLTO.html` | small | stored: `docs/llvm/clang/docs/ThinLTO.md` at the LLVM pin (the source of `ThinLTO.html`; `ThinLTO.rst` no longer exists), addendum `docs/llvm/SNAPSHOT.sharded-compilation.md` |
| `docs/gcc-lto/` | Optimize-Options LTO section; `lto-partition.cc` at a pinned revision | small | stored: `docs/gcc-lto/` at `575b8ec6`, `gcc/lto/lto-partition.cc` and the `-flto` excerpt of `gcc/doc/invoke.texi` |
