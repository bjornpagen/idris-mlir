<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0020: niche layouts of sums

**Status:** investigated 2026-10-16. Nothing is built and nothing is
decided. The owner called the idea "very high leverage… worth
investigating" (2026-10-16). Every stage is **AFTER-SELF**: `make self`
needs none of it. Claims are marked *read* (the path given), *measured*,
*recalled* (from memory, to be checked), *conjecture* or *decision*. A
*decision* here is a proposal for the owner to take or change. Paths
under `foreign/idr/` are written from there.

**In short.** A sum held in place carries a tag component. That holds
even when one constructor's field already tells the constructors apart.
`Maybe String` is two components today, an `i8` tag and a pointer. The
pointer is NULL in `Nothing`, so the constructor is held twice. Under
this proposal the layout holds the other constructors in values that
component never holds:
- `Nothing` is the word 0, and `Just s` is `s`'s raw address;
- one word, with no tag.

These values are the component's *niche*, as Rust names it. The niche is
read from the component's representation. Its counted values come only
from the words the runtime already counts as nothing: NULL and odd
words. So no pass of the owned stage changes, and no count is added or
removed.

It is a change to the one in-place layout (`SumLayout`), not a second
layout. It therefore stands as its own proposal, not as a stage of 0013
(D1).

In the self compile:
- 481 in-place sums lose their own tag under the first rule (N2);
- 512 more lose it under the second (N4);
- under the first rule, the words of parameters fall by 12.9% and those
  of results by 7.6%, counted statically over the frontend's Core (§4).

In `tests/programs` the effect is about 1%, because the most-used
`Maybe` there is `Maybe Int`, which has no niche.

## 1. What a sum costs today (question 1)

**The layout** (*read*):
- **Every sum of two constructors or more has a tag:** `i8` up to 256
  constructors, `i16` up to 65,536, then `i32`
  (`lib/IR/Layout/Components.cpp:31-34`).
- **Slots are shared.** A constructor's field takes the first free slot
  of its component type and countedness (`Components.cpp:35-67`).
- **A counted slot that a constructor does not use holds NULL**
  (`include/idr/IR/Layout.h:137-164`, `lib/Conversion/Words.cpp:56-69`).
  Counting a sum then counts every counted slot with no dispatch on the
  tag. The runtime takes NULL and every odd word and does nothing with
  them (`runtime/Rc/Rc.h:22-26`, `:80-90`; `runtime/idris_rt.h:68-71`).
- **A sum is held in place unless it lies on a cycle of containment in
  place.** Then `layout::fit` boxes every type on the cycle
  (`lib/IR/TypeGraph.cpp:180-192`, `lib/IR/Layout/Fit.cpp:24-38`).
  - A box is a pointer to a cell. The cell's header holds the tag.
  - A box's nullary constructor is static data, its atom
    (`lib/IR/OpsCon.cpp:157-176`, `lib/Conversion/Counting.cpp:138`).
- **At a call** (*read*):
  - each component is one argument (`lib/Conversion/Lower.cpp:91-97`);
  - a result of several components is one LLVM struct
    (`lib/Conversion/Facts.cpp:114-119`);
  - on a tail call, a result that does not fit the return registers goes
    through memory (`lib/Conversion/TailCallPlan.cpp:179-195`).
- **In a cell,** object slots come first, then the other components,
  most aligned first, rounded to a word (`lib/IR/Layout/Layouts.cpp:167-223`).
- **In an array,** an element is laid out the same way, at its own
  alignment (`Layouts.cpp:141-161`).
- **The allocator** steps size classes by 8 bytes
  (`runtime/CMakeLists.txt:168`). So a word saved in a cell is 8 bytes
  saved.

**What a `Maybe a` costs** (*read*, from the rules above):

| `a` | Components today | In a cell field | Array stride | After N2 |
| --- | --- | --- | --- | --- |
| a box, `String`, `Lazy`, an array or IORef cell | `i8` tag + counted pointer | 1 object slot + 1 tail byte | 16 | the pointer: 1 word, stride 8 |
| `Integer`, `Nat`, `Fin n` | `i8` + counted `i64` | 1 object slot + 1 byte | 16 | the word: 1, stride 8 |
| `Int`, `Bits64`, `Int64` | `i8` + `i64` | 9 bytes in the tail | 16 | unchanged |
| `Char` (`i32`) | `i8` + `i32` | 5 bytes | 8 | unchanged |
| `Double` | `i8` + `f64` | 9 bytes | 16 | unchanged |
| `Bool`, `Ordering`, an enum | `i8` + `i8` | 2 bytes | 2 | the enum's tag: 1 byte |
| `()` | `i8` | 1 byte | 1 | unchanged (it is `Bool`) |
| `(String, Int)` | `i8` + pointer + `i64` | | 24 | pointer + `i64`, stride 16 |
| `Maybe (box T)` | `i8` + `i8` + pointer | | 16 | the pointer, 1 is the outer `Nothing` |
| a type on a containment cycle with `Maybe` | a pointer to a 16-byte cell per `Just`; `Nothing` an atom | | | N3: in place, 1 word |

