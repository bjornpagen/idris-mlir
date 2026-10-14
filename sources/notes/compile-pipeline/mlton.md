# MLton: pipeline, closure conversion, inlining, chunks

Research report of 2026-10-14 for the pipeline cutover proposal, written by a research agent from read-only reading, kept verbatim. Paths are as the report gives them: `M/` and `L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`, Modular paths are relative to `~/Documents/modular` at 9211931, MLton paths are under `code/mlton/` here or the fetch named in it. Claims marked recalled or inferred are not read from source.

---

I read the vendored MLton passes, the guide pages, both sharded-compilation notes and the Weeks 2006 slides. I also read the Futhark defunctionalisation paper (Hovgaard 2018) as a counterpoint. I did not use the Danvy and Huang papers.

**One caveat on sources:** the files that define the pipeline are not in the repo. That includes the SSA pass list, the top-level driver, chunkify, the C and LLVM codegens and the control flags. I fetched them from GitHub at the same pinned revision (`aa2fd1ad`) into `/tmp/mlton-aa2fd1ad-fetch/`. That copy is not stored in the library, and adding it to `sources/code/mlton/` would need your approval.

Citation prefixes:
- **V:** vendored, `sources/code/mlton/mlton/`
- **U:** upstream at the pin, in `/tmp/mlton-aa2fd1ad-fetch/`
- **G:** guide pages, `sources/docs/mlton/doc/guide/src/`
- **S#n:** slide n of `sources/papers/weeks-2006-mlton-whole-program/slides.pdf`

Claims I recalled or inferred are marked **[inferred]**.

---

## 1. Pipeline and pass lists

**Top-level order** (U:`main/compile.fun`):
- parseAndElaborate → `deadCode` on CoreML → `defunctorize` → XML (329–381)
- `xmlSimplify` (449–455) → `monomorphise` → SXML (463–467) → `sxmlSimplify` (475–481)
- `closureConvert` → SSA (489–493) → `ssaSimplify` (501–507)
- `toSsa2` (515–519) → `ssa2Simplify` (527–533)
- `toRssa` (552–556) → `rssaSimplify` (565–571)
- `backend` → Machine (578–582) → `machineSimplify` (592–599)
- codegen (610–622)

The guide lists a "CoreMLSimplify" step (G:`CompilerOverview.adoc:15`). The only CoreML pass in source is `deadCode`.

**Pass lists, in order:**
- **XML:** `xmlShrink`, `xmlSimplifyTypes` (U:`xml/xml-simplify.fun:22–25`).
- **SXML:** `sxmlShrink1`, `implementSuffix`, `sxmlShrink2`, `implementExceptions`, `sxmlShrink3`, `polyvariance`, `sxmlShrink4` (U:`xml/sxml-simplify.fun:31–41`).
- **SSA:** 44 entries, 37 enabled (U:`ssa/simplify.fun:46–122`), plus `ssaOrderFunctions` appended (291–294).
  - Enabled order: removeUnused1, introduceLoops1, loopInvariant1, inlineLeaf1, inlineLeaf2, contify1, localFlatten1, constantPropagation, splitTypes1, useless, removeUnused2, duplicateGlobals2, splitTypes2, simplifyTypes, polyEqual, polyHash, introduceLoops2, loopInvariant2, contify2, inlineNonRecursive, localFlatten2, removeUnused3, contify3, introduceLoops3, loopInvariant3, localRef, flatten, localFlatten3, combineConversions, commonArg, commonSubexp1, commonBlock, shareZeroVec, redundantTests, redundant, knownCase2, removeUnused4.
  - Disabled (`execute = false`): duplicateGlobals1, loopUnroll1/2, loopUnswitch1/2, knownCase1, commonSubexp2.
  - Times each runs: removeUnused 4; contify, introduceLoops, loopInvariant and localFlatten 3 each; inlineLeaf 2 (sizes 20, then 40); splitTypes 2; everything else once.
- **SSA2:** `deepFlatten`, `refFlatten`, `removeUnused5`; `zone` is off (U:`ssa/simplify2.fun:26–31`).
- **RSSA:** shrink, three collectStatics, insertChecks, shrink, bounceVars, implementHandlers, shrink, implementProfiling, orderFunctions; `rssaShuffle` is off (U:`backend/rssa-simplify.fun:18–38`).
- **Machine:** only `machineShuffle`, and it is off (V:`backend/machine.fun:1753–1761`).

**It is a fixed sequence, never "until nothing changes".** `Control.simplifyPasses` is one `List.fold` over the list, so each entry runs once (U:`control/control.sml:497–508`). A pass with `execute = false` is skipped (462–495).

