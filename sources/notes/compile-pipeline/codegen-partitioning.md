# Code generation partitioning across compilers

Research report of 2026-10-14 for the pipeline cutover proposal, written by a research agent from read-only reading, kept verbatim. Paths are as the report gives them: `M/` and `L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`, Modular paths are relative to `~/Documents/modular` at 9211931, MLton paths are under `code/mlton/` here or the fetch named in it. Claims marked recalled or inferred are not read from source.

---

# How other compilers split code generation, and which codegen unit idris-mlir should use

Most of this comes from vendored sources, cited as file:line. Four gaps:
- **Swift and Zig:** `sources/code/swift` holds only SIL and SILOptimizer, and `sources/code/zig` holds only `InternPool.zig` and a few other files. I fetched Swift's IRGen and Zig's link/codegen code from upstream at the pinned tags; those line numbers are approximate.
- **GHC and Lean compilers:** not vendored, so those parts are from memory, marked **recalled**.
- **`ParallelCG.cpp`:** not in the pinned LLVM 24 tree at all.
- **The ThinLTO PDF:** there is no PDF tool on this machine, so its figures come from `sources/notes/sharded-compilation/whole-program-at-scale.md` §1 plus the LLVM source.

## 1. LLVM: `SplitModule` and split codegen

**What `SplitModule` does.** The function is `llvm::SplitModule(M, N, cb, PreserveLocals=false, RoundRobin=false)` (`llvm/include/llvm/Transforms/Utils/SplitModule.h:39-42`, defined in `llvm/lib/Transforms/Utils/SplitModule.cpp:226`).

- **Promotion of locals.** With `PreserveLocals=false`, every local function, global, alias and ifunc is made external first (`SplitModule.cpp:230-239`). `GlobalValue::externalize()` gives it external linkage, hidden visibility, and a name if it had none (`GlobalValue.h:573-579`). Names are not changed.
- **What stays together.** `findPartitions` (`:114-203`) joins symbols into clusters with union-find:
  - members of a comdat that contains locals (`:134-140`);
  - an alias or ifunc with its target or resolver (`:144-146`);
  - a function whose block address is used, with the users of that address (`:148-155`);
  - every local-linkage symbol with all of its users (`:157-158`), so no local ever has to be promoted.
- **How clusters are placed.** Each cluster goes to the currently least-loaded of N bins, where load is the *number of symbols*, not their size (`:168-202`). The comment says clusters are sorted by size (`:175-176`), but the loop just walks them in `EquivalenceClasses` insertion order. That order is deterministic, but it is not largest-first.
- **Everything else** goes by the low 16 bits of MD5(name or comdat name) mod N (`:206-224`). The alternative, `RoundRobin`, deals unclustered external functions out by count (`:251-279`).
- **Building the parts.** It calls `CloneModule` N times with a predicate. Symbols that are not selected become external declarations (`CloneModule.cpp:90-165`), and module inline asm stays only in part 0 (`:293-294`). It clones the whole module even for the last part (FIXME at `:281-283`).
- **A known gap.** The header admits that internal symbols are not protected from colliding with symbols defined outside the module (`SplitModule.h:32-38`).

**Who calls it.** `ParallelCG.cpp` does not exist in the pinned tree. The regular-LTO version lives in `llvm/lib/LTO/LTOBackend.cpp:517-570`:
- It makes a thread pool of N threads.
- On the main thread it writes each part to bitcode, and a worker parses it into a fresh `LTOLLVMContext` with its own `TargetMachine`. This is done because a context cannot be shared across threads (`:528-548`).
- It tries the target's `TM->splitModule` hook first. Only AMDGPU implements it: a cost-based splitter that weighs functions by TTI code size and may copy callees into several parts (`AMDGPUSplitModule.cpp:9-24, 173-190`). Otherwise it falls back to `SplitModule(..., PreserveLocals=false)` (`:559-563`).