**What it costs in branches:**
- **Matching is the same.** A match is `idr.tag` and then
  `scf.index_switch` (`lib/Conversion/Matches.cpp:79-82`). For an
  in-place sum `idr.tag` is the tag component, zero-extended
  (`lib/Conversion/Cells.cpp:86-105`). Under a niche it is one compare
  of the payload word. So a two-constructor match has one
  compare-and-branch either way.
- **Counting is the same.** `Maybe (box T)` counts its one slot, with
  the runtime's test, in both layouts.

What the niche saves is words:
- one argument and one result register per `Maybe`;
- one value in every phi and select;
- the tag's stores and loads in cells and arrays;
- a word of the cell, wherever the tail had no room for the byte.

**Is a niche used already? No.**
- Every sum of two constructors or more gets a tag.
- NULL fills an unused counted slot only so that counting needs no
  dispatch.

So `Maybe (box T)` holds `Nothing` twice, as tag 0 and as the slot's
NULL: one fact in two places. And a state that should not exist can be
written: the tag says `Just` and the slot is NULL. With a niche it cannot
be written.

**What Idris tells us** (*read*):
- **Idris computes constructor shapes on the polymorphic type:**
  `NIL`/`CONS`, `NOTHING`/`JUST`, `ENUM`, `UNIT`, `RECORD`, `ZERO`/`SUCC`
  (`compiler/idris/src/Core/CompileExpr.idr:21-31`). `calcMaybe` takes two
  constructors with 0 and 1 unerased arguments. It is tried after the
  Nat-like and list-like shapes
  (`compiler/idris/src/TTImp/ProcessData.idr:313-323`, `:378-391`).
- **The frontend reads only `ZERO`/`SUCC`**
  (`compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:81-90`).
  A constructor's role comes from the registry by name, for base's list
  alone (`Translate/Types.idr:657`, `:686`;
  `Registry/Recognized.idr:174-177`). A one-constructor, one-field type
  is not declared at all: its values are its field's (`Types.idr:593`,
  `:652`).
- **Idris's own backends cannot use the niche.** In RefC, `Nothing` is
  NULL and `Just` allocates a constructor
  (`third_party/Idris2/src/Compiler/RefC/RefC.idr:516`, `:572-574`). In
  Chez, `Just x` is `(box x)` (`Compiler/Scheme/Common.idr:563-567`).
  A uniform representation cannot make `Just x` be `x`, because `x` may
  itself be NULL (`Maybe (Maybe a)`). Monomorphisation is what makes the
  niche sound here: the layout knows the payload's components.

## 2. The niches (question 2)

A niche is a run of words that the component never holds. It is
half-open, `[first, first + count)`, and wraps at 2^w. A counted
component draws its niche only from words that the runtime's counting
leaves alone. The runtime's `isObject` (`Rc.h:22-26`) is that rule: a
word is an object exactly when it is neither 0 nor odd.

**The niche of each component** (*decision*, D3):

| A component from | Niche | Why |
| --- | --- | --- |
| a cell reference: box, string, memo cell, array or IORef cell | `[0, 2)`: NULL and the odd word 1 | every cell is 8-aligned and none is at 0. The empty string and constant arrays are static cells, not NULL (`idris_rt.h:441`, `:191-193`). Counting skips both words |
| a big or natural word (`Integer`, `Nat`, every Nat-like type) | `[0, 1)` | an odd word is a small value and an even one a bignum's cell, never 0 (`idris_rt.h:151-170`) |
| a sum's tag, `n` constructors in `w` bits | `[n, 2^w)` | `idr.tag`'s range is `[0, n)` (`lib/IR/OpsCon.cpp:334-340`) |
| a slot of a sum | the niche its constructors' components share there, less 0 where a constructor leaves the slot empty, less the words already used for encodings | so nesting composes: `Maybe (Maybe (box T))` takes 0 and then 1 |
| a machine word, `Char`, `Double`, an array descriptor's size or stride, a handle | none | every bit pattern is a value of the type |

