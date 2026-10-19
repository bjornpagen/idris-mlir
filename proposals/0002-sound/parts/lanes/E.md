<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## E — every idr-expect property is shown to fail where it should, or is gone
Findings: F21
Owner / exclusive writes: `foreign/idr/lib/Transforms/Expect/**`, `foreign/idr/include/idr/Transforms/Expect.h`, `tests/idr/expect/**`. No excludes. `foreign/idr/lib/Transforms/CMakeLists.txt` is the coordinator's; `foreign/idr/include/idr/Transforms/Passes.td` (the `IdrExpect` pass def) is K2's; every fixture outside `tests/idr/expect/` is X1's or X2's.
Read first:
- Packet README §2 (brittle tests, no oracle), §3 F21, §4.1 (K1 calls idr-expect's definitions; K1's dispatch calls `quantitiesKept`, `crashSites`, `foldsBalanced`, `functionsOf` and `names`), §7.
- `foreign/idr/include/idr/Transforms/Expect.h:113-372`: the one list of properties; each comment is that property's specification, including when it fails.
- `foreign/idr/lib/Transforms/Expect/Lookup.cpp:11-95`: the name table. It has **82** names (the README says 81).
- `foreign/idr/lib/Transforms/Expect/Report.cpp:11-22`: `fail(loc, property)` prints `expected <property>: `, and `where(op)` gives `@name`.
- `foreign/idr/lib/Transforms/Expect/Named.cpp:24-91`: `programOf`, `functionsOf`, `names` and `named` (the `@f` rule: the symbol is `f`, or the function's own location holds a NameLoc `f`, through FusedLocs); `rootsOf` (no argument means the whole module).
- The 13 fixtures in `tests/idr/expect/`, each `<name>.mlir` plus `<name>/run` and `<name>/expected`. `closures.mlir` and `one-clone.mlir` show the trick of pulling a second module out of `// CLEAN:` comment lines with `sed`. `counting.mlir` shows a pass run before idr-expect.
- `harness/lib/lit.sh:46-110`: how a RUN line runs. `%status N`, `%s` and `%t` are available, `\` continues a line, `count` and `FileCheck` are on PATH, and `expected` holds one `RUN <n>: ok` per joined RUN line. `harness/templates/dialect/example.mlir` gives a program's minimal shape: one `idr.program` with a root of type `() -> i64` or `(!idr.world) -> (...)`.
- `.toolchain/llvm-project/mlir/test/IR/locations.mlir`: the syntax of `loc("f")` and `loc(fused["f", "g"])`.
Permitted outcome:
- Mandatory: each of the 68 properties below gets a fixture in `tests/idr/expect/` that fails it on a hand-written module and holds it on another function, or on a second module pulled out with sed.
- Mandatory: `folds-balanced` stays as the one documented exemption.
- Mandatory: the stale `structured-loops.mlir` is fixed.
- Mandatory: a coverage test enforces the invariant from now on.
- Optional: a property that you show cannot fail on any module the verifier accepts, and that has no user outside `tests/idr/expect/`, is deleted.
- Later: an exported crash-site predicate for K1, which K1's dispatch defers too.
Fixed decisions:
- **Fixture placement.** The failing fixture of a property lives in `tests/idr/expect/`, whatever X1 keeps or culls elsewhere. There is one new fixture per Expect source file, named after that file in kebab case (table below), each a `<name>.mlir` plus `<name>/run` and `<name>/expected`.
- **Siblings of an existing fixture.** `labels` joins `closures.mlir` (both are in `Closures.cpp`). `specialized-once` joins `one-clone.mlir` (both are in `Clones.cpp`).
- **Fixture shape.** Line 1 is `// NEEDS-ACCEPTANCE: <what to confirm>`. Then come:
  - one holding RUN: `idris-mlir-opt %s --idr-expect=holds=<every holding request> -o /dev/null`;
  - one failing RUN: `%status 1 idris-mlir-opt %s --idr-expect=holds=<every failing request> -o /dev/null 2> %t.err`;
  - `// RUN: FileCheck %s < %t.err`;
  - `// RUN: grep -c 'error: expected ' %t.err | count <N>`, where N is the number of CHECK-DAG lines.
  
  Each failing place gets one `// CHECK-DAG: error: expected <name>: <message>`. Build `<message>` from the property's `fail(...)` call in its `.cpp`: write its fixed words literally, write every piece printed from the module (op names, types, counts, other symbols) as `{{.*}}`, and write the failing function `@f` literally. The fixed words are what tell a real failure from an argument error (`no function @f, and no copy of it`); the CHECK-DAG lines plus the count are what keep the check independent of order.
- **Module-wide properties.** A property that takes no function (`contified`, `facts-as-marked`, `linker-names`, `entry`, `in-llvm`) holds on a second module, pulled out of `// CLEAN:` lines (or another prefix) with `sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir`, as in `closures.mlir`.
- **Owned stage.** Write the owned module by hand where you can. Where the owned verifier makes that the hard part, run `--idr-rc` on a first-stage module in the RUN line, as `counting.mlir` does. The function must then fail by construction of its source (for example, a value used twice gets a dup, so its take is not exclusive).
- **Stage.** Each fixture is one module at one stage. Closure properties (`applies`, `forces`, `labels`) need `stage(higher)`. Lowered-stage properties use a module of `func.func` or `llvm.func` with no `idr.program`; `programOf` then answers the module itself.
- **Facts must be consistent.** Every hand-written `idr.func` that declares `effects` declares at least what its body does, because lane F's program verifier refuses anything less (§4.3). Concretely: no `total` means `diverge`; a world parameter or an `idr.world.new` means `io`; a guard or a crash op means `crash`; a call adds the callee's declared effects; and in the higher stage an `idr.apply` or `idr.force` means all three. A module that declares no `effects` is never checked.
- **One new property, `folded=@f`, and no new export.** Lane N's fuzz check needs it (packet §4.7): `folded=@f` holds when no op left in any copy of `@f` that has no memory effect, is not a call and is not a constant has only constants as operands (an op such a fold would have replaced). It lives in a new `lib/Transforms/Expect/Folded.cpp`, is added to `Lookup.cpp`'s table and declared in `Expect.h` beside the others, and gets a fixture in `tests/expect-folded/expect-folded.mlir` where it holds (all arithmetic over constants folded by `--canonicalize`) and where it fails (an `arith.addi` of two constants left in place: `expected folded: ...`). No other new property. K1's contracts call `quantitiesKept`, `crashSites`, `foldsBalanced`, `functionsOf` and `names` as declared at HEAD: their names, signatures and behaviour stay, and none of the five is ever deleted.
- **`folds-balanced` is exempt.** It reads `IdrDialect::foldLeakCount()` (`IdrBase.td:47-48`, counted in `lib/IR/Fold/Scope.cpp:31`). Only a defective folder makes that count nonzero, so no module can make the property fail. §4.1's K1 calls the same count. It stays, with no failing fixture, and the coverage test names it as the one exemption, with the reason.
- **Deleting a property.** You may delete one only if both hold: it has no use in any file outside `tests/idr/expect/` (search the whole `tests/` tree, RUN lines joined across `\`, and `mlir.expect` files), and you can state why no verified module can make it fail. A property that cannot fail but is still used elsewhere is kept and escalated with the list of its users.
Inputs: nothing from a sibling at dispatch. The fixtures must satisfy lane F's verifier rules as §4.3 states them (effects coverage). X1's `--verify-roundtrip` in the harness means every hand-written module must round-trip.
Outputs:
- `Expect.h` unchanged except for a property deleted under step 5. K1 consumes it as at HEAD.
- Fixtures under `tests/idr/expect/`.
- `tests/expect-coverage/`.
Implement:
1. **Fix `structured-loops.mlir`.** `structure::structurable` (`lib/Transforms/StructureLoops/Forms.cpp:127-129`) is now `isa<TabulateOp, TabulateIOOp, FoldLastOp, ScanLastOp, TransposeOp>`, and the failure message is `<op> is left unlowered in @f` (`StructuredLoops.cpp:32`). The fixture's `@left` holds an `scf.for`, which today gives `no structured op in @left`, and its LEFT check expects text the source no longer prints.
   - Make `@left` hold an `idr.tabulate` (syntax from `tests/structure-tabulate/structure-tabulate.mlir:12-19`) beside a `linalg.generic`, so it fails once.
   - Rewrite the LEFT check to `error: expected structured-loops: idr.tabulate is left unlowered in @left`.
   - Rewrite the header comment to the current rule.
   - Add the first-line NEEDS-ACCEPTANCE mark.
   - No other existing fixture's checks disagree with the source; leave them as they are.
2. **Extend `closures.mlir` and `one-clone.mlir`.** Add `labels` (holding and failing; syntax in `tests/defunc-choice/defunc-choice.mlir`) to `closures.mlir`, and `specialized-once` (copies carry `loc("f")`; see `tests/optimize-specialize-ends/optimize-specialize-ends.mlir`) to `one-clone.mlir`. Each gets the fixture shape above and a first-line mark. Update both `expected` files to the new RUN count.
3. **Write the new fixtures.** For each row: the file; its properties; when each fails, from `Expect.h`; and an existing fixture to copy op syntax from. You may only read the syntax fixtures; copy module text from them, never their checks.

   | Fixture | Properties: how each fails | Syntax from |
   |---|---|---|
   | `apart` | apart=@f:@g: some function is made from both, e.g. `loc(fused["f","g"])` | dedup/keep-apart.mlir |
   | `by-name` | by-name / not-by-name=@f: a memo label of @f without / with `by_name`, or no label names @f | effects/forced-labels.mlir |
   | `calls` | call-order (wrong order or a call missing); calls-distinct (an identical call dominates); calls-read (a result unread); calls-only (a call outside the list); direct-calls (a call through a value) | lower/entry.mlir, effects/call-effects.mlir, lower/world.mlir, defunc/force-call.mlir |
   | `computes-nothing` | computes-nothing=@f: an op other than a guard, a no-return op, ub.unreachable or a terminator | effects/div.mlir |
   | `constant-stack` | constant-stack=@f: @f reaches a cycle not made of musttail calls (before tail calls, any cycle); tail-calls=@f:@g: a call of @g that is not musttail, or none | tail-calls/positions.mlir |
   | `continuations` | contified: a function called once, from one it calls back, used nowhere else | contify/contify.mlir |
   | `counted-loop` | counted-loop=@f: a loop that is not `scf.for`, or no loop | loops/tail-loop.mlir |
   | `crash-sites` | crash-sites=@f:<n>: another count | guards/byte-message.mlir |
   | `dims-known` | dims-known=@f: a dim of an array @f made | fold/array-dim.mlir |
   | `does` | matches, matches-nothing, forces, forces-nothing, builds, builds-nothing, reads-fields, reads-no-fields, applies, never-returns, calls, never-calls, calls-closed. Each fails on its complement (e.g. matches on a function with no match; calls-closed=@f:@g on a call of @g with a non-constant operand). Use one `stage(higher)` module. | canon/match-results.mlir, canon/force-of-own-constant.mlir, canon/eta-known.mlir, fold/pending.mlir, canon/upstream-passes.mlir, lower/crash.mlir, canon/held-not-read.mlir |
   | `facts` | facts-as-marked: an op marked `expect.facts = "drop"` that cannot be dropped (an `idr.io.put_str`) | effects/io.mlir, effects/force-strict.mlir |
   | `growth` | grows-nothing=@f:<file>: a copy of @f with more ops than @f in <file> (a smaller module written with sed) | canon/held-not-read.mlir |
   | `linker-names` | linker-names: a symbol with another character, e.g. `@"a-b"` | lower/mangle.mlir |
   | `lowered` | lowered=@g: an idr type in a `func.func` signature; in-llvm: a non-LLVM op (holds on a clean `llvm.func` module) | lower/to-llvm.mlir |
   | `memory` | aligned-access: an `llvm.load` without `alignment`; reads-nothing / writes-nothing=@f: a load / store through a pointer parameter | lower/llvm-facts.mlir, lower/data-layout.mlir |
   | `moves-out` | moves-out=@f: no `idr.array.update` or `idr.element.update` | canon/array-moves.mlir |
   | `narrowed-lanes` | narrowed-lanes=@f: no loop computes lanes in 32 bits or fewer (the target-free failing case) | vectorize/lanes-x86-64.mlir |
   | `output` | output-fused=@f: a string built only for `idr.io.put_str` | canon/output-fusion.mlir |
   | `paths` | loops=@f:<n>: another count or no loop; straight-line=@f: an op that chooses among regions | lower/may-loop.mlir, lower/select.mlir |
   | `placement` | builds-where-used, calls-where-used, matches-once, crashes-before-output, parameters-used, results-used, regions-distinct, checks-every-path: each as `Expect.h:263-285` states | canon/held-not-read.mlir, raise/sunk-call.mlir, canon/match-enclosing.mlir, canon/facts.mlir, canon/upstream-passes.mlir, canon/match-results.mlir, canon/match-merge.mlir, canon/head.mlir |
   | `proved` | total=@f on a function without `total`; not-total on one with it | effects/inlined-proof.mlir |
   | `reaches` | reaches=@f:@g: no chain of symbol uses from @f reaches @g | defunc/force-call.mlir |
   | `resets-unshared` | resets-unshared=@f: a take of a box its function gives a second reference | rc/consumed.mlir |
   | `returns` | returns=@f:<v> (another value, or `_` where it folded); returns-argument=@f:<n>; returns-on-paths=@f:<v>+<v> (a constant not listed, or a listed one on no path) | fold/sccp.mlir, lower/linear.mlir, canon/match-enclosing.mlir |
   | `reuses-every-cell` | reuses-every-cell=@f: a cell a take yields that is freed, not reused | rc/nested-reuse.mlir |
   | `signature` | signature=@f:<type>: another type; convention=@f:<cc>: another cc, or not an `llvm.func`; entry: a second public function, or `@main` of another type | lower/world.mlir, tail-calls/positions.mlir, lower/entry.mlir |
   | `solved-effects` | effects=@f:<e>: declared effects other than written (declared consistently with the body; see the fixed decision above) | effects/long-cycle.mlir |
   | `stage` | stage=<s>: the program is at another stage | pipeline/stages.mlir |
   | `tests-nothing` | tests-nothing=@f: a take of a non-exclusive value, or none; exclusive-copy=@f: no copy takes every reference parameter at `excl` | rc/exclusive.mlir, rc/second-redirect.mlir |
   | `vectorized` | vectorized=@f: a scalar `linalg.generic` over words with a parallel dimension | vectorize/rows-x86-64.mlir |
   | `words` | word-loop=@f: every loop of @f defines or binds a big or a nat | narrow/descending.mlir |

   Each fixture's `run` is the 5-line form of the existing ones (`lit ../<name>.mlir`), and its `expected` has one `RUN <n>: ok` per joined RUN line. The header comment says what the fixture shows, in two to four lines; mention a stage or a sed module only where it matters.
4. **Add the coverage test.** Create `tests/expect-coverage/run` (POSIX sh: `. "$IDRIS_MLIR_ROOT/harness/testutils.sh"`, then `cd "$root"`, using `$work` and `say` as `tests/no-behaviour-options/run` does), plus `expected`. It:
   - reads the names with `sed -n 's/^ *\.Case("\([^"]*\)".*/\1/p' foreign/idr/lib/Transforms/Expect/Lookup.cpp`;
   - says `properties: found` (or `properties: none found`), which is its non-vacuity witness;
   - for each name except those in `exempt='folds-balanced'` (a comment gives the reason above), requires `grep -qF "expected <name>: " tests/idr/expect/*.mlir`;
   - says either `every property has a fixture where it fails, folds-balanced aside`, or `no fixture where it fails:` followed by the names;
   - says `exempt and unknown:` followed by the name, for an exemption Lookup.cpp no longer has.
   
   `expected` holds the two holding lines, and its first line is `NEEDS-ACCEPTANCE: that every property's failing fixture is found, folds-balanced aside`.
5. **Handle what cannot fail.** If you cannot make a property fail in a verified module:
   - with no outside users, delete its `.Case`, its `Expect.h` declaration and comment, and its definition; if a `.cpp` becomes empty, delete it and put the CMake removal in your handoff;
   - otherwise keep it and escalate.
   
   Record each case in the handoff.
6. **Check.** If step 5 changed C++, run `python3 tools/check-units.py` on every Expect unit you touched (Lookup.cpp at least). Run `IDRIS_MLIR_ROOT=$PWD sh tests/expect-coverage/run` and diff it against `expected`. Because the mark is that file's first line, compare from line 2.
Delete: The LEFT check and the `scf.for` case of `structured-loops.mlir`'s `@left` (replaced in step 1). Any property deleted under step 5, together with its declaration and its case. Nothing else: every other property has users and keeps its definition.
NOT TO DO:
- Do not edit, cull or restate any fixture outside `tests/idr/expect/`, even one whose idr-expect check you find wrong; report it instead.
- Do not reword a property's message to make a fixture easier to write.
- Do not add a property, an option, an export or a helper to idr-expect.
- Do not make a failing fixture depend on a transform pass's output where a hand-written module can fail (only the owned-stage exception allows `--idr-rc`).
- Do not touch `harness/lib/lit.sh` (X1's), `Passes.td` (K2's) or `tests/ACCEPTANCE.md` (X3's).
- Do not make `folds-balanced` fail through a test-only folder or a hook in the dialect.
Stop and return: Return when the following hold:
- the 68 properties each have a failing case and a holding case under `tests/idr/expect/`;
- `structured-loops.mlir` is fixed;
- the coverage test's run matches its expected lines.

If a property cannot fail and has outside users, return its name, the reason, and the users.
Acceptance:
- `folded`: `idris-mlir-opt tests/expect-folded/expect-folded.mlir --idr-expect=holds=folded=@<the holding function>` exits 0, and the failing invocation reports `expected folded:` once; the property is in `Lookup.cpp`'s table, so a misspelling is an error.
- **On the owner's build:**
  - every `RUN n` of every `tests/idr/expect/*` fixture prints `ok`;
  - each failing RUN exits 1 with exactly the CHECK-DAG errors, one per failing place;
  - each holding RUN exits 0.
- **Discriminator:** replace any one of the 68 properties' bodies with `return success();` and its fixture's `%status 1` line fails (`RUN n: failed`). Today, for the 69 names that have no failing case under `tests/idr/expect/`, no test notices that replacement.
- **The coverage test:** today it would print the 69 names (68 once `folds-balanced` is exempted); after the lane it prints the holding line.
- **On this machine:** check-units on the changed Expect units, and the coverage run diffed against its expected lines.
- **Only the owner's build can show** that each hand-written module verifies under lane F's rules and that each message pattern matches.
Tempting partial solution: Write failing RUN lines that pass because of an argument error (`no function @f`), or one RUN per property that only checks `%status 1`. The fixed-words-in-the-message rule and the count line reject both: an argument error prints other words, and a property that reports two errors where its specification says one fails the count. Writing fixtures only for the easy properties and calling the rest exempt fails the coverage test, which allows exactly one exemption.
Escalate if:
- A property cannot fail on any verified module but is used outside `tests/idr/expect/`.
- A property's `Expect.h` comment contradicts what its `.cpp` checks, so that a fixture written to one fails the other.
- A fixture can only be written by violating lane F's §4.3 rules.
- A property you would delete is one of K1's five (`quantitiesKept`, `crashSites`, `foldsBalanced`, `functionsOf`, `names`), or K1 asks for an export this wave.
Handoff:
- **Shape (per parts/common.md):** changed paths, each mapped to an obligation; contracts supplied; consumer adaptations made; hub text the coordinator must apply; checks actually run with their results, or NotRun; unresolved seams, each with its evidence.
- **This lane in particular:**
  - the property-to-fixture map as built;
  - the properties deleted under step 5 (with their reasons) or escalated (with their users);
  - the new `NEEDS-ACCEPTANCE` files, for X3 to list in `tests/ACCEPTANCE.md`;
  - for K1: that its five definitions stand as at HEAD;
  - hub text only if a `.cpp` was deleted: the line to drop from `foreign/idr/lib/Transforms/CMakeLists.txt`'s `IdrExpect` list.
