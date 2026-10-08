# Adversarial review: the representation cutover

## Verdict: executable after named concrete prerequisites

The move holds: consumption on ops, guards plus total ops, closure
conversion on `makeRegionIsolatedFromAbove`, memo sums, one lowering, a
generated primitive set and handles are each the right MLIR mechanism.
But four contracts would make lanes write code that does not compile or
does not verify: C2.2's `borrow` grade, C2.1's trait table, C7's runs and
C3's folds. Several others leave a literal worker to guess. P1 to P12
below are contract sentences the coordinator can write before launch. P1
needs the owner (see "Disagreements"). No lane in the row of a
prerequisite should start before it is in `contracts.md`.

| # | Prerequisite (the chosen sentence is in the finding) | Lanes | Finding |
|---|---|---|---|
| P1 | Decide C2.2: either the ODS operand constraints and every declared-vs-view comparison accept `borrow`, plus a graded-array length op; or views stay plain and the stage is derived from `own`/`excl` grades | U03, U21, coordinator | R1 |
| P2 | C2.1: `idr.con` keeps its own effects and speculation; ops whose effects ODS declares get only the interface; `idr.force` is not in the static table | U03, U04, U09, coordinator | R2 |
| P3 | C7: an iteration API over a run's cells, every spine walker listed with its owner, the spine-mismatch rule and `getRun`'s canonical form | U19, U14, U13, U09, U21, U04, U03, U10 | R3 |
| P4 | C3.4: guards fold on today's `known*` predicates, not on constants alone; folders read no analysis | U04, coordinator (`Canonicalize.td`) | R4 |
| P5 | C3: the ownership of a guard on a string or a big | U03, U04, U17 | R5 |
| P6 | C3.3: an operand is guarded only by a guard of the same string or array | U04 | R6 |
| P7 | C5.1/C6.4: unknown lazy keys are `unsupported` in a program and leave the round for runtime in the evaluator | U09, U14 | R7 |
| P8 | C5.1: the `by_name` criterion and the CAF case; C12's `memo-shared-stream` observes memoization without an effect | U09, U23, owner (O3) | R8, R9 |
| P9 | C8.3/C4.2/C8.4: what replaces `IOOp` in `Term.Effect`, `Hook.IOCall` and `Hooks.idr`; where operand `Ty`s come from | U07, U17, U18 | R10 |
| P10 | C9: who owns the string of an `env_get`/`env_pair`/`dir_entry` handle; `exitWith`; `exit` and the live-cell count; `OSClock`'s type entry; `prim__castPtr` | U16, U18 | R11 |
| P11 | Ownership of the files no lane owns but the contracts change | coordinator | R12 |
| P12 | C13: `make check` is not build-free and is red mid-swarm; hold U01's `IDR/Simplify` change out with the clang hunks | coordinator | R13 |

**Evidence timing.** Everything below is **source-confirmed at ee4ce8e**
(`git log -1` = ee4ce8e; the packet is the only untracked change).
Upstream claims are checked against the pinned sources under
`.toolchain/llvm-project`, which are **source-confirmed at the pin**. I
built nothing and ran nothing but read-only commands.

**Already folded by the coordinator while I reviewed** (current at review
end; I confirm them with evidence of my own and do not repeat them as
findings):

- C5.5 no longer makes static memo cells thread-local. Two further
  reasons, besides the one C5.5 gives: lld resolves an absolute
  relocation against a TLS symbol to its offset in the TLS segment, not
  an address (`lld/ELF/Symbols.cpp:131-140`, `Relocations.cpp:127-129`),
  so a constant cell pointing at a TLS memo cell would hold a small
  integer; and the evaluator's JIT is built with
  `setUpInactivePlatform` (`IDR/Eval/Jit.cppm:226`), and JITLink's ELF
  TLS needs ELFNixPlatform's `__tls_get_addr` and key fix-up
  (`JITLink/ELF_x86_64.cpp:33-80`, `Orc/ELFNixPlatform.cpp:1172-1216`), so
  `tests/programs/eval/memo-lazy`'s compile-time evaluation of its CAF
  chain would have failed to link.
- C5.3 now handles a label function that borrows a capture. That was
  needed: after defunctionalization no op names a memo label, so borrow
  inference's "fixed" set (`IDR/Ownership/Borrow.cppm:47-63`, built from
  `ClosureOp`, `SuspendOp` and `ClosureAttr`) no longer keeps its
  parameters owned.
- C2.2 now decides "counted" by `Idr_CountedValueType`, so `view(Type)`
  needs no scope.

## Packet edits made by the reviewer

Each is evidence-determined: a wrong API spelling, an omission or a
non-discriminating test.