`lto::backend` runs the whole-module `opt` serially and only then calls `codegen` or `splitCodeGen` (`:603-622`). So regular LTO is a serial optimizer followed by parallel codegen. The legacy `LTOCodeGenerator::compileOptimized` now restores external linkage "to increase scope for splitting" and then calls the same `backend` (`LTOCodeGenerator.cpp:637-655`). **Recalled:** the old `ParallelCG.cpp` did the same thing (SplitModule plus a bitcode round-trip per thread).

**How lld uses it.**
- ELF has `--lto-partitions=` (`lld/ELF/Options.td:653-654`), default 1 (`Driver.cpp:1515`), passed as the parallelism level (`ELF/LTO.cpp:207-212`).
- COFF has `/opt:lldltopartition` (`COFF/Driver.cpp:2084`).
- Mach-O builds `lto::LTO` without a level (`lld/MachO/LTO.cpp:124`), so it is always 1. On our macOS target there is no split codegen through lld.
- ThinLTO does not use SplitModule. Its parallelism is one backend per input module (`ELF/LTO.cpp:195-198`).

**Determinism.** The output is deterministic for a fixed input module and a fixed N. But LTO uses the same number for threads and parts (`LTOBackend.cpp:521-522, 562`), so the set of object files changes with the thread count. Placing symbols by name hash is stable per symbol under edits, but it balances by count, not size.

**Can we use it after we have the one whole-program module?** Yes, as a stopgap. Today `toObject` internalizes everything except `main`, runs O3, then does one codegen (`foreign/idr/lib/Driver/Run.cpp:186-198`). After O3 we could call SplitModule with a **fixed N**, give each part its own context, and link N objects. Very little is lost:
- After O3, LLVM codegen is per function. The only passes that look across functions are IPRA, the machine outliner and global merging, all minor.
- Our program links already use `--icf=all` (`CMakeLists.txt:174, 213`) with function sections on (`Optimize.cpp:30`), so identical code is still folded across objects.

The catches:
- Externalized internal symbols must not collide with libc symbols in a static link, so they need a reserved name prefix.
- Balancing by symbol count is crude.
- Cloning the module N times and writing bitcode are serial on the main thread.
- O3 itself stays serial, and it may well be the larger cost. S2 is meant to measure that.

The partitioning logic is only about 40 lines. Writing our own predicate is cleaner than taking SplitModule's.

## 2. GCC WHOPR

WHOPR has three stages: per-file summary generation, serial whole-program analysis (WPA) on summaries only, and parallel local transformation (LTRANS) per partition (`hubicka-arxiv.tex:271-300`). Inlining and cloning decisions are made in WPA as "virtual clones" with no bodies, and LTRANS turns them into real functions (`:407-420`). Partitioners are in `sources/docs/gcc-lto/gcc/lto/lto-partition.cc`:

- **`balanced`** (the default, invoke.texi excerpt `:243`), at `:1198`:
  - Functions are taken in a fixed order (`tp_first_run`, then source order, `:1239`).
  - Target size is `max(total/n, min_partition_size)`.
  - Below 7/8 of the target it accepts anything. After that it tracks the best ratio of internal edges to boundary edges (weighted by call frequency, `:1365-1460`). Past 9/8 of the target, or the maximum size, it rolls back to the best cut (`:1468-1520`).
  - The comment still says 3/4 and 2× (`:1190-1193`); the code says 7/8 and 9/8.
  - Target size is recomputed after each partition. The pass is linear in the call graph.
- **`one`** puts everything in one partition; **`max`** puts each symbol in its own partition (`:500-518`, testing only); **`1to1`** follows the source files (`:420`).
- **`cache`** (`:1099-1157`) keeps source files together "to minimize propagation of divergence":
  - First it splits into a fixed number of groups by file count, deliberately ignoring size.
  - Then it breaks up files that are too large and halves the rest until it reaches the target (`:1046-1097`).
  - It exists for `-flto-incremental`.