`Bool` is an in-place sum, so its tag has the niche `[2, 256)`: `Maybe
Bool` is one byte, with `Nothing` as 2. `()` has no component, so `Maybe
()` keeps its tag and is `Bool`. A closure is a sum after
defunctionalization, so it takes its niche by the same table:
- a set of 2 to 255 labels has spare tag values;
- a single label has its captures' niches.

The census below precedes defunctionalization and counts no closure
(*conjecture* that most closure payloads find a niche).

**What is not a niche** (*decision*, D6):
- **A range from analysis.** `Maybe Int` stays two components even
  where `idr-narrow` proves the `Int` small. A layout read from an
  optimizer's result would hold the fact outside the type.
- **`Char`.** In the dialect, `Char` is a plain `i32`
  (`compiler/src/IdrisMLIR/Emit/Index.idr:41`). `idr.to_char` keeps it a
  scalar value (`lib/IR/OpsScalars.cpp:31-33`), but the layout cannot
  tell a `Char` from an `Int32`. A `!idr.char` type for one niche is not
  proposed. The self compile holds one `Maybe Char` (21 uses), and the
  programs one (110 uses).
- **`Double`'s NaN payloads.** Using them would mean canonicalising
  every float operation.
- **A target's unmapped addresses** (macOS's 4 GiB page zero, Linux's
  `mmap_min_addr`). That would be a per-target case (AGENTS.md).
- **An erased index.** `Fin n`'s bound is not in its representation, a
  big, so it is no niche. Erased does not mean constant. Under 0019's
  D1, a `Fin` with a closed bound becomes a plain byte-class word with
  no niche, and `Maybe (Fin 256)` is then two one-byte components.
- **The rest of a pointer's odd words, and a natural's negative small
  words.** They are free and count-free, but they would break the run's
  contiguity. Three-value pointer niches are measured in §4 and gain
  little.

**The rule that picks the encoding** (*decision*, D4: rule A, stage
N2):
- It applies to a sum of `n ≥ 2` constructors with exactly one
  constructor `U` that has components.
- When some slot of `U` has a niche of at least `n − 1` words, the slot
  with the largest niche is the niche slot. Ties go to the first slot.
- The other constructors are the words `first, first + 1, …` of that
  niche, in tag order. Every other slot is zero, as today.
- Decoding the tag: `rel = word − first`. If `rel <u n − 1`, the tag is
  `rel + (rel ≥ U)`; otherwise it is `U`.
- For `Maybe` this is one compare: `tag = zext(word ≠ 0)`.
- When no slot has room, the sum keeps its tag, as today.

The largest niche is taken so that an outer sum still finds room.
`Maybe (Bool, String)` puts `Nothing` in the `Bool`'s tag and leaves the
pointer's niche for the next `Maybe` out.

**One fact, one place.**
- The niche of a component is computed where its components already
  are, `layout::componentsOf` (`Components.cpp:127-149`).
- The encoding is computed where the slots already are, `sumLayout`.
- The count-free words come from the runtime's predicate. It moves into
  `idris_rt.h`, where `Rc.h`'s `isObject` and the layout both read it.
- `Facts.cpp` computes the tag's LLVM range (`Facts.cpp:50-58`); that
  becomes the complement of each uncounted integer component's niche.
  Its own computation is deleted.

## 3. Ownership, counting and the DMP (question 3)

**Counting** (*read*, `IdrOwnershipOps.td:59-73`, `:159-170`):
- **`Nothing` has no cell.** No in-place sum ever has one. Its words, 0
  or 1, are words the runtime does not count.
- **`dup` and `drop` of a niche sum** call `idris_rt_inc` and
  `idris_rt_dec` on each counted component, as now. In `Nothing` both
  are no-ops by the runtime's own test, as an empty slot is today.
- **`Just x` holds `x`'s reference.** Taking it apart is `x`, and no
  count changes ("an unboxed sum is its fields already").
- **A niche sum is exclusive when `x` is.**

So none of this changes:
- **idr-rc, the ownership analyses and the verifier.** They reason on
  idr values and grades, and those are unchanged: the dialect's types
  and ops do not move.
- **Reuse and idr-stack,** except that they read cell sizes from
  `Layouts`, and those shrink (`lib/Analysis/Ownership/Reuses.cpp:188`,
  `:210`). Reuse then pairs other cells, and the program means the same.