1. `contracts.md` C1.1 item 1: `Idr_Consumes` now uses a class
   `Idr_ConsumesOperandsTrait` that sets `cppNamespace = "::idr"`. A bare
   `ParamNativeOpTrait` names `::mlir::OpTrait::ConsumesOperands<...>::Impl`
   (`mlir/include/mlir/IR/Traits.td:37-53`, `lib/TableGen/Trait.cpp:44-49`),
   which does not exist. `Idr_MayCrashTrait` (`IdrOps.td:329-332`) already
   does this.
2. `contracts.md` C4.3 steps 2 to 4, and `dispatch/parts/U08-isolate.md`
   "Fixed decisions":
   - the outlined function's results are the `!idr.fn` results, which
     covers a body that ends in `ub.unreachable`;
   - only the region's own terminator becomes `func.return`. The text
     said "each `idr.yield`", which would also rewrite the yields of
     matches nested in the body;
   - the attributes in MLIR terms: `idr.break_last` when the enclosing
     function has it, and `idr.total` always (`Emit/Attributes.idr:31-45`,
     `Emit/Bodies.idr:177`);
   - the location is the `NameLoc` that `Emit/Bodies.idr:181-182` gives
     today. `IDR/Expect/Named.cppm:29-45` finds lifted code by that name.
3. `contracts.md` C8.1: removed `to_char`, `div`, `mod`, `shl` and `shr`
   from the `Idr_Primitive` list. Each has the inherent
   `UnitAttr:$is_signed` (`IdrOps.td:679` class `Idr_DivisionOp`, the
   class `Idr_ShiftOp`, and `Idr_ToCharOp`), which the same section says
   makes `idris-mlir-tblgen` fail.
4. `contracts.md` C7.2: added `IDR/Eval/Encoding.cppm`'s `decodeResults`
   to the cell-by-cell builders (`Encoding.cppm:134` calls `ConAttr::get`
   once per cell).