**What crosses partitions.**
- Inline clones and "duplicate" symbols are copied into each partition that uses them (`:134-158, 204-213`).
- Read-only variables whose initializers can be folded have their references followed (`:144-157`).
- Statics that are referenced from another partition are promoted to hidden, renamed `name.lto_priv.N` with a per-name counter, and marked prevailing (`:1806-1898, 1998-2057`).

**Measured** (24-core AMD, `hubicka-arxiv.tex:998-1072`):

| Build | Serial LTO link | WHOPR link | WPA | Parallel non-LTO build |
| --- | --- | --- | --- | --- |
| GCC | 6m31s | 48 s | 19 s | 56 s |
| Firefox | 19m29s | 5m30s | 4m24s | 9m38s |

- The WPA time goes to I/O, not analysis: for GCC, reading declarations and types is 28% and streaming 42%, against 9% for IPA. For Firefox it is 24%, 20% (merging) and 28%, against 8% for IPA.
- Memory: WPA peaks around 4 GB on Firefox; LTRANS stays under 400 MB (`:1116-1121`).
- The authors expect more than 24 workers to gain little because the serial WPA dominates (`:1555-1558`).

## 3. ThinLTO

- **Summaries.** Each function's summary holds its linkage, instruction count, hotness, flags, and every call and reference. Summaries add about 0.8% to IR size (notes §1).
- **The import decision** is made at the thin link by walking call chains (`FunctionImport.cpp:86-121`): instruction limit 100, multiplied by 0.7 per level; hot call sites ×10, critical ×100, cold ×0.
- **Imported bodies** become `available_externally` (`FunctionImportUtils.cpp:190-237`). Promoted locals are renamed `name.llvm.<64-bit module hash>` (`ModuleSummaryIndex.h:1958-1968`). The thin link also does internalization, prevailing-copy resolution and dead-symbol removal (`LTOBackend.cpp` `dropDeadSymbols`).
- **Why it scales.** The only serial step reads no IR. The backends are independent, and each is cached by a key built from sorted import and export lists.
- **Measured** (notes §1): Chromium ThinLTO takes 3m18s against 28m18s for full LTO. An incremental rebuild takes 25 s against 17m11s. Halving the import threshold cost 5% on povray and 6.7% on milc.

**What applies to us.** We already make the global decisions: inlining (`idr-inline`), whole-program internalization, dead code. The parts worth taking are:
- `available_externally` imports. The runtime already enters our module this way (`Run.cpp:186-190`), and every unit could take it the same way.
- Content-derived names for promoted symbols.
- Sorted cache keys.

Running LLVM's own summary-based importer would compute a second inlining analysis next to `idr-inline`, which the repository's one-representation rule forbids.

## 4. Rust codegen units (recalled, except where cited)

The dev guide (`sources/docs/rustc-dev-guide/src/backend/monomorph.md:58-73`) and the `partitioning.rs` module docs (fetched) say:
- Each source module gets two CGUs: a "stable" one for non-generic code and a "volatile" one for monomorphized instances. The reason is that adding a reference to a generic function creates a new instance, and that should not invalidate the module's other code.
- Only `#[inline]` items are copied into the CGUs that use them.
- The steps are `place_mono_items`, `merge_codegen_units` (which uses `compute_inlined_overlap`), and `internalize_symbols`.

Recalled:
- Defaults are 16 CGUs, or 256 in incremental builds (also in the notes §4).
- Merging prefers pairs of CGUs that share the most inlined items, plus, outside incremental builds, a minimum CGU size.
- Merged CGUs are named by hashing their sorted names. Output must be sorted, and the code calls `bug!` if it is not.
- At opt-level 0, `#[inline]` items are not copied.
- With more than one CGU at opt-level above 0, rustc runs "thin local LTO" across the crate's own CGUs to win back cross-CGU inlining.
- MIR-to-LLVM translation happens on the main thread, which caps how many LLVM workers are busy (the "staircase"). Large CGUs are started first.