The invariant N2 adds is this: a word that encodes a constructor in a
counted slot is count-free. The unit box of §9 checks it against the
runtime's predicate.

**Poison.**
- Poison's counted components lower to NULL (`Cells.cpp:156-169`), which
  decodes as some constructor. Any value will do for poison.
- An uncounted niche slot, such as an inner tag, decodes poison as
  poison. Poison is a move that never runs
  (`lib/Transforms/Defunctionalize/Converter.cpp:150-160`), so no match
  runs on it.

**The DMP.** Apple's prefetcher scans each line a load fills. It follows
a word that shares its 4 GiB region with the word's address, and the
heap sits in one such region (`runtime/Alloc/Cells.cpp:30-37`).
- **`Just x` is `x`'s raw, untagged address.** The prefetcher follows it
  as it follows any cell reference. This is the rule AGENTS.md states.
- **The niche words 0 and 1 are not in the heap's region.** The
  prefetcher never follows them, so no prefetch is wasted.
- **The tag word goes.** An array of `Maybe (box T)` holds 8 references
  per 64-byte line instead of 4 references and 4 tag words. A cell
  shrinks by the word its tail byte took, so more cells keep every
  reference in the line the first load fills. 0018's D2 counts that at
  97.5% of corpus placements (0018, the DMP proposal, in the working
  tree).
- **Pointer tagging is rejected** (§8). That means a constructor in a
  cell address's low bits (GHC) or in its spare high bits (Swift's
  multi-payload enums, *recalled*).
  - 0018 measured low tags as transparent to the DMP. Its D1 keeps every
    reference untagged anyway, so the DMP is not the reason here.
  - The reasons are the word: it would no longer be the cell's address,
    every load would pay an untag, and a niche needs no tag.

## 4. How much it matters (question 4)

*Measured.*
- **The frontend.** HEAD (de7f12d9) built on Chez with
  `/tmp/s22/proto/build.sh` (597 s), against the tree's prefix
  `build/idris2`, with `--no-prelude` as `tools/compile.sh` runs it.
- **The analysis.** Scratch scripts in `/tmp/niche-proposal/scripts`
  read each `--core` dump:
  - they rebuild `fit`'s boxes from the dump's containment graph;
  - they simulate `sumLayout`'s slot rule, today's and with each rule;
  - they size cells as `cellOf` does.
- **Uses.** A use is a mention in a field, a parameter, a result, or a
  closure or suspension type. These are static counts over the
  frontend's monomorphic Core. They come before inlining and dead-value
  removal, so they bound the lowered module from above.
- **Programs.** Of `tests/programs`' 305 fixtures, 290 dumped:
  - 12 linear-array fixtures are refused by HEAD's frontend against this
    prefix (`polymorphism`, "a shape whose rank no analysis fixes");
  - 3 need a step their `run` performs.

  Of `bench/`'s 27 programs, 22 dumped.
- **The self compile.** HEAD refuses it (`polymorphism`,
  `Core.Context.Context.PartialEval` first; 0003's S2.2 is being
  written) and writes no Core. Its counts come from the newest whole
  self dump on disk: `/tmp/0014-S21C/self/m.core`, written 2026-10-16
  06:08 by lane S21C's frontend over d1dc847e, with 394 refusals. It
  holds 5,932 data instances and 63,463 functions. (0003's census at
  1380a9d0 counts 8,720 data instances, 0019 §4.)

**`Maybe`-shaped instances.** That means two constructors, with no
field and one field after erasure: Idris's `NOTHING`/`JUST` shape at the
instance.

| Payload | Self: distinct (uses) | Programs: distinct (uses) |
| --- | --- | --- |
| record | niche 213 (3,809); tag 1 (36) | niche 8 (99); tag 6 (80) |
| box | niche 88 (2,722); boxed by `fit` 9 (414) | niche 8 (163); boxed 3 (6) |
| enum or `Bool` | niche 20 (693) | niche 1 (24); tag 2 (2), empty types |
| `String` | niche 5 (666) | niche 1 (111) |
| sum in place | niche 37 (609); tag 3 (14) | niche 5 (80) |
| `Nat`, `Fin` | niche 11 (556) | niche 2 (33) |
| `Integer` | niche 1 (125) | |
| array, `Lazy` | niche 2 (44) | niche 3 (105) |
| `()` | tag 4 (176) | tag 1 (76) |
| closure | 25 (142), after defunctionalization | 26 (148) |
| `Int`, `Bits64` | tag 2 (95) | tag 3 (898) |
| `Char`, `Double` | tag 2 (33) | tag 2 (116) |
| **total** | **423**: niche 377, tag 37, boxed 9 | **71**: niche 28, tag 40, boxed 3 |

