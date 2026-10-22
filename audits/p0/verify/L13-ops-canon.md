<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L13: ops, canonicalization, primitives

Lane L13 of the P0 verification swarm. Rulings in scope: D9 (the op half:
one op per semantics), D10, D16 (families from lists), D19, D41, §5.3;
with D20, D27, D48 and C3 as the frame the op inventory is re-derived
under. HEAD `e96bb991` at the start (2026-10-21T21:31Z) and at the finish
(checked again before writing). Nothing built, run or typechecked; every
count is from the source, with its command. Paths are relative to the
checkout; `foreign/idr/` is abbreviated `idr/` where it would repeat.

Read in full: `.claude/skills/representation-first/SKILL.md`,
`AGENTS.md`, `proposals/0000-mlir-native.md`, `audits/p0/03-ods-ops.md`,
`audits/p0/04-canon.md`, `audits/p0/synthesis/A-dialect.md`; read by
section: `audits/p0/12-conversion.md` (§1-§2, §3.1-3.2, §4 CV-10 to
CV-56, §5 T1, T11, T12, §6 NQ1, §7, §8), `wave1/5.2-mlir-ods.md` (§5.2.2,
§5.2.3, §5.2.4), `wave1/5.6-ecosystem.md` (§5.6.2),
`wave1/5.8-dialect-design.md` (§5.8.2 op granularity, effects; §5.8.3
DS1-DS4; §5.8.4), `synthesis/G-coordinator-decisions.md` (DP-31 to DP-47,
DP-66 to DP-69), `synthesis/F-decisions.md` (DP-17),
`design/one-source.md` (§4, §9, §10), `design/effect-vocabulary.md`
(§2, §3), `design/typed-effects.md` (§3.3.6), `design/compile-time-cpp.md`
(§2.3(e)-(f)). Code read: every `idr/include/idr/IR/Idr*Ops.td` (11
files, 3,209 lines), `IdrBase.td:230-359`, `idr/lib/IR/Ops.cpp:195-301`,
`OpsScalars.cpp`, `OpsChecks.cpp`, `Fold.h`, `Fold/Bigs.cpp`,
`Fold/Strings.cpp:1-130`, the canon anchors 04 cites (spot-checked: all
hold at HEAD), `lib/Transforms/Pipeline.cpp:1-60`,
`Optimize/Optimize.cpp:55-70`, `lib/Conversion/Scalars.cpp`,
`Conversion/Checks.cpp:1-100`, `Conversion/Runtime.cpp:30-60, 185-200`,
`Verify/Linearity.cpp:1-60`, `tools/idris-mlir-tblgen.cpp:720-790,
2940-3000`, `runtime/Big/Arithmetic.cpp`, `runtime/Strings/Show.cpp`,
`runtime/Io/Output.cpp:150-176`, `runtime/Doubles/Truncation.cpp`,
`runtime/Doubles/Printing.cpp:119-123`; pinned upstream
`include/mlir/Transforms/Passes.td:20-60`,
`GreedyPatternRewriteDriver.h:70-90, 170`, `OpDefinition.h:1940-2015`,
`Utils/InferIntRangeCommon.h`, `docs/DeclarativeRewrites.md:486-520`.

## 1. Verification

Each item: the claim, its verdict, its evidence, and the class of each
observation (*defect* confirmed in the source; *incompleteness*
(structural); *mismatch* (integration); *unverified* behaviour;
*simplification* (optional)).

### 1.1 D9, the op half: "the dialect redesigned whole ... if two ops are secretly the same with slightly different effects"

