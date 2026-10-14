# Audit: idris-mlir casework, acceptance and sharding blockers

Research report of 2026-10-14 for the pipeline cutover proposal, written by a research agent from read-only reading, kept verbatim. Paths are as the report gives them: `M/` and `L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`, Modular paths are relative to `~/Documents/modular` at 9211931, MLton paths are under `code/mlton/` here or the fetch named in it. Claims marked recalled or inferred are not read from source.

---

I've finished the read-only audit; I ran no builds and edited nothing. The casework comes from three root causes, and fixing each one deletes most of the mechanisms it spawned:

1. **Acceptance depends on optimization.** The closure analysis has an "unknown" top element, and a second, narrower list of ops it follows. So whether a closure is accepted depends on how far simplification got before its budget ran out.
2. **Change is detected by hashing the module.** That brought fingerprints, the RDV resume loop, the inliner's cycle guard, budgets reported as `unsupported`, three upstream patches, and a 150-line instrumentation.
3. **Types are nominal.** `!idr.data<@T>` keeps its constructors in a symbol, so canonicalization patterns scan the module, and recent "compile time" commits added branches to dodge those scans.

Short file names are used in the body; absolute paths are listed at the end.

## 1. Inventory

### A. Options and toggles
- **`idr-simplify{scc-pipeline}`**, default false (Passes.td:613-616; branch Simplify.cpp:165-176; three extra pass managers at :119-120, :131-136, :149-153, :217; do-block.mlir:5-6). Accidental. Despite its name it computes no SCCs: it is the round with SCCP, IntRange and SymbolDCE moved out, and it still takes fingerprints (Scc.cpp:83-110). **Delete.**
- **`idr-simplify{max-rounds=64}`** (Passes.td:611; Simplify.cpp:123-128, 189-209; Scc.cpp:95-100). Only tests set it (obs/budget.mlir). It "asserts" that the rounds terminate, but F0 shows 16 rounds with no decay. The loop learns it is over budget by letting upstream's composite run one extra round (Simplify.cpp:19-22). Accidental; it goes with the rounds.
- **`idr-rc{reuse,sink}`**, default true (Passes.td:668-671). Set only by `--without=reuse,sink` (Pipeline.cpp:119-120). Measurement toggles, accidental. **Delete** and A/B by binary.
- **`idr-demand{in-place}` / `--demand-in-place`** (Passes.td:696; Options.cpp:53-57; Pipeline.cpp:123-124; turned on per test fixture, e2e.sh:64). This is semantics: the command line decides whether a program is rejected, which makes two languages. The promise belongs in the data: mlir-linear's types should declare "rebuilt in place, exclusive" as a fact the frontend emits, and idr-demand checks it every time. Then the flag goes.
- **`--without`** (Options.cpp:46-50; Run.cpp:80-104). The Sink/Build/Names classes in Pipeline.cpp:29-89 and `pipelinePassNames` (:182-187) exist only to validate it. Commit 44495199 then added a usage-error rule to reconcile two of these toggles with each other. Upstream already covers the use: `idris-mlir-opt --pass-pipeline`. **Delete.**
- **`--dump-dir`** (Options.cpp:66-69; Dump.cpp) duplicates upstream `-mlir-print-ir-tree-dir` (PassManagerOptions.cpp:61), which Run.cpp:118 already enables. **Delete.**
- **Keep:** `--num-threads` (a resource setting; output bytes don't depend on it) and `idr-expect{holds}` (a test API).

### B. Change detection and resume loops
- **The composite's `OperationFingerPrint` fixpoint** (Simplify.cpp:126-128). Three upstream patches have this loop as their only site: 02 (sccp re-makes constants), 16 (RDV rebuilds unchanged calls), 22 (RDV re-poisons operands) (PINS.md:108-152, 335ff). PINS itself says "the module prints the same, but OperationFingerPrint changes." Accidental.
  - Fix: each pass returns whether it changed something (`applyPatternsGreedily`'s `changed`, the inliner's clone callback). In a bottom-up pipeline, an empty worklist is the fixpoint.
- **RDV resume loop** (Simplify.cpp:193-204, Scc.cpp:106-110): two whole-module SHA1s per resumption. **Delete**; run RDV once at the end.
- **Inline cycle guard** (Inline.cpp:174-181): a list of module fingerprints, and a silent stop when the module returns to an earlier shape. That means preparation and inlining can oscillate, with no decreasing measure — a check that discards rather than a fact that proves.
- **Rc exclusivity loop** (Rc.cpp:84-96): bounded by the number of calls, internal error "did not settle". The need is real (grade-specialized copies); the shape is accidental. Fix: compute each function's grade contexts as a key set first, then clone once.

### C. Budgets that reject programs
- **`unsupported (compile-time budget)`** comes from two places: the rounds (Simplify.cpp:207-209) and specialization (`kClonesPerOwner=1024`, Clones.cpp:30-33, Analysis/Specialize.h:59). Both are assertions about the optimizer's termination, reported as user rejections. HANDOFF's "fuzz fixpoint failures" were exactly this. After §2, a spent budget should mean "stop optimizing", and a broken termination argument should be an internal error.
- **Code-quality thresholds:** inline 40/60/320 (Analysis/Inline.cpp:23-25), `kUnrollLimit` 32 (Specialize/Keys.cpp:38), stack 256/1024/64 (Passes.td:543-544), in-bounds branch budget 512 (Empty.cpp:83-85). These are fine — but only once they can't change acceptance. Today the inline and unroll thresholds can (§2).

### D. Discardable or self-referential state between passes
- **`idr.inlined` seed marks** (Inline.cpp:74): set at :257-260, read at :98-121, swept with a module walk at :299-301. Accidental.
- **`idr.stack`** is a dialect discardable attribute (IdrBase.td:58). Written by Stack.cpp:62-96, read by Reuses.cpp, Exclusivity.cpp, OpsCon.cpp:38 and Cells.cpp:52. A memory fact in a discardable attribute, which AGENTS.md forbids. If it is dropped between idr-rc and idr-lower, the two disagree about the cell. Make it an inherent property of `idr.con`.
- **`idr.program`** (IdrBase.td:58; Lower.cpp:217-219) is the only thing that turns on the module verifier's stage and linearity rules. Dropping it silently disables them.
- **`CloneAttr` names its own function** on purpose, so that SCCP, dead-code analysis and RDV treat clones as having unknown callers that "later callers fill" (IdrAttrs.td:231-242). It is a lie to upstream analyses so they survive the round structure. It then needs its own special case in LabelSites.cpp:118-122, Rc.cpp:70-73 (which strips it) and Deduplicate.cpp:306-320.
- **Call-site `effects`** is a cached copy of the callee's (IdrOps.td:59-75), rewritten every round and briefly absent on new calls (Prepare.cpp:200). It's a deliberate cache checked by the verifier; keep it, but it is why idr-effects has to lead every round.

### E. One thing held twice
- **Closure flow:** Labels' op cases (Labels.cpp:68-123) and Slots' `isFollowed` list (Moves.cpp:75-79) plus its own sink cases (Moves.cpp:27-69, 209-247). They disagree: the dataflow framework follows `cf.br`, but Slots marks every unlisted op and every non-entry block argument as unknown (Moves.cpp:229-245).
- **Canonicalization:** Canonicalize.h says it is "the one configuration", but it isn't:
  - Specialize canonicalizes clones with the default config, bottom-up with region simplification on (Clones.cpp:74).
  - InlineCleanup is an op-list driver followed by `simplifyRegions` (Inline.cpp:143-153).
  - The pattern set is collected three times (Inline.cpp:86-94, Specialize.cpp:82-90, upstream's canonicalizer pass).
- **Effects** are computed three ways: idr-effects, `ByName::reaches` (ByName.cpp:25-46) and `giveFirstFacts` (Clones.cpp:54-66).
- **Closure forms:** Emit writes `idr.lambda`/`idr.delay` regions that idr-isolate immediately outlines. Emit knows the captures and could write the symbol form directly.
- **InBounds/Empty.cpp** reimplements integer emptiness because upstream's exact search was slow (qsort, 180 s). AGENTS.md says that belongs upstream as a patch with a reproducer.

### F. Keyed by name, string or shape
- The instrumentation finds the round by the string `"composite-fixed-point-pass"` (Simplify.cpp:242), and idr-simplify fails without that observer (:160-164): the loop's own counter lives in the instrumentation.
- The driver decides a rejection by the message prefix `"unsupported ("` (Run.cpp:252).
- `"reuse"`, `"sink"`, `"in-place"` are matched as strings (Run.cpp:83-85, Pipeline.cpp:119-124).
- Deduplicate refuses functions with an `instance` fact because idr-expect looks functions up by provenance name (Deduplicate.cpp:183-195, 322-331). A test API is constraining an optimization.
- `listElement` treats any two-field constructor as "the cons" (Symbols.cpp:65-72).
- Generated names come from counters and module order: `.lam<n>`/`.delay<n>` (Isolate.cpp:124-125), `.capture<n>` (Prepare.cpp:126), `.spec<n>`/`.raise<n>` (Clones.cpp:40-41), `fn$<n>`/`lazy$<n>` by first appearance (Decide.cpp:188-198), plus `.acc`, `.trmc`, `.excl`. Names derived from the key would make creation order-independent.
- Frontend:
  - Holes are a sentinel name renamed around Idris's normaliser (`MN "idris-mlir-hole"` → `-held`, Closed.idr:173, 287-295, 471-476). Normalise the open term under an environment that binds the holes instead.
  - The synthetic world binder was renamed to `$world` because binder facts are keyed by (name, span) (Programs.idr:182-193). Key by binder identity instead.

### G. Environment variables
- **`Frontend/Translate/Prof.idr`** reads 8 environment variables, including the toggles `IDRIS_MLIR_FIX_TOLOC`, `FIX_TYPEPARAMS`, `FIX_REPR`, `FIX_CONTINUE` and `NOTOTAL`, and keeps global IORef memo tables (:58-66, :224, :240-313). Its header says "never committed". It arrived with the e569ea3f checkpoint, is listed in idris-mlir.ipkg:42, and nothing imports it. **Delete.**
- The C++ reads no environment.

### H. Branches that dodge declaration lookups
- MatchPatterns.cpp:101-121 (a branch on quantity, with the lookup kept as fallback), Eta.cpp:43-87 (ask the match first, scan otherwise), OpsClosures.cpp:325-326 (look up only when there are captures).
- 20 module-scanning lookups remain in lib/IR (`declarationOf`/`constructorOf` → `lookupNearestSymbolFrom`, Symbols.cpp:51-62).
- Root cause: nominal types. Fix: identified mutable types that carry their body (LLVM's identified-struct mechanism), and closure constants whose captures are typed. Patterns then read the type and every one of these branches goes.

## 2. Why acceptance depends on optimization

**What a closure must satisfy to be accepted.** A key becomes a sum only if its labels are known, they fit its type, and (for a lazy key) they all return into one key (Decide.cpp:38-47). It also must never meet a key that didn't convert: one such key marks every label it may hold as a closure, and their parameters, results and applies, transitively (Decide.cpp:97-184). `unknownKeys` (:204-219) then becomes `unsupported (runtime closure)` (Pass.cpp:43-50, 96-101).

**Where labels become "unknown" (`LabelSet::top`):**
- Any op with a closure result that Labels doesn't handle (Labels.cpp:119-121), and any op not in `isFollowed`: its operands flow into "unknown" and its results come from it (Moves.cpp:226-238).
- Every non-entry block argument of an `idr.func` (Moves.cpp:240-245). That is exactly what the inliner produces for a multi-block callee: its `handleTerminator` writes `cf.br` (Func/Inliner.cpp:32-39). It is lost until a cleanup merges the block.
- The yield of an evaluated `idr.delay` (Moves.cpp:37-38). Isolate's new branch (Isolate.cpp:80-86) exists only to steer around this.
- Public or escaping functions (Labels.cpp:165-166; LabelSites.cpp:116-122) and external ones (Labels.cpp:145-148; Keys.cpp:226-235).
- An apply whose callee is unknown: its results go to top and its arguments join every label of the type (Labels.cpp:134-141). This spreads.
- Region arguments of fold, generate and match that aren't fields (Labels.cpp:199-221).
- On top of that, `fits` demands exact type equality (Keys.cpp:84-95), and a lazy component whose labels return different types is refused (Moves.cpp:185-198).

**What simplification contributes.** None of it makes the analysis more precise. It deletes closures before they reach these gaps:
- Apply of a known closure becomes a call (OpsClosures.cpp:316-346).
- Inlining puts the closure and its apply in one body.
- Specialization substitutes static closures into clones (Specialize/Keys.cpp:13-15).
- Raising (Raise.cpp) handles closures that are returned and immediately applied.
- SCCP turns closures with constant captures into closure constants; Round.cpp:64-66 says the rounds' end depends on that.
- The two force rewrites delete suspensions (Prepare.cpp:68-211).

So whether `Idris.Parser.directive.lam4` is accepted depends on the round count, the inline thresholds, `kUnrollLimit` and `kClonesPerOwner`. The F0 record doesn't say which gap that refusal hit: the error names the op kind (Pass.cpp:48-49), but only the function was kept. Record the op and the key next time.

**This is a representation bug, not a language boundary.** AGENTS.md calls a construct megamorphic when no analysis bounds its set. In a closed monomorphic program, a 0CFA label set is always a subset of the program's finite functions, so it is always bounded. MLton's closure conversion has no top value at all:
- every abstract value is built from its type (abstract-value.fun:273);
- each constructor argument gets one value (closure-convert.fun:249-256);
- an application adds a handler on the callee's lambda set (:312-326);
- shared mutable cells are unified, not joined (abstract-value.fun:316-329);
- every set becomes a datatype (:500-525), with coercions where sets differ (:584-661).

It cannot fail. idr already has the coercion machinery (`SlotTypeConverter::coerce`, Defunctionalize.h:214-219).

**The change:**
1. **Closed world as a verified invariant.** No external `idr.func`, and no public function except the root (which takes a world). This deletes `escapes`, the external tops and Decide.cpp:158-164.
2. **One flow table.** An interface (upstream's Call/Region/Branch interfaces plus one idr interface for ops that carry values) that both Labels and Slots read. The verifier refuses a closure- or lazy-typed operand on an op without it. This deletes `isFollowed`, Labels.cpp:119-121 and Moves.cpp:240-245, and `cf.br` gets followed.
3. **A forced-state anchor keyed by the lazy value type,** the way `ElementsAnchor` is keyed by element type (Labels.h:170-180). Evaluated delays write it, and the labels of a lazy slot return into it. This deletes `unifySuspensions` (Moves.cpp:147-206), the Isolate branch and Moves.cpp:37-38.
4. **No `unknown` in `LabelSet`.** This deletes `labelsFor` (LabelSites.cpp:92-114), the sealing cascade and both `unsupported` reasons (an internal error if ever reached).

After that, inlining, specialization, SCCP and the force preparation are pure optimization: a budget stops them, never rejects a program, and the fixpoint is no longer load-bearing.

**Further, in MLton's order:** defunctionalize right after isolate and simplify first-order code. Case-of-known-constructor then does what ApplyOp's canonicalization does today, and closure references become direct calls in the call graph. LoopBreakers, Effects, SCCP, Raise and ForceAtCapture all lose their closure cases. MLton itself inlines after closure conversion; its earlier polyvariance pass is optional precision. The costs to measure are larger sums before inlining, and a solve over ~100k functions that needs union-find and hash-consed sets.

## 3. What blocks sharding

**Inherent whole-program facts.** These must be decided globally, then read frozen; the rewrites can still be per function.
- Defunctionalization's label sets and sum types. The solve is a serial DataFlowSolver. The conversion is one module-wide `applyFullConversion` (Pass.cpp:117-136), which is accidental: once keys are decided, each function's types are a pure function of the decision.
- Rc's borrow and exclusivity grades, which are signature facts; placement and commit already run nested (Rc.cpp:66, 101).
- Lower's layouts and type converter. The conversion itself is one serial `applyPartialConversion` (Lower.cpp:166), and `Runtime` inserts declarations into one SymbolTable as it goes — both accidental.
- The tail-call cycle plan, idr-stack's escape summaries, and narrow/in-bounds ranges. These are summaries; their proofs and rewrites are already nested. SymbolDCE reachability is inherent but cheap.

**Accidental:**
- The round: every round reruns Effects, LoopBreakers, RoundFacts, Inline (with a CallGraph rebuilt per cycle, Inline.cpp:292), Specialize, serial SCCP (21-43 s per round) and SymbolDCE.
- RoundFacts exists only because a nested pass manager drops module analyses (RoundFacts.cpp:6-15).
- LoopBreakers exists only because inlining repeats across rounds (LoopBreakers.cpp:15-20); a bottom-up SCC order needs none.
- RDV's serial module liveness (51 s); InlineCleanup is effectively serial on singleton SCCs (one instance took 211 s).
- Symbol creation is serialized and order-named (F above); `CloneTable` is mutable and shared; the CloneAttr self-reference blocks SCCP from entering clones.
- The Simplify instrumentation's mutex and records keyed by pass pointer (Simplify.cpp:372-376).
- Isolate, Contify, Deduplicate, Accumulate and Trmc are module passes for one symbol or one use count each.
- Nominal types: every canonicalization reads the module's top level (H), which a shard would not hold.
- One LLVM module (Run.cpp:164-201): translate, link the runtime, internalize, O3 and a single codegen. LLVM's `splitCodeGen` would parallelize codegen.

## 4. Verdicts on what landed since 17efeff3

**Delete outright:**
- scc-pipeline (552d682a): the option, Scc.cpp, the do-block RUN line and the Simplify branch.
- The RDV resume loop (3b166aa3).
- The prep/inline repeat and its cycle guard (24eff40c).
- The seed marks (5088d7a8). Keep them only until a per-callable cleanup exists, with no further investment.
- `--without`, reuse/sink, the demand-vs-without usage error (44495199), Pipeline.cpp's Sink/Names, and `--dump-dir`.
- Prof.idr.
- The composite loop together with its instrumentation and Trace.cpp (df5d8742).

**Replace:**
- `unifySuspensions` and the Isolate evaluated-keyed branch (43a9e235) → the forced anchor.
- Empty.cpp → an upstream patch with a reproducer.
- The lookup-dodging branches (0768bc9f, 4d207761) → types that carry their declaration. The fingerprint removal in 0768bc9f is right; keep it.
- Canonicalize.h → keep, and make it actually the one configuration.
- `$world` and the hole-marker renaming → binder identity and open-term normalisation.
- `--demand-in-place` → a fact of the library's types.
- Deduplicate (234b81a0) → keep for now, drop the `instance` exclusion, and long term hash-cons the outlines at emission.

**Keep:** IntRange per function (5d3318fb), labels in one walk (6a7841dc, though `labelsFor` goes when "unknown" does), the upstream/23 CSE statistics patch, `--num-threads`, and `idr-expect`.

## Key files (absolute paths)
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Transforms/Simplify/Simplify.cpp, Scc.cpp, Round.cpp, RoundFacts.cpp, LoopBreakers.cpp
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Transforms/Inline/Inline.cpp, Prepare.cpp
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Transforms/Defunctionalize/Moves.cpp, Keys.cpp, Decide.cpp, Pass.cpp
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Analysis/Labels.cpp, LabelSites.cpp; /Users/bjorn/Documents/idris-mlir/foreign/idr/include/idr/Analysis/Labels.h
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Transforms/Specialize/Clones.cpp, Keys.cpp, Specialize.cpp
- /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Transforms/Pipeline.cpp; /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/Driver/Run.cpp, Options.cpp
- /Users/bjorn/Documents/idris-mlir/foreign/idr/include/idr/IR/IdrAttrs.td, IdrBase.td; /Users/bjorn/Documents/idris-mlir/foreign/idr/lib/IR/Func/Inliner.cpp
- /Users/bjorn/Documents/idris-mlir/compiler/src/IdrisMLIR/Frontend/Translate/Prof.idr, Closed.idr
- /Users/bjorn/Documents/idris-mlir/sources/code/mlton/mlton/closure-convert/closure-convert.fun, abstract-value.fun
