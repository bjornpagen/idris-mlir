<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## B — Exhaustive boxes for the arithmetic narrowing and the tagged bigs rest on

Findings: F10

Owner / exclusive writes: `foreign/idr/unittests/**` (ownership.json `B`; no excludes), and within it only C++ units. B writes no CMakeLists.txt: README §6 makes every `CMakeLists.txt` the coordinator's, `foreign/idr/unittests/CMakeLists.txt` included; its exact text, and the Makefile's, are in Handoff below.

Read first:
- Packet: README §2 (proof before contract before generated test; library first; no outside oracle), §4.5, §5 (the googletest row), §7; AGENTS.md (two targets; one representation; tests check behaviour).
- The range rules: `foreign/idr/include/idr/IR/Ranges.h:20-62` (`idr::ranges`: `smallMin`, `smallMax`, `Bounds`, `bounded`, `natural`, `boundsOf`, `add`, `sub`, `mul`, `ofInteger`, `rangeOf`, `nonNegative`) and `foreign/idr/lib/IR/Ranges.cpp:19-97`.
- The big ops' range hooks: `foreign/idr/lib/IR/OpsBigs.cpp:21-31` (`ofType`, `setBounds`), `:36-46` (ConstantOp), `:48-67` (add, sub, mul), `:71-79` (BigPredOp), `:81-85` (NatToBigOp), `:88-96` (NatFromBigOp), `:98-116` (BigCmpOp), `:118-126` (BigFromIntOp, BigSmallOp), `:129-147` (BigToIntOp). The solver that calls them, read only: `foreign/idr/include/idr/Analysis/Ranges.h:21-56`, `foreign/idr/lib/Analysis/Ranges.cpp:25-49`.
- The narrowing transfer, inline in the pass: `foreign/idr/lib/Transforms/Narrow/Ops.cpp:26-29` (`noWrap`), `:67-99` (`wordOf`), `:117-121` (`allFit`); `Narrow/Facts.cpp:51-65` (`Facts::of` reads `ranges::boundsOf`); `Narrow/Versions.cpp:100-121` (the mask); `Narrow/Widths.cpp:69-71` and `include/idr/Transforms/Narrow.h:108-109` (`fits32`).
- The tables the pass and the folders read, generated from the ODS: `foreign/idr/include/idr/IR/IdrBigOps.td:15-24` (`Idr_WordOp`), `foreign/idr/tools/idris-mlir-tblgen.cpp:2117-2156` (`emitBigToWord`); the generated `build/typecheck/foreign/idr/include/idr/IR/IdrBigToWord.inc` (`BigToWord<OpT>`, `GET_BIG_TO_WORD_LIST`), `IdrRuntimeAbi.inc` (`idr::runtime::Abi<OpT>::function`, `::signedFunction`, `::unsignedFunction`), `IdrOps.h.inc` (each op's `create` builders).
- What the folders call: `foreign/idr/include/idr/IR/Fold.h:38-57` (`fold::runtime`, `fold::runtimeOfWord`), `:132-138` and `foreign/idr/lib/IR/Fold/Values.cpp:17-42` (`fold::wrapped`, `fold::compared`); `foreign/idr/include/idr/IR/Layout.h:180` (`layout::signedPredicate`).
- The tagged small paths: `runtime/Big/Big.h:20-37`, `runtime/Big/Arithmetic.cpp:41-47` (why one overflow test suffices), `:78-116` (`a + (b-1)`, `a - (b-1)`, pred, nat_from_big, `(a>>1)*(b-1)+1`), `:138-144` (`2-a`); `runtime/Big/Bitwise.cpp:16-64` (`places`, `up`, `down`), `:93-131` (`a & b`, `a | b`, `(a^b)|1`, shl `(a-1)·2^k+1`, shr `(a>>k)|1`); `runtime/Big/Compare.cpp:21-34`.
- The meanings: `runtime/idris_rt.h:151-155` (an odd word is a 63-bit integer shifted left by one; one representation per integer), `:495-531` (each big operation), `:540-548` (`idris_rt_gmp_init`); `foreign/idr/tools/idris-mlir-opt.cpp:106` (a native caller calls it first).
- googletest: `.toolchain/llvm-project/third-party/unittest/` (googletest 1.14 with LLVM's printers, `googletest/README.LLVM`; its `CMakeLists.txt:58-104` shows what LLVM compiles and defines).
- The specs your files meet (X3 owns them): `tests/spec/mlir-layout/run:59-101` (no plain `add_library`; the list of CMakeLists; no mutable static, `thread_local` or `std::atomic`), `tests/spec/no-local-headers/run:27-33` (no header beside a .cpp under foreign/idr), `tests/spec/zones/run:24-29`, `tests/spec/file-size/run:13-14` (a unit is at most 400 lines), `tests/registry/registry-only/run:16-38` (no string literal shaped like a qualified Idris name, `"Capital.rest"`, in foreign/idr).

Permitted outcome:
- Mandatory: four googletest programs, one per rule family, each exhausting its rules over the domains fixed below and comparing against each rule's stated meaning: `idr-box-ranges` (the range rules), `idr-box-hooks` (the big ops' range hooks), `idr-box-words` (the word each big op narrows to, the versioning mask, `fits32`), `idr-box-tagged` (the runtime's tagged small paths and the small range itself). Each test also checks that `idris_rt_live_cells()` ends where it started. The CMake and Makefile text in Handoff.
- Optional: in `idr-box-words`, the lowering of `idr.big.small` (`foreign/idr/lib/Conversion/Bigs.cpp:29-41`: `(v << 1, nsw) | 1`) against the runtime's small word; in `idr-box-hooks`, the ConstantOp, BigFromIntOp, BigSmallOp and add/sub/mul hooks.
- Later (not this lane): the tagged identities exhausted at 8-bit words (needs the small paths written generic over the word's width in `runtime/Big`, R3's write set, outside F10's correction; see Escalate if); a box for upstream's `arith-int-range-narrowing`; the boxes in `tests/toolchain/static-linking` (R3's).

Fixed decisions:
1. Units, programs and suites (exact): `Main.cpp` (shared); `Ranges.cpp` → `idr-box-ranges`; `Hooks.cpp` (pred, nat_from_big, nat.to_big) and `HooksCompare.cpp` (big.cmp, big.to_int) → `idr-box-hooks`; `Words.cpp` → `idr-box-words`; `Tagged.cpp` (add, sub, mul, neg, pred, nat_from_big, cmp, the small range) and `TaggedBits.cpp` (and, or, xor, shl, shr) → `idr-box-tagged`. Each program is its units plus `Main.cpp`. Test suite names are the unit names (`TEST(Ranges, ...)`, `TEST(HooksCompare, ...)`), so no two units of a program define the same test. No header: each unit keeps its own glue (domains, read-back helpers) in an anonymous namespace; that duplicated glue is permitted (binding rule 3). Each unit at most 400 lines.
2. `Main.cpp` is exactly: the license header, `#include "idris_rt.h"`, `#include "gmock/gmock.h"`, and `int main(int argc, char **argv) { idris_rt_gmp_init(); testing::InitGoogleMock(&argc, argv); return RUN_ALL_TESTS(); }`.
3. A rule is reached, never restated. Where the rule is a function, the test calls it; where it is inline in a pass, the test states it as a check of the functions the pass calls, with the meaning from outside the rule:
   - `idr::ranges::*` (Ranges.cpp) and `idr::narrow::fits32` (Widths.cpp:69): called.
   - A hook (OpsBigs.cpp): `inferResultRanges` called on an op built in a scratch block; its result read through `ranges::boundsOf` (what `Facts::of` calls, Facts.cpp:61) or as the `ConstantIntRanges` it is; the meaning is the runtime's value through `idr::runtime::Abi<OpT>::function`.
   - The word op of a big op (Ops.cpp:67-99): `BigToWord<OpT>::Op` from `IdrBigToWord.inc`, built with arith and folded by MLIR (`Operation::fold`); compared with `idr::runtime::Abi<OpT>::function` on the small words; a comparison's predicate through `layout::signedPredicate` and its verdict through `fold::compared`; a conversion's result through `fold::wrapped`.
   - The no-wrap flags (Ops.cpp:26-29): stated as "the exact result, in `__int128`, equals the folded 64-bit result", read signed always and unsigned when operands and result are not negative.
   - The mask (Versions.cpp:111-121): `Abi<BigCmpOp>::function` against the small word of `ranges::smallMax`, `Abi<BigToIntOp>::function`, and `arith.andi` with `ranges::smallMax` folded.
   - The tagged identities: `idr::runtime::Abi<OpT>::function` for each big op (the C entry, whose small path is the identity).
4. Oracles: exact integer arithmetic in `__int128` (clang has it on both targets); the documented meaning of each operation (idris_rt.h:495-531: the bitwise operations and the shifts are those of infinite two's complement, a right shift the floor of value / 2^n, a left shift value * 2^n; division and modulus have no small identity and are not boxed); two's-complement bitwise operators and `>>` on `int64_t` (arithmetic since C++20) for the values of small operands; and a big read back through the runtime:
   - `is(idris_rt_big r, __int128 e)`: when `e` is inside `[idr::ranges::smallMin, idr::ranges::smallMax]`, `r` is odd and `r == idris_rt_big_from_int_s((int64_t)e)`; when `e` is outside it but inside `int64_t`, `r` is even and `idris_rt_big_cmp(r, x) == 0` for `x = idris_rt_big_from_int_s((int64_t)e)` (released after); when `e` is outside `int64_t`, `r` is even, `(uint64_t)idris_rt_big_to_int(r) == (uint64_t)e` and the sign of `idris_rt_big_cmp(r, idris_rt_big_from_int_s(0))` is the sign of `e`.
   - `within(idris_rt_big r, ranges::Bounds b)`: `!b.lo || idris_rt_big_cmp(r, from_int_s(*b.lo)) >= 0`, and `!b.hi || idris_rt_big_cmp(r, from_int_s(*b.hi)) <= 0`.
   - An operand `x` of `int64_t` becomes a big by `idris_rt_big_from_int_s(x)`: small inside the small range, a cell outside it; every big a test makes or receives is released (`idris_rt_big_release`) once.
5. Domains, each with its reason in a comment beside it:
   - `D64` (range rules, hooks): `smallMin, smallMin+1, smallMin+2, -2, -1, 0, 1, 2, smallMax-2, smallMax-1, smallMax`. The rules act only where a bound leaves the small range (`bounded`) or a product leaves `int64_t` (`checkedMul`) or a sign changes (the corners of a product): each end of the small range with two neighbours inside, and 0 with two either side.
   - `OUT` (members a missing bound stands for): below, `smallMin-1` and `INT64_MIN`; above, `smallMax+1` and `INT64_MAX`.
   - Intervals over `D64`: every `Bounds{lo, hi}` with `lo`, `hi` in `D64 ∪ {none}` and `lo <= hi` when both are present. The members of an interval: the points of `D64` inside it, plus `OUT`'s lower points when `lo` is none and `OUT`'s upper points when `hi` is none.
   - `Dw` for `big.to_int` at width w in {8, 16, 32, 64}: `D64` plus `±2^(w-1)+d` and `2^w+d` for d in [-2, 2] (inside `int64_t`): where a value stops fitting w bits signed or unsigned, the two branches of OpsBigs.cpp:133-145.
   - `W32` for `fits32`: `INT32_MIN+d`, `d`, `INT32_MAX+d` for d in [-2, 2], with `INT64_MIN`, `INT64_MAX`.
   - Small widths for `ofInteger`, `boundsOf`: every `ConstantIntRanges(umin, umax, smin, smax)` with `umin <= umax`, `smin <= smax` and at least one member at widths 1 to 4; every `fromSigned` and `fromUnsigned` range at widths 5 to 8; at width 64, `fromSigned` over `D64 ∪ {INT64_MIN, INT64_MAX}` and `fromUnsigned` over `{0, 1, 2, smallMax-1, smallMax, smallMax+1, INT64_MAX, INT64_MAX+1, UINT64_MAX-1, UINT64_MAX}`. A member of a `ConstantIntRanges` is a value `v` of its width with `umin <= v <= umax` unsigned and `smin <= v <= smax` signed (its class comment, `.toolchain/llvm-project/mlir/include/mlir/Interfaces/InferIntRangeInterface.h:21-29`); at width 64 the members are the listed points inside it.
   - `B` (tagged identities, words): `{0}` and every `s·2^k + d` with s in {1, -1}, k in [0, 62], d in [-2, 2] that lies in the small range, sorted, without duplicates. The identities change behaviour only where an exact result crosses ±2^62 (Arithmetic.cpp:41-47) or, for products and shifts, where the operands' bit lengths add to 62 or 63: every power of two up to the ends of the small range with two words either side puts pairs on both sides of each boundary for every split of the bits between two operands.
   - Shift amounts: left (shl with n ≥ 0, shr with n ≤ 0) every n with |n| in [0, 64]: 63 is the small path's last place (Bitwise.cpp:118), and x·2^64 still fits `__int128` for a small x; right (shr with n ≥ 0, shl with n ≤ 0) every |n| in [0, 130] and every 2^k and 2^k+1 for k in [8, 61] with `smallMax`: from 63 places only the sign is left, and 130 is past twice a word.
6. Each `TEST` is one rule: it counts its failing inputs, reports the first with every operand through `ADD_FAILURE()`, and ends with `EXPECT_EQ(failures, 0u)`. No failure message holds a string literal shaped like a qualified Idris name.
7. No mutable static variable, `thread_local` or `std::atomic` in any unit (tests/spec/mlir-layout); the MLIR context, the scratch block and the ops a test builds are locals of the test.

Inputs:
- §4.5. The generated tables as at HEAD (`IdrBigToWord.inc`: `BigToWord<OpT>::Op`, `BigToWord<OpT>::constant`, `GET_BIG_TO_WORD_LIST`; `IdrRuntimeAbi.inc`: `idr::runtime::Abi<OpT>::function`, `signedFunction`, `unsignedFunction`), the `idr::ranges` declarations (Ranges.h), the hooks' `inferResultRanges` (the ops' `InferIntRangeInterface`), `idr::narrow::fits32` (Narrow.h:109), `fold::compared`, `fold::wrapped`, `fold::runtimeOfWord`, `layout::signedPredicate`, the C ABI of idris_rt.h. Each is consumed by its declaration; none of their bodies is copied.

Outputs:
- The seven units under `foreign/idr/unittests/`; the programs `idr-box-ranges`, `idr-box-hooks`, `idr-box-words`, `idr-box-tagged`, which `make test-unit` runs (consumers: the owner's build; the coordinator's hub files).
- Hub text for the coordinator and spec requests for X3 (Handoff).
- Every input on which a rule disagrees with its meaning found while writing, reported with file:line (consumer: the coordinator, routing to F, K3 or R3).

Implement:
1. `Main.cpp` as Fixed decision 2.
2. `Ranges.cpp` (all functions of `idr::ranges` but `nonNegative`):
   - `bounded`: for lo, hi each in `D64 ∪ OUT ∪ {none}`: `bounded(lo, hi).lo == lo` when `lo` is inside the small range, else none; the same for hi.
   - `rangeOf` and `boundsOf` at width 64: for every interval `b` over `D64` (bounds inside the small range), `boundsOf(rangeOf(b))` is `b`; every member of `b` read as `int64_t` lies in `rangeOf(b)`'s signed bounds.
   - `boundsOf`: at every width but 64 in the small-width domain, both bounds none; at width 64, every signed member is within the result, and the result's `lo` is `smin` when `smin` is inside the small range (none otherwise), `hi` likewise.
   - `add`, `sub`, `mul`: for every pair of intervals `(a, b)` over `D64`, every member pair `(x, y)`: the exact `x op y` in `__int128` lies within the result (a missing bound holds anything); each present bound of the result is inside the small range. Exactness: for add, when `a.lo` and `b.lo` are present the result's `lo` is the least member sum if that is inside the small range, else none (the same for `hi` with `a.hi`, `b.hi`; for sub with `a.lo`, `b.hi` and `a.hi`, `b.lo`); for mul, when `a.fits()`, `b.fits()` and every member product fits `int64_t`, the result is `bounded(least product, greatest product)`.
   - `ofInteger(range, isSigned)` over the small widths and width 64: every member, read signed when `isSigned` and unsigned otherwise, is within the result; each present bound is inside the small range; for a `fromSigned` range read signed and a `fromUnsigned` range read unsigned, each bound is the least or greatest member when that is inside the small range, else none.
3. `Hooks.cpp` and `HooksCompare.cpp`: in each test, an `mlir::MLIRContext` with `idr::IdrDialect` and `mlir::arith::ArithDialect` loaded, an `mlir::OpBuilder` at the end of a local `mlir::Block` whose arguments are the operands, the op built with its `create` builder (`IdrOps.h.inc`), and `op.inferResultRanges(ranges, set)` called with the operands' ranges and a setter that keeps the result's range. A big operand's range is `ranges::rangeOf(interval)`, as the analysis holds it.
   - BigPredOp (`!idr.nat` → `!idr.nat`): for every interval over `D64`, every member x with x ≥ 1 (the op's operand is not zero): `within(Abi<BigPredOp>::function(big(x)), boundsOf(result))`.
   - NatFromBigOp (`!idr.big` → `!idr.nat`): every member x: `within(Abi<NatFromBigOp>::function(big(x)), boundsOf(result))`.
   - NatToBigOp (`!idr.nat` → `!idr.big`): every member x ≥ 0: `within(big(x), boundsOf(result))`.
   - BigToIntOp (`!idr.big` and `!idr.nat` → `iw`, w in {8, 16, 32, 64}): every interval over `Dw`, every member x (x ≥ 0 for a natural): `v = cast<IntegerAttr>(fold::wrapped(iw, Abi<BigToIntOp>::function(big(x)))).getValue()` is a member of the result's `ConstantIntRanges`.
   - BigCmpOp (`!idr.big`, and `!idr.nat` with members ≥ 0): every predicate of `CmpPredicate`, every pair of intervals over `D64`: when the result is a constant `c` (`getConstantValue()`), every member pair (x, y) has `fold::compared(ctx, p, Abi<BigCmpOp>::function(big(x), big(y)))` equal to `c`; an undecided result (`maxRange(1)`) asserts nothing.
4. `Words.cpp`:
   - `checkWord<OpT>()` for every `OpT` of `GET_BIG_TO_WORD_LIST`, called through one fold expression over the list (so an op the ODS marks later is checked or fails to compile). With `Word = BigToWord<OpT>::Op`, built once on `i64` block arguments and folded per input with `IntegerAttr` operands:
     - `Word` void (nat.to_big): the table says the word is the operand, which is the op's ODS meaning (IdrBigOps.td:163-165, the same big under another type) and has no runtime function: the branch folds nothing and calls nothing; it exists so that the fold expression over the list is total.
     - Binary (add, sub, mul): for every (x, y) in `B²` whose exact result `e` is inside the small range: the folded word equals `e` (no signed wrap), `is(Abi<OpT>::function(big(x), big(y)), e)`, and when x, y, e ≥ 0 the folded word read unsigned equals `e` (no unsigned wrap).
     - With `constant` (pred: subi 1; nat_from_big: maxsi 0): for every x in `B` (x ≥ 1 for pred): the folded `Word(x, constant)` equals the runtime's value (`is(...)`); for nat_from_big, also for every x ≥ 0 the runtime's result is `big(x)` (Ops.cpp:88's shortcut).
     - `CmpIOp`: for every predicate p and (x, y) in `B²`: the folded `CmpIOp(layout::signedPredicate(p), x, y)` equals `fold::compared(ctx, p, Abi<BigCmpOp>::function(big(x), big(y)))`.
     - `TruncIOp`: for w in {8, 16, 32} and x in `B`: folded `trunci` of x to `iw` equals `fold::wrapped(iw, Abi<BigToIntOp>::function(big(x)))`; for w = 64 the word is x and the runtime's value is x.
   - The mask: for every x ≥ 0 in `B`, `Abi<BigCmpOp>::function(big(x), big(ranges::smallMax)) <= 0` and the folded `arith.andi(x, ranges::smallMax)` equals `Abi<BigToIntOp>::function(big(x))`; for the naturals `smallMax+1`, `INT64_MAX` and `2^64` (made by `idris_rt_big_from_int_u` and, for `2^64`, by `Abi<BigShlOp>::function(big(1), big(64))`), the comparison is `> 0`.
   - `fits32`: for every `fromSigned(lo, hi)` at width 64 with lo ≤ hi in `W32`: `narrow::fits32(r)` exactly when `INT32_MIN <= lo` and `hi <= INT32_MAX`; at widths 8, 16 and 32, every `fromSigned` range over each width's extremes and 0 fits.
5. `Tagged.cpp` and `TaggedBits.cpp`, over `B` and the shift amounts, every result through `is` (Fixed decision 4):
   - The small range is the runtime's: `idris_rt_big_from_int_s(ranges::smallMax)` and `(ranges::smallMin)` are odd, `(ranges::smallMax + 1)` and `(ranges::smallMin - 1)` are even (released after).
   - add, sub, mul over `B²`: `is(Abi<OpT>::function(big(x), big(y)), x op y)` in `__int128`.
   - neg over `B`: `-x`; pred over x ≥ 1 in `B`: `x - 1`; nat_from_big over `B`: `max(x, 0)`.
   - cmp over `B²`: the sign of the result is the sign of `x - y`.
   - and, or, xor over `B²`: the result is `big(x & y)`, `big(x | y)`, `big(x ^ y)`, words equal (bitwise results of small values are small).
   - shl, shr over `B` and the amounts: left by n gives `x·2^n` in `__int128`; right by n gives `x >> n` for n ≤ 62 and `x < 0 ? -1 : 0` beyond.
   Each test records `idris_rt_live_cells()` first and expects it again at its end.
6. Syntax-check every unit on this machine (the typecheck build does not list them until the coordinator adds the CMake): take `foreign/idr/lib/IR/Fold/Bigs.cpp`'s entry in `build/typecheck/compile_commands.json`, drop `-o <file>`, `-c` and its source, append `-isystem .toolchain/llvm-project/third-party/unittest/googletest/include -isystem .toolchain/llvm-project/third-party/unittest/googlemock/include -DGTEST_HAS_RTTI=0 -fsyntax-only <your unit>` (absolute paths), run it in the entry's directory; every unit exits 0. Fix what it reports in your own units only.
7. Failure path: a rule that disagrees with its meaning on some input is a finding, not a test to weaken: keep the test as the meaning states it, mark it in the unit's `NEEDS-ACCEPTANCE` line, and report the input, the rule and file:line in Handoff.
8. Each unit's third line is `// NEEDS-ACCEPTANCE: <what to confirm>` after the license header (for example: "that every pair of B through the runtime's add is its exact sum, a small word exactly inside the small range").

Delete: nothing. F10 is a gap: no box exists, and no existing test is restated here.

NOT TO DO:
- No copy of a rule: no `lo + lo` beside `ranges::add`, no tagged arithmetic on `int8_t` or any word written in a test, no restatement of `wordOf`'s or `noWrap`'s choices; the oracles are Fixed decision 4's.
- No edit outside your units: not `runtime/Big/**` (R3), `foreign/idr/lib/IR/**` (F), `foreign/idr/lib/Transforms/Narrow/**` (K3), `idris-mlir-tblgen.cpp` (K2), any CMakeLists.txt, the Makefile or `tests/spec/**` (X3).
- No sampling, no prop.h, no libFuzzer, no lit or FileCheck test: every box is exhaustive over its domain.
- No test of the solver (`Ranges::solve`), of a pass run, of `Facts::of`'s natural clamp (a type's fact, needing a solve), or of `ranges::nonNegative` (one call of upstream's `fromUnsigned`).
- No helper header, shared library or framework of our own over googletest.

Stop and return: the seven units written; each syntax-checks by Implement step 6; the Handoff carries the CMake and Makefile text and the spec requests. Return with the missing operand named if a generated table's names differ from those above, or if googletest's headers do not compile under the profile with the flags above.

Acceptance:
- On the owner's build, both targets: `make build` builds `idr-box-ranges`, `idr-box-hooks`, `idr-box-words`, `idr-box-tagged`; `make test-unit` runs the four, every test passes, the command exits 0.
- Discriminators (a scratch change on the owner's machine, never committed), each failing exactly the named test: `runtime/Big/Bitwise.cpp:109` `(a ^ b) | 1` → `a ^ b` fails TaggedBits' xor; `runtime/Big/Arithmetic.cpp:81` `b - 1` → `b` fails Tagged's add; `foreign/idr/lib/IR/Ranges.cpp:55` `minus(a.lo, b.hi)` → `minus(a.lo, b.lo)` fails Ranges' sub; `foreign/idr/lib/IR/OpsBigs.cpp:74` without `- 1` fails Hooks' pred; `IdrBigOps.td:66` BigSubOp's word op `SubIOp` → `AddIOp` fails Words' sub.
- Typecheck evidence here: Implement step 6 exit 0 for each unit; after the coordinator applies the CMake, `python3 tools/check-units.py foreign/idr/unittests/*.cpp` exit 0 and `make typecheck` passes its cxx part. Only the owner's build shows that googletest links under the profile on both targets and that every box passes.

Tempting partial solution: a handful of hand-picked values per rule, or every input near 0 only; or each rule re-derived in the test (`EXPECT_EQ(add(a, b).lo, *a.lo + *b.lo)`), or the tagged identities written on `int8_t` in the test. Acceptance rejects them: near 0 nothing crosses ±2^62, where every identity's overflow test and every `bounded` drop acts, so the discriminators above pass unnoticed; a re-derived rule agrees with the rule it copies when both are wrong, and an `int8_t` copy never runs the runtime's code at all.

Escalate if:
- `IdrBigToWord.inc` or `IdrRuntimeAbi.inc` no longer declares `BigToWord<OpT>::Op`, `BigToWord<OpT>::constant`, `GET_BIG_TO_WORD_LIST` or `idr::runtime::Abi<OpT>::function` as above (K2 owns the generator).
- A rule disagrees with its stated meaning on an input of the box (a bug): report it as Implement step 7 says; do not fix it.
- The coordinator requires the tagged identities at 8-bit words as §4.5 says: that needs `runtime/Big`'s small paths written over a word of any width, a change in R3's write set that no lane's obligation covers; return with that seam named.
- googletest 1.14 from the pinned tree does not compile as C++26 against libc++ with `-w` and `GTEST_HAS_RTTI=0`.

Handoff: the shape of parts/common.md, plus these hub requests, as exact text:
1. New file `foreign/idr/unittests/CMakeLists.txt` (the coordinator writes it; it adjusts the source lists if B split a unit differently):
   ```cmake
   # SPDX-License-Identifier: 0BSD
   # Copyright (c) 2026 Bjorn Pagen
   # The exhaustive boxes: one googletest program per family of the
   # arithmetic a rewrite rests on, each over every input of a reduced domain:
   # the range rules (ranges), the big ops' range hooks (hooks), the word each
   # big op narrows to (words) and the runtime's tagged small paths (tagged).
   # googletest and googlemock are the pinned llvm-project's
   # (third-party/unittest), which LLVM's install does not export: compiled
   # here from upstream's sources, outside our warnings. make test-unit runs
   # the programs.
   set(IDR_GTEST "${PROJECT_SOURCE_DIR}/.toolchain/llvm-project/third-party/unittest")
   set(IDR_BOXES ranges hooks words tagged)
   set(IDR_BOX_SOURCES_ranges Ranges.cpp)
   set(IDR_BOX_SOURCES_hooks Hooks.cpp HooksCompare.cpp)
   set(IDR_BOX_SOURCES_words Words.cpp)
   set(IDR_BOX_SOURCES_tagged Tagged.cpp TaggedBits.cpp)
   # What the boxes call: the rules (the dialect's range rules, hooks and
   # folders, the narrowing's widths), arith's folders, and the runtime,
   # natively, as idris-mlir-opt links it.
   set(IDR_BOX_LINKS IdrNarrow IdrIR idris_rt MLIRArithDialect MLIRIR MLIRSupport LLVMSupport)

   # The typecheck build compiles the units against googletest's headers and
   # links nothing.
   if(IDRIS_MLIR_TYPECHECK)
   	set(IDR_BOX_UNITS Main.cpp)
   	foreach(box IN LISTS IDR_BOXES)
   		list(APPEND IDR_BOX_UNITS ${IDR_BOX_SOURCES_${box}})
   	endforeach()
   	add_mlir_library(IdrUnitTests
   		${IDR_BOX_UNITS}

   		EXCLUDE_FROM_LIBMLIR
   		DISABLE_INSTALL

   		DEPENDS
   		IdrOpsIncGen
   		IdrRuntimeAbiIncGen

   		LINK_LIBS PUBLIC
   		${IDR_BOX_LINKS}
   	)
   	target_include_directories(IdrUnitTests SYSTEM PRIVATE
   		"${IDR_GTEST}/googletest/include" "${IDR_GTEST}/googlemock/include")
   	target_compile_definitions(IdrUnitTests PRIVATE GTEST_HAS_RTTI=0)
   	return()
   endif()

   add_mlir_library(IdrGTest
   	"${IDR_GTEST}/googletest/src/gtest-all.cc"
   	"${IDR_GTEST}/googlemock/src/gmock-all.cc"

   	EXCLUDE_FROM_LIBMLIR
   	DISABLE_INSTALL
   	PARTIAL_SOURCES_INTENDED

   	LINK_LIBS PUBLIC
   	LLVMSupport
   )
   target_include_directories(IdrGTest SYSTEM PUBLIC
   	"${IDR_GTEST}/googletest/include" "${IDR_GTEST}/googlemock/include")
   target_include_directories(IdrGTest PRIVATE "${IDR_GTEST}/googletest" "${IDR_GTEST}/googlemock")
   target_compile_definitions(IdrGTest PUBLIC GTEST_HAS_RTTI=0)
   target_compile_options(IdrGTest PRIVATE -w)
   set_target_properties(IdrGTest PROPERTIES CXX_CLANG_TIDY "")

   foreach(box IN LISTS IDR_BOXES)
   	add_executable(idr-box-${box} Main.cpp ${IDR_BOX_SOURCES_${box}})
   	target_link_libraries(idr-box-${box} PRIVATE IdrGTest ${IDR_BOX_LINKS})
   	add_dependencies(idr-box-${box} IdrOpsIncGen IdrRuntimeAbiIncGen)
   endforeach()
   ```
2. `foreign/idr/CMakeLists.txt`, right after `add_subdirectory(lib)`:
   ```cmake
   # The exhaustive boxes over the arithmetic the passes and the runtime's
   # small paths rest on (unittests, make test-unit).
   add_subdirectory(unittests)
   ```
3. `Makefile`: `test-unit` added to `.PHONY`; in the opening comment, after the `make test-mlir-tools` entry:
   ```make
   #   make test-unit         foreign/idr/unittests, the exhaustive boxes (googletest);
   #                          after C++ changes, once make build has built them
   ```
   and the target, after `test-mlir-tools`:
   ```make
   # The exhaustive boxes (foreign/idr/unittests): each googletest program the
   # build made there, under the timeout every test command has. The largest
   # box makes some 10^7 runtime calls of nanoseconds each, so one still
   # running after 600 s has hung.
   test-unit:
   	@$(PINS) built llvm sysroot
   	@boxes=$$(find '$(ROOT)/build/$(PRESET)/foreign/idr/unittests' -maxdepth 1 -type f -name 'idr-box-*' -perm -u+x 2> /dev/null | LC_ALL=C sort); \
   	if [ -z "$$boxes" ]; then echo 'test-unit: no box is built (make build builds them)' >&2; exit 1; fi; \
   	failed=; for box in $$boxes; do \
   	  echo "==> $${box##*/}"; \
   	  $(or $(TIMEOUT),$(error $(TIMEOUT_MISSING))) -k 10 600 "$$box" || failed="$$failed $${box##*/}"; \
   	done; \
   	if [ -n "$$failed" ]; then echo "test-unit: failed:$$failed" >&2; exit 1; fi
   ```
4. To X3, through the coordinator: `tests/spec/mlir-layout/run`'s layout list (its `for dir in ...` line) gains `unittests`; `tests/spec/zones/run`'s foreign/idr areas gain `-e '^foreign/idr/unittests/[^/]*\.cpp$'`; `tests/spec/commands/run`'s target list gains `test-unit`.
5. To the owner: AGENTS.md's Checks line gains "After C++ changes, also run `make test-unit`".
