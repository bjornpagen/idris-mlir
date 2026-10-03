# One representation: where the compiler says one thing twice

Research note, 2026-10-02, at f5dd434. The brief: "we should deeply avoid
having multiple representations for the same thing", with as much of the
representation work as possible done by MLIR. The yardsticks are Brooks and
Pike (data dominates), Minsky (illegal states unrepresentable), King (parse,
don't validate), Dijkstra (special cases are coordinate artifacts), SICP
(control flow as data) and Brooks's limit (representation removes only
accidental complexity). Nothing here changes the compiler.

Every claim is marked: **R** read (the file and line given, at f5dd434; a
claim with a reference and no mark is R), **M** measured (method in the
appendix or where it is used), **C** conjecture. In the tables, the copies
are R and the mechanisms and sizes C unless marked. Paths: Idris under
`compiler/src/IdrisMLIR/`, C++ under `foreign/idr/lib/`, `IdrOps.td`,
`Passes.td` and `Idr.h` under `foreign/idr/include/idr/`, upstream under
`.toolchain/llvm-project/` (`mlir/...`, `llvm/...`).

## Lead

What Idris proves is already where no pass can lose it. Quantities and
ownership are grades in the types (`!idr.lin`, `!idr.erased`, `!idr.own`,
`!idr.excl`: IdrOps.td:131-146, 1281-1316), checked after every pass
(Dialect/Dialect.cc:773-788); effects are op declarations that every upstream
pass reads (Idr.h:51-73, 143-175; Facts/CallEffects.cc:38-62); exclusivity is
proved on MLIR's solver and written into the grade (Ownership/Exclusive.cc:1-16);
arrays are builtin memrefs that upstream vectorizes (Lower/Loops.cc:1-27). No
C++ string names an Idris definition [M: a grep for the module and
constructor names of Builtin, PrimIO, the Prelude, base, Main and
Linear.Array in string literals under `foreign/idr` finds none], and no Idris
code outside the registry can compare one (Ids.idr:33-45).

The copies sit in three places.

- **The language boundary.** 1,871 of the Idris side's 6,742 lines (28%) [M]
  exist to write MLIR: a second program language (`Term`, 20 constructors,
  each handled in 7 places), a third type language (`MType`, beside Idris's
  `Ty` and the dialect's types), a second primitive set (`Prim` and `IOOp`,
  Types.idr:215-472), and 91 op and attribute spellings and 9 type spellings
  typed as strings [M], against the 81 ops ODS declares [M]. Two
  whole-program analyses run on both sides: loop breakers and the totality
  of lifted lambdas.
- **Derived facts re-derived by hand in C++.** The function-reference graph
  is built in 12 places with at least four edge definitions; "holds
  references" is defined 5 times; 10 of the 14 partial ops state their
  precondition three times (statically, in the lowering, in the folder);
  consumption is a table over 21 op kinds; 4 primitives lowered inline have their
  meaning twice.
- **Decisions kept where they drift.** A module attribute changes what a
  plain type means (`idr.stage`); a lattice point nothing produces
  (`Permission::Borrow`); a pass option nothing reads (`clone-limit`);
  rejection reasons the frontend cannot parse; an exit status nothing
  produces.

Copies have already drifted. **M** (appendix): on a 20-line program, Emit
makes a Prelude function the breaker of a cycle through user and Prelude
code; `idr-loop-breakers` alone makes the user's function the breaker; the
pipeline runs a mix, Emit's rule for that cycle and the C++ rule for the
self-recursive functions Emit leaves unmarked. The two rules read different
columns of one table (Registry/Libraries.idr:67-72): Emit reads *break last*
(Builtin, PrimIO), the pass reads `idr.library`, which Emit writes from
*report at caller* (Builtin, PrimIO, Prelude: Emit/Attributes.idr:32-33,
Loc.idr:38-40). And `idris-mlir-cc` rejects with `unsupported (array)` and
`unsupported (target)` (Lower/Arrays.cc:235-238, Lower/Layout.cc:89), which
`parseRule` cannot read (Rule.idr:53-64); but no Idris program reaches
either, so they were never a user's rejection, only internal errors spelt as
rejections (row 19).

Sizes [M, `wc -l`]: Idris 6,742; `foreign/idr/lib` 20,511 (19,399 of `.cc`
and `.h`); `foreign/idr/include` 2,497; `foreign/idr/tools` 1,092; `runtime`
2,424. PINS.md has 29 entries: 7 upstream MLIR bugs with reproducers, 1
upstream gap without one, 21 toolchain, platform and build entries; a better
representation retires or shrinks 4 (§5).

The ten that pay most, in order: (1) one loop-breaker rule, MLIR's; (2)
divergence as an effect bit that idr-effects computes; (3) the Idris mirror
of ops and types generated from ODS; (4) partiality as guard ops whose result
is the checked value; (5) one meaning per primitive; (6) ownership read from
grades and operand declarations, not a module flag and an isa table; (7) one
reference analysis; (8) one runtime form of closures and one evaluation mode;
(9) flat constants for list spines; (10) the quick fixes: one table of
rejection reasons, the dead option and branches, a verifier rule for the
`inline-unreachable` invariant. The plan is §7.

## 1. Every duplicated representation