- **Self.**
  - 405 of the 423 are `Prelude.Types.Maybe`. The rest include
    `IMaybe`, the tree's `Decision`, `WithDefault`, `Fuel` and `Phase`.
  - 414 are held in place.
  - Uses by place: 4,152 parameters, 1,734 results, 3,630 in closure
    types, 377 in in-place fields, 125 in box fields, 57 array elements.
- **Programs.** 54 of the 290 programs hold one. `Maybe Int` alone has
  875 uses, so most uses keep their tag.
- **Bench.** Three distinct instances: of an array, of `Int`, and of a
  box. The bench barely uses `Maybe`, so its check of N2 is a regression
  check.

**Every in-place sum with a tag**, closures excepted:

| | Self | Programs (per program) |
| --- | --- | --- |
| in-place sums of 2+ constructors | 2,372 (682 hold a closure) | 978 (52) |
| enums: the tag is the value | 83 (15,677 uses) | 509 (8,960) |
| one constructor with components: rule A removes the tag | **481** (14,381) | 80 (1,274) |
| … keeps it (no room: `Maybe Int`, `Prec`, `FileError`) | 19 (556) | 287 (3,125) |
| several with components: rule B removes the tag | **512** (12,203) | 26 (413) |
| … keeps it (`FC`, `Either Error Name`: two cells in one slot) | 595 (17,873) | 24 (349) |

The tag that rule B keeps is essential. Both constructors fill the one
slot with valid values, so the slot cannot tell them apart.

**Words in signatures, rule A** (self):

| | Today | Rule A | Change |
| --- | ---: | ---: | --- |
| parameter words | 781,419 | 680,260 | −12.9% |
| functions with fewer parameter words | | 10,312 | |
| result words | 194,201 | 179,514 | −7.6% |
| functions with fewer result words | | 5,260 | |
| results of more than two words | 13,191 | 11,943 | |

Programs: −0.96% parameter words and −0.80% result words.

Most of the self saving is the `Maybe` fields of large records held in
place. Each is a type with its components today and under rule A:

| Type | Components | Signature positions |
| --- | --- | ---: |
| `Defs` | 135 → 107 | 1,958 |
| `GlobalDef` | 51 → 44 | 596 |
| `TS` | 63 → 46 | 197 |
| `PkgDesc` | 107 → 82 | 131 |
| `Hooks` | 55 → 35 | 121 |
| `Maybe GlobalDef` | 52 → 44 | 405 |

**Cells.** In the self compile, 87 boxed constructors' cells shrink:

| Bytes | Constructors |
| --- | ---: |
| 40 → 32 | 26 |
| 32 → 24 | 25 |
| 48 → 40 | 12 |
| 56 → 48 | 6 |
| other sizes, 64 to 1,064 bytes | 18 |

**`fit`.** The self compile has 638 cyclic components, with 854 boxed
types. 21 of those types are thin: at most one constructor with fields,
and that one with one field. Among them:
- 9 `Maybe`s, among them `Maybe Error`, `Maybe RawImp`, `Maybe Term`,
  `Maybe PTerm` and `Maybe MlirAttr` (414 uses);
- `PiInfo` and `AltType` over `RawImp` and `PTerm`.

Every `Just` among them is a 16-byte cell today (N3).

**The pointer niche's size**, measured on the self compile:

| Pointer niche | Rule A | Rule B |
| --- | ---: | ---: |
| `{0}` (Rust's) | 466 | 487 |
| `[0, 2)` | 481 | 512 |
| `[-1, 2)` | 483 | 518 |

`PiInfo`, once N3 holds it in place, needs three words: three nullary
constructors and `DefImplicit`.

**Not covered here: large records held in place.** `Defs` is passed as
135 components in 1,958 signature positions (*measured*). Whether a
record that large is held in place is no niche question. 0013 holds the
layouts of records.

## 5. The design (question 5)

The dialect does not change: no type, no attribute, no op, no role.
`idr.con`, `idr.field`, `idr.tag` and `idr.match` are abstract over the
layout. Only `Layouts` and the lowering know the components.

- **`include/idr/IR/Layout.h`.**
  - `struct Niche { int64_t first; uint64_t count; }`.
  - `struct Component { Type type; bool counted; Niche niche; }`.
  - `SumLayout` holds `std::variant<Single, Tagged{IntegerType},
    Niched{slot, untagged, first}>` and one `SmallVector<Component>` of
    slots.
  - That replaces `std::optional<IntegerType> tag` and the parallel
    `slots`/`counted` vectors (`Layout.h:141-164`).
  - `Layouts::components` returns `Component`s. `Layouts::counted` and
    `layout::countedOf` are deleted: one record, no parallel lists.
  - `encode(tag)` and `decode(builder, words)` are declared beside the
    layout, one copy each.
- **`lib/IR/Layout/Components.cpp`.** The niche table of §2, in
  `componentsOf`. Rule A, and later B, in `sumLayout`.
- **`lib/Conversion/Words.cpp`.** `unboxedSum` writes the encoding, so
  static data gets it too (`StaticData.cpp:142`). `unboxedField` is
  unchanged: `Just`'s field is its slot.
- **`lib/Conversion/Cells.cpp`.** `LowerTag` calls `decode`.
- **`lib/Conversion/Facts.cpp`.** Each uncounted integer component's
  `range` is the complement of its niche. A niche sum's pointer gets no `nonnull`,
  as a sum's slot gets none today (`Facts.cpp:39-46`).
- **`runtime/idris_rt.h`.** The count-free predicate, a `static inline`
  or `constexpr` function as `idris_rt_info` is (`idris_rt.h:113-127`).
  `Rc.h`'s `isObject` becomes it. A `static_assert` in the layout checks
  every counted niche word against it.
- **Nothing else changes.** The frontend, the registry, the fork,
  `libs/`, idr-rc and the ownership analyses, the verifier and the
  bytecode are untouched.

The handoff, per obligation:
- **The state made unrepresentable:** a sum whose tag and slot disagree.
- **The fact moved to one place:** the tag's range (from `Facts.cpp` to
  the niche).
- **The parallel lists deleted:** `counted` beside `slots` and
  `components`.
- **The cases kept, as essential:** the variant's three: one
  constructor, a tag, a niche. The problem has them. Each is visited
  once, in `encode`, `decode` and `componentsOf`.

## 6. Generalisation (question 6)

- **Several constructors with components** (rule B, stage N4; Rust has
  done this since 2022, *recalled*).
  - The constructor with the most components is untagged when one of
    its slots has room for the other `n − 1`. The others lay their
    fields out by the same slot rule, around that slot.
  - The layout with fewer components wins, and ties go to the tag.
  - `Either String Int` becomes two words: `Left s` is `(s, 0)` and
    `Right n` is `(0, n)`.
  - So does `Either Error Int`, the Core monad's result at `Int` (592
    uses).
  - It removes 512 more tags in the self compile.
- **Thin sums on a cycle** (stage N3). Today `fit` boxes every type on a
  cycle. Instead, of each cycle's types it boxes:
  - every type that is not thin;
  - and, of the thin ones, those on a cycle of thin types alone. A thin
    type has one field at most, so these cycles are simple and disjoint,
    and the rule is linear and total.

  Then every cycle still passes through a box. A thin type left in
  place is one word under N2, where it was a pointer to a 16-byte cell
  per `Just` (21 types in the self compile).
- **A box's nullary constructors as niche words** (stage N5, gated).
  Take a boxed sum with one constructor with fields and at most two
  without, as a list is.
  - The constructors without fields could be NULL and 1 instead of
    static atoms.
  - A match would then be a compare of the box word, with no load of
    the header.
  - The list's end would need no atom.

  It costs two things:
  - box parameters of those sums lose `nonnull` and `dereferenceable`
    (`Facts.cpp:30-34`);
  - the header load it saves is of a line that the case's field loads
    touch anyway (*conjecture*). What it removes is the branch's wait on
    a load, which only a measurement prices.

  In the self compile 600 boxed sums are this shape (*measured*): 512
  `List`s, 32 `SnocList`s, 28 `Vect`s and 10 `List01`s among them.

  Lean boxes every nullary constructor as an odd word (*recalled*,
  `lean_box`). For a sum with several constructors with fields that
  would put a test before `Runtime::loadTag`'s header load
  (`lib/Conversion/RuntimeCells.cpp:52-67`) in every match, so it is
  rejected.