5. `contracts.md` C3.1: split the buffer row. `buffer_load` and
   `buffer_store` have no count operand (`IdrOps.td:1312-1337`; the span
   is the word's size). `buffer_set_string`'s count is the string's byte
   length. `buffer_copy` has two spans (`IdrOps.td:1341-1351`).
6. `contracts.md` C12, `idr/guards/speculation`. LICM visits only a loop
   body's top-level ops (`mlir/lib/Transforms/Utils/LoopInvariantCodeMotionUtils.cpp:75-87`),
   so the old `scf.if` case could never fail. It is now an `scf.while`
   case.
7. `dispatch/parts/U14-eval.md`: the JIT's symbol table also gains
   `idris_rt_inc`, `idris_rt_dec` and `idris_rt_caf_release`. Today's
   table, `IDR/Eval/Jit.cppm:85-122`, has none of them, and C6.1 and C5.5
   make every scratch module call them. Without them, every compile-time
   evaluation fails to link with "Symbols not found".
8. `findings.md` F-own-2: added the other homes of `idr.stage`:
   - `Rc.cppm:39`, `:61`;
   - `IdrOps.td:45`;
   - `CS/Dialect/Idr.idr:136-139`;
   - `Passes.td:550`;
   - 14 `tests/idr` files.

## Findings

### R1. The `borrow` grade on views does not type-check against today's ODS, and three unowned verifiers reject it (C2.2)

**Claim.** "`idr-rc` writes `(u, borrow)` on every value of a counted
carrier that it treats as a view … It never writes plain `T`", and
`view(type)` returns `(q, Borrow)`.

**Evidence** (source-confirmed at ee4ce8e). The ops that take views
declare plain-type operand constraints:

- `idr.field` and `idr.tag`: `Idr_SumType` (`IdrOps.td:437`, `:454`);
- `idr.str.length`, `str.index`, `str.head` and the other string ops:
  `Idr_StrType` (`IdrOps.td:883-1182`);
- the big ops: `Idr_BigType`.

In all, 31 operand declarations use `Idr_StrType`, `Idr_BigType`,
`Idr_NatType`, `Idr_BoxType`, `Idr_SumType` or `Idr_BigOrNat`. Each is a
TypeDef constraint, which a `!idr.q` does not satisfy. The generated
getters are `TypedValue<StrType>`, so `op.getStr()` on a graded value is
a failed `cast`.

The declared-vs-value checks compare a declared plain type with
`view(...)` or with `fieldType(...)`, which gives permission `·`
(`Dialect/Grades/FieldType.cc:8-13`):

- `Dialect/Ops/Con.cc:53`;
- `Dialect/Ops/Field.cc:28-31`;
- `Dialect/Ops/Matches.cc:76-82`, the case region's arguments;
- `IDR/Ops/Elements.cppm:15`;
- `idr.dest.write`'s `PredOpTrait` (`IdrOps.td:501-503`).

Upstream `memref.dim` takes only a memref type. Today it reads a view of
an array (`tests/idr/lower/arrays.mlir:117-119`), and C3.1 builds every
array guard's length with it.

**Counterexample.** `tests/idr/effects/erased-consumer.mlir:34-37`, as
`idr-rc` would write it under C2.2:

```mlir
%v = idr.borrow %b : !idr.own<!idr.box<@Box>>        // result now (ω, borrow) box
%s = idr.field %v[@Box, 0] : ... -> <(ω, borrow) str>  // operand fails Idr_SumType; Field.cc:28 wants plain !idr.str
%n = idr.str.length %s                                // operand fails Idr_StrType
```

Two more:

- `idr.dest.write %h, %v` in `tests/idr/loops/trmc.mlir:21`:
  `view(!idr.own<box>)` is no longer the destination's `!idr.box<@List>`;
- `idr.con` of an owned field: `Con.cc:53`.

None of `Con.cc`, `Field.cc` or `Matches.cc` is in any lane (R12), and
C1.1 changes none of these constraints.

**Correction (P1, owner's choice; see Disagreements).** My chosen
sentence: "Views stay plain `T`; `idr.stage` is replaced by
`ownership::inOwnedStage(Operation *)`, true when any value in the
enclosing module has permission `own` or `excl`, and `idr-rc`, which
grades as it goes, hands its own stage to `Counting` and `isBorrowed`
explicitly instead of asking the module."

That keeps F-own-2's goal: no attribute that a pass can drop or forget.
It changes no ODS constraint. A module with no `own`/`excl` value has no
counted value to misjudge.

If the owner keeps the `borrow` grade instead, C1.1 must change every
operand constraint above to an at-view-grade constraint, and also needs:

- a graded-array length op in place of `memref.dim`;
- `fieldType` and `view` split into "declared" and "view";
- `Con.cc`, `Field.cc`, `Matches.cc` and `Tag.cc` owned by a lane.

### R2. C2.1's trait table does not compile for three of its rows (C1.1 item 1, C2.1, C5.4)

1. **`idr.con` is not `Pure`.** It declares
   `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` and
   `ConditionallySpeculatable` (`IdrOps.td:405-408`), and `Con.cc:17-33`
   reports `Allocate` on a box (on `AutomaticAllocationScopeResource` for
   an `idr.stack` cell) and `NotSpeculatable`.
   - Adding `Idr_ConsumesOnly` lists the same interfaces again through
     different defs. tblgen dedups traits by def (`lib/TableGen/Operator.cpp:759-768`),
     so the op gets the interface trait twice.
   - If the old ones are dropped instead, a box `idr.con` becomes
     `AlwaysSpeculatable` and loses its allocation.
   - So U03's acceptance "Before `idr-rc`, `idr.con` … `isMemoryEffectFree`
     holds" is false for a box today.
2. **"today's, plus `consumedEffects` in `Lin.cc`, `Dest.cc`,
   `IDR/Ownership/Ops.cc`" cannot be written.** Those ops' effects are
   ODS-declared:
   - `Res<…, [MemAlloc<Idr_LinResource>]>` (`IdrOps.td:1774`, `:1786`);
   - `Arg<…, [MemWrite]>` (`:505`);
   - `Arg<…, [MemRead, MemWrite, MemFree]>` (`:1612`, `:1673`, `:1652`).

   For those, OpDefinitionsGen generates the whole `getEffects`
   (`tools/mlir-tblgen/OpDefinitionsGen.cpp:3613-3720`). None of the
   three files has a hand-written `getEffects` to extend (grep: no match).
3. **`idr.force`'s consumption is not static.** `Idr_Consumes<"0">` makes
   `consumes()` true, so `useOf` says Consume at every force, and
   `idr-rc` would `dup` the cell before every force that is not its last
   use. C5.4 wants a borrow except at the last use. That is placement, as
   for `idr.take`, not a per-op fact.

**Correction (P2):** "`idr.con` gets `Idr_Consumes<"0">` and keeps its
own `getEffects`/`getSpeculatability`, which also call `consumedEffects`
(`Dialect/Ops/Con.cc` joins U03); an op whose effects ODS declares gets
`Idr_Consumes` (the interface) and no `Free`, since its effects already
make it impure; `idr.force` gets no consumption trait, `consumes` is
false for it, and `idr-rc` makes a force that is its operand's last use
an owned use as it places `idr.take`, with `ForceOp::getEffects` reporting
`Free` when the operand is owned."

`getODSOperandIndexAndLength` itself is fine. It is generated public on
every op, inline when there is no variadic
(`OpDefinitionsGen.cpp:2087-2124`, `:2199-2216`). The interface default
calling `$_op.consumedByTrait(number)` also works: `$_op` becomes
`(*static_cast<ConcreteOp *>(this))` (`OpInterfacesGen.cpp:144-150`).

### R3. `#idr.con` runs make every walk of a list quadratic, and two attributes can still denote one value (C7)

**Claim.** "A run of any length is therefore one level deep to MLIR's
printer, parser, bytecode and walks", and `getFields()` reads both forms
"as today".

**Evidence.** C1.1 item 6's storage is `(ctor, stored, tail, spine)`,
with no offset. So the suffix `getFields()` must return at index `s`
("the same run at offset k + 1") is a new `ConAttr` whose `stored` is a
new `ArrayAttr` of the remaining n-1 cells: O(n) to build, and uniqued
in the context for the rest of the compilation. Walking a list by
`getFields()[s]` then costs Σ(n-k) = O(n²) time and storage. For C12's
10^5-element constant that is about 5·10^9 cell pointers.

Our own walkers do exactly that, and C7 lists only three of them
(StaticData, Reify, Fold). The others:

- `Ops/Constants.cppm:60`, reached from `ConstantOp::verifySymbolUses`
  (`Dialect/Ops/Constant.cc:80`). It runs **after every pass**.
- `Lower/Lowering.cppm:101-127`, `functionClosure`, run by
  `checkNoClosures` on every `idr.constant`.
- `Eval/Encoding.cppm:17-18`, `:63-72` (encode) and `:134` (decode).
- `Defunctionalize/Closures.cppm:69`, `:89`; `Analysis.cppm:37`;
  `Converter.cppm:226`; `Slots.cppm:309`.
- `Specialize/KeyOf.cppm:29`, `Specialization.cppm:107`,
  `ShapeOf.cppm:43`, `UnrollSize.cppm:34`.
- `Sharing/Aliases.cppm:25`.
- `Ownership/ReachesOnlyAtoms.cppm:29-30`.
- `Facts/Passed.cppm:77`.
- `Ops/Untyped.cppm:17`. It rebuilds through `ConAttr::get`, and each
  prepend copies the run.
- `Layout/Layouts.cppm:145`.

The canonical form also leaves two things open:

- what `get` does when the one same-constructor field is a run with
  another spine index. Example: a zig-zag tree,
  `Node Leaf 1 (Node (Node …) 2 Leaf)`, spine 2 then spine 0;
- whether `getRun` given a same-constructor tail, or one cell, merges or
  stays plain.

Either leaves two attributes for one value. The default ODS builder over
`(ctor, stored, tail, spine, type)` bypasses canonicalization.

**Correction (P3):** "A run is walked only through
`ConAttr::getRunCells() -> ArrayRef<ArrayAttr>`, `getTail()` and
`getSpine()`; `getFields()` on a run is for reading one cell's fields;
`get` and `getRun` canonicalize (a run's cells share one spine index, a
cell whose same-constructor field is a run of another spine starts a new
run, a run has at least two cells, and a same-spine tail is merged), the
default builder is skipped (`skipDefaultBuilders = 1`) and the verifier
rejects a non-canonical run; C7.2 names every walker above with its
owner, and each walks cells in a loop."

Without that, U19's representation turns the linear walks that exist
today into quadratic ones, and the deep-list test runs out of memory.

### R4. Guards that fold only on constants kill today's string folds (C3.4)

**Claim.** "A guard folds to its operand when … the operand is a
constant; `IntegerRangeAnalysis` proves it; its type proves it …; it is
a `nonempty` of a constant non-empty string."

**Evidence.**

- Emit now writes `str.head (check.nonempty (str.cons c s))` (C3.2).
- `Canonicalize.td:50-55` matches `(Idr_StrHeadOp (Idr_StrConsOp $c, $s))`
  and the two `HeadOfShow*` patterns, so none of them can match until
  the guard folds. Under C3.4 the guard never folds on a `str.cons`.
- `Canon/Feeds.cppm:124-125` asks whether a builder's consumer is a
  `StrHeadOp`, and now it is a guard.
- Today's `knownNonEmpty` already proves "a string built with a character
  or a number in it" (`Idr.h:177-183`, `StrTailOp::getCrashCause`,
  `IdrOps.td:893-899`).
- work-units deletes `Dialect/Crashes/*`, but
  `Canon/MatchPatterns.cppm:25` still calls `knownNonEmpty`.
- A folder cannot run `IntegerRangeAnalysis`: range-based erasure is a
  pass, here `idr-in-bounds` (C3.5).
- "Its type proves it (a `!idr.nat` is never negative)" applies to no
  guard: no guard takes a natural.

**Counterexample.** `tests/idr/canon/head.mlir`, after Emit's new form:
`HeadOfCons` no longer fires.

**Correction (P4):** "A guard's folder returns its operand exactly when
`knownNonZero` (`nonzero`), `knownFinite` (`finite`) or `knownNonEmpty`
(`nonempty`) holds, or when the condition holds of constant operands
(`in_bounds`, `byte`, `range`); `IDR/Dialect/Crashes` stays; the
`HeadOf*` patterns of `Canonicalize.td` and `Canon/Feeds.cppm` look
through a `nonempty` guard; and no folder reads an analysis."

C3.4's "a guard whose operand is the result of an identical guard" is
harmless. It is nearly dead, though: Emit guards the original value
before each op, so two guards are siblings. C3.5's dominance rule is
what removes the repeat.

### R5. A guard on a string or a big passes a reference through, and no contract says how `idr-rc` counts it (C3, C2.1)

`check.nonzero` takes `Idr_BigValue` and `check.nonempty` takes
`Idr_StrValue`. Each result is the operand itself
(`SameOperandsAndResultType`). By today's `useOf` default (`UseOf.cppm:48`)
the operand is a Borrow, and the result, a new value of a counted type,
is graded owned.

**Schedule:**

```mlir
%b = idr.big.add %x, %y : !idr.own<!idr.big>
%g = idr.check.nonzero %b, "division by zero"
idr.drop %b        // last use of %b was the guard
%q = idr.big.div %a, %g
```

This either drops `%b` before `%g` is read, or double-counts `%g`.
`ReadFrom.cppm:12-22` knows views only from `idr.field` and match
arguments.

**Correction (P5):** "`idr.check.nonzero` and `idr.check.nonempty` are
`Idr_Consumes<"0">` with `Idr_ResultCarriesOperand`: the guard takes the
operand's reference and its result holds it, at the operand's grade."

### R6. The speculation rule does not tie the guard to the op's own string or array (C3.3)

`checkSpeculatability` checks only that the guarded operand is "the
result of its guard op". Nothing checks that the guard's length is the
length of the op's own string or array:

```mlir
%g = idr.check.in_bounds %i, %lenT : (%lenT = idr.str.length %t)
scf.while … do { … %c = idr.str.index %s, %g … }   // %s ≠ %t
```

Here the index op counts as speculatable, and LICM may hoist it above
the `while` condition that protects `%s`.

**Correction (P6):** "An operand counts as guarded only when its
defining guard's length (size) operand is `idr.str.length` (the
`index_cast` of `memref.dim`) of the total op's own string (array or
buffer) operand."