The trade-off is the one the module docs state: bigger CGUs let LLVM optimize better, smaller ones make incremental rebuilds cheaper.

## 5. Swift whole-module optimization with `-num-threads`

- `CompilerPerformance.md:184-189, 239-242`: the AST and SIL phases never run multithreaded; IRGen and LLVM do.
- `lib/IRGen/IRGen.cpp` at `swift-6.4.0-RELEASE` (fetched; approximate lines ~1767-2030), `performParallelIRGeneration`:
  - One `IRGenerator` over the whole SIL module.
  - One `IRGenModule`, with its own LLVM context and target machine, **per source file**.
  - Things emitted once for the whole module go through the shared generator or the "primary" module: protocols, conformances, metadata records, vtable stubs.
  - Then a linkage fix-up: `linkonce_odr` symbols referenced from another file's module become `weak_odr`.
  - `LLVMCodeGenThreads` with `NumThreads-1` extra threads pull modules from a queue; the main thread is worker 0.
- So the number of modules equals the number of files, not threads.
- What is whole-module: type checking, SIL optimization (all cross-file inlining and specialization), and lazy emission of shared definitions. What is split: LLVM optimization and codegen.

## 6. Zig

All Zig citations below are from 0.15.2 sources fetched online.

- `Zcu/PerThread.zig` (`runCodegen`): codegen "is self-contained/pure". With a self-hosted backend, AIR becomes MIR on worker threads.
- `link.zig`: the result is handed over through `SharedMir` (pending, ready or failed) to the **single linker thread**. The link task is queued at the same moment as the codegen job "to ensure that the linker receives functions in a deterministic order". The queue limits how much AIR is in flight.
- Unit of partition: the single function.
- The LLVM backend is different: `assert(pt.tid == .main); // LLVM has a lot of shared state`, and it produces one LLVM module, so one object, per compilation unit. LLVM's optimizer and codegen then run on that one module serially (recalled).
- Measured (notes §7): the self-hosted x86 backend cut the compiler build from 75 s to 20 s; a separate codegen thread took a self-build from 12.8 s to 8.6 s.

## 7. GHC and Lean 4

**GHC.** Compilation is separate per module. Cross-module inlining goes through interface unfoldings:
- Unfoldings larger than `-funfolding-creation-threshold=750` are not written to the interface; call sites inline below `-funfolding-use-threshold=80` (`users_guide/using-optimisation.html:1826-1898`).
- Each simplifier run stops at a fixpoint or after `-fmax-simplifier-iterations=4` (`:999-1003`; `commentary-compiler-core-to-core-pipeline.md:85`), in 2 phases by default.
- `-fsimpl-tick-factor=100` bounds the total work.
- **Recalled:** the occurrence analyser picks loop breakers in each recursive group and never inlines them, which is what guarantees termination.
- One object per module. Measured `-jsem` (notes §8): lens 152→118 s, pandoc 788→556 s.

**Lean 4 (recalled).** Each module becomes one C file. Lake compiles them in parallel in import order. `@[inline]` and `@[specialize]` bodies stored in `.olean` files are copied into importing modules. Every other call is an external call to a deterministically mangled name.

## 8. Comparison

| System | Unit of partition | What stays whole-program | Cross-unit optimization | Determinism | Measured |
|---|---|---|---|---|---|
| LLVM regular LTO with split codegen | name hash or symbol count, N = threads | the entire `opt` run | none needed after opt (codegen only) | fixed for given N; objects change with N | none in tree |
| GCC WHOPR | size-balanced intervals with best cut; `cache` follows files | IPA on summaries (inlining, cloning) | WPA decisions, inline clones copied in | sorted order, `lto_priv.N` counters | GCC 6m31s→48 s; Firefox 19m29s→5m30s (24 cores) |
| ThinLTO | input module | thin link (imports, internalization, dead code) | `available_externally` imports | sorted cache keys, `.llvm.<hash>` names | Chromium 28m→3m18s; incremental 17m→25 s |
| rustc | 2 CGUs per module, merged to 16/256 | monomorphization, collection | `#[inline]` copies, thin local LTO | sorted, hashed names | none in sources |
| Swift WMO | source file | AST, SIL optimization | done at SIL; `weak_odr` shared definitions | file order | none in sources |
| Zig (self-hosted) | function | Sema, linking (1 thread each) | none (debug-oriented) | link queue order | 75→20 s compiler build |
| GHC, Lean | module | none (module DAG) | interface unfoldings / `.olean` inline and specialize | GHC needs `-fobject-determinism` | `-jsem` 22-29% |

