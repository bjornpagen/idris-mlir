<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0018: `Fin n` as a machine word where its bound is static

**Amended by P0 (2026-10-21, `0000-mlir-native.md`), by C22, D48, D58,
C4, D90 and D41.** P0 decides what F1 and F2 were to build, in its own
terms:
- **The type decides, not the frontend (C22, D48).** A family of numeral
  shape (`Fin`, `Elem`, `LNat`, a user's Peano type) is the family Idris
  checked, applied to its index terms (`!idr.data<#Fin[n]>`), with a
  number layout, one function of the type: a fixed width at a closed
  bound, a natural otherwise. It converts by `idr.numeral.to_nat` and
  `idr.numeral.of_nat`, with no range check. This replaces §6.1's (c),
  D1 and D5.
- **One form per type (D58).** A known index meets code compiled for
  every index by specialization by layout class, so `Fin 256` is a byte
  through calls, "one mechanism with 0018's". F1's seam, one type in two
  forms by position, is gone (§6.2, D3), and F1 and F2 become that one
  mechanism (C22, taking L04's I7).
- **The countdown recognizer goes (C4),** so D6 has nothing to widen.
- **A linear word is graded `once`** (`!idr.graded<…>`, D90), not
  `!idr.lin` (§11).
- **Unsigned division is `arith`'s** behind `idr.check.nonzero`, and the
  signed division and the four shifts are inline arithmetic, each one C++
  template (P0 §5.3, D41, C23): the MLIR form owed below.

What stands: D2 (byte classes), D4's rule (the height from constructor
types, never names), D8, §5, §7, and F0's measurement, which gates
nothing now that D58 settles F2's question.

**Status:** open, nothing built (2026-10-19). F1 and F2 are P0's: C22's
number layout and D58's specialization by layout class, which settles
F2's question, so F2 waits on no measure. F0 stays **AFTER-SELF**, on the
first stage-1 self run, and gates nothing (D58). Claims are marked
*read* (the path given), *measured*, *recalled*, *conjecture* or
*decision*. The
frontend was read on 2026-10-16: the definitions named are there under
the same names, and its line numbers are left out. LLVM and MLIR paths
are under `.toolchain/llvm-project` (the pinned tree at 7208ba24).

**In short.** The type `Fin n` proves `0 <= i < n`. Today the compiler
drops that fact: every Nat-like type becomes `!idr.nat`, a big (a tagged
63-bit word, or a GMP number), which is counted and tag-tested.

The premise was that `n` is known after monomorphisation. For most
values it is not, and this is by design:
- an erased argument keys no instance;
- a data instance's key erases every index;
- so one instance serves every `n`.

In the self module:
- 0 of the 234 data instances that hold a `Fin` know its bound;
- 150 of the 63,462 function instances have a closed bound anywhere in
  their signature.

The `Fin`s the frontend uses most have bounds known only at run time:
- de Bruijn variables, `Fin nv`;
- growth-check positions, `Fin g.size`;
- `ConId`'s `Fin arity`.

These stay bigs under every design here.

Where a bound is closed, the type's fact can decide the representation:
its layout makes such a value an unsigned word of the smallest byte
class, u8, u16, u32 or u64 (C22). The work comes in three stages:
- **F1** does this where the bound is closed.
- **F2** gives each type one form, so a type argument closes it too: the
  bytes of `Vect 8 (Fin 256)`, or an array of `Fin 256`. D58 settles
  it, as specialization by layout class.
- **F0** is a measurement of what they gain; it gates nothing (D58).

Exact widths, such as `i7` for `Fin 100`, are examined in §5 at the
owner's request and not recommended. They save no memory, cost masks on
x86_64, and make the vectorizers scalarise arrays.

## 1. What exists

- **Every Nat-like type is a natural** (*read*). `coreTypeIn` returns
  `NatT` for any type constructor whose `natness` is not `NotNat`. It
  does this before it reads the type's arguments
  (`compiler/src/IdrisMLIR/Frontend/Translate/Types.idr`).
  - **Nat-likeness** is Idris's `ZERO`/`SUCC` constructor flags, read by
    `natRole` (`Translate/Closed.idr`) and `natnessOf` (`Types.idr`).
  - **`Natness`** (`Translate/State.idr`) is three-way:
    - `NotNat`;
    - `Numeral`, Nat-like with an erased constructor argument, as
      `Fin`'s `FS` has;
    - `Chain`, `Nat` itself.

    `tyConFacts` reads it once per type constructor (`Types.idr`).
  - **`FZ` and `FS`.** `FZ` is the literal 0, and `FS x` is
    `idr.big.add x 1` (`Translate/Terms.idr`).
  - **A match on `FZ`/`FS`** is a match on zero that binds the
    predecessor (`Translate/Cases.idr`).
- **A big** is one 64-bit word. An odd word holds a 63-bit integer, and
  an even word points to a GMP cell (`runtime/idris_rt.h`). A
  natural is counted, and its component is one `i64`
  (`foreign/idr/lib/IR/Layout/Components.cpp`). So
  a `Fin` field takes a counted word, and dropping its cell tests its tag.
- **Ranges and narrowing.** MLIR's integer range analysis is solved over
  the program across calls. Every `!idr.nat` the analysis cannot see
  computed is seeded with `[0, +inf)` (`lib/Analysis/Ranges.cpp`).
  `idr-narrow` then makes each web of bigs that it proves small plain
  `i64` words. Conversions sit where a web meets a big
  (`lib/Transforms/Narrow/`). Fields are untouched: a word
  goes back into a big at the cell.
- **`Data.Fin`** (*read*, `third_party/Idris2/libs/base/Data/Fin.idr`):
  - `Fin : (n : Nat) -> Type`; `n` is an index, not a parameter (`:18-22`).
  - `finToNat` is the unary recursion (`:56-58`). idr-tail's countdown
    rewrite turned it into the identity, for a `!idr.nat` argument only
    (`lib/Transforms/Tail/AccumulatorPlan.cpp`); C4 deletes that
    recognizer, a countdown being the closed form of an accumulated
    loop (D6).
  - `natToFinLT` is the identity through the registry
    (`compiler/src/IdrisMLIR/Registry/Recognized.idr`).
  - Base's own `%builtin NaturalToInteger` for `finToInteger` is
    commented out (`:86`).

## 2. Where `n` is (question 1)

*Read*:
- **Function keys.** An erased parameter that is not type-like and not
  an array shape is `Unkeyed`, so one instance serves every value of it
  (`Translate/Instances.idr`). `n` in `sameFin : Fin n -> Fin n
  -> Bool` keys nothing.
- **Data keys.** `eraseIndices` erases every argument of a type
  constructor that is not a parameter, so that "`Vect 3 Double` and
  `Vect n Double` name one instance" (`Types.idr`). `n` is an
  index of `Fin`. So `Vect 8 (Fin 256)` is the instance
  `Vect[-, Fin _]`.
- **Types.** Even where `n` is closed, `coreTypeIn` drops it (§1).
- **Where a closed `n` survives.** It survives inside a *type argument*
  of a function key. `Typed` keying normalises the type and keeps it:
  `Builtin.fst[… Vect (S^8 Z) (Fin (S^256 Z)) …]`.

*Measured* (2026-10-16). A probe program went through the frontend built
on Chez (`--core`). Its Core dump:

```
data Data.Vect.Vect[-, Data.Fin.Fin _]
  :: tag 1 (w Nat, w Data.Vect.Vect[-, Data.Fin.Fin _])
data Main.Pixel
  MkPixel tag 0 (w Nat, w Nat)              -- two fields declared Fin 256
Main.bump (w Nat) : Nat =                   -- bump : Fin 255 -> Fin 256
  idr.big.add(#0, 1:Nat)
Main.sameFin (w Nat) (w Nat) : Prelude.Basics.Bool = ...
Data.Fin.finToNat (w Nat) : Nat =           -- one instance for every n
```

So `n` reaches the frontend's translation wherever the instance's own
normalised types close it, and it reaches the dialect nowhere. It can get
to the lowering in one of three ways (§6.1):
- re-derived by the frontend from the Idris type it holds at each
  position;
- carried in a dialect type;
- carried as a seeded range.

## 3. How the bound flows (question 2)

Every operation keeps a `Fin n` value inside `[0, n)` by its type: Idris
checked it. Nothing in the dialect needs `n` itself. Only the width of
the representation needs it, and a width needs a static upper bound, not
`n` exactly.

The one way an out-of-range `Fin` could appear is a `believe_me` in a
trusted library. Base has two, `restrict` and `fromInteger`'s lemma, and
both are sound arithmetic (*read*, `Data/Fin.idr`).

| Operation | Today (*read*) | With a closed bound (F1) |
| --- | --- | --- |
| `FZ` | literal 0, a natural | literal 0, a word |
| `FS x : Fin (S k)` | `idr.big.add x 1` | add 1; first zero-extend when `S k` crosses a class (257, 65537, 2^32 + 1) |
| match on `FZ`/`FS` | match zero, predecessor by `idr.big.pred` | match 0, predecessor = subtract 1 (truncated when `k` falls a class) |
| `natToFinLT` | the identity (registry) | natural to word: `idr.numeral.of_nat` (C22), no check; Idris proved `x < n` |
| `finToNat`, `weaken`, `Eq`/`Ord`/`DecEq (Fin n)` | open `n`, one instance; the countdowns become the identity | the caller passes a natural, made of the word by `idr.numeral.to_nat` (C22); under P0 a call whose callee's layout changes at the caller's closed class reaches a copy at that class instead (D58) |
| `natToFin x n`, `last {n}`, `integerToFin` | `n` at run time | unchanged (open) |
| `index : Fin n -> Vect n a -> a` | walks cells; `n` erased | unchanged (open) |
| an array's `!!` with `Index s` | coordinates, as naturals, to extents | unchanged: `Index`'s field is `Fin n` with `n` an index |
| `Data.Bits` shifts (`Index = Fin 64`) | `finToNat`, `cast`; constants fold | the parameter is a word; the conversions fold (*conjecture*) |

## 4. How much it matters (question 3)

*Measured* (2026-10-16). The numbers are from a census of the self
module: the frontend on Chez over `compiler/src` at 1380a9d0 (548 s,
exiting 3 for its refusals then). The dump lists each signature twice,
and the counts are of distinct lines. F0 recounts on the self module of
its own run.

| What | All | With a closed bound |
| --- | ---: | ---: |
| function instances | 63,462 | |
| … with a `Fin` anywhere in their signature | 694 | 150 |
| distinct signature positions that mention `Fin` | 1,163 | 230 |
| … whose type is `Fin` itself (a scalar) | 185 | 11 |
| instances whose key (type arguments) mentions `Fin` | 1,151 | 688 |
| data instances | 8,720 | |
| … that mention `Fin` | 234 | **0** |

The closed bounds in instance keys, by mentions:
- `Fin 256`, the bytes of `Address = Vect 8 (Fin 256)`
  (`Proof/Requests.idr`): 854;
- `Fin 2048` and `Fin 1024`, a `Glyph` (`Proof/Forms.idr`): 323 and
  326;
- `Fin 14`: 210;
- `Fin 3`: 94;
- `Fin 64`, `Data.Bits`: 7.

The constructors with a field of type `Fin`:
- **Bound only at run time:**
  - `Term`'s `Var`, `Case`, `CaseLit` and `CaseNat`, each `Fin nv`;
  - `ConId`'s `Fin arity`.
- **Closed:** the three in `Form`, namely `Bound` (`Fin 3`), and
  `IntegerLit` and `PrimitiveType` (`Fin 14`).

*Read*, the sources:
- **`compiler/src`:** 24 files, about 370 code lines. Most are in the
  growth checker, where positions are `Fin g.size`
  (`Frontend/Growth/Potential.idr`, `Proof/Growth.idr`), and in
  `Term`/`Translate`, as `Fin nv`.
- **The fork:** 5 files.
- **`libs/`:** 3 files, all with run-time bounds or bounds indexed by a
  shape: `Index`, `checkIndex`, `Linear.Vec`.
- **`tests/`:** 13 files.
- **`bench/`:** 3 files, all with run-time bounds: `Fin cap` in
  `unionfind` and `k-nucleotide`, and `Fin n` in
  `spectral-norm-linear`.

So in this tree, the values a static bound would turn into words are:
- the `Address` bytes and `Glyph`s, held inside type arguments;
- a few code functions over `Form`;
- shift amounts, which are constants and fold today.

The hot `Fin`s are bounded at run time.

`Address`'s bytes cost one step a bit: `doubled` computes on the number
itself, `finToNat` and `natToFinLT` being the identity at run time
(`Proof/Requests.idr`, since 3fc4d2e4). What a word representation would
save there is the big's counting and tag tests, which F0 measures.

## 5. Exact widths: `i7`, `i15`, `i1` (the owner's question)

The owner asked: "we can just use the exact mlir sizes for data types…
zig supports… u15 and u7… and leaves it to the compiler." Here is the
evidence from the pinned tree (*read*):

- **Registers.** An illegal width is rounded up and promoted
  (`llvm/lib/CodeGen/TargetLoweringBase.cpp:1131-1137, 1455-1466`):
  - **x86_64:** `i7` becomes i8 and `i15` becomes i16.
  - **arm64:** the SelectionDAG promotes both to i32.
  - **Ops that ignore the high bits:** add, sub, mul and the bitwise ops
    (`LegalizeIntegerTypes.cpp:201-206, 1453-1459`).
  - **Ops that clear the high bits first,** with an `and` of the low-bit
    mask (`LegalizeTypes.h:263-268`): udiv and urem (`:219-224`), lshr
    (`:1521-1533`), and unsigned compares (`:2200-2241`). The `and` is
    skipped only where known bits prove it.
  - **arm64 at -O0** uses GlobalISel, which widens the same way
    (`AArch64Options.td:272-273`; `AArch64LegalizerInfo.cpp:181-185`;
    `LegalizerHelper.cpp:3088-3112, 3341-3358`).
  - **Free zero-extension** exists only from i32 to i64, or after a load,
    on both architectures (`AArch64ISelLowering.cpp:18896-18923`,
    `X86ISelLowering.cpp:36772-36800`).
  - **Net cost:**
    - x86_64 holds i8 and i16 natively, so an `i7` costs masks a u8
      does not (*read*).
    - arm64's legal integers are i32 and i64 (*recalled*), so there an
      i8 is promoted too, and an `i7` costs what a u8 does.
- **Memory.** The store size and the alloc size round up to bytes:
  - `i7` and `i1` take 1 byte, `i9` to `i16` take 2, and `i33` takes 8
    (`DataLayout.h:579-596`, `DataLayout.cpp:969-974, 780-794`;
    LangRef: "the i7 type will use the alignment of i8",
    `llvm/docs/LangRef.md:3704-3710`).
  - Arrays and struct fields take each element's alloc size
    (`DataLayout.cpp:953-958, 60-79`). Our cells and arrays place a
    component by its size and alignment
    (`foreign/idr/lib/IR/Layout/Layouts.cpp:136-152, 190-212`).
  - So an exact width never stores smaller than its byte class.
  - A store of an `iN` zero-extends to bytes (`LangRef.md:12486-12489`).
- **No packing.** MLIR lowers a `memref` of `i7` one element per alloc
  size (`mlir/lib/Conversion/LLVMCommon/TypeConverter.cpp:291-293`,
  `MemRefToLLVM.cpp:980-986`). Its narrow-type emulation packs only
  widths that divide 8 (`i1`, `i2`, `i4`), and it exists only as patterns
  and a test pass (`mlir/lib/Dialect/MemRef/Transforms/EmulateNarrowType.cpp:53-57`,
  `mlir/lib/Dialect/Arith/Transforms/EmulateNarrowType.cpp:27-31`,
  `mlir/test/lib/Dialect/MemRef/TestEmulateNarrowType.cpp:43-52`).
- **The vectorizers.** A type whose alloc bits differ from its bits is
  "irregular" (`LoopVectorizationPlanner.h:1100-1108`):
  - the loop vectorizer scalarises its loads and stores
    (`LoopVectorize.cpp:2524-2529, 2605-2610`);
  - the SLP vectorizer gathers them (`SLPVectorizer.cpp:6313-6314,
    9808-9813`).

  An array of `Fin 100` as `i7` would not vectorize, while as `i8` it
  would.
- **Analyses.** These work at any width:
  - `ConstantIntRanges` holds APInts (`InferIntRangeInterface.h:27-31`);
  - its transfer functions are APInt ops
    (`InferIntRangeCommon.cpp:186-197`);
  - `arith` folding is APInt (`ArithOps.cpp:448-450`);
  - `arith-int-range-narrowing` narrows to a list of widths it is given
    (`mlir/include/mlir/Dialect/Arith/Transforms/Passes.td:79-92`).
- **Our dialect.** `Idr_Int` admits i8, i16, i32 and i64 only
  (`IdrTypes.td:293`), and the frontend's `IntTy` has
  `UInt8`..`UInt64` (`compiler/src/IdrisMLIR/Types.idr:32`). Exact
  widths would widen both, and every op over `Idr_Int`.
- **Readability.** An exact width does not state `n` either: `Fin 100`
  is `i7`, which says "below 128". It states `n` only for a power of two.
  If the IR ever needs `n`, a range states it. §3 found no consumer.
- **Zig** (*recalled*, not checked): outside a `packed struct`, a `u7`
  takes its ABI-sized container (`@sizeOf(u7) == 1`), and LLVM is given
  `i7` for values. The snapshot has only a `packed struct(u16)` with a
  `u7` field (`sources/code/zig/lib/std/zig/Zir.zig:2508-2512`).

| | byte classes (u8, u16, u32, u64) | exact `iN` |
| --- | --- | --- |
| bytes per field or element | 1, 2, 4, 8 | the same: sizes round up to bytes |
| x86_64 registers | legal | promoted, masked before udiv, urem, lshr and compares |
| arm64 registers | u8 and u16 promoted to i32 and masked; u32 and u64 legal | the same as u8 and u16 |
| loop and SLP vectorizers | regular | irregular: scalarised |
| dialect and frontend change | none | `Idr_Int`, `IntTy`, the ops over them |
| classes a bound falls in (instances under F2, §6.2) | 4, plus big | 64, plus big |

The owner's intuition is right for registers: LLVM picks register widths
whatever we hand it. Storage is ours to choose, though, and there the
DataLayout rounds every width up to bytes. So an exact width buys
nothing and costs vectorization and the instance count. *Decision:*
byte classes (D2).

## 6. The design choices (question 4)

### 6.1 How the fact reaches the representation

- **(a) Seed range analysis with `[0, n)` from a `Fin n` type, and let
  `idr-narrow` do the rest.**
  - **It needs a type that carries `n`.** `!idr.nat` would need a
    parameter, because a discardable attribute may not hold a fact
    (AGENTS.md).
  - **The value stays a counted, tag-tested big** that the type proves is
    always small. The type's check is made again at run time: this is
    validation, not parsing.
  - **A load from a data instance gets nothing,** since its key erased
    `n` (§2).
  - **Little is left for it.** The interprocedural solve already joins
    every call site's range (`Ranges.cpp:55`). The seed would help only
    where a caller is blind, and those callers are loads. *Conjecture:*
    it adds little.
- **(b) A dialect type `!idr.fin<n>`, lowered to the smallest word.**
  - **For it:** the IR states `n`, and the width rule lives in the C++
    layout.
  - **Against it:** it is a second scalar type beside the builtin
    integers. Each of these would need a case for it:
    - the 25 lines in 15 C++ files that read `NatType` (*read*, grep),
      or every integer op;
    - layout, counting, columns and bufferization.

    `arith`, range analysis, bufferization and the vectorizer already
    serve `i8`. And `n` has no consumer (§3).
- **(c) The frontend decides.** A Numeral with a static height is
  `IntT UIntW`, and every other Nat-like type stays `NatT`, with the
  dialect unchanged and the width computed at translation by one
  function.

*Decided by P0, replacing (c) (C22, under D48; C81; C111).* Layout is not
the frontend's. A numeral family is the family Idris checked, applied to
its index terms (`!idr.data<#Fin[n]>`, D48), so the IR states `n` with no
scalar type of its own beside the builtin integers, which (b) would have
added. Its layout is a number, one function of the type computed when
the type is made (C81): a fixed width at a closed bound, a natural
otherwise. A numeral and a natural convert by `idr.numeral.to_nat` and
`idr.numeral.of_nat`, with no range check (C22). The ranges domain seeds
a `Fin n` operand with `[0, n-1]`, so a bounds check on a `Fin n` index
is never built (C111). (c) goes because the frontend cannot decide a
width it does not know: inside a function compiled for every `n` the
index is a variable, and only a copy at a closed class has the word
(D58; L04's I7, which C22 takes).

### 6.2 Where the bound may decide: the keys

The obstacle is a function that is polymorphic in `n` over a container of
`Fin n`, such as `allFins : (n : Nat) -> List (Fin n)`:
- it has one instance for every `n`, so its list cannot have a per-`n`
  element;
- a caller at `n = 256` would hold its `List (Fin 256)` as bytes, while
  the callee holds bigs;
- passing one to the other would copy the list.

There were two ways through. F1 decided only at the top of a position
whose type the instance key closed, reading every nested type with its
indices erased, so one Idris type, `Fin 256`, had two forms by position:
a word at the top of an instance's own types, a big inside a type
argument. P0 removes that seam (D58): a known index meets code compiled
for every index by specialization by layout class. A call whose callee's
layout changes under the call's indices targets a copy of the callee at
that class, a refined recursive call is specialized in turn, and an index
that climbs past the shape budget reaches the general copy; the class
set is finite, so the specialization ends by construction, and the
budget only ever leaves code less optimized. A bounded conversion
(`idr.reindex`) remains only where an index becomes known inside a
function. So `Fin 256` is a byte through calls, F2's one form per type,
"one mechanism with 0018's" (D58). F2's design as written, the
mechanism D58 names:

- **F2: give each type one form.**
  - **Data keys.** A type argument keeps a Numeral's class: `Vect[-, Fin
    _:u8]`.
  - **Function keys.** A value binder that bounds a Numeral in the
    callee's signature keys the instance by the class the caller sees.
    This follows the `Formed` precedent: "an erased shape of the array
    language that a value array's type needs is its form… so it keys the
    instance" (`Instances.idr:188-194`).
  - **No container conversion at a call.** The classes of the callee's
    signature come from the caller.
  - **Agreement inside an instance.** Classes are computed from
    normalised types, so definitionally equal types agree. An upper
    bound is exact on maxima through `S`, `+`, `*` and `power`, and a
    match refines it (`n = S k` gives `k <= ub(n) - 1`).
  - **Open:** a `replace` across a propositional equality whose two
    sides bound differently, through a non-monotone index function such
    as `minus`. F2's design settles that case before it is built.
  - **Cost:** a recursion whose index climbs (`S n`) crosses at most
    four class boundaries, so it has at most five instances. Keying by
    the exact `n` would give `allFins 256` 256 instances, one for each
    `n` its recursion visits.

*Decision:* F2 is the target, because it is one form per type. P0
decides it as D58's specialization by layout class, over C22's number
layout, and F1's seam does not exist (C22, taking L04's I7). D58
settles F2's question, so F2 waits on no measure of F0's.

### 6.3 The height, keys and the growth checker

- **The height.** The width needs a numeral's height: the most its value
  can be at a closed index. Under P0 it is the family's, computed with
  its layout when the type is made (C22, C81), never the frontend's
  `Natness`, whose Numeral mapping C22 deletes.
  - **Read generically,** from the family's constructors and their index
    equations (D48), never from names. The successor's argument index is
    a proper subterm of its result index at one position:
    - `Fin k` becomes `Fin (S k)`;
    - `Elem x xs` becomes `Elem x (y :: xs)`.

    The height of `T idx` is the depth of that position's closed index,
    less the depth its zero constructor needs (1 for both).
  - A numeral whose successor does not descend on any index has no
    height, and is a natural; `Nat` itself stays a natural. Unbounded is
    the problem's own case.
- **Keys.** No instance key changes. A data type carries its index
  terms (D48), and D58's copies are made by specialization by layout
  class in the dialect, not by the frontend's keys (`eraseIndices`,
  `keyingOf`).
- **The growth checker** (0001 S2.2). Nothing changes: Caps already
  leaves a `Numeral` uncapped (`Frontend/Growth/Caps.idr:24-31,
  205-211`), and no frontend key carries a class. D58's specialization
  ends by construction: its class set is finite, and its shape budget
  only ever leaves code less optimized.

## 7. What cannot be done (question 5)

- **A bound known only at run time.** It stays a big, and `idr-narrow`
  serves it as today. This covers `Term`'s `Fin nv`, `Fin g.size`,
  `Fin arity`, `Numbered`'s `Fin range` (`Proof/Requests.idr:96-104`),
  and the benches' `Fin cap`.
  - **Such a value can exceed 2^62.** `lowBits 100 v : Fin (power 2
    100)` is one.
  - **Range analysis does not relate two values.** It cannot learn
    `i < cap` together with `cap` small.
  - **The representation-first answer is a library type, not a compiler
    rule.** For the frontend's own hot positions, that would be a word
    with an erased proof of its bound, a change to the frontend's code,
    not the compiler's. *Decision:* not now; 0011 decides for its typed
    ids.
- **A closed bound past 2^64** stays a big. No representation limit
  refuses a program.
- **A bound closed only in an erased variable of a shared instance:** F1
  does nothing, and F2 handles it by class.
- **A `Fin` forged out of range by a trusted library's `believe_me`**
  would wrap as a word. Base's two uses are sound (§3).

## 8. Decisions

- D1. **Amended by P0 (C22, D48):** a numeral family's number layout is
  one function of its type, computed from the family, never the
  frontend's choice; there is no scalar type of its own, and the ranges
  domain seeds a `Fin n` operand from its type (C111; §6.1).
- D2. **Byte classes:** u8, u16, u32, u64, else a natural. No exact
  widths (§5).
- D3. **Withdrawn by P0 (D58).** No position decides apart: a numeral's
  layout is its type's wherever it occurs, and a call that meets a closed
  index reaches a copy of its callee at that class (§6.2).
- D4. **Amended by P0 (C22, C81): the height is the family's,** computed
  with its layout when the type is made, from its constructors' types,
  generically. `Fin` gets no special case, so `Elem` and a user's
  numerals get the height too (§6.3).
- D5. **Amended by P0 (C22): a numeral's own ops convert,** with no range
  check, since Idris proved the bound:
  - numeral to natural: `idr.numeral.to_nat`, the identity at a natural's
    layout and a widening at a fixed width;
  - natural to numeral: `idr.numeral.of_nat`, a narrowing at a fixed
    width.
- D6. **Withdrawn by P0 (C4).** The countdown recognizer goes: a
  countdown is the closed form of an accumulated loop, which
  `idr-accumulate` makes of a self call combined in a tail by an exactly
  associative operation with its identity, `+` on naturals and on fixed
  widths among them. So a closed-signature countdown needs no rewrite of
  its own here.
- D7. **F2 is the target** (one form per type), settled by D58 as
  specialization by layout class; it waits on no measure of F0's (§9).
- D8. **A bound known only at run time stays a big** (§7).

## 9. Staged plan

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| F0 **AFTER-SELF** | the first stage-1 self run (0001's S4) | (1) A sampling profile of the stage-1 self run and the bench set, by source location. It reports the share in code over closed-bound numerals (`addressOf`, `lowBits`, `doubled`, `sameAddress`, `Ord (Vect …)`, `Glyph`, `Form` codes) and over run-time bounds. (2) Fixtures written twice, with `Fin 256` and with `Bits8`: a record of fields, a `Vect 8` of them, and an array of them. The `Bits8` version is what F1 and F2 make, so the ratio bounds their gain. | Gates nothing: D58 settles F2's question, which this stage was to decide. The record states the share and the ratios it measured. |
| F1, P0's | P0 (C22, D58) | D1, D2, D4 and D5 as P0 amends them (D3 and D6 withdrawn). `Numeral`'s height. Words at closed bounds, wherever they occur (D58). `FZ`, `FS` and the match on words. Conversions by C22's ops. | Fixtures, on every target: a record of `Fin 256` fields; `FS` across 256 and 65536; a `Fin (power 2 64)` at its top value; a `Fin (power 2 100)` that stays a big; a closed-signature countdown at `Fin (power 2 62)`, which times out unless it is the identity; a closed `Fin` through an open-`n` function and through a closure in `map`; an `Elem` as a numeral. A new `idr-expect` property, `no-bigs=@f`: @f computes on no big and no natural. It holds of a closed-signature function after F1 and fails today. |
| F2, P0's | D58's ruling, with no gate of F0's; F1 | D58's specialization by layout class over C22's number layout (§6.2). The `replace` case settled. | F0's fixtures, with `Fin 256` within 10% of the `Bits8` version. An array of `Fin 256` is a `memref` of `i8`. A property that no definition has more copies than D58's class set and budget allow. The self run's `Address` cells hold no counted byte. |

## 10. Rejected alternatives

Rejected for the reasons in the sections named:
- seeding ranges from the type (§6.1);
- `!idr.fin<n>` (§6.1);
- exact widths (§5);
- keying by the exact closed `n` (§6.2).

Rejected for their own reasons:
- **Converting containers at boundaries:** it is a copy proportional to
  the value, hidden in a call.
- **Recognising `Fin` by name:** the height comes from constructor types
  (D4).
- **A 64-bit word for every `Fin` whatever its bound:** a `Fin` can
  exceed 2^64, and no representation limit may refuse a program.

## 11. Rules it keeps

- **Erased does not mean constant.** Only a closed bound, or F2's class
  of what a call site passes, decides a width. An erased binder is never
  read as a value.
- **One representation.** F2 gives one form per type, which P0 decides
  as D58's specialization by layout class; F1's seam of two forms by
  position does not exist (§6.2).
- **No fact in a discardable attribute.** The width is the value's type.
- **Quantities.** A linear `Fin` is graded `once`
  (`!idr.graded<once, …>`): uses apply to every type, a linear word
  included (D90), so the grade wraps the numeral whatever its layout.
- **No per-target cases.** The byte classes are the same on every
  target.
- **No refusal.** A bound past 2^64 is a natural.
- **Upstream MLIR first.** Builtin integers, upstream range analysis and
  the vectorizer do the work; there is no new dialect type.
- **Two hosts.** No Idris source and no library changes; `Data.Fin`
  means what base says.
- **Hard cutover.** A numeral at a closed bound is a word wherever it
  occurs (C22, D58), with no option.
- **Tests check behaviour.** That means outputs, timeouts, and an
  `idr-expect` property, never op sequences.

## 12. Relations

- **`idr-narrow`.**
  - It keeps serving naturals and run-time-bounded `Fin`s.
  - F1's words are words without its proof.
  - Its conversion folds remove the round trips F1's boundaries make.
  - Its seed stays `[0, +inf)` from `!idr.nat`.
- **0012.** A `Vect 8 (Fin 256)` held as one 64-bit word is a 0012
  layout over F2's byte element, and contiguity is 0012's choice. Indexed
  vectors do not imply contiguous storage (AGENTS.md).
- **0001 S2.2, the growth checker, and its `Natness`.** Nothing changes
  for them (§6.3): the height is the family's (C22), and no frontend key
  carries a class (D58).
- **0009.** Arrays of closed-bound numerals become `memref`s of bytes
  under F2. An `Index`'s coordinates stay naturals, since their bounds
  are the shape's.
- **idr-tail.** D6, withdrawn by C4.
- **0011.** Its typed ids are bounded at run time. This proposal does
  not make them words (§7).

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- Built by the representation wave: signedness is the op, not a flag
  (`divs`/`divu`, `mods`/`modu`, `shls`/`shlu`, `shrs`/`shru`,
  `to_char_s`/`_u`, `int_head_s`/`_u`, `io.put_sint`/`uint`,
  `str.show_sint`/`uint`, `big.from_sint`/`uint`).
- Decided by P0, where this text left them open:
  - `divu` and `modu` go: unsigned division is `arith.divui` and
    `arith.remui` behind `idr.check.nonzero`, which the frontend writes
    (P0 §5.3).
  - Signed (Euclidean) division, the four shifts (kept four, C23) and the
    char conversions are inline arithmetic: each op's meaning is one C++
    template, instantiated as its folder, as its integer ranges and as
    its expansion into `arith`, emitted at the stage that needs `arith`;
    the op stays until then (D41).
  - A numeral converts by its own ops, `idr.numeral.to_nat` and `of_nat`
    (C22), never through `big.from_uint`, so whether that op's choice of
    a big or a natural by its result type splits is no question of this
    proposal's.