C3.1 should say "the `arith.index_cast` of `memref.dim`": the guard takes
`I64` and `memref.dim` gives `index`.

### R7. An unknown lazy key is a regression in programs and a contradiction in the evaluator (C5.1, C6.4)

**Evidence.**

- `Defunctionalize/Slots.cppm:160-165` follows only func, call, return,
  yield, con, closure, suspend, force, apply, field, match, match_lit,
  lin.enter/use and constant. Every other user, every array op among
  them, gives an `unknown` key (`:331-337`).
- So `IOArray (Lazy Int)` or `newArray n (Delay x)` gives an unknown lazy
  key. At ee4ce8e suspensions stay suspensions and this compiles
  (`Lower/Closures.cppm:120-123`). Under C5.1 it is "internal error".
- U09's dispatch even lists "array elements" among the rewrites.
- In the evaluator the same internal error aborts the whole round
  (`Eval/Round.cppm`: `runPipeline` fails, then `internal(0, "lowering
  the round's calls failed")`). That contradicts C6.4's "left for
  runtime".

**Correction (P7):** "A lazy or closure key the analysis cannot know is
`unsupported (…)` naming the op it flows through, in a program; in
`Round.cppm`, which runs `idr-defunctionalize` alone first, any such key
(and any closure left) keeps every call of the round for runtime."