- **Enums as small integers: already so** (*read*).
  - An all-nullary sum has no fields, so it is never on a containment
    cycle and never boxed.
  - Its value is its tag, `i8` up to 256 constructors
    (`Components.cpp:31-34`).
  - One constructor has no component at all.
  - No enum allocates. An enum inside a cell is one tail byte.
- **A tag that shares storage with another field** (0015's feature 3,
  `tokValue`) stays with 0013. It is a fact relating two fields, not a
  value a field never holds.

## 7. Decisions (proposed)

- D1. **Own proposal, not a stage of 0013.**
  - 0013's layouts are types (`!idr.packed<T>`, 0013 D1). Each is chosen
    per value by its access pattern and gated at 1.3×.
  - A niche is the encoding of the one in-place layout. It is not
    chosen, has no type, and needs a property rather than a speed bar.
  - Making it a type would hold one sum in two representations.
  - Its stages need nothing of 0013, and 0013's F2 reads it (§11).
- D2. **The layout decides,** from the monomorphic body. The frontend
  reads no `ConInfo` flag and gains no role.
  - Idris's `NOTHING`/`JUST` is a shape of the polymorphic type. It says
    nothing of the payload's representation: `Maybe Int` has the shape
    and no niche.
  - Reading it would make a second copy of a fact the body holds.
- D3. **The niche table of §2.** Counted niches are drawn only from the
  runtime's count-free words, read from its one predicate.
- D4. **Rule A.** The largest niche wins, ties go to the first slot, the
  encodings follow tag order, and decoding is the formula in §2.
- D5. **Hard cutover.** The tag layout remains only where no niche fits.
  There is no option to turn niches off.
- D6. **No niche from ranges, `Char`, `Double`, target address ranges or
  erased indices** (§2).
- D7. **The owned stage is unchanged.** Counts are per counted
  component, as today. The new invariant, that an encoding word is
  count-free, is checked in the unit box.
- D8. **Pointer niche `[0, 2)`.** It gains 15 sums under rule A and 25
  under rule B over `{0}` (§4). It adds no kind of word an object slot
  does not already hold (`idris_rt.h:68-71`).
- D9. **N3's thin rule for `fit`** (§6).
- D10. **Rule B (N4):** fewest components, ties to the tag.
- D11. **N5 only on its measurement** (§9).
- D12. **Pointer tagging stays rejected** (§3, §8).

## 8. Rejected alternatives

Rejected for the reasons in the decisions or sections named:
- reading Idris's `NOTHING`/`JUST`, or a new `CtorRole` (D2);
- a dialect type or attribute for the niche layout (D1);
- an option to keep the tag (D5);
- niches from ranges, `Char`, NaNs, address ranges or erased indices
  (D6);
- low-bit or high-bit pointer tags (§3);
- Lean-style immediates for every boxed nullary constructor (§6).

Rejected for their own reasons:
- **Boxing `Maybe`, as Idris's backends do:** an allocation per `Just`.
  idris-mlir already avoids it.
- **A one-bit tag:** 0013 D6 rejected it for columns. LLVM stores an
  `i1` in a byte, and it would be a second form of the tag.

## 9. Staged plan

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| N1 **AFTER-SELF** | the owner's build of 0002 and 0001 | `layout::Component` with `type`, `counted` and `niche` replaces the parallel lists in `Layouts`, `SumLayout` and their callers. The niche table. The runtime's count-free predicate in `idris_rt.h`, read by `Rc.h` and the layout. `Facts.cpp`'s ranges read from niches. No layout changes. | The corpus passes on both targets, and its executables are byte-identical to N1's parent (a refactor). A googletest box, `Niches` (`make test-unit`): every counted niche word is count-free by the runtime's predicate, and a tag's niche is disjoint from `[0, n)`. |
| N2 **AFTER-SELF** | N1 | Rule A in `sumLayout`; `encode` in `unboxedSum`, `decode` in `LowerTag`. A niche slot's remaining niche serves the sum that holds it. | The `Niches` box, over generated bodies (every source kind of §2, nested three deep). For each: decode after encode is the identity on every tag; no layout has more components than the tag layout; every word an encoding writes into a counted slot is count-free. e2e fixtures `tests/programs/data/niche-*`: `Maybe` of `String`, a box, `Integer`, `Nat`, `Bool`, `Ordering`, a record and `Decision`, and a nested `Maybe (Maybe (box T))`; each in a cell, in an array, as static data and through a closure, with `idris_rt_live_cells` back at its start. A new `idr-expect` property, `words=<sum>:<n>`: the sum is held in `n` components. It states the layout's guarantee, not an op sequence; `words=Maybe[String]:1` fails today. The bench, A/B against N2's parent on both targets: no program worse by more than 2%, best of five (0007's rule). The owner's stage-1 self run records the change in peak memory and in `TailCallPlan`'s results through memory. |
| N3 **AFTER-SELF** | N2 | `fit` boxes the non-thin types of each cycle, and the thin types on cycles of thin types alone. | A fixture of a tree with `Maybe` children: its live cells at the peak fall by the number of `Just`s. `words=` on the `Maybe`. A property that every cycle of containment in place passes through a box, over generated type graphs (the `Niches` box). |
| N4 **AFTER-SELF** | N2 | Rule B. | The `Niches` box extended to several constructors with components. Fixtures: `Either String Int`, `Either Error Int`, and a sum of three constructors that share a slot. The bench rule of N2. |
| N5 **AFTER-SELF** | N2; the owner's go | A boxed sum with one constructor with fields and at most two without holds those as NULL and 1; its match is a word compare. | Built only if it pays. A prototype must make a list-heavy bench program (`qsort`, `deriv`, `k-nucleotide`) at least 5% faster on both targets, with no program worse than 2%, best of five. |