**Holds, with corrections.** The op set today is 189 ops (*measured*:
`grep -hE '^def Idr_[A-Za-z0-9_]+Op *:' idr/include/idr/IR/Idr*Ops.td |
wc -l` = 189; the proposal's §1 says 191, 03 §2 says 189). Under D9's
test (same structure and effects, differing in a pure function or in an
operand the rulings delete), the pairs that are one op are:

| pair | verdict | ground |
| --- | --- | --- |
| `tabulate`/`tabulate_io`, `array.update`/`element.update` | one op each | *read*: the only difference is a world operand and result (`IdrArrayOps.td:119-124, 362-368, 401`); D20 deletes the world. Arrays are L12's |
| six clock readings | one `io.clock <kind>` | *read*: `IdrPlatformOps.td:330-335` differ only in the clock; the runtime already holds the enum (`runtime/Io/Clock.cpp:39-58`, 03 §6) |
| `crash`/`crash_str` | one terminator | *read*: same effects (`Idr_MayCrash`, `Idr_NoReturn`, `IdrCheckOps.td:22-35`); differ only in where the message comes from (§2.1) |
| `lin.enter`/`lin.use` | one cast | *read*: identical effects (`MemAlloc<Idr_LinResource>` on the result, `IdrOwnershipOps.td:410, 422`), identical traits but the direction of `TypesMatchWith`, mirrored folds (`OpsScalars.cpp:92-108`), identical range bodies (03 O-73), no runtime form; upstream's same-value casts are one op each way (`memref.cast`, `arith.index_cast`; *recalled*) |
| `yield`/`array.yield` | one yield | *read*: both end a region and move their operands on; they disagree on effects, `ConsumesOnly` against `Pure` (`IdrMatchOps.td:163-170`, `IdrArrayOps.td:215`), synthesis A B19 |
| `put_sint`/`put_uint`/`put_double` and `show_*` then `put_str` | composed | *read*: the runtime's put and show share one formatter each: `idris_rt_io_put_int_s` and `idris_rt_str_show_s` both call `rt::strings::formatSigned` (`runtime/Io/Output.cpp:158-163`, `runtime/Strings/Show.cpp:12-17`); `put_double` and `show_f64` both call `rt::doubles::formatDouble` (`Output.cpp:173-176`, `Doubles/Printing.cpp:119-123`). 03 §8's open risk ("lane 18 must confirm") is closed by this reading |
| `io.put_list` and `str.pack`/`str.concat` then `put_str` | composed (new here) | *read*: `IdrStringOps.td:73-83` says put_list is exactly "output of a pack or a concat whose string has no other use"; it is the fusion DP-43 moves to the lowering |
| `divu`/`modu` and `arith.divui`/`remui` | upstream's | *read*: `Scalars.cpp:75-77` lowers them to exactly those, behind the guard |
| `shls`/`shlu` | **two ops (G DP-41 refuted)** | *read*: `idrisShift` turns a negative signed amount (`Ops.cpp:260-264`); an unsigned amount with its top bit set is a huge count. `shls 4, -1 : i8` is 2, `shlu 4, 255 : i8` is 0: the same bits, two results. G DP-41's reason ("dialect, folds, lowering ... are there already") does not address it |
| `take`/`unpack`, `borrow`/`share`, `own.adopt`/`own.give` | two ops each | *read*, 03 §3: effects differ (memory against none; pure against consuming; pure against consuming) |
| `match`/`match_lit` | two ops (kept) | *read*: keys, bindings and exhaustiveness differ (`IdrMatchOps.td:101-160`); after integer and `i1` keys leave for `scf` (§2.1) the rest is string and big keys only |
| `big.small`/`big.from_sint` | two ops | *read*: `big.small` is undefined outside the small range ("the pass that writes the op is the proof", `IdrBigOps.td:228-234`) and acquires nothing; an attribute for that would be `nsw`, a flag |

Corrections:
- *mismatch*: the effect-vocabulary's per-op table (`design/
  effect-vocabulary.md` §3: `con` with `AcquiresCell result`; `closure`,
  `suspend`, `delay` with `Allocate` on `idr.heap`) and G DP-31 ("every op
  that makes a cell allocates, so CSE merges none") contradict C3 as
  revised under the owner's word (proposal §3: construction is pure before
  counting; a linear or owned result takes a fresh identity). C3 is the
  later and binding text. L01 owns the declarations; the op inventory
  below is written under C3.
- *incompleteness*: D9's merge list in §5.3 omits the clock queries, the
  handle null test (both inline arithmetic on runtime encodings, §4 I5),
  `io.put_list` (composition), the six file-time readers (03 O-40) and the
  two GC clocks that are "never valid" yet call the runtime
  (`IdrPlatformOps.td:334-335`, *read*).

### 1.2 D10 in this lane's area

**Holds as a ban; the design deletes every instance read here, with three
corrections.** AGENTS.md's "never" lines that fall in this area, each
checked at HEAD:

| never line | at HEAD | the design's deletion | verdict |
| --- | --- | --- | --- |
| "37 folders converting constants by hand though the generated ABI table says how (04 C40)" | *read*: 47 fold bodies in `lib/IR/Fold/` (*measured*: `grep -c '^OpFoldResult [A-Za-z]*Op::fold'` gives 23 in `Bigs.cpp`, 24 in `Strings.cpp`); my reading of `Bigs.cpp` whole: 16 generic, 7 with their own rule (add's zero, two shifts' size policy, pred's zero, `nat.to_big`, `big.small`, `big.to_int`'s round trip); 04 read `Strings.cpp` one by one: 21 generic | §5.3's "one runtime fold read off the generated ABI table" | holds; correction: a 38th hand fold restates a runtime function outside `lib/IR/Fold/`: `ToIntOp::fold` computes the truncation in 1,100-bit `APSInt` (`OpsScalars.cpp:66-75`) where `idris_rt_to_int` does it by bits (`runtime/Doubles/Truncation.cpp:13-26`): two meanings that agree today by construction of each, not by being one |
| "trying a pattern on every op when ODS knows which ops it can match" (3a96c407) | *measured*: `grep -rn MatchAnyOpTypeTag idr/` finds none; the two by-name expansions over every registered op are defunctionalization's `RetypePattern` and the reducer's `PoisonResults` (04 §3.1) | G DP-48 deletes `RetypePattern`; the reducer's is an honest any-op root over an open set | holds |
| "Euclidean division written in the folder, the lowering and the runtime (03 O-47)" | *read*: `idrisDivMod` (`Ops.cpp:208-224`), `LowerDivision` (`Scalars.cpp:58-104`), `euclidean` (`runtime/Big/Arithmetic.cpp:20-33`) | D41 | holds |
| attributes made on a worker's hot path | *read*: `fold::Scope::big` makes a `StringAttr` per big operand per fold (04 C41) | the one runtime fold passes the text without an attribute | holds |
| a question answered by mutating IR (1b2e31da) | *read*: `foldsWith` clones the consumer per query (`Canon/Feeds.cpp:75-93`, 04 C12) | 04 T2 (`meets` declared per op) | holds; not in §5.3's text (*incompleteness*) |
| a static fact paid at the compiled program's run time | (a) a crash site re-read from debug info: §1.6; (b) the guards' condition written three times: §1.4 | §4 I2, I3 | **corrected**: neither is in the design yet |

A third correction, *mismatch*: §5.3 asks for "one bounded canonicalizer
configuration" and G DP-33 for "`maxNumRewrites` is k times the function's
ops, k a `Passes.td` constant". Upstream's option is an absolute count per
pass instance (*read*: `Passes.td:46-47` `max-num-rewrites`, default -1;
`GreedyRewriteConfig::setMaxNumRewrites(int64_t)`,
`GreedyPatternRewriteDriver.h:84-90`); "k times the function's ops" is not
expressible without a patch or a pass of ours (§2.4).

### 1.3 D16: families from lists, TableGen 100% generated

**Holds, with four corrections.**
- *read*: every family is a TableGen class today (`Idr_IOOp`,
  `Idr_PlatformIOOp`, `Idr_HandleQueryOp`, `Idr_PathOp`, `Idr_ReadingOp`,
  `Idr_ActionOp`, `Idr_ClockQueryOp`, `Idr_BigBinaryOp`,
  `Idr_BigNaturalOp`, `Idr_BigShiftOp`, `Idr_BigDivisionOp`,
  `Idr_BigFromIntOp`, `Idr_StrBuilderOp`, `Idr_StrShowIntOp`,
  `Idr_DivisionOp`, `Idr_ShiftOp`, `Idr_ToCharOp`, `Idr_IntHeadOp`,
  `Idr_CheckOp`, `Idr_GeneratingOp`, `Idr_MatchOpBase`, ...), and every
  member is a hand `def` (03 M8). One-source §4.2's `division`/`ioOp`
  family functions make "a member keeps its family's traits and
  constants" a property of the encoding: holds.
- *mismatch* (text): §5.3 says each family is "emitted as one generated
  TableGen class"; one-source §10 says the output is "flat, one `def` per
  op with its spec name in a comment", so errors point at a def. Flat is
  right: the family is the Idris function, and a printed TableGen class
  would be a second spelling of it. Correction: flat defs; the family's
  constants reach C++ as generated `static constexpr` members (below).
- *defect* against AGENTS.md ("A choice is a type or an enum case, never a
  `bool`"): the family constants are bools today (`static constexpr bool
  quotient`, `isSigned`, `left`: `IdrScalarOps.td:31-34, 66-69, 101-102`,
  `IdrBigOps.td:90-91`, `IdrStringOps.td:104-105`), read by the concepts
  `DivisionOp`/`ShiftOp` (`Ops.cpp:227-233, 276-281`). Correction: the
  spec's `Signedness`, `Part`, `Direction` enums, generated as
  `static constexpr Signedness signedness` and kin.
- *mismatch* with D41: one-source §4.2's `Meaning = Runtime Symbol |
  HandFolder | NoFold` has no case for an op whose meaning is an inline
  template; its own `division` sketch still writes `meaning = Runtime
  (divSymbol part sign) -- [DP-17]`, which D41 settled the other way.
  Correction: `Meaning = Runtime Symbol | Inline InlineFn | HandFolder |
  NoFold`, `InlineFn` a closed enum (§2.3). L03's seam.
- *incompleteness*: D16 makes every `.td` of ours generated, and G DP-66
  chose DRR for local rewrites; DRR patterns are `.td` records, so the
  specification must hold them. Nothing in one-source names a rewrite
  record. Correction: `Spec.Rewrites` (§2.5), within one-source §10's
  Greenspun bound (one spec constructor per ODS construct, printed one to
  one).

### 1.4 D41: "an op of inline arithmetic has one meaning, a C++ template"

**Holds, with corrections.** Claim by claim:
- *"Euclidean division, the total shifts, the scalar-value test and the
  char conversions are each one function generic over a numeric
  domain"*: holds; correction: "the scalar-value test" and "the char
  conversions" are one function, `to_char_s`/`to_char_u` (widen, test the
  scalar range, select), *read* `OpsScalars.cpp:22-33`, `Scalars.cpp:
  166-192`. The covered ops are `divs`, `mods`, `shls`, `shlu`, `shrs`,
  `shru`, `to_char_s`, `to_char_u`, and the runtime's small-Integer
  `div`/`mod` path. `divu`/`modu` are not inline arithmetic: they are
  `arith`'s (1.1).
- *"instantiated over integers as the folder (its edge cases
  `static_assert`ed when the compiler is built)"*: holds only if the
  integer domain is not `APInt`, which is not `constexpr` (*recalled*;
  today's folders are on `APInt`, `Ops.cpp:208`). Correction: the integer
  domain is a `constexpr` word on `uint64_t` with its width
  (`rt::numeric::Word`), the folder converting an `IntegerAttr` (8 to 64
  bits, `Idr_Int`, `IdrTypes.td:312`) once.
- *"over intervals as upstream's `InferIntRangeInterface`"*: holds; every
  operation the templates use has an upstream transfer function (*read*,
  `Utils/InferIntRangeCommon.h`: `inferAdd` :83, `inferSub` :86,
  `inferDivS` :92, `inferRemS` :102, `inferAnd` :114, `inferShl` :120,
  `inferShrS` :123, `inferShrU` :125, `extSIRange`/`extUIRange`/
  `truncRange` :71-80, `evaluatePred` :145; `rangeUnion`,
  `InferIntRangeInterface.h:88`). Correction: this is new capability, not
  a deletion: `divs`, `mods` and the four shifts declare no
  `InferIntRangeInterface` today (*read*, `IdrScalarOps.td:23-90`); only
  `to_char` does, with the constant [0, 0x10FFFF].
- *"over an IR builder as its expansion into `arith`"*: holds, with an
  obligation the ruling does not state (*incompleteness*): the expansion
  must never build an `arith` op that is poison or undefined on the
  inputs Idris defines (`arith.divsi` at MIN / -1, `arith.shli` at or past
  the width). Today the lowering avoids both by hand (`Scalars.cpp:79-90,
  121-127`). Correction: the domain's partial operations take evidence
  types only the domain constructs (§2.3), so a template that divides by a
  raw divisor or shifts by an unmasked amount does not compile.
- *"the runtime includes the same header"*: holds; correction: the header
  lives in `runtime/`, freestanding (no MLIR, no LLVM ADT), so AGENTS.md's
  "its one meaning is the runtime's (`runtime/`), which folders call too"
  holds as written and needs no amendment (F DP-17 said B would need one).
  A second correction: the runtime's small path is not the fixed-width
  function. Integer's `div` at the least small value by -1 is 2^62, a
  large big (*read*: `Arithmetic.cpp:119-120`, "small, but for
  IDRIS_RT_SMALL_MIN / -1"), where `divs` at `INT64_MIN / -1` wraps. One
  template serves both only through a domain fact, `wraps`, that is
  `true` for fixed words and `false` for the runtime's 63-bit smalls,
  read by `if constexpr` (§2.3): D10 keeps the impossible MIN / -1 test
  out of the runtime's hot path.
- *"The op stays until then (D18)"*: holds.
- *"Deletes the meaning written three times"*: holds for division (three
  copies, *read*); shifts and `to_char` are written twice (folder and
  lowering).
- *"Strings, big integers and IO stay runtime functions"*: holds.
- *incompleteness*: the five guards' conditions are inline arithmetic
  written three times (fold `holds`, `OpsChecks.cpp:22-61`; range clamp,
  `OpsChecks.cpp:130-168`; lowering `fails`, `Conversion/Checks.cpp:
  43-97`, all *read*). D41's words cover them ("an op of inline
  arithmetic"); its list does not name them. §4 I2.

### 1.5 D19 in this lane's area

**Holds.** Consequences read off the ops and canon:
- No CFG case terminator (03 §5.2(b), §5.9 Design 2) exists in the target;
  `match` stays a region op with `RecursiveMemoryEffects`, which upstream's
  known-case inlining requires (*read* 04 C50,
  `ControlFlowInterfaces.cpp:1228-1231`).
- `match_lit`'s integer and `i1` keys become `scf.index_switch` and
  `scf.if` (upstream region ops; `cf.switch` is excluded by D19's "blocks
  only at the lowering").
- Every region of every op is one block (*read*, 03 W-E8): holds until
  `convert-scf-to-cf`.
- *incompleteness*: canon's region shapes gain kinds of end. Today a
  region ends in `idr.yield` or `ub.unreachable` (`OpsMatch.cpp:30-36`);
  under R4 (crash and exit as terminators, §5.3) and D25 (`idr.jump`),
  three more. 04 T4's `MatchView` must classify a region's end as a
  closed sum `Yields | Stops | Jumps`, and `EndAfterNoYield` generalizes
  to "every region stops or jumps".
- `MergeIdenticalRegions` and `Rebuild`'s O(N) per result change stay
  ours (04 C25, C39 essential under regions).

### 1.6 §5.3, the dialect's surface

- **Types bullet: *mismatch* (stale text).** "a token names its cell
  (`!idr.token<!idr.box<T>, @C>`)" contradicts D48 ("`!idr.box` is no
  longer a type"); "a `static` lifetime, ordered static < heap < frame"
  contradicts D40 (`static`, `counted`, `frame` and lexical variables;
  `heap` is D28's resource). "a name with no body refused at the parser"
  is moot under D48 (no table, no name without a body). L04 and L05 own
  the types; the coordinator fixes the text.
- **Ops bullet: holds with corrections.** "about 189 ops become about
  168": my disposition (§2.1) leaves 161 of today's 189, plus
  `io.unsafe_run` (D20) and the other lanes' new ops (`idr.join`,
  `idr.jump`, `idr.lifetime`, `idr.is_unique`): 166 (*derivation*, §2.1's
  count). "`divu` and `modu` to `arith` behind their guard": holds
  (1.1). "each op's legal stages as ODS data": holds (G DP-47;
  one-source's `stages` field). "no verifier that follows def-use
  chains": holds when `own.adopt`/`own.give` are replaced (L12/L07).
- **Canonicalization bullet: holds; the configuration needs the patch
  of §2.4**, and the dialect filter should be derived, not listed (§2.4).
- **A defect the bullet does not reach**: the crash site is read from
  the op's `Location` (*read*, `Conversion/Runtime.cpp:42`:
  `loc->findInstanceOf<FileLineColRange>()`; "A location may name no
  place at all", :43), and `MergeIdenticalRegions` compares bodies with
  `OperationEquivalence::IgnoreLocations` (*read*, `Canon/Merge.cpp:36,
  48`). Two case regions that crash with one message at two source sites
  merge, and the program prints one site for both paths. D37 and D38 make
  the site part of committed standard error. *Unverified behaviour*
  (reachability: no test written); the representation that admits it is
  *read*. §4 I3.

### 1.7 The deletions this lane verifies

- **The 37 hand folders**: holds (1.2), 38 with `to_int`.
- **The meaning of division written three times**: holds (1.4).
- **Patterns rooted at every op**: holds (1.2).
- **`maxNumRewrites` unset**: holds (*read*: `Pipeline.cpp:28-32` sets only
  `regionSimplifyLevel`; `Optimize.cpp:64-66` sets top-down and region
  simplification). C8 sends the bug to main as its own change; the target
  configuration is §2.4.

### 1.8 Observations from the code, classified

- *defect*: `delay` drops a quantity. `closure` and `suspend` carry
  `Idr_LinearWhenACaptureIs` (`IdrClosureOps.td:37, 54`); `delay` does not
  (`IdrClosureOps.td:72-80`), and its `TypesMatchWith` compares carriers
  with grades ignored (`Idr_SameCarrier`, `:15-17`), so `idr.delay
  %x : !idr.lin<i64> -> !idr.lazy<i64>` verifies with a plain result
  (*read*). Whether the frontend can emit it is *unverified*. §4 I7.
- *defect*: the guards' condition held three times (1.4).
- *defect*: the crash site in debug info (1.6).
- *incompleteness*: two GC clocks call the runtime to learn a constant
  (`IdrPlatformOps.td:334-335`); three clock queries and the handle null
  test are runtime calls for one to three integer operations on an
  encoding the runtime documents (`IdrPlatformOps.td:14-19, 337-361`),
  the queries taking a world (IO for a pure computation, 03 O-40).
- *simplification*: `Idr_Primitive` is a marker the Idris side reads;
  C6 replaces it with the specification naming the base primitive.

## 2. Boundaries

### 2.1 The op inventory, re-derived

Rules applied, in order: D20 (no world: every world operand, result and
`world.new` goes); D27 and C3 (effects as L01 declares them; construction
pure before counting); D48 (no `!idr.box`; data types are families
applied to index terms; quantity-0 parameters are compile-time arguments,
never operands); D41 (inline arithmetic one template); D19 (regions);
§5.8 O1/O2 (one op per computation; an enum only for the pure function in
a shared shape; ops differing only in a resource are one class); arith's
school for signedness (G DP-41's school, not its shift merge). Effects
named here are those the rows read (L01 declares them). "Kept" means the
op survives with its world removed and its family generated from a list.

**Program, functions, values** (9 today)

| op | disposition | reason |
| --- | --- | --- |
| `program` | kept; `types` property deleted | D48 deletes `#idr.types`; the root through `verifySymbolUses` (03 O-64); `stage` stays, the pipeline's typestate |
| `func` | kept; gains quantity-0 parameters `<n : nat, ρ : lifetime>` (D48, D39); `no_inline` deleted | G DP-38: the row (D22), tail position, conventions live on it; `no_inline` is a function of the type (03 O-3, `Emit/Declarations.idr:52-57`) |
| `call` | kept; gains compile-time arguments `@f<k, frame>` (D48), checked by substitution in `verifySymbolUses` | G DP-38; D30's tail kind on the call |
| `return` | kept | our function op stays |
| `constant` | kept; value constrained to the constant attributes, including `#idr.cause<k>` (§2.6) | 03 O-7 |
| `con` | kept, one op; pure before counting (C3), a fresh identity for a linear or owned result | D48 deletes the box/sum distinction that 03 O-8 would split on; C3 deletes the allocation |
| `field` | kept; takes the refined constructor type, loses `tag` (G DP-37) | L04 owns the type |
| `tag` | kept | — |
| `dest.write` | kept | the hole's write (L07) |

**Matches** (3)

| op | disposition | reason |
| --- | --- | --- |
| `match` | kept: region per case (D19); refined case binding (G DP-37); `PropagateControlFlowBreak` (D25, L09); O(1) `getPredecessors` overrides (03 O-13) | — |
| `match_lit` | split by key: integer and `i1` keys are `scf.index_switch`/`scf.if`; string and big keys stay `match_lit`, keys a typed array (03 O-16) | D19; upstream first |
| `yield` | kept as the one yield of every region op of ours | merged with `array.yield`; `ParentOneOf` generated from the spec's region ops |

**Closures and suspensions** (6; legal at stage `higher` only)

| op | disposition | reason |
| --- | --- | --- |
| `closure`, `suspend`, `delay` | kept as one capture family, each with `Idr_LinearWhenACaptureIs` | 03 O-18; `delay` gains the trait (§4 I7) |
| `force`, `apply` | kept; one "runs unknown" declaration | 03 O-19 |
| `memo.run` | kept; its static effects declared; region ends in `idr.yield` | 03 O-20 |

**Ownership and cells** (14; counting is L07's, arrays L12's)

| op | disposition | reason |
| --- | --- | --- |
| `dup`, `drop` | kept (L07; a token's drop may split, 12 CV-31) | — |
| `borrow`, `share` | kept | effects differ |
| `cell.new`, `cell.stack` | kept as one class differing in the resource | 03 O-25, §5.8 O2 |
| `cell.recycle`, `cell.init` | kept | — |
| `take`, `unpack` | kept; refined type, no `tag`; which one is a function of the type's layout | 03 O-27; D48 makes "has a cell" layout's fact |
| `own.adopt`, `own.give` | replaced (L12, L07): the def-use verifiers go | 03 O-70 |
| `lin.enter`, `lin.use` | **merged: `lin.cast`** | 1.1; §3 |

**Integers and naturals** (23): every op kept, families from lists:
`big.add`, `big.mul` (Integer or natural); `big.sub`, `big.and`, `big.or`,
`big.xor`; `big.shl`, `big.shr` (their size policy stays a hand rule);
`big.div`, `big.mod` (guarded); `big.neg`, `big.cmp <pred>` (§5.8 B4's
legitimate enum); `big.pred` renamed `nat.pred` (it takes a natural,
`IdrBigOps.td:144`); `nat.to_big`, `nat.from_big`; `big.from_sint`,
`big.from_uint` (two runtime functions, two ABI extensions); `big.small`
(a proof-carrying op, 1.1); `big.to_int`, `big.from_double` (guarded),
`big.to_double`, `big.show`, `big.from_str`. Their results: pure before
counting, acquiring when owned (§4 I4).

**Fixed-width integers and doubles** (14)

| op | disposition | reason |
| --- | --- | --- |
| `divs`, `mods` | kept, `Meaning = Inline` (D41) | Euclidean, wrapping MIN / -1 |
| `divu`, `modu` | **deleted**: `arith.divui`, `arith.remui` behind `check.nonzero` | 1.1 |
| `shls`, `shlu`, `shrs`, `shru` | kept, four, `Meaning = Inline` | 1.1 |
| `to_char_s`, `to_char_u` | kept, `Meaning = Inline` | — |
| `to_int` | kept; folded by the one runtime fold | 1.2 |
| `double_head`, `int_head_s`, `int_head_u` | kept | runtime functions |

**Strings** (22)

| op | disposition | reason |
| --- | --- | --- |
| `str.append`, `str.cons`, `str.from_char`, `str.show_sint`, `str.show_uint`, `str.show_double`, `str.substr`, `str.reverse`, `str.drop_bytes` | kept, one builder family whose class lists `StrBuilderOpInterface` | 03 O-35 |
| `str.pack`, `str.concat` | kept, two | the element kinds differ (arith's school, as `addi`/`addf`) |
| `io.put_list` | **deleted**: `put_str(str.pack l)`, fused at lowering | composition (1.1) |
| `str.tail`, `str.index`, `str.head` | kept, guarded family | — |
| `str.length`, `str.bytes_length`, `str.scalar_at`, `str.scalar_bytes`, `str.cmp <pred>`, `str.to_int`, `str.to_double` | kept | — |

**Checks and endings** (8)

| op | disposition | reason |
| --- | --- | --- |
| `crash`, `crash_str` | **merged: one terminator `idr.crash %message at #idr.site<...>`** | R4; §2.6 |
| `may_loop` | kept (L10, L01) | D13 |
| `check.nonzero`, `check.in_bounds`, `check.nonempty`, `check.finite`, `check.range` | kept, five (operand structures differ; DS4's `cmpi` + `check` refuted, 03 §3); `cause` a `Cause` enum property, `site` a property; conditions of three under D41 (§4 I2) | 03 O-38 |

**Arrays** (13; L12's semantics): `tabulate` kept (destination style,
D43), `tabulate_io` merged into it (D20); `fold_last`, `scan_last` kept;
`transpose` deleted (G DP-45); `array.yield` merged into `idr.yield`;
`array.new`, `array.get`, `array.set` L12's; `array.update` kept,
`element.update` merged into it (D20); `nat.to_extent`, `tie_shape` kept.

**IO and buffers** (18)

| op | disposition | reason |
| --- | --- | --- |
| `io.put_str`, `io.put_char`, `io.get_byte`, `io.get_line`, `io.write_bytes`, `io.read_bytes`, `io.eof`, `io.n_processors` | kept | — |
| `io.put_sint`, `io.put_uint`, `io.put_double` | **deleted** | composition (1.1) |
| `os` | kept as `target.os`, folded from a field of the target's entry; the build-triple fallback goes | 03 O-81 |
| `io.buffer_load`, `_store`, `_copy`, `_set_string`, `_get_string` | kept as `buffer.*`: memory ops, no IO | 03 table |
| `world.new` | **deleted**; `io.unsafe_run` (new, region op, `RecursiveMemoryEffects`, ends in `idr.yield`) | D20 |

**The platform** (59)

| op | disposition | reason |
| --- | --- | --- |
| `io.file_open`, `file_close`, `file_error`, `file_errno`, `file_read_line`, `file_read_chars`, `file_read_char`, `file_write_line`, `file_flush`, `file_seek_line`, `file_remove`, `file_size`, `file_poll`, `file_is_tty`, `file_chmod`, `dir_current`, `dir_change`, `dir_create`, `dir_remove`, `dir_open`, `dir_close`, `dir_entry`, `arg_count`, `arg`, `env_get`, `env_pair`, `env_set`, `env_unset`, `sleep`, `usleep`, `time`, `pid`, `term_raw`, `term_reset`, `term_setup`, `term_cols`, `term_lines`, `errno`, `handle.string`, `handle_free` | kept, members of the shape families (`HandleQuery`, `Path`, `Reading`, `Action`, `PlatformIO`) from one list | R1 |
| `io.file_time` and the six `file_{a,m,c}time_{sec,nsec}` | **merged: one op of seven results** (a status and six fields), mirroring the one OS call | 03 O-40; the registry maps base's `fileTime` (L16), a multi-result runtime entry (L11) |
| `io.exit` | kept as a terminator, no results | D14 |
| `io.strerror` | kept, no world, no IO | 03 O-41 |
| `clock_monotonic`, `clock_utc`, `clock_process`, `clock_thread` | **merged: `io.clock <kind>`**, `kind` the spec's `ClockKind` (D50), the runtime's entries explicit instantiations per case | G DP-42 |
| `clock_gc_cpu`, `clock_gc_real` | **deleted**: the frontend writes the constant -1 | §4 I5 |
| `clock_valid`, `clock_second`, `clock_nanosecond`, `handle.is_null` | **deleted**: `arith` from the spec's encoding constants | §4 I5 |

**Count** (*derivation*): deleted without an `idr` successor: `divu`,
`modu`, `io.put_sint`, `io.put_uint`, `io.put_double`, `io.put_list`,
`transpose`, `world.new`, the two GC clocks, three clock queries,
`handle.is_null` (14). Merges: crash (-1), `lin.cast` (-1), yield (-1),
tabulate (-1), update (-1), clocks 4 to 1 (-3), file times 7 to 1 (-6):
-14. 189 - 28 = 161 of today's ops, plus `io.unsafe_run` = 162; with the
other lanes' `idr.join`, `idr.jump`, `idr.lifetime`, `idr.is_unique`:
166. `own.adopt`/`own.give`'s replacement is L12's count.

### 2.2 The specification of an op (the seam with L03)

The fields this lane's dispositions read, in one-source's `Op` record:
- `family : Family`, the family applied to its constants; constants are
  enums (`Signedness`, `Part`, `Direction`, `ClockKind`), never bools;
  generated as `static constexpr` members of the op class.
- `meaning : Meaning`, `Runtime Symbol | Inline InlineFn | HandFolder |
  NoFold`, with `InlineFn = EuclidQuotient | EuclidRemainder | Shift
  Direction Signedness | ToChar Signedness` (and, under §4 I2, `Nonzero |
  InBounds | InRange`). The generator prints from it the trait that
  supplies the fold (`RuntimeFolds` or `InlineArith<F>`), the range method
  and the expansion's registration.
- `foldable : Foldable op` (an erased proof the generator needs for
  `RuntimeFolds`): the op's effects are pure or an acquisition only, and
  every ABI kind of its row has a constant form (`Str`, `Big`, `Int32`,
  `Int64`, `Signed`, `Unsigned`, `Double`, `Bool`; not `Buffer`, not
  `Pointer`). An IO op or a buffer op cannot get the trait.
- `guards : List Guard`, each `MkGuard kind operands cause`, `cause : Cause`
  (the generated crash-cause enum, D50's ending table's neighbour).
- `stages : Stages` (G DP-47).
- `implements : List BasePrimitive` (C6), replacing `Idr_Primitive`.

### 2.3 D41's template, exact

**Where.** `runtime/Numeric/Domain.h` (the concept, the evidence types,
the two runtime domains) and `runtime/Numeric/Inline.h` (the templates),
freestanding C++26, included by the runtime and by the compiler.
`idr/include/idr/IR/Numeric.h` with `idr/lib/IR/Numeric.cpp`: the two
compiler domains, which need MLIR.

**The concept** (a sketch in the real shape; nothing compiled):

```cpp
namespace rt::numeric {

// Generated from the specification's family constants.
enum class Signedness : unsigned char { Signed, Unsigned };
enum class Direction : unsigned char { Left, Right };
enum class Part : unsigned char { Quotient, Remainder };

// Evidence a domain alone constructs (private constructor, `friend D`):
// a divisor that is not -1 against the least signed value where the domain
// wraps, and a shift amount below the width. A template cannot reach a
// partial operation without one, so the IR-builder instantiation never
// builds an arith.divsi at MIN / -1 or an arith.shli at the width.
template <class D> class SafeDivisor;
template <class D> class BelowWidth;

template <class D>
concept Domain = requires(const D d, typename D::Value a, typename D::Value b,
                          typename D::Truth t, SafeDivisor<D> s, BelowWidth<D> n,
                          Signedness g, unsigned w, std::int64_t c) {
  { D::wraps } -> std::convertible_to<bool>;  // constexpr: MIN / -1 wraps, or cannot occur
  { d.width(a) } -> std::same_as<unsigned>;
  { d.constant(c, w) } -> std::same_as<typename D::Value>;
  { d.add(a, b) } -> std::same_as<typename D::Value>;
  { d.sub(a, b) } -> std::same_as<typename D::Value>;
  { d.bitAnd(a, b) } -> std::same_as<typename D::Value>;
  { d.divisible(a, b) } -> std::same_as<SafeDivisor<D>>;  // b, or 1 where a is MIN and b is -1
  { d.divisor(s) } -> std::same_as<typename D::Value>;
  { d.quotientTowardZero(a, s) } -> std::same_as<typename D::Value>;
  { d.remainderTowardZero(a, s) } -> std::same_as<typename D::Value>;
  { d.belowWidth(b) } -> std::same_as<BelowWidth<D>>;       // b masked to width - 1
  { d.shiftLeft(a, n) } -> std::same_as<typename D::Value>;
  { d.shiftRight(a, n, g) } -> std::same_as<typename D::Value>;  // arithmetic or logical
  { d.extend(a, g, w) } -> std::same_as<typename D::Value>;
  { d.truncate(a, w) } -> std::same_as<typename D::Value>;
  { d.equal(a, b) } -> std::same_as<typename D::Truth>;
  { d.less(a, b, g) } -> std::same_as<typename D::Truth>;
  { d.both(t, t) } -> std::same_as<typename D::Truth>;
  { d.either(t, t) } -> std::same_as<typename D::Truth>;
  { d.negation(t) } -> std::same_as<typename D::Truth>;
  { d.select(t, a, b) } -> std::same_as<typename D::Value>;
};

}  // namespace rt::numeric
```

**The templates** (one each; the body is the meaning):

```cpp
template <Domain D, Part P>
constexpr typename D::Value euclid(const D &d, typename D::Value a, typename D::Value b) {
  auto w = d.width(a);
  auto zero = d.constant(0, w), one = d.constant(1, w);
  auto s = d.divisible(a, b);  // where D::wraps: MIN / -1 divides by 1, giving MIN and 0
  auto q = d.quotientTowardZero(a, s), r = d.remainderTowardZero(a, s);
  auto negative = d.less(r, zero, Signedness::Signed);
  auto up = d.less(zero, d.divisor(s), Signedness::Signed);
  if constexpr (P == Part::Quotient)
    return d.select(negative, d.select(up, d.sub(q, one), d.add(q, one)), q);
  else
    return d.select(negative, d.select(up, d.add(r, d.divisor(s)), d.sub(r, d.divisor(s))), r);
}

template <Domain D, Direction Dir, Signedness S>
constexpr typename D::Value shift(const D &d, typename D::Value a, typename D::Value amount);
// as idrisShift: a signed negative amount turns the direction (its
// negation, which at the least value stays negative and reads as a huge
// count); an amount at or past the width leaves the fill (0, or the sign
// of a signed right shift); otherwise the shift by belowWidth(amount).

template <Domain D, Signedness S>
constexpr typename D::Value toChar(const D &d, typename D::Value x);
// x extended to 64 bits as S says; itself, truncated to 32, if
// x <=u 0xD7FF or 0xE000 <=u x <=u 0x10FFFF, else 0.
```

`divisible` is `d.select(d.both(d.equal(a, MIN), d.equal(b, -1)), 1, b)`
where `D::wraps`, and `b` unchanged otherwise (`if constexpr`).

**The instantiations.**

| domain | `Value`, `Truth` | `wraps` | reader | file |
| --- | --- | --- | --- | --- |
| `rt::numeric::Word` | `{uint64_t bits; unsigned width}`, `bool`; every operation masks to the width, signed comparisons sign-extend | `true` | the inline ops' folds; the `static_assert`s | `runtime/Numeric/Domain.h` |
| `rt::numeric::Small` | `int64_t` holding a 63-bit Integer, `bool` | `false` | `idris_rt_big_div`, `idris_rt_big_mod` small paths (replacing `euclidean`, `Arithmetic.cpp:20-33`) | `runtime/Numeric/Domain.h` |
| `idr::numeric::Ranges` | `mlir::ConstantIntRanges`, `std::optional<bool>`; arithmetic through upstream's `intrange::infer*`, comparisons through `intrange::evaluatePred`, `select` on an unknown condition the `rangeUnion` | `true` | `inferResultRanges` of every inline op | `idr/lib/IR/Numeric.cpp` |
| `idr::numeric::Arith` | `mlir::Value`, `mlir::Value` of `i1`; holds an `OpBuilder &` and a `Location`; each operation builds `arith.addi`, `subi`, `andi`, `divsi`, `remsi`, `shli`, `shrsi`/`shrui`, `extsi`/`extui`, `trunci`, `cmpi`, `select`, and `andi`/`ori`/`xori` on `i1` | `true` | the expansion patterns | `idr/lib/IR/Numeric.cpp` |

**The trait.** `Idr_InlineArith<F>` (a generated `NativeOpTrait`, `F` the
op's `InlineFn`) supplies:
- `foldTrait` (upstream runs trait folds for an op with no `fold` of its
  own, *read* `OpDefinition.h:1958-1965`): the guard asked first where the
  op is `GuardedOp`; constants converted once to `Word`; the template;
  the result back. Right identities as template constants
  (`euclid<Quotient>(a, 1) = a`, `euclid<Remainder>(a, 1) = 0`,
  `shift(a, 0) = a`), each `static_assert`ed against the template on a
  sample.
- `inferResultRanges` through `Ranges`.
- `ExpandInline<OpT>`, an `OpRewritePattern<OpT>` through `Arith`,
  registered by one generated `populateInlineExpansion` over the spec's
  list of inline ops, used at the stage that needs `arith`: the
  vectorization's preparation (0009) and the lowering. Upstream's
  `-int-range-optimizations` and canonicalization then fold the compares
  ranges decide, so a division whose divisor's range excludes -1 pays no
  overflow test at run time (D10).

**The `static_assert`s**, in `runtime/Numeric/Checks.cpp` (built with the
runtime, so with every target's toolchain):
- Euclid at 8 bits: (-7, 2) = (-4, 1); (7, -2) = (-3, 1); (-7, -2) =
  (4, 1); (7, 2) = (3, 1); (0, -5) = (0, 0); (-128, -1) = (-128, 0);
  (-128, 1) = (-128, 0); (-128, 127) = (-2, 126); (127, -128) = (0, 127);
  (-1, -128) = (1, 127); (-128, -128) = (1, 0). At 64 bits: (`INT64_MIN`,
  -1) = (`INT64_MIN`, 0). On `Small`: (-2^62, -1) = (2^62, 0), no wrap.
- Euclid's laws at 8 bits, exhaustive: for every `a` and every `b != 0`,
  `a == q*b + r (mod 2^8)`, and `0 <= r < |b|` but at (-128, -1); one
  `static_assert` per dividend (256), each over 255 divisors, to stay
  under clang's default `-fconstexpr-steps` (1,048,576, *recalled*): the
  step count per chunk is the measurement to take when it first builds.
- Shifts at 8 bits: `shift<Left, *>(1, 7) = 0x80`; `(1, 8) = 0`;
  `shift<Left, Unsigned>(1, 255) = 0`; `shift<Left, Signed>(4, -1) = 2`;
  `shift<Left, Signed>(-128, -1) = -64`; `shift<Left, Signed>(1, -128) =
  0`; `shift<Left, Signed>(-1, -128) = -1`; `shift<Right, Signed>(-128,
  7) = -1`; `(-128, 8) = -1`; `shift<Right, Unsigned>(0x80, 7) = 1`;
  `(0x80, 8) = 0`; `shift<Right, Signed>(4, -1) = 8`;
  `shift<Right, Unsigned>(4, 255) = 0`; and for amounts 0 to 7, every
  value, against multiplication and division by powers of two.
- `toChar`: `<Signed>(-1 : i8) = 0`; `<Unsigned>(0xFF : i8) = 0xFF`;
  0xD7FF, 0xE000, 0x10FFFF themselves; 0xD800, 0xDFFF, 0x110000 give 0;
  `<Unsigned>(2^32 + 65 : i64) = 0` (no truncation before the test);
  `<Signed>(INT64_MIN) = 0`; `<Unsigned>(0xFFFFFFFF : i32) = 0`.

What `static_assert` cannot check, a unit test does (L19): the `Ranges`
result contains the `Word` result for every pair of 8-bit ranges of
width at most 4 and every value in them; the `Arith` expansion, run
through upstream's folder on constants, equals `Word`.

### 2.4 The canonicalizer's bounded configuration

One configuration, generated from the pipeline's specification (D50:
the stages are the spec's; compile-time-cpp §2.3(f) prints
`IdrConfigured<Canonicalizer, "::idr::canonicalizer", ...>`), used at
every point and by idr-optimize's inner pipeline (deleting
`Optimize.cpp:64-66`'s second copy, 04 C59):
- top-down; region simplification `Disabled` (CSE beside it);
  `maxIterations` 10 (upstream's default; non-convergence ignored, never
  a refusal, *read* 04 §3.1); `cseBetweenIterations` off;
  `testConvergence` off in the pipeline and on in the canon tests, so a
  pattern cycle stays a test failure.
- **the rewrite bound per op**: a carried upstream patch adds
  `GreedyRewriteConfig::setMaxNumRewritesPerOp(k)` and the pass option
  `max-num-rewrites-per-op`, the driver bounding one iteration's rewrites
  by k times the ops it seeded. A bound in the program's units that
  leaves a function less canonical and never fails; with `maxIterations`
  it makes the run terminate by construction (AGENTS.md). k is debt: the
  largest rewrites per op of any canonicalize run on the stage-1 module,
  measured with `--profile-actions-to`, times a margin. Patch:
  `upstream/<id>-greedy-rewrites-per-op/llvm-project.patch`, with its
  report, reproducer, `tests/upstream-<id>` and PINS.md entry.
- **dialects**: `filterDialects` is derived, never listed: each point's
  stage admits a set of ops (G DP-47's per-op stages), and the generator
  prints the dialects of that set. No hand list to drift.
- **preservation**: a carried upstream patch makes the canonicalizer pass
  `&changed` and mark all analyses preserved when nothing changed, as CSE
  does (04 C62, *read* `Canonicalizer.cpp:84-90` against `CSE.cpp:51`).
- **the points**: before defunctionalization (G DP-68), after the columns
  conversion, after bufferization, after linalg-to-loops, after
  returned-arguments, and idr-optimize's inner pipeline (*read*,
  `Pipeline.cpp:93, 116, 167, 181`; `Optimize.cpp:64`).
- **the patterns of ours**: 04 T4's one match canonicalization over one
  view per visit (region ends a closed sum, 1.5), T5's declared
  `retryBetween` class, T6's one `knownConstructor` (gone under G DP-37's
  refined case binding), the DRR patterns of 2.5; no string root, no
  stage read in a pattern (04 C19, C22).

### 2.5 DRR, where a pattern is local

Generated from `IdrisMLIR.Spec.Rewrites`: a record per pattern, `root`,
`source` and `target` as typed DAGs over the spec's op names, constraints
(`HasOneUse`, a native constraint naming a hook), erased proofs that every
target variable is bound in the source and that the root is the source's
root; printed one to one as `Pat<>` or `Pattern<>`. Rooted (DRR's
generated patterns are op-rooted, *read* 04 E4). The patterns:

| pattern | rewrite | replaces |
| --- | --- | --- |
| output of a character | `put_str(str.from_char c)` [one use] to `put_char c` | `PutStrOfBuilder`'s from_char case |
| output of an append | `put_str(str.append a b)` [one use] to `put_str a; put_str b` (auxiliary ops, *read* `DeclarativeRewrites.md:486-496`; a root of no result: *conjecture* until built) | its append case |
| output of a cons | `put_str(str.cons c s)` [one use] to `put_char c; put_str s` | its cons case |
| output of a packed cons | `put_str(str.pack(con @Cons(x, xs)))` [both one use] to `put_char x; put_str(str.pack xs)`, and the concat twin | `PutListOfCons` |
| output of nothing | `put_str(constant "")` erased | `PutStrOp::fold`, which needed the world |
| head of a show | `str.head(check.nonempty(str.show_sint x))` to `int_head_s x`; likewise `show_uint`, `show_double` | `HeadOfBuilder` |

Removed with them: `StrBuilderOpInterface`'s `writesInPieces`,
`writePieces`, `knowsFirstChar`, `firstChar` and the five `unasked` stubs
(04 C31); the fusion `put_str(show_* x)` to `put_* x` (DP-43; 04 C32).
Patterns that read regions stay C++ (04 §6's fourteen).

### 2.6 The one runtime fold, and the crash's shape

**The fold.** `idr/include/idr/IR/RuntimeFold.h`:

```cpp
namespace idr::fold {
// The C value of a constant operand by the kind its runtime function takes
// it as; the kinds with no constant form (Buffer, Pointer) have none.
template <runtime::OperandKind K> struct Operand;   // from(Scope &, Attribute) -> std::optional<C>
// The constant of a result by its kind: Wrapped reads the op's width,
// Order the op's predicate.
template <runtime::ResultKind K> struct Result;     // to(Scope &, OpT, C) -> Attribute

template <class OpT>
concept FoldsByRuntime = requires { runtime::Abi<OpT>::function; } &&
    everyKindHasConstantForm(runtime::Abi<OpT>::operands, runtime::Abi<OpT>::entry.result);

template <FoldsByRuntime OpT>
mlir::OpFoldResult foldByRuntime(OpT op, llvm::ArrayRef<mlir::Attribute> constants);
// the guard first (GuardedOp), then each operand converted by its row's
// kind through an index_sequence over Abi<OpT>::operands, the function
// called in one Scope, the result converted by entry.result.
}
```

Supplied as `foldTrait` by `Idr_RuntimeFolds`, attached by the generator
exactly where `foldable` holds (2.2). `Abi<OpT>` is generated by
`specgen` from `Spec.Runtime` (one-source §6.2's `RuntimeAbi.h.inc`),
`constexpr` today (*read*, `idris-mlir-tblgen.cpp:2970-2986`). The
lowering reads the same row, so a fold and a call disagree only through
one of two readers of one row. `Scope::big` hands the decimal text to the
runtime without a `StringAttr`. `folds-balanced` keeps reading the scope's
leak count.

**The folders deleted**: the 37 bodies 04 §7 names (`Fold/Bigs.cpp`:
`sub`, `mul`, `and`, `or`, `xor`, `div`, `mod`, `neg`, `nat.from_big`,
`cmp`, `from_sint`, `from_uint`, `from_double`, `to_double`, `show`,
`from_str`; `Fold/Strings.cpp`: `append`, `cons`, `from_char`,
`show_sint`, `show_uint`, `show_double`, `substr`, `reverse`, `tail`,
`length`, `bytes_length`, `scalar_at`, `drop_bytes`, `scalar_bytes`,
`index`, `cmp`, `to_int`, `to_double`, `double_head`, `int_head_s`,
`int_head_u`); `ToIntOp::fold` (`OpsScalars.cpp:66-75`); `foldDivision`,
`foldShift`, `idrisDivMod`, `idrisShift` (`Ops.cpp:200-293`) and the
`fold` bodies the scalar `.td` classes declare (`IdrScalarOps.td:35-39,
71-75`); `foldToChar` (`OpsScalars.cpp:22-33`); `strUnary`, `strBinary`,
`bigUnary`, `bigBinary`, `strAtOffset`. **Kept, each its own rule**:
`big.add`'s zero, the big shifts' size policy, `nat.pred`'s zero,
`nat.to_big`, `big.small`'s range, `big.to_int`'s round trip, `str.head`
of a cons, `str.pack`/`str.concat`'s list walk, `con`/`closure`/`suspend`
(one `FoldsToConstant` trait, 04 T1), `field`, `tag`, `force`, `constant`,
`target.os`, `tie_shape`, `lin.cast`'s round trip, the guards' fold to
their operand.

**The crash.** `idr.crash %message : !idr.str at #idr.site<file, line,
column>`, a terminator with no successor, `Write` on `crash`. Its message
has two kinds of source, each an op of its own (the skill: "where several
sources feed one effect, each source is its own op"): a static cause is
`idr.constant #idr.cause<k> : !idr.str`, `k` a case of the generated
`Cause` enum, which lowers to the cause's static string from the
generated table (one global per cause, D38, no text hashed); `idris_crash`
passes a computed string. A guard holds `cause : Cause` and `site` as
properties. `#idr.site` is written by the frontend alone, from the TT
location, and compared by `OperationEquivalence` because it is a property
(§4 I3). The runtime entry is `idris_rt_crash_at(const idris_rt_str
*cause, file, line, column)`, L11's.

### 2.7 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| the op set, each op's family and constants | `IdrisMLIR.Spec.Ops.*` family functions; `specgen` prints the `.td` and the C++ constants | the specification |
| an op's meaning (runtime, inline, hand, none) | the spec's `meaning` field; the generator attaches the trait | the specification |
| the runtime ABI row `Abi<OpT>` | `Spec.Runtime`, printed by `specgen` into C++ and `idris_rt_ops.h` | the specification |
| the inline functions' meaning | `runtime/Numeric/Inline.h` (hand C++, the meaning) | the runtime's source |
| a fold's constant | `Idr_RuntimeFolds` or `Idr_InlineArith<F>` | the greedy driver and `OperationFolder` calling the trait |
| an inline op's range | `Idr_InlineArith<F>::inferResultRanges` | upstream's range analysis and idr-narrow calling it |
| an inline op's `arith` | `ExpandInline<OpT>` | the vectorization's preparation and the lowering |
| a guard's kind, operands, cause | the spec's `guards`; generated `Guarded<Op>` and the Idris guard builders | the specification; the frontend emits the guards |
| a crash's site | `#idr.site`, written by the frontend from the TT location | the frontend; passes copy it |
| a static crash cause | `#idr.cause<k>` constants, `Cause` from the spec | the frontend and the guards |
| a clock reading's kind | `io.clock`'s `kind` property, `ClockKind` from the spec (D50) | the frontend |
| the OSClock and handle encodings | `Spec.Clocks`, `Spec.Handles` constants, printed for the runtime and imported by the frontend | the specification |
| a local rewrite | `Spec.Rewrites`, printed as DRR | the specification |
| an op's legal stages | the spec's `stages`; one generated trait | the specification |
| a `lin.cast`'s direction | its operand and result types (quantity) | the frontend's emission, kept by every pass, verified after each |
| the canonicalizer's configuration | `Spec.Pipeline`'s canonicalize step; `idr::canonicalizer` generated; k a spec constant | the specification |
| each op's effects | `Spec.Effects` (L01) | L01 |
| refined case types, index terms | D48's family attributes (L04) | the frontend and the passes that declare a family |

### 2.8 Consumers, failure and cleanup

- A fold with a non-constant operand returns nothing; a guard that does
  not hold stops a fold of the op it guards; a guard refuted on constants
  keeps its crash (D13: a statically certain crash stays where evaluation
  reaches it; §4 I2 makes it a plain `idr.crash`).
- The generic fold cannot be attached to an IO or buffer op: `foldable`
  fails in the specification, and the concept fails in C++.
- A canonicalize run that reaches the per-op bound stops and returns
  failure, which the pass ignores: less canonical, never refused.
- The expansion builds no poison: the evidence types (2.3).
- A fold's runtime references are released by its `Scope`; a leak is
  counted and `folds-balanced` reads it.

### 2.9 What it deletes

`idr/lib/IR/Fold/Bigs.cpp`, `Fold/Strings.cpp`: the bodies of 2.6;
`include/idr/IR/Fold.h`: `strUnary`, `strBinary`, `bigUnary`,
`bigBinary`; `lib/IR/Ops.cpp:200-293`; `lib/IR/OpsScalars.cpp`:
`foldToChar`, `toCharRanges`' constant range, `ToIntOp::fold`, the two
`lin.*` folds (one `lin.cast` fold); `lib/Conversion/Scalars.cpp`:
`LowerDivision`, `LowerShift`, `LowerToChar`, `LowerWorldNew`, the
unsigned division arm and the hand family list (12 CV-37, CV-38);
`runtime/Big/Arithmetic.cpp:17-33` (`euclidean`); `lib/IR/OpsChecks.cpp`:
the `holds` of nonzero, in_bounds and range (`checkedBefore` stays: a
guard writes `crash`, so CSE never merges two, 04 C55);
`lib/Conversion/Checks.cpp`: the `fails` of the same three; `include/idr/IR/Traits.h:31-40` `CallsRuntime` as an empty
marker (the trait carries the row); the `.td` defs of `divu`, `modu`,
`put_sint`, `put_uint`, `put_double`, `put_list`, `crash_str`,
`lin.enter`/`lin.use` (one `lin.cast`), `array.yield`, `world.new`,
`tabulate_io`, `element.update`, the six clock readings (one op), the two
GC clocks, three clock queries, `handle.is_null`, `file_time` and its six
readers (one op), `Idr_NoReturn`, `Idr_Primitive`, the guards'
`StrAttr:$cause`; `lib/IR/Canon/Output.cpp`'s fusion and stubs;
`lib/IR/Canon/PutList.cpp` (DRR); `Pipeline.cpp:28-32`'s configuration
and `Optimize.cpp:64-66`'s copy (generated); the runtime functions
`idris_rt_io_clock_valid`, `_second`, `_nanosecond`, `_clock_gc_cpu`,
`_clock_gc_real`, `idris_rt_handle_is_null` (the six readings become
instantiations; the put entries become the lowering's helpers).

### 2.10 Distinctions that must remain

The signedness pairs whose computation or runtime function differs
(`divs`/`mods` signed only; four shifts; `to_char_s/u`; `from_sint/uint`;
`show_sint/uint`; `int_head_s/u`); `take`/`unpack` (memory); `borrow`/
`share` (consumption); `match`/`match_lit` (keys, bindings); five guards
(operand structures); `idr.crash` (stops) against a guard (crashes on a
condition); `big.small` against `big.from_sint` (a proof); `str.pack`/
`str.concat` (element kinds); `Word` against `Small` (`wraps`); runtime
meaning against inline meaning.

### 2.11 Seams

- **L01** (declarations): every op's `Effects` value; the C3 rule as
  `NewIdentity result IfLinear`/`IfOwned` for `con` and the capture
  family, and §4 I4's for the builders, replacing effect-vocabulary §3's
  `AcquiresCell` and closure `Allocate` (1.1, a mismatch to fix there).
- **L02**: the row on `func` and `call`.
- **L03**: `Meaning`'s `Inline` case, `Spec.Rewrites`, flat defs, enum
  constants, `foldable` (1.3, 2.2).
- **L04**: `!idr.ctor<T, @C>` for `field`, `take`, `unpack` (G DP-37);
  layout's "has a cell" for take/unpack; `Fin n` ranges for §4 I8.
- **L05**: `idr.lifetime`; the call's lifetime arguments.
- **L07**: `dup`, `drop`, `is_unique`, the cell ops; C3's materialization
  at `cell.new`.
- **L09**: `idr.join`, `idr.jump`; the match's `PropagateControlFlowBreak`;
  canon's `Jumps` region end; `idr.yield`'s parent list.
- **L10**: `may_loop`; the call's tail kind.
- **L11**: `idris_rt_crash_at` with a string cause; the clock
  instantiations; the file-times entry; `runtime/Numeric/`.
- **L12**: every array op; `own.adopt`/`own.give`'s replacement.
- **L15**: the concept-constrained fold and domain templates; explicit
  instantiation of the two compiler domains behind `extern template`.
- **L16**: the frontend emits `arith` for `divu`/`modu`, the clock
  queries and the null test; the GC clocks as constants; composed output;
  `#idr.site`; `lin.cast`; the file-times `Faster` hook.
- **L18**: the canonicalizer in idr-optimize and before defunctionalization
  is this configuration.
- **L19**: the static_asserts' unit-test half; the tests of §4.

## 3. QTT

**Quantity 0.** Nothing erased reaches an op as a value (AGENTS.md;
*read*: no op has an erased operand). D48 adds the one place quantity 0
enters this lane: index and lifetime variables are compile-time
parameters of `idr.func` and arguments of `idr.call` (`@map<k, frame>`),
checked by substitution in `verifySymbolUses`, never operands. They are
read at compile time only. What this lane should do with them is §4 I8:
an erased index bounds a value (`Fin n` is one word below n, D48, 0018),
and the interval instantiation of D41 can read that bound off the type,
so a guard the index already proves is never built.

**Quantity 1: where it enters, is kept and read.**
- Enters at `lin.cast` to quantity one (today `lin.enter`), which the
  frontend writes where a value fills a quantity-1 binder (*read*,
  `compiler/src/IdrisMLIR/Emit/Operations.idr:144-152`), and at a
  quantity-1 parameter or result of a function.
- Consumed, at most once on each path (the verifier's rule is affine:
  "each is used at most once on every path", *read*
  `Verify/Linearity.cpp:3-6`), by: `lin.cast` to many, `call` and `apply`
  arguments, `return`, `yield`, the capture family, `con` and `cell.init`
  fields, `dest.write`, the scrutinee of `match`, and the two guards that
  pass a reference on (`check.nonzero`, `check.nonempty`).
- Never consumed by a runtime op: every runtime op's read operands are
  `Idr_Read`, which requires quantity many (*read*, `IdrOps.td:19-23`). A
  primitive reading a linear value in place cannot be written; a linear
  value reaches a primitive only through a `lin.cast` to many. Holds; keep
  it in the specification's operand constraints.
- Lost at the lowering, where the type converter strips `!idr.lin<T>`,
  after counting has read it.

**`lin.enter` and `lin.use` as one cast.** `lin.cast %v : A -> B`, one op:
`A` and `B` equal up to quantity and exactly one of them at quantity one
(a generated relation, checked by the op's verifier); effect `Allocate` on
`identity` of the result in both directions (C3: a linear result is a
fresh identity, never merged; and an unused cast is deleted, which the
affine rule allows). The direction is read off the types by one generated
accessor returning `enum class QuantityChange { Enter, Leave }`, for the
readers that ask (*read*: `Specialize/Patterns.cpp:35, 65, 125`;
`Contracts/Contracts.cpp:222`; `Bufferize/Linear.cpp:38` goes with D43).
One fold, the QTT rule stated once: `cast(cast(x))` is `x` when the outer
result's type is `x`'s, and, when that type is linear, only if the inner
result has exactly one use: making a linear value from an unrestricted
one is free, but a value of quantity many may already be used elsewhere
(*read*, today's two folds, `OpsScalars.cpp:92-108`, which hold exactly
this asymmetry).

**Canonicalizations a quantity licenses, honestly.** Fewer than the theme
hopes, because AGENTS.md is right that a linear binder implies neither
unique ownership nor a single region of use:
- The `lin.cast` round trip above.
- Deleting an unused linear value's producer: affine, so legal; it falls
  out of `Allocate` on the result.
- A known-case fold of a match on a linear `con` leaves no residual
  construction: the con had one use. With C3 the con is pure anyway and
  dead code removes it; no new rule.
- What the quantity does not license: sinking a linear producer is not
  free of duplication (a linear value may be used once in each of two
  case regions), and no in-place rewrite follows from linearity alone
  (exclusivity, `!idr.excl`, does that, L08).

**Where the quantity is not kept today**: `delay` (1.8). And `apply`'s
`TypesMatchWith ... sameCarriers` compares argument and parameter types
with grades ignored (*read*, `IdrClosureOps.td:126-131`), so a linear
argument meets a parameter of quantity many unchecked before
defunctionalization, which makes every `apply` a call whose operand types
equal its callee's (*read*, `Call.cpp:34-43`, 03). L18's window, noted.

**D10 and quantities.** What a quantity proves that this lane still pays
for: (a) a guard whose condition an erased index proves (§4 I8); (b) a
"one use" test where the type says it (negligible: `hasOneUse` is O(1)).

## 4. Improvements

**I1. The expansion's no-poison obligation as types.** *Coordinator.*
- Evidence: D41 does not say how the `arith` instantiation avoids
  `arith.divsi` at MIN / -1 and `arith.shli` past the width; today
  `Scalars.cpp:79-90, 121-127` avoid them by hand (*read*).
- Counterexample: a template written `q = d.quotientTowardZero(a, b)`
  compiles over `Word` (which wraps) and over `Arith` builds `divsi
  %min, %m1`: poison, and LLVM may then delete the program's `divs i8
  -128, -1` path's result.
- Root cause: the domain's partial operations accept any value.
- Correction: `SafeDivisor<D>` and `BelowWidth<D>`, constructed only by
  `d.divisible` and `d.belowWidth` (2.3).
- Deletes: the hand avoidance in `Scalars.cpp`.
- Discriminator: the bad template does not compile.

**I2. The guards' conditions are D41 functions; ranges decide guards.**
*Coordinator* (D41's own words, "an op of inline arithmetic", and D13,
D10).
- Evidence: each of nonzero (on an integer), in_bounds (index against a
  length) and range is written as a fold (`OpsChecks.cpp:22-61`), a range
  clamp (`:130-168`) and a lowering (`Conversion/Checks.cpp:43-97`), all
  *read*.
- Counterexample: `check.range`'s fold uses `sadd_ov` and rejects an
  overflowing end (`OpsChecks.cpp:58-60`); its lowering computes `room =
  size - offset` and compares the count (`Checks.cpp:88-97`). They agree
  today by care. A change to one (say, a count of zero at an offset equal
  to the size) moves the fold or the lowering, not both, and a constant
  program folds to a different answer than the same program with
  opaque inputs.
- Root cause: one condition, three spellings.
- Correction: `InlineFn` gains `Nonzero`, `InBounds`, `InRange`; each
  condition one template; `Word` decides it on constants (the fold),
  `Ranges` gives holds, fails or unknown (a guard that holds on ranges
  folds away, "a proof is the absence of the guard", `IdrCheckOps.td:
  56-62`; one that fails becomes `idr.crash` of its cause and site, the
  rest of its block erased, D13's statically certain crash with no
  run-time test), `Arith` builds the failure test. The backward clamp of
  the result's range stays per kind (a different function, essential).
  `nonempty` (a runtime length) and `finite` (`math.isfinite`) stay as
  they are.
- Deletes: three `holds`, three `fails`.
- Discriminator: a test whose guarded operations run once on constants
  and once on values read from input, both outputs equal to one committed
  file; a canon test where a range-proved guard is gone and a refuted one
  is a crash.

**I3. The crash site is a property, not debug info.** *Coordinator*
(AGENTS.md: a fact in a place a pass may drop; D37, D38 make it output).
- Evidence: 1.6 (`Runtime.cpp:42-43`; `Merge.cpp:36, 48`).
- Counterexample: `g : T -> Nat`, `g A = idris_crash "bad"` at line 3,
  `g B = idris_crash "bad"` at line 4. After inlining, the two case
  regions are equal ignoring locations; `MergeIdenticalRegions` keeps one;
  `g B` prints `Main.idr:3:...`. Committed stderr names line 4.
- Root cause: a printed fact held in the `Location`, which equivalence
  ignores and rewrites may replace or fuse.
- Correction: `#idr.site<file, line, column>` an inherent property of
  `idr.crash` and of each guard, written by the frontend; the lowering
  reads it; the `Location` stays debug info.
- Deletes: `crashMessage`'s location search and its "may name no place"
  branch (`Runtime.cpp:41-50`).
- Discriminator: the test above, failing before (one site), passing after
  (two sites, no merge).

**I4. C3 for every builder of an immutable value.** *Coordinator* (C3's
reason, verbatim: "traded an optimization for an exact count before
counting, where no reader needs one").
- Evidence: `big.*` and `str.*` builders declare `MemAlloc` on their
  result at every stage (*read*, `IdrBigOps.td:31, 50`,
  `IdrStringOps.td:20`); effect-vocabulary §2.2 keeps them acquiring
  before counting.
- Counterexample: `f : Integer -> Integer -> Integer; f x y = (x + y) *
  (x + y)` compiles to two `big.add` calls and two allocations; CSE may
  not merge an op that allocates (*read*, effect-vocabulary §2.3,
  `CSE.cpp:268`).
- Root cause: acquisition declared where no cell is materialized yet.
- Correction: the builders' acquisition is a typed rule on the result,
  `Allocate` on `heap` when the result is owned (from counting on),
  nothing before; a linear result a fresh identity, as C3 says for `con`.
  D23's "where new memory enters the arena is marked" holds where the
  memory is: after counting, at the builder.
- Deletes: nothing; changes declarations (L01).
- Discriminator: the counterexample's IR after the first canonicalize
  holds one `big.add`.

**I5. Runtime encodings in the specification; their queries `arith`.**
*Coordinator.*
- Evidence: `clock_valid`, `clock_second`, `clock_nanosecond` take a world
  and call the runtime for `c != -1`, `c >> 30`, `c & (2^30 - 1)` on the
  documented encoding (*read*, `IdrPlatformOps.td:14-19, 337-348`);
  `handle.is_null` calls it for `h == -1` (`:351-361`); two GC clocks call
  it to learn -1 (`:334-335`).
- Counterexample: a loop timing itself with `clockValid` and `toNano`
  pays three runtime calls per iteration, each ordered as IO, so none
  folds or hoists.
- Root cause: an encoding the runtime documents in prose, so the compiler
  cannot compute on it.
- Correction: `Spec.Clocks` and `Spec.Handles` hold the encodings (the
  seconds shift, the nanosecond mask, the invalid and null values),
  printed for the runtime's packing and imported by the frontend (D50),
  which emits `arith`; `ClockKind` holds the four clocks that exist, and
  the frontend writes -1 for the GC clocks.
- Deletes: six ops, six runtime functions, the IO on three pure
  computations.
- Discriminator: a test reading the clocks and handles prints what it
  does today; idr-expect "no runtime call" on the queries.

**I6. `shls` and `shlu` stay two.** *Coordinator* (G DP-41's merge
reversed on the code's evidence; its school stands).
- Evidence and counterexample: 1.1 (`shls 4, -1 : i8` = 2; `shlu 4, 255 :
  i8` = 0).
- Root cause: the amount's signedness is part of the computation.
- Correction: four shift ops, `shift<Dir, S>`.
- Deletes: nothing. Discriminator: the 2.3 `static_assert`s.

**I7. `delay` joins the capture family.** *Coordinator* (AGENTS.md: no
pass may drop a multiplicity).
- Evidence: 1.8.
- Counterexample: `idr.delay %x : !idr.lin<!S> -> !idr.lazy<!S>` verifies;
  two forces of the plain suspension use the linear value twice, and
  D24's in-place rule, which reads quantities, no longer sees it.
- Root cause: the quantity rule written on two of the three capture ops.
- Correction: one family `closure`, `suspend`, `delay` with
  `Idr_LinearWhenACaptureIs`.
- Deletes: the separate `delay` definition.
- Discriminator: a verifier test refusing the line above.

**I8. Erased indices as ranges.** *Coordinator* (D10 with D48 and 0018).
- Evidence: D48: "`Fin n` is one word below `n`"; guards on array and
  string indices are emitted from the guarded op's ODS (*read*,
  `IdrArrayOps.td:311-312`, `IdrStringOps.td:216-218`).
- Counterexample: `xs !! i` with `i : Fin n` and `xs` of extent `n` (D48's
  `#Array[n]`) keeps `check.in_bounds` and its run-time compare, which the
  index's type already proves.
- Root cause: the bound lives in an erased index the range hook never
  reads.
- Correction: the `Ranges` domain seeds an operand of type `Fin n` with
  [0, n-1] (a constant `n`) or with its index variable's bound; I2 then
  deletes the guard at the first canonicalize. Where the frontend sees it
  first, it emits no guard.
- Deletes: the compare and branch per indexed access with a `Fin` index.
- Discriminator: idr-expect "no guard" on such a program.

**I9. The canonicalizer's bound per op, and its dialects derived.**
*Coordinator* (corrects G DP-33, DP-67).
- Evidence: 1.2's mismatch.
- Counterexample: a fixed `maxNumRewrites` of 10^6 lets a cycle spend a
  million rewrites in each of 70,000 functions; 10^3 stops a legitimate
  cascade in a large function.
- Root cause: upstream's unit is per run, ours per op.
- Correction: 2.4's carried patch and the derived `filterDialects`.
- Deletes: `kNoLimit`; the hand dialect list G DP-67 names.
- Discriminator: a test with a planted two-pattern cycle that stops and
  reports non-convergence under `test-convergence`.

**I10. Output composes, `put_list` included.** *Coordinator* (G DP-43's
reason applies to the list).
- Evidence: 1.1.
- Counterexample: `putStr (pack cs)` and `putStr (pack cs ++ "!")` take two
  paths today, the first through `put_list`, the second through a built
  string; the pure halves never meet CSE.
- Correction: `io.put_list` deleted; 2.5's packed-cons pattern.
- Deletes: the op, its lowering's selection by element type (12 CV-41),
  `PutList.cpp`.

## 5. Work units

Drafts for the implementation swarm; none dispatched here. Paths under
`compiler/spec/` follow C7.

**U1. The inline templates (D41).**
- Writes: `runtime/Numeric/Domain.h`, `runtime/Numeric/Inline.h`,
  `runtime/Numeric/Checks.cpp`, `runtime/Big/Arithmetic.cpp`,
  `runtime/CMakeLists.txt`; `idr/include/idr/IR/Numeric.h`,
  `idr/lib/IR/Numeric.cpp`, `idr/include/idr/IR/Traits.h` (the
  `InlineArith` trait), `idr/lib/IR/Ops.cpp`, `idr/lib/IR/OpsScalars.cpp`,
  `idr/lib/Conversion/Scalars.cpp`.
- Outcome: 2.3; `divs`, `mods`, four shifts, `to_char_s/u` fold, infer
  ranges and expand through one template each; the runtime's small path
  instantiates it.
- Deletes: 2.9's scalar items and `euclidean`.
- Must not: hand-write a fourth copy; put MLIR in `runtime/`; keep a
  `bool` constant.
- Acceptance: the `static_assert`s build on all four targets; a program
  over a grid of `Int8`/`Int64`/`Bits8`/`Bits64` divisions, shifts and
  `chr` prints the committed output whether its inputs are literals or
  read from standard input.

**U2. The one runtime fold.**
- Writes: `idr/include/idr/IR/RuntimeFold.h`, `idr/include/idr/IR/Fold.h`,
  `idr/lib/IR/Fold/Bigs.cpp`, `Fold/Strings.cpp`, `Fold/Scope.cpp`,
  `idr/lib/IR/OpsScalars.cpp` (`to_int`).
- Outcome: 2.6; every pure runtime op folds its constants by its row.
- Deletes: the 38 bodies and the helper templates; the `StringAttr` per
  big operand.
- Must not: attach the fold to an IO or buffer op; read a symbol by name.
- Acceptance: `folds-balanced` holds; every fold fixture's output is
  unchanged; an op with no hand folder folds.

**U3. The canonicalizer's configuration and its two upstream patches.**
- Writes: `upstream/<id>-greedy-rewrites-per-op/`,
  `upstream/<id>-canonicalize-preserves/`, `tests/upstream-<id>` (two),
  `PINS.md`, `tools/bootstrap.sh` (patch list),
  `idr/lib/Transforms/Pipeline.cpp`, `idr/lib/Transforms/Optimize/
  Optimize.cpp` (until the pipeline is generated, then the spec's step).
- Outcome: 2.4.
- Deletes: both hand configurations.
- Must not: turn a stopped run into an error.
- Acceptance: a planted cycle stops; a canonicalize that changes nothing
  keeps a cached analysis (a test pass counting recomputations).

**U4. Ops: the merges, splits and deletions of 2.1 in the
specification.**
- Writes: `compiler/spec/IdrisMLIR/Spec/Ops/*.idr`, `Spec/Runtime.idr`,
  `Spec/Clocks.idr`, `Spec/Handles.idr`, `Spec/Rewrites.idr`; the
  generated `.td`; `idr/lib/IR/OpsChecks.cpp`, `OpsClosures.cpp`,
  `OpsOwnership.cpp`, `OpsPlatform.cpp`, `OpsMatch.cpp`;
  `idr/lib/Conversion/{Checks,Runtime,Strings,Matches}.cpp`; the
  frontend's emission (with L16's unit).
- Outcome: 161 of today's ops plus `io.unsafe_run`; `lin.cast`; one
  `idr.crash` with `#idr.site`; `io.clock <kind>`; one file-times op;
  composed output; `divu`/`modu`, clock queries and the null test as
  `arith`.
- Deletes: 2.9's `.td` items, `Idr_NoReturn`, `Idr_Primitive`.
- Must not: land the world's removal apart from L01/L02's row; rename
  ops before the owner's answer (§6).
- Acceptance: the program suite and the semantics runs pass unchanged;
  I3's and I7's tests.

**U5. Match canonicalization over one view, DRR from the specification.**
- Writes: `idr/lib/IR/Canon/*`, `idr/include/idr/IR/Canon.h`,
  `compiler/spec/IdrisMLIR/Spec/Rewrites.idr`.
- Outcome: 04 T4 with region ends `Yields | Stops | Jumps`; T5; 2.5's
  patterns; the probe deleted (04 T2).
- Must not: depend on the driver's order between rewrites (04 §8); read
  the stage in a pattern.
- Acceptance: canon fixtures pass with `test-convergence=true`.

**U6. Guards under D41 and erased indices as ranges (I2, I8).**
- Writes: `runtime/Numeric/Inline.h` (conditions),
  `idr/lib/IR/OpsChecks.cpp`, `idr/lib/IR/Numeric.cpp`,
  `idr/lib/Conversion/Checks.cpp`.
- Outcome: I2, I8.
- Deletes: three `holds`, three `fails`.
- Acceptance: I2's and I8's tests.

## 6. Owner questions

**Q1. Op names.** 46 of 189 mnemonics have no family prefix (03 §2,
*measured*): `con`, `field`, `tag`, `match`, `divs`, `shls`, `to_char_s`,
`take`, `unpack`, `dup`, `drop`, `closure`, `force`, ... The owner has
named each vocabulary so far (D28, D29, D40: "maximally churn the names to
be maximally correct").
- (a) Every op in a family named for the type or resource it acts on
  (`data.con`, `data.match`, `int.divs`, `int.shl_s`, `int.to_char_s`,
  `own.take`, `own.dup`, `fn.closure`, `lazy.force`, `big.pred` as
  `nat.pred`), in the same cutover. Costs: 9,647 unprefixed occurrences in
  334 fixtures (03 §6, *measured*), mechanical; the Idris side follows
  from the specification. Buys: a name says what an op acts on.
- (b) Keep today's mnemonics but for the merged and new ops. Costs:
  nothing now; two naming schemes side by side.
- Recommendation: (a), landed last in the op cutover.