The only repetition anywhere is bounded or monotone:
- `polyvariance` loops exactly `rounds` times, default 2 (U:`xml/polyvariance.fun:433–466`; U:`control/control-flags.sml:1343–1348`).
- The analyses (0CFA, contify's dominators, useless) are monotone worklist fixpoints inside one pass. Nothing ever repeats a transformation to a fixpoint.

The guide still documents a `-loop-passes` option (G:`SSASimplify.adoc:51`). `main.fun` at the pin has no such option, only `-ssa-passes` (U:`main/main.fun:868`) and `-disable-pass` (397). So that page is stale **[inferred]**.

The SSA verifier runs at the start and end of the optimizer. Running it after every pass (`-type-check true`) slows the optimizer by 50% (S#17).

## 2. From higher-order to first-order

**Defunctorize** duplicates each functor at every use (S#11).

**Monomorphise** keeps, for every polymorphic binding, a hash table keyed by the vector of type arguments (U:`xml/monomorphise.fun:42–67`). It emits one copy per distinct instantiation, for both `PolyVal` and `Fun` (353–418). There is no budget. Termination relies on SML having no polymorphic recursion; the worst growth seen was 30% (S#12).

**Polyvariance**, on SXML before closure conversion, is the one budgeted duplication:
- It copies a let-bound function at each reference if `(numOcc−1)·(size−small) ≤ product` (U:`xml/polyvariance.fun:91–99`).
- It only considers higher-order functions (`hofo`, line 106).
- Defaults: `small = 30`, `product = 300`, 2 rounds (control-flags.sml:1343–1348).
- The slides' reason: "Prior code duplication helps speed and precision" of 0CFA (S#14).

**0CFA** is one walk over SXML that generates constraints (V:`closure-convert/closure-convert.fun:246–391`):
- At an `App`, it adds a handler to the function value's lambda node. Each lambda that arrives coerces the argument into the formal parameter and the body's result into the call's result (311–325).
- A lambda node is a disjoint-set cell holding a set, its handlers and its outgoing edges (V:`closure-convert/abstract-value.fun:59–61`).
- `send` propagates only the difference between sets (87–95). `coerce` adds an inclusion edge (105–115). `unify` merges two cells (123–148).

The speed tricks (S#14: under 2 s on MLton itself, cubic in theory):
- **First-order values carry no flow.** Every first-order type gets one shared abstract value (abstract-value.fun:242–246), and first-order tuples are not tracked (closure-convert.fun:364–367).
- **Sets are hash-consed with cached operations:** `UniqueSet`, cacheSize 5, 13 bits (abstract-value.fun:42–44).
- **Mutable containers unify instead of coerce** (341–345), so union-find handles all equality constraints.

**Representation of closures:**
- Each distinct lambda set gets its own new datatype. It has one constructor per lambda, carrying the tuple of that lambda's free variables (closure-convert.fun:499–546).
- Each lambda becomes exactly one top-level SSA function.
- A call becomes `apply`: a `case` over the set's constructors, where each arm calls that lambda's function with its environment and the coerced argument (676–708).
- Where a value flows between two different sets, the coercion is a `case` that re-tags it (596–644).

**Correctness does not depend on inlining.** `closureConvert` is a translation pass that produces complete first-order SSA. The minimal SSA pipeline is only `polyEqual` and `polyHash`, which "cannot be omitted" because they implement primitives (U:`ssa/simplify.fun:124–129`). The minimal SXML pipeline has no polyvariance (sxml-simplify.fun:51–54). So `-ssa-passes minimal` produces a correct program with no inlining, contification or flattening. Closure conversion is exact from the analysis alone.

**Large closure sets:** there is no cap, no refusal and no boxed fallback. A large set compiles to a `case` with one arm per lambda. The slides say "almost no calls require case dispatch" (S#14).

## 3. The inliner and contification

**Size metric** (V:`ssa/ssa-tree.fun`):
- Expressions (294–301): `ConApp`, `PrimApp` and `Tuple` cost 1 + number of arguments; `Select` costs 2; `Const`, `Var` and `Profile` cost 0.
- Transfers (573–580): 1 + number of arguments, or 1 + number of cases for `Case`.
- Function size is the sum over its blocks. `sizeMax` stops counting as soon as the budget is exceeded (854–874, 1000–1013).

**Leaf inlining** runs twice, with budgets 20 and 40 (U:`control-flags.sml:1011–1032`; simplify.fun:50–53):
- It walks the call graph's SCCs bottom-up.
- A function alone in its SCC is inlinable if its size is within budget, counting each call to an already-inlinable callee at that callee's inlined size (V:`ssa/inline.fun:146–190`).
- With the default `loops = true` it picks the "NoLoop" variants, which refuse functions that contain a loop (inline.fun:87–92, 214, 493–497).

**Non-recursive inlining** runs once:
- A function is inlined if it does not call itself, is alone in its SCC, and `(numCalls−1)·(size−small) ≤ product` (inline.fun:271–295, 321–327). Its size already includes the callees that will be inlined into it.
- Defaults: `small = 60`, `product = 320` (control-flags.sml:1034–1041). `-inline n` sets `small` (U:`main/main.fun:480–482`).

**How growth stays bounded:**
- **The decision is per function, not per call site.** Every call to the function is inlined and the original is deleted (inline.fun:465–476). The "−1" in the formula is that deleted original, so a function called once always inlines, whatever its size, at zero growth.
- **Nesting is resolved in one pass.** Inlining recurses into the callee's own blocks (402). This terminates because only non-recursive functions qualify.
- **Cleanup is local.** Each function is shrunk once afterwards (444–462).
- **Measured:** in the self-compile the inline pass took statements from 341k to 491k (+44%) while functions went from 7.7k to 1.8k (S#26).
- Loop unrolling and unswitching have limits (150 and 300; control-flags.sml:1213–1218) but are off by default.

**Contification** follows Fluet and Weeks, ICFP 2001 (V:`ssa/contify.fun:9–12`):
- Each function gets a return analysis: Uncalled, Unknown, a continuation, or a function (32–51).
- It builds a graph from a root, the tail calls, and the continuations of non-tail calls, and computes its dominator tree. A function's return point is its ancestor directly under the root (298–313, 417–460).
- A function that always returns to the same place becomes a block inside its caller.

Why it matters for loops: it "exposes control-flow information that is required by... traditional loop optimizations" (G:`Contify.adoc:8–11`). That is why it is interleaved with introduceLoops and loopInvariant (simplify.fun:48–54, 82–97), and how a list fold becomes a loop (S#24). It moves bodies rather than copying them. In the self-compile it cut functions from 18.5k to 7.7k while statements fell from 555k to 536k (S#26).

## 4. Code generation and chunks

**What a chunk is.** A Machine program is a list of chunks, each a vector of blocks (V:`backend/machine.fun:898–935`). Transfers are `Call`, `Goto`, `Return`, `Raise`, `Switch` and `CCall` (599–614). A chunk is compiled as one C or LLVM function containing blocks from possibly many SML functions. SML calls never use the C stack: stack slots are offsets from `StackTop` (U:`include/c-chunk.h:37`). So chunk boundaries only control the size of the C functions handed to the C compiler.

**How chunks are formed** (U:`control-flags.sml:130–140`; U:`backend/chunkify.fun`):
- **`One`:** everything in a single chunk (16–26).
- **`Func`:** one chunk per function (28–37).
- **`Coalesce{limit}`** (54–178):
  - Blocks linked by goto, switch or a C-call return start in the same class (70–97). A class is never split.
  - It adds edges from each call site to its callee, and from each return to the places it returns to (101–125).
  - It coarsens the graph up to `maxClassSize = limit` (126–129). Size is statements + 1 per transfer, or + number of cases for a switch (40–50).
- **`Simple`:** groups by call-graph SCC, and pulls a function into a chunk when all its call sites are there (190–431).

**Defaults.** The control default is `Coalesce 4096` (control-flags.sml:202–204). `main.fun` overrides it by codegen: the native amd64/x86 codegens get `Func`, C and LLVM get `Coalesce 4096` (U:`main/main.fun:1213–1222`). The default codegen is amd64, else x86, else C (1094–1109). So arm64 macOS would default to C with coalesce4096 **[inferred]**.

**Calls between chunks:**
- Each chunk function takes `(gcState, stackTop, frontier, nextBlock)` and opens with `switch (nextBlock)` over its entry labels (U:`codegen/c-codegen/c-codegen.fun:1691–1726`). A computed-goto jump table is an option, off by default.
- To leave a chunk, it writes `frontier` and `stackTop` back to memory and returns `nextBlock` (1191–1209).
- The trampoline then loops on `nextBlock = nextChunks[nextBlock](...)` (U:`include/c-main.h:33–37`). The `nextChunks` table maps every entry label to its chunk (c-codegen.fun:1773–1790).
- A return checks whether its target is in the same chunk and jumps straight there if so (1211–1257).
- `chunkTailCall` replaces the trampoline with a direct call, `musttail` under LLVM (U:`codegen/llvm-codegen/llvm-codegen.fun:1395–1420`). It is off by default.
- **Cost [inferred]:** a call inside a chunk is a stored return label and a goto. A call across chunks spills two registers, returns to the trampoline, and pays an indirect call plus a switch. The C compiler also cannot keep values in registers across the boundary.

**Output files, and no parallelism:**
- Chunks are batched into C files of about `chunkBatch = 2^15` statements each (control-flags.sml:125–127; c-codegen.fun:1739–1770). One more file holds `main` and the `nextChunks` table (1772–1797). The LLVM codegen batches the same way (llvm-codegen.fun:2000–2029).
- `compileCSO` compiles these files with a `List.fold` that calls `System.system` on each in turn, **serially** (main.fun:1475–1494, 1546–1574).
- So MLton splits output to keep each C function and file a manageable size, not to compile in parallel. With `-stop g` a user could compile the files in parallel outside MLton **[inferred]**.

## 5. Compile-time numbers

From the slides:
- **Goals:** programs over 100k lines; a self-compile under 5 minutes (S#3). The compiler itself is 145k lines (S#2).
- **0CFA:** under 2 s on MLton itself (S#14).
- **Overall:** "compile a 100k line program in minutes with 1G RAM" (S#31). The stated drawbacks are compile time, memory and executable size (S#10).

SSA during the self-compile (S#26):

| After pass | Functions | Statements | Size |
|---|---|---|---|
| start | 26.2k | 719k | 101 MB |
| leaf inline | 18.5k | 555k | 72 MB |
| contification | 7.7k | 536k | 68 MB |
| const prop | 7.7k | 341k | 50 MB |
| inline | 1.8k | 491k | 58 MB |
| flatten | 1.8k | 387k | 53 MB |
| local opts | 1.8k | 365k | 52 MB |

The program ends at half its starting size and never exceeds it.

**Which passes dominate is not in the stored sources.** MLton prints each pass's time and GC time in verbose mode (U:`control/control.sml:90–102`), so a breakdown has to be measured. `whole-program-at-scale.md:74–81` agrees on the numbers above and records "No parallelism".

## 6. What this means for idris-mlir

**For an analysis-exact, budgeted, fixed-sequence pipeline:**
1. **Defunctionalization can be total by analysis alone.** MLton's minimal pipeline proves inlining is optional for correctness. Today, idris-mlir's defunctionalize refuses when closures remain unresolved after the label analysis (`foreign/idr/lib/Transforms/Defunctionalize/Pass.cpp:88–101`). That is the dependency to break: unresolved closures should become sums plus dispatch, refused only when a set is truly unbounded.
2. **A fixed order works.** Thirty-seven single-shot passes take 719k statements to 365k. Each pass stays small because the shrinker does the local cleanup after it (S#19–20).
3. **Growth is a formula applied once.** Decisions are per function, bottom-up over SCCs, with recursive SCCs excluded and the original deleted. Your measured problem (471k → 1.25M ops, 16 rounds without converging) is exactly what this rules out.
4. **Contification gives loops without code growth**, and should come before the growth-budgeted inlining.
5. **Partitioning comes after optimization and is independent of it**, with bounded unit size.
6. **The CFA is cheap** when first-order values are pruned by type, sets are hash-consed, mutable cells unify, and only differences are propagated.

**Against, or limits:**
1. **MLton is entirely serial**, including the C compile. It shows bounded units, not a parallel baseline; the parallel part is yours to build.
2. **The trampoline exists because C cannot guarantee tail calls** and MLton keeps its own stack **[inferred]**. With LLVM `musttail`/`tailcc`, idris-mlir's partitions can be ordinary functions, so a partition is a module split rather than a function-merging device.
3. **Called-once inlining is unbounded per function.** MLton has a `maxFunctionSize` control (control-flags.sml:1224–1226) but no code I read uses it. A parallel backend needs a per-function cap that MLton lacks, or 152k-op functions remain possible.
4. **A fixed order needs hand-tuned phase ordering.** You can see the cost in the ordering comments at simplify.fun:59–62, 72–81, 84–87, 105–113.
5. **Monomorphisation termination relied on SML's restrictions.** Idris needs the explicit bound and refusal it already has. MLton never refuses a large closure set; under the project's policy only unbounded sets are refused, and large bounded sets are a dispatch cost, not a correctness issue.
6. **Futhark is the other exact design.** It needs no flow analysis because its type rules forbid conditionals and loops from returning functions, and forbid arrays of functions (`hovgaard-2018-defunctionalisation/paper.pdf`, §1). That is an alternative where branching is unacceptable.

## The 5 most transferable decisions

1. **Defunctionalize by one whole-program label-flow analysis that is complete on its own.** One sum per distinct closure set, coercions between sets, dispatch at calls, one function per lambda. Inlining becomes purely an optimization.
2. **A fixed, ordered pass list where every pass runs once**, with the verifier at the boundaries. Only monotone analyses iterate; no transformation repeats to a fixpoint.
3. **Per-function inlining decided bottom-up over SCCs** with `(calls−1)·(size−small) ≤ product`, leaf passes at 20 and 40, recursive SCCs never inlined, originals deleted. Add a per-function size cap, which MLton lacks.
4. **Dominator-based contification, early and repeated**, interleaved with loop formation. It collapses functions into loops without growth.
5. **Partition after optimization into size-bounded units** (MLton: coalesce along call and return edges to about 4096 statements, files of about 32k statements). Then compile those units in parallel, which MLton never did.