### R8. `by_name` by `io` effect catches pure-observable code, and diverges from Chez for CAFs (C5.1, F-lazy-8)

**Evidence.** `io` in `idr.effects` means "reaches a `world.new`". That
includes:

- every `Linear.Array` operation (`libs/mlir-linear/Linear/Array.idr:48-146`,
  `unsafePerformIO`);
- `Control.Monad.ST.runST` (`base/Control/Monad/ST.idr:31`);
- `System.Errno.strerror` (`base/System/Errno.idr:23`).

So a `Delay` over a linear-array read loses its memo: the complexity
guarantee C5's own README ruling names ("The memo is our complexity
guarantee").

In the other direction, Chez memoizes a top-level `Delay`:
`schDef n (MkNmFun [] (NmDelay …)) = (define n (delay …))`, and
`(force n)` (`src/Compiler/Scheme/Common.idr:578`, `:668-670`). A
world-forging CAF is therefore run once by Chez but at every force here,
because a static memo cell of a `by_name` constructor never memoizes.

`idr.force`'s effects stay empty (`Dialect/Ops/Lazy.cc:243-247`), so a
`by_name` force that runs `trace` can still move past output. That part
of F-lazy-8 is not fixed.

**Correction (P8, owner's O3):** "A label constructor is `by_name` when
its function reaches an IO op other than an array or buffer op (output,
input or `world.new` of a `trace`-like effect), never for a label that a
static constant names; and `ForceOp::getEffects` reports
`Write<IOResource>` when its operand's sum has a `by_name` constructor."

### R9. Two C12 rows cannot pass as written (C12)

- **`programs/eval/memo-shared-stream`** counts forces "through a
  trusted forged world". Such a label has `io`, so it is `by_name` (C5.1)
  and is forced every time. Chez, the oracle named in the row, runs
  non-CAF `Delay` by name too (`defaultLaziness`, `Common.idr:322-326`).
  The row asserts the opposite of both. User code also may not forge a
  world.
  - Correction: "It observes memoization without an effect: `fibs` shared
    by two consumers, sized so that recomputation exceeds the test's
    timeout, as `eval/lazy-double` does."
- **`programs/io/environment-arguments`** prints `getArgs` against Chez.
  `argv[0]` differs between the native binary and Chez's
  `(command-line)`, and the harness passes no arguments
  (`tests/lib/run.sh:7-15`).
  - Correction: "It prints `length !getArgs` and never `argv[0]`."

### R10. Deleting `IOOp` needs edits that no contract names, in three lanes' files and one unowned file (C8.3)

**Evidence.**

- `IOOp` is the payload of:
  - `Term.Effect` (`Term.idr:94`, `:189`), which is U07's, though C4.2
    does not change it;
  - `Hook.IOCall` (`Registry/Entry.idr:190`), which is U18's;
  - `Hooks.ioCallOf` and `arrayLoopOf` (`Frontend/Translate/Hooks.idr:28-37`,
    `:73-75`), which no lane owns.
- U17's dispatch says "Do not change the registry (U18) or `Term.idr`
  (U07)".
- "Operand types come from the primitive's Idris type, which the
  registry entry already has" is false for the array primitives. Their
  shape is `Pi Q0 TypeOfTypes …` with the element a hole
  (`Registry/Primitives.idr:75-79`), and the element type rides on the
  `IOOp` value (`Types.idr:497-499`). `BufferLoad Ty` and
  `BufferStore Ty` pick the width the same way.

**Correction (P9):** "`Term.Effect` becomes
`Effect : Loc -> IdrPrim -> List Ty -> List (Term a) -> DataId -> Term a`,
whose `List Ty` is the operands' Idris types the frontend reads from the
call (U07); `Hook.IOCall` carries `IdrPrim` (U18); and
`Frontend/Translate/Hooks.idr` joins U18."

### R11. Base's surface: leaked strings, `exitWith`, and the clock type (C9)

1. **Leaked strings.** `getEnv` never frees its pointer
   (`base/System.idr:147-152`). Nor do `getEnvironment` (`:158-172`) or
   `nextDirEntry` (`System/Directory.idr:112-123`): in C, `getenv` and
   `readdir` own those bytes. Under C9.1 a slot holds a counted string
   until `handle_free`, so each call leaves a live cell.
   - `run_ours` fails any program with `idris-rt: live cells N`, N ≠ 0
     (`tests/lib/run.sh:17-36`).
   - Then `programs/io/environment-arguments` and
     `programs/io/directory-listing` (C12) fail.
2. **`exitWith`.** It is `primIO . believe_me . prim__exit . cast`
   (`base/System.idr:310`), and `believe_me` is rejected everywhere
   (`Frontend/Translate/Terms.idr:346`, `Frontend/Profile.idr:247`).
   Registering `prim__exit` leaves `exitWith`, `exitFailure` and
   `exitSuccess` rejected.
3. **`exit` and the live-cell count.** C9.2 does not say whether `exit`
   writes the count. A program that exits with live data would fail the
   harness if it does.
4. **`OSClock`.** It is `data OSClock : Type where [external]`
   (`base/System/Clock.idr:102`), and C9 adds a type entry only for
   `Ptr`.
5. **The clock specs.** The clock primitives have only `scheme:` and
   `RefC:` specs (`Clock.idr:119-121`), so "the C support function its
   spec names" names nothing.
6. **`prim__castPtr`.** C9.1 lists it both as an identity hook and as
   staying `RawPointer` "of a non-handle". A registry entry cannot tell
   the two apart.

**Correction (P10):** "A string handle from `env_get`, `env_pair` or
`dir_entry` is owned by the runtime (one slot per environment op, one
per directory, each replaced by the next call and released by
`dir_close` and at exit), and `handle_free` of it does nothing; the
registry recognizes `System.exitWith` by name as `idr.io.exit` then
`ub.unreachable`; `idris_rt_io_exit` writes pending output and no
live-cell count; `System.Clock.OSClock` gets a `WordType` entry; clock
meanings are Chez's `blodwen-clock-*`; and `prim__castPtr` and
`prim__forgetPtr` are identity hooks, `RawPointer` staying for
`System.FFI`'s allocation primitives only."

### R12. Files the contracts change that no lane owns, and a hidden serialization (README frontier, `ownership.json`)

`validate.sh` checks overlaps, not gaps. Each file below must change, and
no lane may write it:

| File | Why it must change | Evidence |
|---|---|---|
| `IDR/Dialect/Ops/Con.cc` | R1 and R2 (`getEffects`, verifier) | `Con.cc:17-33`, `:53` |
| `IDR/Dialect/Ops/Field.cc`, `Matches.cc`, `Tag.cc` | R1, if `borrow` stays | `Field.cc:28`, `Matches.cc:76-82` |
| `IDR/Dialect/Ops/Generated.cc` | C3.4: `foldDivision` is the total `div`/`mod` folder | `Generated.cc:183-196` |
| `CS/Frontend/Translate/Hooks.idr` | R10 | `Hooks.idr:28`, `:73` |
| `CS/Emit/Attributes.idr` | `inherited`/`lifted` become dead when U07 deletes `lifted` | `Attributes.idr:31-45` |
| `IDR/Canon/Feeds.cppm`, `IDR/Canon/MatchPatterns.cppm` | R4 | lines above |
| `tests/toolchain/runtime-api/rc.c`, `runtime-start/start.c`, `page-size-mismatch/start.c` | `IDRIS_RT_KIND_CLOSURE` and the two-argument `idris_rt_start` (C1.5) | `rc.c:185`, `start.c:43`, `start.c:14` |
| `IDR/Sharing/Aliases.cppm`, `Specialize/*`, `Ops/*`, `Layout/Layouts.cppm` walkers | R3 | R3's list |

Two more:

- **The memo label functions.** After `idr-defunctionalize` nothing
  references them: a constructor named `@f` defines a symbol and uses
  none. Every interprocedural solver between `idr-defunctionalize` and
  `idr-lower` therefore marks their bodies dead
  (`mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp:167-230`). That
  covers `idr-rc`'s `ExclusiveAnalysis` (`Ownership/Exclusive.cppm:55`),
  `idr-narrow` and `idr-in-bounds` (`Narrow/Naturals.cppm:45-49`).
  Thunk bodies lose those facts, and `Commit::meet` writes `ub.poison`
  into "dead" exclusive positions (`Ownership/Commit.cppm:146-158`).
  Proposed (U09): "each memo label constructor carries
  `FlatSymbolRefAttr:$label`, a use of its function."
- **`Layout/Layouts.cppm` is at exactly 400 lines** and
  `Defunctionalize/Slots.cppm` at 376. U10 and U09 must split as they
  edit (C0 says so).

### R13. The verification policy's two exceptions do not hold as written (C13, work-units integration)

1. **"`make check` builds nothing".** False. `check` depends on `runner`,
   which runs Idris on `tests/tests.ipkg` (`Makefile:169-180`). Its
   `spec/dialects-current` fails from the moment the coordinator applies
   C1.1 until integration step 2 regenerates `CS/Dialect/Idr.idr`
   (`tests/spec/dialects-current/run`). `spec/file-size` fails while a
   lane's unit is over 400. So lanes told they "may run `make check`"
   will see red by design, and may "fix" it.
2. **The toolchain rebuild.** Work-units step 3 holds out only U01's
   "two C++ hunks". The `IDR/Simplify` change (`idr-dead-values` deleted)
   needs the patched `remove-dead-values` too. On today's MLIR, a call
   rebuilt every round defeats the fingerprint fixpoint
   (`PINS.md` `simplify-structural-fixpoint`), so step 4 would run the
   simplify loop to its budget.

**Correction (P12):** "A lane runs only the one spec test its acceptance
names (`sh tests/spec/<name>/run`), never `make check`; U01's
`IDR/Simplify` change is held out with its two clang hunks until step 5."

### Smaller points (no prerequisite; for the lane)

- **C1.1 item 4.** `RecursiveMemoryEffects` on `idr.lambda` and
  `idr.delay` says that building a closure runs its body. They should be
  `Pure` (with `NoMemoryEffect` and `AlwaysSpeculatable`), as
  `idr.closure` and `idr.suspend` are today (`IdrOps.td:572`, `:587`).
  Nothing runs before `idr-isolate`, so this is harmless now and wrong
  in phase 2.
- **C10.2.** "the `reuses-in-place` property" is per function
  (`Expect/ReusesInPlace.cppm:19-41`) and names no parameter.
  `ExclusiveAnalysis`'s lattice is `Unknown`/`Exclusive`/`Shared`, with
  no reason (`Ownership/Cells.cppm:16`). So the error's "because <the
  reference that made it shared>" needs provenance in U03's files that
  no contract asks for. Define the promise as: "`p` is promised when an
  `idr.reuse` in `f` takes its token from an `idr.take` of `p`".
- **C10.1.** The memo exclusion holds for heap cells. Static memo cells
  can form a cycle (a constant `fibs` whose forced tail captures the
  constant), but that cycle runs through persistent cells, so
  `idris_rt_caf_release` still releases everything counted. C10.1
  should say so.
- **C6.3.** Holds. After `idr-lower` the world has no components, so an
  IO root is `() -> ()`, and `findRoot` still sees `func.func` only
  (`Lower/Lowering.cppm:40-49`). `main(i32, ptr)` is the C entry on both
  musl static PIE and Darwin.

## Disagreements for the owner

| Claim | Packet's evidence | My evidence | Who must choose |
|---|---|---|---|
| Views are `(u, borrow)`, never plain (C2.2) | F-own-2: a module attribute changes what plain `T` means | R1: 31 ODS operand constraints, `memref.dim`, 4 verifiers and `fieldType` reject it. A derived `inOwnedStage` (any `own`/`excl` in the module) removes the attribute without a sweep. | owner |
| `by_name` = `io` in `idr.effects` (C5.1, O3) | F-lazy-8: Chez runs non-CAF `Delay` by name | R8: linear arrays, `runST` and `strerror` forge worlds, so their thunks lose the memo; Chez memoizes CAFs | owner (O3) |
| Static memo cells (C5.5) | now per process, written once | agree; TLS is impossible both in static data (lld) and in the JIT (inactive platform) | settled |
| The cycle check is type-level (C10.1) | `decision-acyclic-heap.md`, agreed 2026-10-01 | agree. It rejects an acyclic trie of `IOArray (Maybe Trie)`; that is the decided subset. | settled |

## What I checked, and what I did not

**Checked (source-confirmed at ee4ce8e or at the pin):**

- **The ODS and tblgen claims of C1.1, C1.4 and C2.1** against
  `Traits.td`, `OpBase.td`, `Trait.cpp`, `Operator.cpp` (TraitList
  flattening), `OpDefinitionsGen.cpp` (`getODSOperandIndexAndLength`,
  generated `getEffects`) and `OpInterfacesGen.cpp` (`$_op`), and
  against `SideEffectInterfaces.cpp`: `isMemoryEffectFree`,
  `wouldOpBeTriviallyDead` and the `EffectInstance` constructors.
- **Every reader of `idr.stage`**, every `ub.poison` site in the C2.4
  table (the counts match, except that `Sums.cppm`'s is a comment), and
  every user of `ConAttr::getFields`.
- **The guard table** against every `Idr_MayCrash` and
  `MayCrashOpInterface` op. It is complete for today's partial ops. I
  also checked their causes and `CrashMessage.cppm`: the message is built
  from the op's location, so a guard at the same location keeps it.
- **`makeRegionIsolatedFromAbove`'s** capture order and cloning, at
  `RegionUtils.cpp:88-177`.
- **LICM's traversal**, `DeadCodeAnalysis`, JITLink TLS and lld TLS.
- **Base's sources** for the pointer wrappers, `exitWith`, the clocks and
  Chez's laziness.
- **The harness's live-cell rule** and `make check`'s dependencies.
- **Read in full:** the dispatch parts U03, U08, U09, U11 and U14.

**Not checked:**

- Nothing was built or run, so every "would not compile" is read from
  tblgen's and C++'s rules, not observed.
- I did not walk U01's clang reductions, and did not check whether
  #189252 is the predeclared-new fix.
- I did not check:
  - the runtime's macOS paths beyond C9.6's list;
  - the generated Idris module's current content;
  - `validate.sh`'s output;
  - dispatch parts other than those five, beyond targeted greps.
- I did not trace `idr-in-bounds`'s systems for string lengths.
- I did not measure compile times.

**Current at review end:** README, contracts and findings were re-read
for the regions I cite. The coordinator's C5.3, C5.5 and C2.2 updates
are reflected above. No finding above is resolved in the packet as of my
last read.