## 9. For idris-mlir

**The strongest case for each candidate:**

- **SCC.** It is the smallest unit closed under mutual recursion, so tail loops, contification, loop breakers and LLVM's per-SCC attribute inference all stay inside one unit. With 93% singletons it is as edit-stable and cacheable as a unit can be, and it can be named by hashing its sorted members. That is why proposal 0006 already uses SCCs for *simplify* units (§3.4). As a codegen unit it is far too fine: about 54k LLVM modules, each with its own context, target machine, pass setup and object file, plus a link with tens of thousands of inputs.
- **Idris module.** It matches how people edit, it is rustc's and GCC `1to1`'s choice, and the names come for free. But only 17% of direct calls stay inside a module. Monomorphized instances have no single home (rustc's volatile-CGU problem). And instance counts are heavily skewed toward Prelude and base, so modules are badly unbalanced.
- **Size-balanced bins of SCCs.** It is the only one of the three that controls load balance and per-unit overhead, it never splits an SCC, and it can be made deterministic and edit-stable. GCC's partitioners and rustc's CGU merging both land here.

**My choice: size-balanced bins of SCCs.** This agrees with 0006's D4, with these properties:

1. **The bin count does not depend on P.** The target is a fixed estimated size (TTI code size, or the `idr` op count), so the objects and the executable are the same for every worker count. This is unlike LTO's N = threads. Aim for several bins per core (over-decomposition) and start the largest bins first (rustc, recalled).
2. **Edit-stable cuts.** Group by top-level namespace first, which keeps 49% of calls together. Inside a group, order SCCs by content hash and cut where the hash meets a boundary condition, within minimum and maximum sizes. GCC's `cache` partitioner fights the same divergence by splitting on group count before size. GCC `balanced` cuts at a running size total, so one edit shifts every later cut. A single function too large for a bin becomes a unit of its own. (The 0006 §2 figure of 174 for the largest SCC is the direct-call graph before inlining; 24 after inlining is well under any bin size.)
3. **Linking between units:**
   - Each definition lives in exactly one unit.
   - A symbol referenced from another unit gets external linkage, hidden visibility, `dso_local`, and its content-derived name under a reserved prefix. That avoids the static-link collision SplitModule's FIXME warns about, and needs no module-hash suffix or counter.
   - Symbols used only inside their unit become internal (rustc's `internalize_symbols`). LLVM's own internal symbols (`.str.N`, constant pools) are local to the unit and deterministic because the unit's contents are.
   - The runtime goes into every unit as `available_externally`, as it does today.
   - Objects are linked in unit-name order. `--icf=all` recovers the cross-unit merging that per-unit MergeFunctions would miss.
4. **Do it in two steps.**
   - **S2 now:** keep the serial whole-module O3, then split only codegen, with a fixed bin count and our own size-based predicate (SplitModule's clone loop is fine to reuse). This loses almost nothing, because codegen is per function.
   - **Phase 3:** move the split before O3, one context per unit. The interprocedural facts LLVM would lose across units should be emitted from our global analyses as attributes on cross-unit declarations: memory effects and nounwind/willreturn from `idr-effects`, noalias/readonly from exclusivity and borrows, nonnull/dereferenceable from layouts. That replaces LLVM's per-module IPO without running a second inliner.