## 10. Rules it keeps

- **One thing, one representation.** `Nothing` is held once, not as a
  tag and a NULL. The niche is a fact of the component, computed in one
  place. The count-free words are the runtime's one predicate.
- **No fact in a discardable attribute.** The niche is computed from the
  body, which is set once (`IdrTypes.td:29-46`).
- **Raw, untagged heap references.** `Just x` is `x`'s address (§3).
- **Erased does not mean constant.** No niche is read from an erased
  index (D6).
- **Quantities.** `!idr.lin<T>` has `T`'s components. No grade moves.
- **Both targets.** No niche reads a target fact. Cells are 8-aligned
  and words are 8 bytes on both, as the runtime asserts
  (`idris_rt.h:81-94`).
- **No refusal.** A layout never refuses a program.
- **Hard cutover** (D5).
- **Upstream first.** LLVM's `range` attributes carry the niches'
  complements. No op is added.
- **Two hosts.** No Idris source, library or fork changes.
- **Tests check behaviour:** a round-trip property, outputs, live
  cells and `words=`, never op sequences.

## 11. Relations

- **0013.**
  - F2 (arrays of sums as columns, 0013 D6) reads the discriminant from
    `SumLayout`.
  - A tagged sum splits as D6 says.
  - A niche sum has no tag tensor. Its niche slot holds what no value of
    the slot's own type is, so it cannot be a value-typed column. Its
    array stays one tensor of the sum, whose element is its components.
  - The packed layout (F1) derives its bytes from the body and is
    unaffected.
  - 0015's tag-sharing question stays with 0013 (§6).
- **0018, the DMP.** Its D1 holds every reference to its cell's raw
  address in every layout, and this proposal adds no layout that does
  not. Its table of what the DMP reads has "a counted slot that a
  constructor does not use is NULL", and that stays true. The word 1 is
  a small odd word, whose upper bits are no heap region. N2's shrunken
  cells are read against 0018's D2 (references in the first line).
- **0019.** A closed-bound `Fin` becomes a byte-class word with no niche
  (§2). A `Fin` with a run-time bound stays a natural, whose niche is 0.
  0019 counts 0 data instances that know a `Fin`'s bound, so the two do
  not conflict in practice.
- **0003, self-hosting.** Not needed for `make self`. The self compile
  is where this pays: §4's counts are the frontend's and the fork's own
  types.
- **0007.** Its bench rule (2%, best of five) is N2's regression check.
- **0010.** An array of `Maybe (box T)` elements halves its stride (§1).
- **0008.** Messages copy in-place sums as they are, so niche sums cost
  nothing new.

## 12. Questions for the owner

Each has its default:
- **The pointer niche: `[0, 2)`, Rust's `{0}`, or `[-1, 2)`** (§4).
  *Default:* `[0, 2)`.
- **N5's bar:** 5% on a list-heavy program, 2% elsewhere. *Default:* as
  written, and N5 is not built until N2 to N4 have landed.
- **The queue position.** It needs only built work. *Default:* after
  0007, whose bench baseline makes N2's check readable; N1 may come
  earlier.
- **Large records held in place** (`Defs`, 135 components). This is no
  question for this proposal. *Default:* recorded here; 0013 decides
  whether a record has a size past which it is boxed.