| # | Concept | Copies (R) | The one | Mechanism (C) | Deleted | Risk | Size (C) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The program | `Term` (Term.idr:83-130), 20 constructors each handled in TermF (:177-197), `hmap` (:212-232), `para` (:238-283), the printer (:390-435), Emit/Breakers.idr:49-69 and Emit/Bodies.idr:188-382; every op-shaped constructor mirrors an op | the dialect | Term keeps binders, scopes and types; PrimApp, Effect, NewWorld, Crash, ArrayGen and ArrayFold become one node over generated ops (row 2); closure conversion moves to MLIR last (§4.1 #5) | 6 constructors × 7 handlers, Breakers' fold | Term's scope guarantee stays (Term.idr:5-9) | −300 to −500 Idris |
| 2 | The primitive set | Idris's `PrimFn` → `primOp` (Frontend/Translate/Primitives.idr:82-100) → `Prim`, `primArgs`, `Show` (Types.idr:249-398) → op text (Emit/Operations.idr:118-220) → 81 ODS ops [M] → 37 folders (Fold/Fold.cc) → lowering generated for the 45 `CallsRuntime` ops [M] (Lower/Patterns.cc:545-563) → 85 functions in `runtime/idris_rt.h` [M] → `runtime/`. IO: registry (Registry/Primitives.idr:119-204) → `IOOp`, `ioArgs` (Types.idr:432-472) → Emit/Operations.idr:263-338 → `idr.io.*` | ODS for the set and its syntax; the runtime for its meaning; `primOp` and the registry stay (they map Idris's names, which only Idris knows) | generate an Idris module of op constructors and a generic-form printer from IdrOps.td: a TableGen backend of ours, as mlir-tblgen generates Python bindings (mlir/tools/mlir-tblgen/OpPythonBindingGen.cpp:1531), or `llvm-tblgen --dump-json` (llvm/utils/TableGen/Basic/TableGen.cpp:67), which reads IdrOps.td whole [M] | `Prim`, `IOOp`, `primArgs`, `ioArgs`, their `Show`, most of Emit/Operations.idr | a build step before the Idris package; the emitted text becomes generic form (tests state properties: `tests/programs/*/mlir.expect`) | −450 Idris, +200 generator |
| 3 | The type language | `Ty`, `Binder` (Types.idr:111-128); `MType` (MLIR.idr:78-111); `mtype` (Emit/Types.idr:17-42); the TypeDefs (IdrOps.td:69-156) | ODS for what is written; `Ty` stays (§8) | `MType` generated with row 2 | `MType`, `showType` | low | −60 Idris |
| 4 | Loop breakers | Emit/Breakers.idr:74-117 with Emit/Index.idr:15-34; Passes/LoopBreakers.cc:37-89. They differ in the library set (row 21) and in self-cycles: Emit cuts cycles of two or more (Breakers.idr:114), the pass and `every-cycle-has-breaker` also one function that refers to itself (LoopBreakers.cc:78; Expect/Breakers.cc:32); on one module they choose differently [M] | `idr-loop-breakers` | Emit writes the registry's *break last* column as the attribute the pass reads, whose only reader is LoopBreakers.cc:46; Emit's breakers go. Contify, the one step before the first round, reads no `no_inline` [R: Passes/Contify.cc] | Breakers.idr:74-117, `Index.breakers`, `NoInline` | which function breaks a user/Prelude cycle changes inlining: bench gate | −120 Idris |
| 5 | May not return | Emit/Breakers.idr:119-138 (lifted lambdas, over Graph.reach); Facts/Functions/Inherit.cc:9-19 (clones); Facts/Functions/Of.cc:15 (no `idr.total` is partial); `facts::Effects` (Facts/Effects.cppm:9-17); `#idr.effects`, two bits (IdrOps.td:255-266); the divergence resource (Idr.h:63-67) | `idr-effects` | a third bit, `diverge`, propagated as `crash` is (Facts/Infer/Infer.cc:16-17, 81-92), seeded by Idris's per-instance proof; `idr.total` then means only that, as idr-tail-loops reads it already (Passes/TailLoops.cc:173, 479) | Breakers.terminating, `Index.terminating`, Inherit's totality | the rules agree: propagating through instances is at least as conservative, and a lambda's own body has no loop (C) | −40 Idris |
| 6 | Closures | Term `Lam`/`Suspend` with a `Label` (Term.idr:104-109); lifted functions (Emit/Bodies.idr:162-183); `idr.closure`, `#idr.closure` (IdrOps.td:205-214, 539-549); sums of closures whose constructor's *name* is the label (IdrOps.td:326-329; Facts/Closures/ClosureLabel.cc:9-13); the specializer's closure pattern and key (Specialize/Pattern.h:39-42; IdrOps.td:1443-1447); closure cells and labels in the lowering (Lower/Layout.h:103-159), lowered only for idr-eval (Lower/Closures.cc:1-4; Lower/Pass.cc:89-101); the runtime's closure release (runtime/rc.cc:90-93), which nothing reaches: programs hold no closure and the evaluator's cells are persistent (runtime/alloc.cc:61-63). Four readers handle both forms (Facts/Closures/Passed.cc:17-27, 48-66; Facts/Infer/Infer.cc:38-61; Facts/Evaluation/CanEvaluate.cc:47-54; Specialize) | `!idr.fn` with the label as a symbol; at runtime, sums only | (a) a sum's constructor names its label with a `FlatSymbolRefAttr`, a symbol use upstream sees; (b) idr-eval runs idr-defunctionalize on its closed scratch module (Eval/Eval.cc:210-249, 282-287) before lowering it | Lower/Closures.cc, `Runtime::code`, `codeType`, `emitCode` (Lower/Runtime.cc:413-465), labels in `Layouts`, Reify's code table, rc.cc's closure branch | a result of closure type is read back from a sum | −250 C++ |
| 7 | Contiguous runs | the string cell (runtime/idris_rt.h:118-127; runtime/strings.cc; Lower/Strings.cc; Lower/Runtime.cc:284-310); the array cell (idris_rt.h:147-157; `arrayView`, Lower/Arrays.cc:85); lists.md's seq (its §4.3). Buffers are arrays already (Registry/Primitives.idr:151-169; Emit/Operations.idr:299-316) | one cell kind and one view builder; three idr types | §1.1 (a) | a second cell kind | the string ABI is the folders' and `io.cc`'s | lists.md 3a; strings C |
| 8 | Specialization | frontend keys: types, implementations, and the shape of an argument the rest of the type mentions (Frontend/Translate/Instances.idr:104-152), bounded by 4096 instances per definition (:30-35), no termination argument; idr-specialize: patterns of constructors, closures and constants, finite by binding times (Specialize/Specialize.cc:1-21; Specialize/BindingTimes.h), 1024 clones per owner (Specialize/Clones.h:22), and a `clone-limit` option nothing reads (Passes.td:417-418; Passes/Simplify.cc:208) | MLIR for value shapes; Idris for what makes a type reduce | §1.1 (b) | the dead option | frontend lane in flight | small |
| 9 | Function facts | Facts.idr (one fact and its provenance); Emit's three function attributes (Emit/Attributes.idr:12-38); Facts/Functions/*; the attributes (§1.1 (c)) | the fact that must cross is Idris's per-definition termination proof; the rest is MLIR's | rows 4 and 5 | — | — | — |
| 10 | What a function refers to | 12 C++ walks: Passes/LoopBreakers.cc:60-67, Expect/Breakers.cc:17-25, Expect/Loops.cc:20-27, Expect/Continuations.cc:20, Stack/Recursion.cc:15-46, Ownership/Borrow.cc:90-102, Specialize/BindingTimes.cc:191-205, Inline/Inline.cc:45-80, Facts/Infer/Infer.cc:26-64, Passes/Contify.cc:48, Passes/Defunctionalize.cc:241, Eval/Eval.cc:219-233; one Idris walk (Emit/Breakers.idr:49-93). Edges differ: calls only, calls and closures, all symbol uses, with or without labels of closure sums | one analysis | an MLIR `Analysis` the AnalysisManager caches, with the edge kind (call, closure label, sum label) as data | ~11 walks | some differences are deliberate: keep the kind | −150 C++ |
| 11 | Strongly connected components | Graph.idr:15-54 (quadratic, by reachability); Frontend/Translate/Recursion.idr:40-73 (Tarjan on Idris's size-change graphs); Passes/Scc.h:43-72 (`llvm::scc_iterator`); Dialect/Dialect.cc:597-624 (a DFS) | Scc.h in C++; Recursion.idr stays (it reads TT) | after rows 4 and 5, Graph.idr only decides boxes | — | low | small |
| 12 | Is a sum a box | Frontend/Translate/Programs.idr:98-114 (user data); Passes/Defunctionalize.cc:19-23 (sums of closures); the verifier (Dialect.cc:597-624); and box-ness stored in the type and in the declaration, checked equal (Dialect.cc:558-579) | Idris decides (AGENTS); the type caches it (§8) | one C++ helper for the two C++ copies | one copy | low | small |
| 13 | Holds references | IdrOps.td:1300-1306; Ownership/Counting.cc:9-38; Lower/Layout.cc:196, 209-229; Lower/Facts.cc:13 | ODS | a trait on the carrier TypeDefs; sums answered once per module | three classifiers | low | −40 C++ |
| 14 | A partial op's precondition | 14 ops; 10 of them three times: `getCrashCause` (IdrOps.td:615-619, 764-768, 800-804, 889-893, 1011-1015; Dialect/Ops.cc:1201-1205, 1234), the lowering's condition (Lower/Patterns.cc:262-266, 388-425), the folder's guard (Fold/Fold.cc:121-130, 231, 252, 262, 393; Dialect/Ops.cc:215-218) | a guard op | §2 #1 | the triples | crash messages and locations must not move | −150 C++ |
| 15 | A primitive's meaning, the runtime's (AGENTS) | restated: Euclidean `div` and `mod` in a folder (Dialect/Ops.cc:188-227) and a lowering (Lower/Patterns.cc:249-307); `to_char` (Ops.cc:1072-1083; Patterns.cc:309-332); `to_byte` (Ops.cc:1173; Patterns.cc:335); `to_int`'s folder computes with APFloat (Ops.cc:1190-1199) while the op calls the runtime (IdrOps.td:654); the small cases of bigs ("their small case restated", Lower/Bigs.cc:1-10); `pack`/`concat` as the lowering's walk (Lower/Strings.cc) and the folder's loop of `str_cons` (Fold.cc:170-190) | `arith` for inline ops, the runtime for called ones | expand inline ops into `arith` early, so upstream folders and IntegerRangeAnalysis are their meaning; `to_int` folds by calling the runtime as Fold.cc does | 4 folders | semantics fixtures against Chez | −120 C++ |
| 16 | Consumes or borrows | Ownership/Counting.cc:94-122 (21 op kinds); the callee's parameter grade (Counting.cc:84-87); `MemFree` on `drop` and `take` only (IdrOps.td:1347, 1408) | operand declarations | §2 #2 | the table | Ownership lane | −40 C++ |
| 17 | The owned stage | `idr.stage` (Ownership/Rc.cc:48), read in four places (Counting.cc:86; Passes/Narrow.cc:491-492; Ownership/Ops.cc:44-50; Rc.cc:24); plain `T` is (ω, ·) before it and a view after it; `Permission::Borrow` is parsed and printed, never produced (Idr.h:37; Dialect.cc:187-219) | the grades | §2 #3 | the stage reads | Ownership lane | small |
| 18 | Evaluation mode | the lowering's `jit` flag: allocation, header, counts, crash, tick, `@main`, closures (Lower/Runtime.cc:90-147, 204-213; Lower/Pass.cc:112-225; Lower/Counting.cc:37; Stack/Cell.cc:13; 31 mentions in 8 files [M]); the runtime's arena mode, which makes every cell persistent and counting a no-op already (runtime/alloc.cc:48-63; idris_rt.h:193-198) | the runtime's mode | allocation and counting call the runtime in both modes; the lowering keeps the tick and the evaluator's crash | ~5 branches | a call per cell in the evaluator | −40 C++ |
| 19 | Rejections and exit statuses | `Rule` (Rule.idr:14-64) against the C++ phrases `array`, `compile-time budget`, `layout`, `runtime`, `target`, three of which Rule lacks [M: grep]; exit statuses 3 and 4 in Frontend/Main.idr:214-229 against 0 to 3 in foreign/idr/tools/idris-mlir-cc.cc:147, which never exits 4. Correction (R, after this note): no Idris program reaches the three. `array` is a `memref.dim` of a non-array or at a dimension other than the constant 0, and Emit asks an array only for its dimension 0; `target` is a data layout whose pointers are not the runtime's words, and the data layout is the target entry's, the one the runtime is built for; `runtime` is idris-mlir-cc's own complaint about a runtime member, printed outside the diagnostics, exit status 1. All three are internal errors spelt as rejections, reachable only from MLIR input (tests/idr/lower/internal-errors.mlir), not reasons `Rule` lacks | `Rule`, for what a program can reach | `array` and `target` spelt as the internal errors they are; `runtime` with the driver's lane, which owns idris-mlir-cc.cc | the dead branch, two phrases | idris-mlir-cc.cc in flight | small |
| 20 | Compile-time constants | runtime cells in the child, a flat table in transit (Eval/Reify.h:63-73), a nested `ConAttr` in the module, LLVM globals; the nesting is as deep as a list is long (PINS.md `mlir-recursion`, `bytecode-deferred-quadratic`) | one flat form for list spines | a constant attribute for a run of one cons constructor (its elements and its tail), read through one accessor | Reify's decoding, the list half of two pins | every constant reader | ±0 C++ |
| 21 | Which library | `Origin` and `Purpose` (Registry/Libraries.idr:41-85) → `idr.library` (Emit/Attributes.idr:32-33) and the `fused<"library">` location (MLIR.idr:166-170) | the registry | keep both forms (decisions, messages); the attribute carries the column its reader means (row 4) | — | — | — |
| 22 | A program | the IO root, the only one the frontend makes (Frontend/Main.idr:259-328); a `() -> i64` root (Dialect.cc:517-525; Lower/Pass.cc:114-123) that 8 hand-written tests use [M] | the IO root | port the 8 tests | the Int root's code | test churn | small |
| 23 | A quantity | `Quantity` for registry shapes (Types.idr:21); `Use` and `Binder` for Term (Types.idr:40, 122); `Mode` for Emit (Emit/Monad.idr:69-84) with the world's exception, stated again in C++ (Dialect.cc:278-280) | `Quantity` (TT) and `Binder` | `Mode` generated with row 3 | `Mode` | low | small |

### 1.1 The three questions of the brief

**(a) Contiguous runs.** Buffers and arrays are one representation already:
`Buffer` is `ArrayType (Just byte)` (Registry/Primitives.idr:156) and every
buffer primitive is an `idr.array` op on `memref<?xi8>`
(Emit/Operations.idr:299-316). Strings are a second one: their own cell
kind (a byte length, a scalar count, the bytes), their own static data
(Lower/Runtime.cc:284-310), and no view MLIR can load from, since every string
op is a runtime call. lists.md's seq is the array cell viewed from a dynamic
offset (lists.md §4.3). It can be the same view at lowering, the same cell
kind and the same descriptor builder (`arrayView`, Lower/Arrays.cc:85), but
not the same idr type: an array is `memref<?xE>` in the identity layout
(`isArray`, Dialect.cc:147-154), mutated in the order of the world, and a seq
spelled as a strided builtin memref would make one type family carry two
invariants told apart by a layout predicate. So `!idr.seq<@T>`, as lists.md
has it, lowered by the array's code. The same holds for strings (C): keep
`!idr.str` for what it proves (immutable, well-formed UTF-8, its scalar
count), and give its bytes the array's cell and a read-only view, so that
`str.index` and `str.length` on ASCII strings, `pack` and output become loads
and stores MLIR sees, and `substr` of an immutable string may be a view (with
lists.md §4.7's space caveat).

**(b) Specialization.** What must stay in Idris is what makes a type reduce:
type and implementation arguments (`TypeParam`, `DictParam`,
Frontend/Translate/State.idr:27) and the shape of a runtime argument when the
rest of the type mentions the parameter (`shrink sc`, Instances.idr:147-149;
`treeDelete` is the case it names, :134-145). Every other shape is a value
shape, and MLIR specializes value shapes with a termination argument
(binding times), where the frontend has only a budget (Instances.idr:30-35).
The frontend keys a shape as written (`skeleton`, Frontend/Translate/Closed.idr:291-296),
with shaped variables replaced by their shapes (`closeWritten`,
Closed.idr:166-179), so a recursion that wraps its argument in one more
constructor each call makes a new key each time, up to the budget, each
normalising a larger type (C: the hang the review found has this form).
Keyed by the normalised, index-erased types the shape induces (indices are
erased already, Frontend/Translate/Types.idr:243-258), instances are as many
as representations, a finite set (C). Dictionary fields
(Frontend/Translate/Dictionaries.idr:1-28) are the one place the frontend
specializes a value of a data instance for its own sake;
idr-defunctionalize tracks closures per constructor field already
(Passes/Defunctionalize.cc:1-13), so a dictionary kept as a runtime record of
closures would reach the same direct calls in MLIR, and a program whose sites
give a constructor two implementations, rejected today (Dictionaries.idr:15-18),
would compile (C). Both belong to the frontend lane in flight.

**(c) The discardable attributes.** The only fact Idris proves that sits in
one is termination, and it is conservative when absent. Two can be lost with
a silent loss of checking: the verifier triggers `idr.program` and
`idr.stage` (§2 #3, #6).

| Attribute | Written by | Read by | If dropped | If stale or copied |
| --- | --- | --- | --- | --- |
| `idr.program` | Emit.idr:41 | its own verifier: root, attribute names, declared sums, acyclic containment, linearity (Dialect.cc:508-629, 773-779) | silent: no whole-program or linearity check; results unchanged | — |
| `idr.stage` | Ownership/Rc.cc:48 | the owned-stage verifier (Dialect.cc:782-788); the owned ops' verifiers (Ownership/Ops.cc:44-50); `isBorrowed` (Counting.cc:84-87); idr-narrow (Narrow.cc:491-492) | loud while a `dup`, `drop`, `take` or `reuse` is left; otherwise silent: no owned-stage check, every call operand consumes, idr-narrow skips the drops it owes, a leak (C) and never a wrong result | — |
| `idr.total` | Emit (an instance: Idris's proof; a lambda: Breakers.terminating); Inherit.cc:15-18 | Of.cc:15 → CallEffects.cc:50-55 and CanEvaluate.cc:57; TailLoops.cc:173, 479 | safe: slower only (no dead-call erasure, `idr.may_loop` added, the smaller budget) | unsound if added where Idris proved nothing: a dead diverging call is erased |
| `idr.effects` | idr-effects each round (Facts/Pass.cc); Inherit.cc | Of.cc:16-19 | safe: absent is `io, crash` (Of.cc:10-14) | unsound if a bit is missing: an IO call evaluated, moved or erased |
| `idr.library` | Emit/Attributes.idr:32-33 | LoopBreakers.cc:46 only | safe: another breaker | — |
| `idr.stack` | idr-stack, which recomputes it (Passes.td:317-318) | Dialect/Ops.cc:458; Exclusive.cc:141; ResetReuse.cc:112, 172; Verify.cc:216; Stack/Cell.cc:13 | safe: a heap cell | unsound if copied onto a cell that escapes; no verifier re-checks escape; sound by pipeline order (no pass after idr-stack inlines, and its analysis anticipates idr-tail-loops: Passes.td:304-312; Registration.cc:28-31) |
| `idr.clone` | Specialize/Clones.cc:99-105 | the clone table (Clones.cc:34-67); LoopBreakers.cc:42; Simplify.cc:116; Expect/Pass.cc:41 | safe: the key is forgotten and re-cloned within the budget; the clone loses the self-reference that keeps sccp and remove-dead-values from fitting it to its present callers (IdrOps.td:1473-1478), harmless since a forgotten key is never called again | its self-name is checked equal to the function's (Dialect.cc:810-817) |
| `idr.hole` (argument) | Clones.cc:119-123 | Clones.cc:40-51 | safe: a clone whose holes do not parse is only a function (Clones.h:3-7) | — |
| `no_inline` | Emit, LoopBreakers | Inline.cc:68, 95; LoopBreakers.cc:74 | inherent on `func.func` (mlir/include/mlir/Dialect/Func/IR/FuncOps.td:298), not discardable; clearing one can unroll a cycle once per round until `max-rounds`, a budget error | — |
| `idr.io`, `idr.crash`, `idr.divergence`, `idr.lin` | — | — | not attributes: the names of the four effect resources (Idr.h:51-73), recomputed from each op's interface at every query | — |
| `expect.facts` | tests | idr-expect (Dialect.cc:828-832) | test-only | — |

A comment still names an attribute that no longer exists, `idr.spec_key`
(IdrOps.td:1423-1425); the key lives in `idr.clone`.

## 2. Validation a type or a declaration could carry

By kind (R; the counts M, by the greps in the appendix):

| Kind | Instances |
| --- | --- |
| A derived fact re-derived by hand | 11 kinds: references (12 + 1), holds references (5), preconditions (3 × 10), a primitive's meaning (2 × 6), consumption (3), closure labels (4), `viewRoot` (2: Exclusive.cc:113-130, Verify.cc:95-112), string builders (3: Dialect/Canonicalize/Meet.cc:27, Expect/Output.cc:16, Dialect/Ops.cc:42), list shape (2: Ops.cc:1138-1154 and the looser Fold.cc:154-168), SCC (4), box rule (3) |
| A verifier rule that keeps two copies equal | 3: type kind against declaration (Dialect.cc:558-579), containment re-checked (:597-624), the clone's self-name (:810-817) |
| A meaning that depends on a module attribute | 1: plain `T` across `idr.stage` (4 readers) |
| An invariant kept by convention, unchecked | 3: no function body ends in `ub.unreachable` (kept by Emit/Bodies.idr:145-160, Passes/Prune.cc:10-13, TailLoops.cc:492-499); `idr.stack` is valid; `idr.total` is never over-claimed |
| A sentinel | `ub.poison` as "no value" in 14 sites in 10 files (Dialect.cc:726; Counting.cc:54; Counts.cc:304; Exclusive.cc:163; Narrow.cc:62, 99, 127, 409; ReturnedArguments.cc:163; CanEvaluate.cc:40; Specialize/Pattern.cc:23; Lower/Facts.cc:64; Prune.cc:49, 95), at least 3 of them made by the `remove-dead-values-address-taken` workaround (Prune.cc:95 → Lower/Facts.cc:64, CanEvaluate.cc:40); the clone's self-reference as "callers to come"; `Permission::None` for "nothing said" and "a view" |
| `CPred` constraints | 13 (IdrOps.td:150-172, 471-472, 1046, 1170, 1303-1314, 1379-1380), all from the grade being a wrapper type and arrays being builtin memrefs, each declared once and generated into verifiers: keep |

Ranked by payoff:

1. **Partiality as guard ops** (King). Row 14's triples become one op per
   kind of precondition (nonzero, finite, nonempty, in bounds, a byte, a
   range of a buffer), `MayCrash`, whose result is its operand checked; the
   op that consumes it is total, speculatable and folded by `arith` or by
   the runtime. A guard folds away on a constant and, with survey §2's
   ValueBoundsOpInterface, under a dominating test of the program. Payoff:
   high (14 ops; preconditions once; total ops move freely). C.
2. **Consumption declared on operands.** `useOf` (Counting.cc:94-122) is a
   table over 21 op kinds every new op must remember; an owned operand's
   consumption declared in ODS (an effect on a reference resource, as the
   survey's census suggests for calls) is what the verifier, counting and
   upstream passes would all read, and closes the census's hole where an
   unused consuming call looks dead (mlir-survey.md §C, `func.call`). C.
3. **The owned stage in the grades.** Views take the `borrow` permission
   that exists unused (Idr.h:37), so plain `T` means one thing, `isBorrowed`
   reads the parameter's grade, idr-narrow reads types, and `idr.stage`
   stays only as the verifier's trigger. Or `Borrow` is deleted (Minsky: no
   state nothing produces). C; the Ownership lane's call.
4. **One reference analysis** (row 10). Medium.
5. **Holds references as a trait** (row 13). Medium.
6. **Make losing a verifier trigger loud.** builtin.module has no inherent
   slot (§8), so `idr.program` and `idr.stage` stay discardable; but an idr
   op that sees a linear or owned type can check the mark, as the owned ops
   check the stage already (Ownership/Ops.cc:44-50). Low cost. C.
7. **Check the `inline-unreachable` invariant.** A rule in `verifyProgram`
   that no function body ends in `ub.unreachable`, and one C++ normal form
   that produces it, so Emit stops caring (§4.1 #4). Low cost.
8. **Fewer poison special cases**, as the address-taken workaround shrinks
   (§5). Medium, follows the pin.
9. **Small helpers and traits**: `viewRoot` once, a `BuildsString` trait for
   the three op lists, `consOf` as the one list shape, the closure label as a
   symbol (row 6). Low.

## 3. Special-case control flow

Ranked by payoff:

1. **The evaluation mode threaded through the lowering**: 31 mentions in 8
   files [M] (row 18), and with it a second runtime form of closures (row
   6). High.
2. **`ub.poison` as "no value"** in 14 sites (§2). Medium.
3. **One library's two loops as a vertical slice**: two Term constructors
   with their 7 handlers, Frontend/Translate/Terms.idr:96-104 and 415-428,
   two registry entries, two ops, Lower/Loops.cc (205 lines), and
   `isArrayLoop` cases in counting and verification (Ownership/Ownership.h:63-66):
   40 mentions in 8 Idris files and 31 in 7 C++ files [M]. With generated
   ops (row 2) the Idris part is one generic region op; the registry entry
   stays, privileged knowledge being per library by design. Lower/Loops.cc:20-27
   adds a special form (a generate whose body is one fold, named after
   spectral-norm's rows) that upstream linalg fusion would give on tensors,
   not on our memrefs (lists.md §3.1). Medium.
4. **Two program kinds** (row 22). Low.
5. **Dead states**: exit status 4 (Frontend/Main.idr:214-229), rc.cc's
   closure branch (row 6), `clone-limit` (row 8), `Permission::Borrow` (row
   17). Low cost.
6. **Flags kept on purpose**: `is_signed` on 8 ops (IdrOps.td:603 for `div`
   and `mod`, 633, 679, 737, 822, 971, 1076), MLIR's convention of signless integers with the
   signedness on the op; idr-rc's `reuse`, `borrow` and `sink` and
   `--without`, which ablate (Passes.td:462-467). Keep.

No C++ branch names an Idris definition, library or benchmark [M]; the one
benchmark name in the C++ is the comment above.

## 4. Work on the wrong side

### 4.1 Idris work that belongs in MLIR

| # | Idris code | MLIR home | Mechanism | Size (C) |
| --- | --- | --- | --- | --- |
| 1 | Loop breakers (Emit/Breakers.idr:74-117) | `idr-loop-breakers`, which exists | the registry's column on the attribute (row 4) [M: the two disagree today] | −120 Idris |
| 2 | Lambdas' totality (Emit/Breakers.idr:119-138) | `idr-effects` | a `diverge` bit (row 5) | −40 Idris |
| 3 | Op and type spelling: 91 op and attribute names, 9 type names [M] (Emit/Operations.idr, MLIR.idr:78-111, Types.idr:215-472) | ODS | generated (rows 2, 3) | −500 Idris |
| 4 | The `inline-unreachable` epilogue (Emit/Bodies.idr:145-160) | one C++ normal form and a verifier rule | Emit ends a body in `ub.unreachable` like any region; the pin's Idris site goes | −15 Idris |
| 5 | Closure conversion (Term.idr:299-320; Emit/Bodies.idr:162-183, 308-344) | a region op for a lambda that captures implicitly, closed by upstream's `makeRegionIsolatedFromAbove` (mlir/include/mlir/Transforms/RegionUtils.h:69) and outlined by `outlineSingleBlockRegion` (mlir/include/mlir/Dialect/SCF/Utils/Utils.h:69) | after #1-#3; Term then keeps binders, scopes, types and one op node | −300 Idris, +150 C++ |
| 6 | Dictionary fields (Frontend/Translate/Dictionaries.idr; State.idr:116-126; the restart loop, Programs.idr:74-96) | idr-defunctionalize and idr-specialize | §1.1 (b) | −200 Idris |
| 7 | Value shapes beyond what types need (Instances.idr:130-152) | idr-specialize | §1.1 (b) | small |

Stays in Idris: the box/sum decision (AGENTS: Idris decides
representations; row 12), the polymorphic-recursion check on TT
(Frontend/Translate/Recursion.idr), the registry and the profile.

### 4.2 C++ that re-implements an upstream mechanism

Beyond what mlir-survey.md lists (its §3 covers the hand-rolled fixpoints,
its long tail `CallGraph`):

| # | Ours | Upstream | Verdict |
| --- | --- | --- | --- |
| 1 | 12 reference walks (row 10) | an `Analysis` cached by the AnalysisManager; upstream `CallGraph` sees only `CallOpInterface` (survey, long tail) | one closure-aware analysis of ours, cached the upstream way. C |
| 2 | Euclidean `div`/`mod`, `to_char`, `to_byte` folders (Dialect/Ops.cc:188-227, 1072-1083, 1173) | `arith`'s folders and IntegerRangeAnalysis on the expansion the lowering already writes (Lower/Patterns.cc:249-349) | expand early, behind the guard of §2 #1; the folders go. C |
| 3 | idr-canonicalize copies canonicalize's options (Canonicalize/Pass.cc:1-14) | `createCanonicalizerPass(GreedyRewriteConfig)` takes a config with a listener (mlir/include/mlir/Transforms/Passes.h:65-67; mlir/include/mlir/Transforms/GreedyPatternRewriteDriver.h:120-121) | wrap upstream's pass instead of copying its configuration. Low. C |
| 4 | Lower/Bigs.cc restates the runtime's small cases (Bigs.cc:1-10) | the runtime's bitcode is inlined where it pays (idris_rt.h:3-8) | an inlinable small path in `runtime/big.cc` would be the one copy; measure first. C |
| 5 | The Idris mirror of ODS (rows 2, 3) | TableGen backends (`-gen-python-op-bindings`), `--dump-json`, `tblgen-to-irdl` | generate it. M (the dump parses IdrOps.td: 81 ops, typed operands, assembly formats) |

## 5. PINS.md

| Entries | Kind | Report and check | What representation would do |
| --- | --- | --- | --- |
| `remove-dead-values-address-taken` | upstream MLIR bug | upstream/ and tests/upstream/ | Our representation triggers it twice: closures name functions, and every clone names itself on purpose (IdrOps.td:1473-1478). Its poison operands spread into at least 3 special cases (§2). Saying "callers to come" in MLIR's own vocabulary, symbol visibility, instead of a self-reference, would shrink it (C) |
| `inline-unreachable` | upstream MLIR bug (the `ub` dialect's inliner hook) | yes | The workaround lives in 3 producers in 2 languages and nothing checks it (§2 #7): one normal form and a verifier rule; Emit's part goes |
| `mlir-recursion`, `bytecode-deferred-quadratic` | upstream MLIR bugs | yes | Their measured cases are lists ("a computed list of 10,000 elements is a constant nested 10,000 deep", PINS.md): a flat spine (row 20) retires the list case; the reserved stack stays for other deep data (C). The transport table (Eval/Reify.h:63-73) is that flat form already |
| `uplift-final-counter` | upstream MLIR bug | yes | ours to fix by rebuilding the final value (survey §9) |
| `prune-before-remove-dead-values`, `simplify-structural-fixpoint` | upstream MLIR bugs | yes | none |
| `orc-lljit` | an upstream gap | upstream/execution-engine-process-symbols has a README and no reproducer, and tests/upstream/ has no check, which upstream/README.md:6-17 asks of every entry | none; add the reproducer and the check, or record why there is none |
| `mlir-cxx-api`, `cmake-module-restat`, `zones-on-demand`, `llvm-force-enable-stats`, `platform-gate-x86_64`, `versions-in-lock-file`, `no-stdexec`, `llvm-cxx17-headers`, `darwin-inert-mitigations`, `cmake-import-std-uuid`, `clang-libcxx`, `clang-no-reflection`, `no-sanitizer-runtimes`, `musl-thread-stacks`, `stage2-thinlto`, `runtime-quarantine`, `runtime-cx16`, `simdutf-dispatch`, `linux-uapi-from-host`, `mirrored-sources`, `idris-support-host-cc` (21) | toolchain, platform, build, deviations from cpp-starter | — | none; `versions-in-lock-file` is itself a one-source fix |

None is recorded as ours (a bug that does not reproduce upstream).

## 6. Already representation-first: keep

- Grades as types, in canonical form (IdrOps.td:131-146; Dialect.cc:164-183),
  checked after every pass, with `quantities-kept` stating that no pass
  drops or widens one (Expect/Quantities.cc:1-7).
- Ownership and exclusivity as grades proved on the solver and verified
  (Exclusive.cc:1-16; Verify.cc:1-11).
- Effects as declarations: four resources, `MayCrash` derived from one
  `getCrashCause` (Idr.h:143-175), call effects as an external model
  (CallEffects.cc), `onlyAllocates` and `performsIO` derived from effect
  instances (Dialect.cc:836-875).
- Arrays as builtin memrefs, loops as linalg, upstream's vectorizer, and
  `memref.dim` folded through `ReifyRankedShapedTypeOpInterface`
  (Dialect.cc:65-71).
- `CallsRuntime`: the runtime function's name is the op's (Idr.h:80-99), its
  lowering generated from the op list (Lower/Patterns.cc:545-563), its folder
  the runtime itself (Fold.cc:1-6).
- The registry: names only there, `Shown` without `Eq` (Ids.idr:33-45), one
  hook constructor per behaviour and kinds by construction
  (Registry/Entry.idr:176-266), origin computed once and carried in every
  location (Registry/Libraries.idr:28-41; Loc.idr:11-23).
- `Term` as a nested datatype: an unbound variable is a type error
  (Term.idr:5-9).
- One spelling per value: canonical big decimals (Dialect.cc:114-124), one
  runtime form per integer (idris_rt.h:129-133), tags as positions
  (IdrOps.td:341-343), `Nat`'s range in its type (IdrOps.td:109-119).
- Discardable attributes named, placed and verified, and the rule that an
  Idris fact is never one (IdrOps.td:38-41; Dialect.cc:755-901).
- Keys as names, not symbol uses (IdrOps.td:1426-1428); evaluation results as
  a flat DAG (Eval/Reify.h:63-73); divergence as an op with an effect where a
  recursion becomes a loop (`idr.may_loop`, IdrOps.td:585-595).
- Tests as named properties (Passes.td:512-568; `tests/programs/*/mlir.expect`).

## 7. Staged plan

Every lane runs `make check`; after compiler changes `make build` and
`make test`; after C++ changes `make test-idr`; after a change of MLIR usage
`make test-mlir-tools` (AGENTS). Lanes in flight: frontend shapes and
dictionaries (Instances, Closed, Dictionaries, Types.idr, idris-mlir-cc.cc),
Ownership (Borrow, Exclusive, ResetReuse), NarrowLanes, Meet.cc, lowering of
calls, runtime/io.cc.

| Stage | Lane | Files | Gate (besides the above) | Collides with |
| --- | --- | --- | --- | --- |
| 0, now | Quick fixes: the dead `clone-limit` (Passes.td:417-418, Simplify.cc:57, 208); the verifier rule of §2 #7 (Dialect.cc); the internal errors spelt as rejections (Lower/Layout.cc:89 and Lower/Arrays.cc:235-238; row 19); the dead exit-4 branch (Frontend/Main.idr:214-229); the stale comment (IdrOps.td:1423) | as listed | a verifier negative in tests/idr/verify; the internal errors from MLIR input, none spelt as a rejection | none (idris-mlir-cc.cc untouched) |
| 1a, now | The call graph leaves Idris (rows 4, 5, 21) | Emit/{Breakers,Index,Attributes,Declarations,Bodies}.idr (the attribute carries *break last*; the location keeps *report at caller*); Facts/*; IdrOps.td (`Effect`, and the attribute's name if it changes) with Dialect.cc's list; Passes/LoopBreakers.cc; Passes/TailLoops.cc | `every-cycle-has-breaker` after each round; a new property that a cycle with a non-break-last function never breaks at a break-last one, on the appendix's program; `facts-as-marked`; every program's output unchanged against Chez; bench within noise; compile times within 10% | none |
| 1b, now | The ODS mirror, Emit's half (rows 2, 3, 23) | a generator beside the dialect; the Makefile's step before the Idris build; Emit/Operations.idr; MLIR.idr; Emit/Types.idr | a spec that the generated module is current; every emitted module parses and verifies | none: Types.idr waits for stage 4 |
| 1c, after 1a | One reference analysis (row 10) | a new analysis in lib/Facts; LoopBreakers.cc, Expect/*, Stack/Recursion.cc, BindingTimes.cc, Inline.cc, Infer.cc, Contify.cc, Defunctionalize.cc, Eval.cc | no output changes; compile times | Borrow.cc stays for stage 3 |
| 2a, after "lowering of calls" | Guards and one meaning per primitive (rows 14, 15) | IdrOps.td, Dialect/Ops.cc, Fold/Fold.cc, Lower/Patterns.cc, generated ops | tests/programs/semantics against Chez; crash messages, locations and exit status unchanged; `folds-balanced`; bench | lowering of calls |
| 2b, after "lowering of calls" | One runtime form of closures; the runtime's mode (rows 6, 18) | Eval/Eval.cc, Lower/Closures.cc, Lower/Runtime.cc, Lower/Layout.*, Eval/Reify.cc, runtime/alloc.cc, runtime/rc.cc | tests/programs/eval; every program with and without `--no-eval` equal; compile times | lowering of calls; not io.cc |
| 2c, after "lowering of calls" | Flat list constants (row 20) | IdrOps.td, Fold.cc, Specialize/Pattern.cc, Lower/Runtime.cc, Eval/Reify.cc, Facts/Closures/Passed.cc, Dialect/Sharing.cc | a fixture computing a 10^5-element list compiled on an 8 MiB stack (C: today it needs the reserved one); tests/upstream unchanged | Lower/Runtime.cc if the calls lane holds it |
| 3, after Ownership and NarrowLanes | Ownership from grades and declarations (rows 13, 16, 17; §2 #2, #3, #6) | Idr.h, Dialect.cc, IdrOps.td, Ownership/*, Passes/Narrow.cc, Lower/Layout.cc | owned-stage verifier fixtures; `IDRIS_RT_LIVE=1` leak checks on every program; bench | Ownership lane, NarrowLanes |
| 4, after the frontend lane, lists 3a and io.cc | 4a `Prim` and `IOOp` from generated ops (row 2); 4b instance keys by induced types, dictionaries through defunctionalization (row 8); 4c contiguous runs share the cell and the view (row 7) | Types.idr, Frontend/Translate/*; runtime/strings.cc, Lower/Strings.cc, Lower/Arrays.cc | the frontend lane's and lists' gates; string fixtures against Chez | frontend lane, lists, io.cc |
| 5, last | Closure conversion in MLIR (row 1; §4.1 #5) | Term.idr, Emit/Bodies.idr, Frontend/Translate/Terms.idr, a new pass | everything; `.core` dumps change | all Idris lanes |

Stages 0 and 1a are done (cleanup lane R1). Stage 1a as landed: Emit marks
no breakers and writes the *break last* column as `idr.break_last`, which
idr-loop-breakers reads (`breaks-last` states its rule); Emit/Breakers.idr
is gone; `#idr.effects` has a third bit, `diverge`, seeded where a body
lacks `idr.total` and propagated through every function, those Idris proved
included (a proof does not see the implementations an interface method
reaches); every lifted function is `idr.total`, its body having no loop of
its own; and one rule the audit did not name keeps `idr.total` a statement
about a body: a body that takes in one without the proof, by inlining or
contification, loses it (facts::inlined), since a loop of the callee's may
close there. Every benchmark's object code is unchanged by it.

## 8. The limit

Where a second representation is essential, and stays:

- **TT and the dialect.** Idris's terms need a translation, and Idris's
  types make distinctions the dialect's do not (`Ty`'s signedness, `Char`,
  `Lazy`, Nat-likeness), because MLIR's integers are signless and the
  signedness is on the op (`is_signed`, §3 #6). Two type languages for two
  jobs; the third, `MType`, is accidental.
- **The runtime's C ABI.** `idris_rt.h` declares each called op again
  because C is compiled apart; the name is derived (Idr.h:80-99), and a spec
  could check that every `CallsRuntime` op's function is declared (C). The
  word size is stated twice for the same reason, and reconciled by a check
  (Lower/Layout.cc:84-91).
- **Box-ness in the type.** MLIR types cannot look up symbols, so
  `!idr.box` and `!idr.data` cache the declaration's flag, with a verifier
  rule (Dialect.cc:558-579). Grades as wrapper types cost `unrestricted(`
  76 times in 29 files [M]; that is the price of keeping the grade
  orthogonal to the carrier, which keeps the verifier simple.
- **Messages and decisions.** The `fused<"library">` location and
  `idr.library` serve two readers (row 21).
- **No slot on builtin.module or func.func.** Facts of the module and of
  functions are discardable by necessity unless the program and its
  functions become ops of ours, which every module-anchored pass would have
  to follow: not worth it; make losses loud instead (§2 #6). Every such fact
  is conservative when absent (§1.1 (c)).
- **Strings, arrays and seqs** are three types because they prove three
  things; only their cells and views are accidental copies (§1.1 (a)).
- **A transport form for evaluation results** while constants stay nested.
- **Instance keys that make types reduce** stay in Idris, and so does the
  polymorphic-recursion check on TT's size-change graphs.
- **The evaluator's tick and crash report** differ from a program's for good
  reason; its allocation and counting need not (row 18).
- **The semantics** (Nat as a big, the world, laziness, Euclidean division,
  Chez's strings) is essential complexity; representation removes only the
  copies of it.

## Appendix: measurements

**Loop breakers (M).** Tools of the shared tree, built 2026-10-02 08:13
from main (`build/dev/foreign/idr/idris-mlir-opt`,
`compiler/build/exec/idris-mlir`); Emit/Breakers.idr and LoopBreakers.cc have
not changed since 34cdd6e (05:49). The program, in a scratch directory
(blank lines left out here):

```idris
module Main
import Prelude
%default covering
data Rose = Node Int (List Rose)
covering
implementation Show Rose where
  show (Node n ts) = "Node " ++ show n ++ " " ++ show ts
build : Int -> Rose
build 0 = Node 0 []
build k = Node k [build (k - 1)]
main : IO ()
main = do
  s <- getLine
  putStrLn (show [build (cast s)])
```

compiled with `idris-mlir --cg mlir --no-prelude -o prog Main.idr`
(IDRIS2_PREFIX at the pinned Idris), then `idris-mlir-opt --idr-loop-breakers`
on the emitted module, and on the same module with `no_inline` removed.

| | Functions with `no_inline` |
| --- | --- |
| Emit | `Prelude.Show.show[List Main.Rose]` (with `idr.library`) |
| idr-loop-breakers on Emit's module, as the pipeline runs | `Prelude.Show.show[List Main.Rose]`, `Main.build`, the Prelude's local `show'` at `Main.Rose` |
| idr-loop-breakers alone | `Main.show{show_Show_Rose}`, `Main.build`, `show'` at `Main.Rose` |

**ODS as data (M).** `llvm-tblgen --dump-json -I mlir/include -I
foreign/idr/include foreign/idr/include/idr/IdrOps.td` exits 0 and gives 81
records deriving from `Op` with an `Idr_` name, each with `opName`, typed
`arguments` and `assemblyFormat`; 45 carry `Idr_CallsRuntime`.

**Counts (M).** `wc -l` for sizes. `grep` over `compiler/src` for quoted op
and attribute names of `idr`, `arith`, `math`, `func`, `ub` and `memref` (91
distinct) and `!idr.` types (9); over `foreign/idr/lib` for `unrestricted(`
(76 in 29 files), `isJit()|jit` (31 in 8 files), `ub::Poison` (the 14 sites
of §2), `CPred` in IdrOps.td (13), the array loops (`ArrayGenerateOp`,
`ArrayFoldOp`, `isArrayLoop`: 31 in 7 files; in Idris `ArrayGen`, `ArrayFold`,
`ArrayLoop`, `loopTerm`, `arrayLoop`: 40 in 8 files), `unsupported (` phrases
(5 reasons), and for Idris names in C++ string literals (none);
`runtime/idris_rt.h` for `idris_rt_` functions (85); tests/idr for public
`() -> i64` roots (8 files).
