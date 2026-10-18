<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane: accept-reject

**Scope.** `tests/accept` (55 fixtures), `tests/reject` (47 fixtures and the
`without-fixture` table), `tests/compiler` (15 tests), `tests/registry` (6
live tests, plus the two deleted in 45d1b32c), `tests/two-levels` (1 test).
That makes 125 live tests. Another 7 directories under these trees hold only
an untracked `output` file, left behind by deleted tests: `reject/layout-256-counted-fields`,
`reject/layout-512-counted-fields`, `reject/layout-768-counted-fields`,
`reject/primitive-shl`, `reject/program-base`, `registry/base-surface`,
`registry/string-iterator`.

**What I read.** Both guidelines in full: `.claude/skills/testing-by-search`
(cited as TBS §n) and `.claude/skills/representation-first` (cited as RF,
with its parts named: SPOV1-3, "parse at the boundary", "one fact, one
place", "every string that names a thing", "delete what the representation
makes dead", Brooks's limit, and "Map onto MLIR's grain", or MLIR-grain).
Also AGENTS.md, `tests/README.md`, `tests/testutils.sh`, `tests/ACCEPTANCE.md`,
`tests/lib/profile.sh`, `tests/lib/rules.sh`, `tests/lib/properties.sh`,
`tests/lib/mlir.sh` (dump options), `tests/lib/compile.sh`,
`tests/lib/two-levels.sh`, `tests/spec/rules-covered/run`, the `tests/Main.idr`
pools, and `tools/compile.sh`. I read every fixture's sources, `run`,
`expected`, `expected-stdout`, `stdin`, `packages` and marks, and every last
`output`, and I compared each `output` with its `expected` (without the
`NEEDS-ACCEPTANCE` line). On the compiler side: `Frontend/Program.idr` (when
the registry is validated against the profile checks), `Frontend/Resolve.idr`
and `Registry/Libraries.idr` (how trust is decided), `Frontend/Driver.idr`
(how the frontend reports), the registry's Forbidden and Deprecated tables,
and `SyntaxSamples.idr`. Logs: `test.log` from the scratchpad (its verdicts
match the `output` files). Git history: 45d1b32c, 6911742a, 08a065e4,
c7aa7b62.

**Counts (125 live tests).**

| | keep | rewrite | rewrite-as-property | merge | delete |
| --- | --- | --- | --- | --- | --- |
| accept (55) | 20 | 13 | 1 | 6 | 15 |
| reject (48: 47 fixtures and without-fixture) | 37 | 7 | 0 | 0 | 4 |
| compiler (15) | 7 | 3 | 3 | 1 | 1 |
| registry (6) | 4 | 1 | 1 | 0 | 0 |
| two-levels (1) | 0 | 0 | 1 | 0 | 0 |
| **total** | **68** | **24** | **6** | **7** | **20** |

Delete the 7 leftover output-only directories as well (finding AR-18).

Status from the last run: 124 tests have an `expected` file (without-fixture
has none). 90 pass and 34 fail. The 34 failures break down as follows:
- **15 are test bugs that never ran.** 13 fixtures are compiled with
  `--no-prelude` (always on) but never import what they use: 11 lack
  `import Prelude`, `compiler/content-hash` compiles a frontend module that
  relies on the implicit prelude, and the second case of
  `registry/broken-entry` imports only `Prelude.IO`. The other two:
  `compiler/dialect-syntax` (its samples break a root rule) and
  `reject/cycle-ioref-knot` (its header line disagrees with its sibling).
- **5 are stale expectations**, describing behaviour the code no longer
  has: frontend-command-line, main-visible, module-location, registry-only
  and handoff-readable.
- **8 are compiler bugs** (section 4): streams, partial-stream,
  string-primitive-runtime-match, runtime-lazy-value-growing-choice,
  nat-operations, artifacts, handoff-round-trip and two-levels.
- **6 time out or die on the IR tree dump's file names**, cause uncertain
  (AR-10): bounded-field, bounded-method-own, bounded-synonym,
  polymorphic-recursion-swapped, pointer-handles and scalar-bytes.

---

## 2. Verdict table

Status shows the last `output` against `expected`. "FTL" means the IR tree
dump failed with "File name too long".

### tests/accept

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| accept/action-after-effect | an action built before a write runs after it, and the division is not moved before the write | rewrite | Stdin is empty, so d = 255 and the division never crashes; moving it before the write would be invisible, so the test cannot fail on its claim. Make the division crash on empty stdin and expect "ready" before the crash (TBS §9.2 step 5; TBS §1.1) | pass |
| accept/action-run-at-once | an action runs once built; no closure survives | delete | Prints 2. The closure claim is not checked. No rule boundary; any IO program covers it (TBS §1.1, checks nothing beyond the generic) | pass |
| accept/bounded-capped | the growth check admits growth below a cap of 3 | keep | Positive side of the polymorphism rule; a distinct extraction case (TBS §1.2, an alphabet for a generator) | pass |
| accept/bounded-dictionary-root | a node is split by the dictionary's root, not the written head | keep | Distinct extraction case | pass |
| accept/bounded-family-applied | a lambda family is beta-reduced at the instance | rewrite | Lacks `import Prelude`, so it never elaborated under `--no-prelude` ("Undefined name Nat") (AR-1) | fail: no Prelude import |
| accept/bounded-family-head | a family whose value is a type constructor | rewrite | Same as above (AR-1) | fail: no Prelude import |
| accept/bounded-family-higher | a family argument applied to a closed type | rewrite | Same as above (AR-1) | fail: no Prelude import |
| accept/bounded-family-partial | a partially applied definition as a family | rewrite | Same as above (AR-1) | fail: no Prelude import |
| accept/bounded-family-scope | getBinderUnder's shape stays one instance | rewrite | Same as above (AR-1) | fail: no Prelude import |
| accept/bounded-field | Show (T nm) through a List (String, T nm) field | keep | Distinct extraction case; the failure is the compiler's or the dump's (AR-10) | fail: compile timed out at 60 s, FTL |
| accept/bounded-grow-once | a type written once is no arc | keep | Distinct extraction case | pass |
| accept/bounded-grow-shrink | +1/-1 cycle admitted | keep | Distinct extraction case | pass |
| accept/bounded-method | method requests at the implementation's function | keep | Distinct extraction case | pass |
| accept/bounded-method-own | a method with its own constraint | keep | Distinct extraction case | fail: compile timed out at 60 s, FTL |
| accept/bounded-synonym | List1/Pair reached through a synonym | keep | Distinct extraction case | fail: compile timed out at 60 s |
| accept/default-pragma | %default changes only totality | merge-into:reject/pragma-default-with-inline | That fixture's "only error" at the `%inline` line already shows `%default` is not refused (TBS §1.1, redundant) | pass |
| accept/division | a partial function that divides is accepted | delete | The partial-division boundary is gone; programs/basic covers division and its crash (stale-legacy) | pass |
| accept/equality-proofs | Builtin's proof combinators are admitted ("From v3 ...") | merge-into:registry/identity-hook | identity-hook already runs `replace`/`rewrite`; add `sym`. The comment cites a version (AGENTS: comments do not cite) | pass |
| accept/erased-elem-later-match | a later match on an erased `Here` reads the unified field | rewrite | Lacks `import Prelude` (AR-1) | fail: no Prelude import |
| accept/erased-elem-match | a match of `Here` reads the unified runtime field | rewrite | Lacks `import Prelude` (AR-1) | fail: no Prelude import |
| accept/erased-field | a quantity-0 field may have any type | keep | Positive side of the dependent-field rule | pass |
| accept/erased-index-forced-index | a forced index computed by the unifier still matches | rewrite | Lacks `import Prelude` (AR-1) | fail: no Prelude import |
| accept/fib | (no claim) fib 10 | delete | A generic program with no boundary; programs/eval/compile-time-evaluation runs fib (TBS §1.1, redundant) | pass |
| accept/fused-stored-string | "no string is built at runtime" (output fusion through idr.field of idr.con) | merge-into:tests/programs/io/output-fusion | The claim is the e2e `heap-free` mark, which profile_accept cannot state; only stdout is checked (TBS §6.2, perception; AR-12) | pass |
| accept/growing-specialization-function | closures that grow per level are heap values, accepted | keep | Megamorphic boundary: growing values, not types (AGENTS) | pass |
| accept/higher-order-dictionary | a dictionary built by applying a function is one implementation | rewrite | Lacks `import Prelude` (AR-1) | fail: no Prelude import |
| accept/indexed-tags | an indexed type at runtime is only its tag | keep | Positive side of reject/type-dependent. The representation claim is unchecked; state it in mlir.expect if kept (TBS §6.2) | pass |
| accept/linear-ambiguous-let | the fork's linear-candidate disambiguation | keep | A regression for a fork fix, with an exact contract (stdout) | pass |
| accept/map-pair | (no claim) | delete | A generic program, no boundary (TBS §1.1) | pass |
| accept/named-implementations | named implementations chosen statically | keep | The positive pair of reject/runtime-closure-implementation | pass |
| accept/nonterminating | a covering, non-terminating program compiles | keep | Totality boundary; the contract is "compiles" | pass |
| accept/pair-maybe | (no claim) | delete | A generic program, no boundary (TBS §1.1) | pass |
| accept/partial-application | (no claim) | delete | A generic program, no boundary (TBS §1.1) | pass |
| accept/partial-integer | "a closed call of a partial function is evaluated at compile time" | delete | AGENTS: "A closed call runs at run time ... it is not built". programs/eval/compile-time-evaluation runs euclid at run time (stale-legacy) | pass |
| accept/partial-stream | takeBefore on a stream, evaluated at compile time | merge-into:accept/streams | The premise is gone (compile-time evaluation). The run is still a stream program, and it reveals a bug | fail: run timed out (code bug, §4) |
| accept/polymorphic-recursion-swapped | finite polymorphic recursion compiles to two monomorphic functions | keep | Positive boundary of polymorphism, which AGENTS requires to compile | fail: compile timed out at 60 s |
| accept/recursive-string | "no string is built at runtime" (a specialized clone writes at each tail) | rewrite-as-property | Its claim is `heap-free`; move to programs/ with the mark. Only stdout is checked now (TBS §6.2) | pass |
| accept/runtime-closure-growing-choice | closures chosen by a runtime recursion live on the heap and are freed | keep | Megamorphic boundary; frees are checked through the e2e live-cells stderr | pass |
| accept/runtime-data-first-of-two | runtime list and Integer are on the heap and freed | delete | The boundary (runtime data was once refused) is gone; programs/ checks live cells everywhere (stale-legacy) | pass |
| accept/runtime-data-list | a runtime-length list on the heap | delete | Strict subset of runtime-data-first-of-two, and stale like it (TBS §1.1, redundant) | pass |
| accept/runtime-data-prelude-list | the same with the Prelude's List | delete | Stale boundary, covered by programs/prelude | pass |
| accept/runtime-integer | an Integer from a runtime value exists at runtime | delete | The boundary (runtime Integer refused) is gone; Integer semantics belong to Sem/fuzz | pass |
| accept/runtime-integer-prelude | the same through the Prelude's cast | delete | Same as above | pass |
| accept/runtime-lazy-value-growing-choice | Lazy suspensions chosen at runtime live on the heap and are freed | keep | Its contract (freed) catches a real leak | fail: 48 live cells (code bug, §4) |
| accept/runtime-partial-integer | "compile-time evaluation stops ... once it has spent its budget" | merge-into:accept/nonterminating | Its comment describes the fuel AGENTS and RF forbid. What it checks ("compiles") is nonterminating's (TBS §1.1, redundant) | pass |
| accept/runtime-partial-stream | the same with a stream | merge-into:accept/nonterminating | Same as above | pass |
| accept/runtime-string-compared | a string built at runtime and compared | delete | It was the negative control for recursive-string's runtime claim, which nothing checks; string compares are covered in programs/prelude | pass |
| accept/show-dependent-pair | Show of a dependent pair: a function field applied past its arity | rewrite | Imports only Data.Vect, no Prelude (AR-1) | fail: no Prelude import |
| accept/static-integers | "Integers that are constants ... allowed; one at runtime is rejected: reject/runtime-integer-partial" | delete | The premise is removed and the cited fixture does not exist; big-Integer arithmetic belongs to Sem/fuzz (stale-legacy) | pass |
| accept/static-list | "Nothing of them exists at runtime" | delete | Stale (no static evaluation) and unchecked (TBS §6.2) | pass |
| accept/streams | take 10 of countFrom 1 (+1) sums to 55; "evaluated at compile time" | rewrite | Move to programs/ and drop the stale comment and its dead reference reject/runtime-data-partial-stream. The expectation is right and the compiler is wrong | fail: printed 34, not 55 (code bug, §4) |
| accept/string-primitive-runtime-match | a runtime string matched against a literal | keep | A real contract, and it reveals a lowering bug | fail: `'llvm.call' op operand type mismatch` (code bug, §4) |
| accept/totality-past-depth | recursion under six constructors is total, with no pragma | keep | Pairs with reject/idris-totality-depth-pragma; an exact contract | pass |
| accept/unreachable | "An unreachable definition outside the profile is neither checked nor compiled" | rewrite | Its unreached `big : Integer` is no longer outside the profile, so nothing is tested. Use an unreached refused construct, as programs/basic/loads-untrusted-unreached does (stale-legacy, TBS §1.1) | pass |
| accept/with-application-scope | a with block re-entered from a local definition and a record update | keep | Fork-fix regression with an exact contract | pass |

### tests/reject

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| reject/cycle-array-knot | an array holding its own node is refused (cycle) at main's line 15 | keep | One rule at its site (AGENTS: refusal names the site) | pass |
| reject/cycle-ioref-knot | an IORef knot is refused at the Nothing, line 18 | rewrite | The compiler reports main's declaration (line 16), as it does for cycle-array-knot (line 15). Decide one site rule and set the header to it (RF "one fact, one place") | fail: line 16 reported, header says 18 |
| reject/dependent-field-type-field | a `Type` field is refused | keep | Rule smoke | pass |
| reject/deprecated-buffer-data | bufferData is refused: "use bufferData'" | delete | The same Deprecated `deprecatedDef` entry kind as deprecated-get-byte; only table data differs. Replace with a property over the table (AR-14) | pass |
| reject/deprecated-get-byte | getByte is refused: "use getBits8" | keep | The one smoke fixture of the deprecated rule | pass |
| reject/deprecated-set-byte | setByte is refused: "use setBits8" | delete | Redundant like deprecated-buffer-data (AR-14) | pass |
| reject/dictionary-field-opaque-type | an opaque type with its own Ord makes two dictionaries | keep | A distinct cause of the rule | pass |
| reject/dictionary-field-two-implementations | one map type built with two Ords | keep | A distinct cause of the rule | pass |
| reject/escape-hatch-assert-linear | assert_linear is refused | keep | A distinct escape-hatch entry | pass |
| reject/escape-hatch-assert-total-in-second-case-block | the hatch in the second of two case blocks | keep | Site-naming variant (case blocks whose names print alike) | pass |
| reject/escape-hatch-assert-total-in-user-data-module | a user `Data.Evil` module is not trusted | keep | Trust follows the package. The header's line is Data/Evil.idr's, which the harness cannot check (AR-4) | pass |
| reject/escape-hatch-believe-me | believe_me is refused | keep | Rule smoke | pass |
| reject/escape-hatch-believe-me-in-proof | believe_me in an erased definition is still refused | keep | Guards "do not erase facts before the passes that use them" (AGENTS) | pass |
| reject/escape-hatch-crash | prim__crash in user code is refused | keep | A distinct entry | pass |
| reject/escape-hatch-hole-at-runtime | an unsolved hole in a lambda | keep | A distinct entry | pass |
| reject/escape-hatch-hole-in-proof | a hole in an erased argument | keep | Erased position | pass |
| reject/escape-hatch-phrase-in-comment | the verdict comes from the module, not from the phrase in a source comment | delete | It guarded a removed harness that counted phrases in output; the report-based harness reads only `diagnostic:` lines. Otherwise identical to escape-hatch-believe-me (stale-legacy, TBS §1.1) | pass |
| reject/finalizer-collect-any | onCollectAny is refused, naming it | keep | Rule smoke | pass |
| reject/idris-interface-body | a data declaration in an interface body is Idris's error at its line | rewrite | The header names `idris`, which is the one user-error rule `elaboration` under a second name (AR-5) | pass |
| reject/idris-totality-depth-pragma | %totality_depth is refused by the fork's parser | rewrite | Same header rename (AR-5) | pass |
| reject/polymorphism-growing-rank | an array gaining an axis per call | keep | A distinct extraction (array rank) | pass |
| reject/polymorphism-growing-shape | Ints (S n) per call | keep | Smoke for the shape cause | pass |
| reject/polymorphism-growth-dictionary | a dictionary quoted deeper per call | keep | Dictionary cause | pass |
| reject/polymorphism-growth-family-recursion | a family stuck in a type-level recursion | keep | Opaque family cause | pass |
| reject/polymorphism-growth-family-sum | a sum of two heights, refused "though its instances are finite: ... a known limit" | rewrite | It pins an incompleteness: an improved check that compiles this correctly would fail it. The contract is "refused naming the site, or compiled and correct" (TBS §1.1; AR-6) | pass |
| reject/polymorphism-growth-mutual | a +2/-1 mutual cycle | keep | Mutual-cycle cause | pass |
| reject/polymorphism-growth-recursion | "wrap is called once ... its one instance is finite; the program is refused all the same" | rewrite | Same as growth-family-sum: AGENTS wants a finite set compiled (AR-6) | pass |
| reject/polymorphism-nested | depth at (a, a) | keep | The classic nested case | pass |
| reject/polymorphism-nested-data | a nested data type T (a, a) refused at its declaration | rewrite | Lacks `import Prelude` (AR-1). Its "line: as the header says" passed by coincidence on Idris's error at 11:25 (AR-4) | fail: no Prelude import |
| reject/pragma-default-with-inline | %inline refused, %default not | keep | It subsumes pragma-inline and default-pragma | pass |
| reject/pragma-inline | %inline refused at line 5 | delete | Redundant with pragma-default-with-inline: the same refusal of the same pragma (TBS §1.1) | pass |
| reject/pragma-transform | %transform refused | keep | A distinct pragma | pass |
| reject/pragma-unreachable | a pragma on an unreached definition is still refused | keep | The source-check-versus-reach boundary | pass |
| reject/pragma-user-module-named-data | a pragma in a user `Data.Evil` | keep | Trust by package; the file goes unchecked (AR-4) | pass |
| reject/primitive-double-match | a Double literal match | keep | Rule smoke | pass |
| reject/process-system | System.system | keep | Rule smoke, one entry of dozens (AR-14) | pass |
| reject/program-contrib | an import from an untrusted package | keep | Rule smoke | pass |
| reject/raw-pointer-malloc | malloc | keep | Rule smoke | pass |
| reject/runtime-closure-implementation | an implementation chosen by a runtime value | keep | Pairs with accept/named-implementations | pass |
| reject/runtime-closure-index-function | an implementation as a function of a runtime index | keep | Pairs with accept/show-dependent-pair | pass |
| reject/runtime-closure-scope-constructor-field | an implementation closing over a runtime value in a constructor | keep | A distinct cause | pass |
| reject/runtime-closure-shape-constructor-field | an implementation of a shaped argument in a constructor | keep | A distinct cause | pass |
| reject/signal-handler | collectSignal | keep | Rule smoke (AR-14) | pass |
| reject/threads-concurrency | makeMutex | keep | Rule smoke (AR-14) | pass |
| reject/type-dependent | a type computed from a runtime Int | keep | Rule smoke | pass |
| reject/uniqueness-shared-rebuild | an in-place rebuild of a shared linear list | keep | Rule smoke | pass |
| reject/world-unsafe-perform | unsafePerformIO in user code | keep | The AGENTS rule ("User code may not") | pass |
| reject/without-fixture | the rules no fixture states, and why | rewrite | The `hook` line cites the deleted tests/registry/base-surface; `elaboration` is "owed" while two fixtures state it as `idris`; reasons cite source line numbers (`Translate/Closed.idr:1118`) that drift (RF "one fact, one place"; AR-5, AR-17) | n/a (read by spec/rules-covered) |

### tests/compiler

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| compiler/artifacts | artifacts appear after success and are removed when the same module later fails | keep | An exact contract, and it reveals a driver bug | fail: `stale artifacts after the failure: build/exec/Main.0306ec5431f877b2.o` (code bug, §4) |
| compiler/content-hash | the frontend's XXH3-128 against the published test vectors | rewrite | A good oracle (a published specification, TBS §7), but Ids.idr relies on the implicit prelude and tools/compile.sh always passes `--no-prelude`. Give the copied module an `import Prelude`, or import it in Ids.idr (AR-1) | fail: "Undefined name Nat" in Ids.idr |
| compiler/dialect-syntax | every generated type, attribute and op sample is written, parsed and reprinted the same | keep | An exhaustive generated corpus (TBS §8, exhaust the box). The failure is in the sample program | fail: samples' root `@sample` violates the root type rule (test-data bug, §4) |
| compiler/elaboration-error | Idris's error stops the build: exit 3, no pipeline, no artifact | merge-into:tests/reject | This is profile_reject's contract (report, exit 3, no artifacts, line). Make it `reject/elaboration-undefined-name` with `-- expect: elaboration, line 6` (TBS §1.1, redundant) | pass |
| compiler/fork-loops-terminate | the fork's size-change decision on four constructed components | keep | An exact contract on a specific bug. Extend to an enumerated property (§5) | pass |
| compiler/frontend-beside | idris-mlir runs only the idris-mlir-front beside it | keep | Driver contract | pass |
| compiler/frontend-command-line | the frontend's usage, status codes and outputs | rewrite | The "undefined" case expects the frontend to print Idris's error, but Driver.idr says "idris-mlir reads and reports them, and the frontend prints none". Check the refusal the module holds instead (stale-legacy) | fail: `undefined: exit 3, does not say Undefined name` |
| compiler/frontend-named-file | a file not named Main.idr is still the main module | keep | Driver contract | pass |
| compiler/growth-check | the growth check against brute force on every graph of up to 3 positions, and hand cases | keep | Exemplary: exhaustive small scope (TBS §8) with a second-implementation oracle (TBS §7) | pass |
| compiler/handoff-readable | emitted symbols, stage, no func dialect, instances, no old forms, locations | rewrite-as-property | A regex over printed MLIR (RF MLIR-grain "declare, don't write"). The "old forms" check cannot fail, since unregistered ops do not parse. Make the rest an idr-expect property in `universal` and the `instance` property required in ODS (AR-8) | fail: "some idr.func or data type carries none" (instance) |
| compiler/handoff-round-trip | three hand-picked programs' modules print, parse and reprint identically | rewrite-as-property | A property applied to 3 examples; it belongs in `universal`, over every compilation (TBS §1.1 on DefaultConfigsArePrime; AR-9) | fail: linarray-combinators does not compile (`'linalg.generic' op consumes a view`, code bug, §4) |
| compiler/main-visible | a private main elsewhere is not seen; an exported one is ambiguous | rewrite | It greps the exact wording `unsupported (program): main is ambiguous`, and the message gained `main: ` (TBS §1.1, brittle). Split into an accept fixture (Helper.idr private main) and a reject fixture (`-- expect: program, line 1`, `-- message: ambiguous`) | fail: wording changed |
| compiler/module-location | the builtin.module's own location is main's line | delete | It pins the printed layout (`tail -n 1` of the module). The behaviour it served (whole-program refusals at main) is what reject/cycle-* check by line (TBS §1.1; AR-11) | fail: `} loc(unknown)` |
| compiler/no-environment | the compiler reads none of Idris's environment variables | keep | Driver contract; it can fail | pass |
| compiler/probe-names | probe names round-trip | rewrite-as-property | 19 hand-picked probes. `sameProbe` compares names, not probes. expected-stdout pins each probe's spelling, which the contract leaves open (TBS §1.1, §4.1; RF "every string that names a thing"; AR-13) | pass |

### tests/registry

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| registry/broken-entry | a shadowed prelude module with an entry's definition reshaped is refused at the entry | rewrite-as-property | The premise holds for case 1 (Builtin.replace reaches the hook) but case 2's Main cannot elaborate. It text-edits upstream source with awk, and the "unbroken" case checks nothing. Replace with a unit property over every registry entry (AR-3) | fail: case 1 output predates 45d1b32c's fix; case 2 `Undefined name IO`, `Undefined name fromString` |
| registry/identity-hook | `replace` and `rewrite__impl` are the value they move | keep | Positive hook test with an exact stdout | pass |
| registry/nat-operations | Nat operations compute on the big representation | keep | An exact contract; it reveals a leak. Add the unary-copy property (§5) | fail: `idris-rt: live cells 1` (code bug, §4) |
| registry/pointer-handles | pointers are runtime handles | keep | Exact contract | fail: compile timed out at 60 s, FTL (AR-10) |
| registry/registry-only | no Idris name is spelled outside the registry | rewrite | A grep lint with false positives (unittests' `"Prog.main"`, SyntaxSamples' test data) and real hits (Walk's probe names, `Basic "->"`). The rule wants a typed home for compiler-made names, not a regex (RF "every string that names a thing"; AR-15) | fail: 10 lines outside the registry |
| registry/scalar-bytes | the iterator's step over every Unicode scalar value | keep | Exhaustive over the whole domain (TBS §8) | fail: compile exit 1, FTL (AR-10) |

### tests/two-levels

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| two-levels/terms | every primitive and 46 total Prelude terms against recorded values | rewrite-as-property | Its upper level (the stock evaluator) was removed in 08a065e4, so it is now the compiler's own output frozen as golden (TBS §7, wrong-or-missing-oracle). The integer part duplicates Sem's oracle; move String/Char/Double/Integer vectors into a Sem-style specification and state the Prelude corpus as laws (AR-16) | fail: primitives compile timed out at 60 s; prelude `internal error: 'llvm.call' op operand type mismatch` |

### Leftover directories (no tracked files)

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| reject/layout-256-counted-fields, layout-512-counted-fields, layout-768-counted-fields, primitive-shl, program-base | (deleted tests) | delete | Only an untracked `output` survives; it confuses listings and audits (AR-18) | no test |
| registry/base-surface, registry/string-iterator | (deleted in 45d1b32c) | delete | Same as above | no test |

---

## 3. Findings

### AR-1: 13 fixtures never imported what they use, under an always-on `--no-prelude`
- **Category:** infrastructure-gap. **Severity:** high.
- **Paths:**
  - accept/bounded-family-{applied,head,higher,partial,scope}
  - accept/erased-elem-match, erased-elem-later-match, erased-index-forced-index
  - accept/higher-order-dictionary, accept/show-dependent-pair
  - reject/polymorphism-nested-data
  - compiler/content-hash (it compiles `compiler/src/IdrisMLIR/Ids.idr`)
  - registry/broken-entry, case 2 (`import Prelude.IO` only)
- **Evidence:** `tools/compile.sh:42`:
  `"$idris_mlir" --no-prelude --num-threads="$ncpu" "$@" ...`. Every failing
  output opens with `Undefined name Nat`, `Undefined name IO`, or
  `Undefined name Builtin.Pair`. Ids.idr is built by stock Idris with the
  implicit prelude. The fixtures were written in the wave (c7aa7b62,
  d06ed15c, 2c042728) and were never compiled.
- **Guidelines:** TBS §9.2 step 5: check that the system entered the state
  the test claims, "Otherwise the test can silently check nothing". Here a
  `reject/` fixture's line check even passed on Idris's own error at the
  right line. RF "parse at the boundary": whether a fixture elaborates is a
  fact known before the build and checked only after it.
- **Recommendation:** Add the imports (a one-line fix each). Then close the
  gap: run `idris-mlir-front --check` on every fixture as the first step of
  `profile_accept`/`profile_reject`. In `profile_reject`, refuse a fixture
  whose report holds an `elaboration` error unless its header names
  `elaboration`. As it stands, an Idris error is reported as "expected
  once, among 0 unsupported errors", which is correct but buries the cause.
  Also consider a `make check` spec saying every fixture module imports
  Prelude or names its imports. The harness assumes `--no-prelude`, and
  nothing tells a fixture author.

### AR-2: accept/ and reject/ expected files and run scripts are derived data held twice
- **Category:** harness-representation. **Severity:** high.
- **Paths:** all 55 `accept/*/{run,expected}` and all 47 `reject/*/{run,expected}`.
- **Evidence:** Every reject `run` is the same three lines ending in
  `profile_reject .` (47 copies, one md5). The accept runs come in two
  variants: 45 end in `profile_accept .` and 10 in `e2e_io .`. The reject
  `expected` files fall into four md5 classes once the rule name is
  normalised, each a function of the header alone:
  `compile: exit 3 / unsupported (<rule>): the only error / line: as the header says / [message: as the header says] / artifacts: none`.
  The accept expected files are three classes, decided by which of
  `expected-stdout` and `stdin` exist. The `NEEDS-ACCEPTANCE` marks on those
  files restate the header in prose (ACCEPTANCE.md: 45 accept entries, 24
  of them the same sentence).
- **Guidelines:** RF "one fact, one place". The README's own rule ("A
  test's expected files are its specification") does not hold here: the
  specification is the header, and the transcript repeats it.
- **Recommendation:** Make a profile fixture just its sources and header.
  The runner enumerates `accept/*/` and `reject/*/` as it does
  `programs/semantics/prim@<name>` and runs `profile_accept` or
  `profile_reject` with the outcome computed from the header. Delete the 102
  `run` and `expected` files and their marks. One harness for accept: give
  profile_accept stdin and the e2e marks (`heap-free`, `live-cells`)
  instead of switching ten fixtures to `e2e_io` (RF "a switch on a tag").

### AR-3: registry/broken-entry: half its premise holds, and its method is the wrong one
- **Category:** stale-legacy, harness-representation. **Severity:** medium.
- **Path:** registry/broken-entry (and `registry_shadowed` in tests/lib/profile.sh).
- **The question asked (base-surface's premise).** Partly no, partly yes.
  - The shadowed modules here are prelude-package modules (`Builtin`,
    `Prelude.IO`). They are written for `--no-prelude` with explicit
    imports, so a project copy elaborates. `Frontend/Program.idr` runs
    `validated` right after `entryPoint`, before `checkPragmas` and
    `checkReachable`, so the profile does not refuse the copy's `%foreign`
    first.
  - Case 1 does reach the hook: its output is
    `Builtin.idr:161:1: error: unsupported (hook): Builtin.replace: the registry's entry Builtin.replace (faster) expects ... but found ...`.
    The `output` (16:32) predates 45d1b32c's wording fix (16:43), so case 1
    should now pass.
  - Case 2 fails for its own reason. Its Main is
    `import Prelude.IO` / `main : IO ()` / `main = putStr "hello"`, but
    `Prelude.IO` imports `PrimIO` and `Builtin` privately. So Main fails
    with `Undefined name IO` and `Undefined name fromString` before
    validation runs.
  - base-surface's real failure was the same shape. Its copies of base
    modules lost base's implicit prelude (`Undefined name Unit`,
    `Undefined name HasIO` in `System/File/Handle.idr`), which is not quite
    the `%foreign` reason 45d1b32c gives.
  - Not verified: whether Idris accepts the awk-inserted
    `{default MkUnit shadowed : Unit} ->` on a `%foreign` declaration.
    Case 2 never got that far.
- **Other evidence:** `registry_shadowed` edits upstream source with awk
  (`index($0, name " : ")`), which is a text patch on a pinned file. The
  "unbroken" case compiles `import Prelude; main = putStrLn "hello"`, which
  every other test also compiles, so it can never fail alone. The test
  breaks 2 of the registry's many entries.
- **Guidelines:** TBS §1.1 (two examples where the property is "every
  entry is validated"). TBS §7 (the oracle is the table itself).
  RF "parse at the boundary" (validation is a pure function of the table
  and the context, so test the function).
- **Recommendation:** Rewrite as a unit property, run by the pinned Idris
  against the installed fork as growth-check and probe-names are. For every
  entry of the registry table, build a context, or take the loaded prelude
  context and perturb the entry's expected `Shape` (one leading argument,
  one quantity changed, the definition removed). Assert that `validate`
  returns a refusal naming that entry, and that the unperturbed table
  validates. This covers every entry, needs no shadowed source, and does
  not depend on how a library module imports. Until then, fix case 2's
  imports (`import Builtin`, `import PrimIO`, `import Prelude.IO`) and
  delete the "unbroken" lines. Repoint without-fixture's `hook` line.

### AR-4: the reject header's site is a line number with no file, and the line check can pass on the wrong error
- **Category:** perception. **Severity:** medium.
- **Paths:** tests/lib/profile.sh `profile_reject`;
  reject/escape-hatch-assert-total-in-user-data-module,
  reject/pragma-user-module-named-data, reject/polymorphism-nested-data.
- **Evidence:**
  `reject_reported=$(awk 'NR == 1 && $2 ~ /:[0-9]+$/ { sub(/.*:/, "", $2); print $2 }' ...)`
  drops the file. Two fixtures say "The line is Data/Evil.idr's", but a
  refusal at Main.idr line 7 (`import Prelude`) would pass too. In the
  polymorphism-nested-data output, "line: as the header says" printed
  beside an Idris elaboration error at `Main.idr:11:25`.
- **Guidelines:** TBS §6.2 (what is perceived decides what is found).
  AGENTS ("names the site").
- **Recommendation:** Write the header as `-- expect: <rule>, <file>:<line>`.
  Compare the report's whole location. Check the line only when the rule
  matched, so a wrong refusal prints one diagnostic line, not two lines
  that disagree.

### AR-5: `idris` and `elaboration` are one rule under two names
- **Category:** harness-representation. **Severity:** medium.
- **Paths:** reject/idris-interface-body, reject/idris-totality-depth-pragma,
  reject/without-fixture, tests/spec/rules-covered, profile.sh.
- **Evidence:** IdrRules.txt has one user-error rule:
  `elaboration	user error`. Driver.idr: "Idris's own errors among them as
  refusals of the rule `elaboration`". profile.sh maps the header `idris`
  to "the rules of the user-error category". rules-covered: "A header that
  names no rule (`idris`) states no rule". without-fixture: "elaboration
  owed ... tests/reject/idris-interface-body states three, and its header
  names the rule once a build shows them".
- **Guidelines:** RF "one fact, one place". RF "every string that names a
  thing is a missing type".
- **Recommendation:** Name the headers `elaboration` and rename the
  fixtures `elaboration-*`. Delete the `idris` branch in profile_reject and
  the `elaboration` line of without-fixture. compiler/elaboration-error
  then joins them as a fixture.

### AR-6: two reject fixtures pin the growth check's incompleteness
- **Category:** brittle-overspecified. **Severity:** medium.
- **Paths:** reject/polymorphism-growth-family-sum, reject/polymorphism-growth-recursion.
- **Evidence:** family-sum: "refused at T, though its instances are finite:
  a sum of two arguments' heights is no weight the check states (a known
  limit)". growth-recursion: "wrap is called once, at a constant, and its
  one instance is finite; the program is refused all the same".
- **Guidelines:** TBS §1.1. The assertion is stronger than the contract.
  AGENTS says a construct whose choices "form a set the whole program
  fixes" compiles, and never "miscompile silently". Either a refusal by
  the rule at the site or a correct compile meets the contract. Pinning
  the refusal makes an improvement fail the test. Winters' second point
  applies too: the vocabulary has no "refused or correct" assertion, so
  authors pin one side.
- **Recommendation:** Give the harness that assertion: a header such as
  `-- expect: polymorphism or stdout, line N`, with expected-stdout beside
  it. Restate both fixtures with it. Record "a known limit" as data in one
  list (as without-fixture is), not as a passing test.

### AR-7: stale premises: compile-time evaluation, budgets, and boundaries since removed
- **Category:** stale-legacy. **Severity:** high (15 tests).
- **Paths:**
  - accept/partial-integer: "A closed call of a partial function is
    evaluated at compile time".
  - accept/runtime-partial-integer and runtime-partial-stream:
    "compile-time evaluation stops `count 0` once it has spent its budget".
  - accept/streams and partial-stream: "evaluated at compile time and the
    list never exists at runtime".
  - accept/static-list: "Nothing of them exists at runtime".
  - accept/static-integers: "An Integer that would exist at runtime is
    rejected: reject/runtime-integer-partial", a fixture that does not exist.
  - accept/runtime-integer*, runtime-data-*: boundaries of rules that once
    refused runtime Integer and runtime data.
  - accept/unreachable: "An unreachable definition outside the profile",
    but `Integer` is now inside it.
  - accept/division.
  - accept/streams also cites reject/runtime-data-partial-stream, which does
    not exist.
- **Evidence:** AGENTS: "A closed call runs at run time. Static
  normalization (proposal 0007) is what would fold one, and it is not
  built." RF: "Never fuel".
- **Guidelines:** RF "Delete what the representation makes dead in the
  same change: ... the test that checked the impossible state". The
  owner's stance in AGENTS ("exercises removed behaviour").
- **Recommendation:** Delete or merge as in the table. A stream program
  that reveals a bug (streams, partial-stream) moves to programs/eval with
  the stale comments removed.

### AR-8: compiler/handoff-readable greps printed MLIR for facts ODS and the verifier should hold
- **Category:** brittle-overspecified, cannot-fail. **Severity:** medium.
- **Path:** compiler/handoff-readable.
- **Evidence:**
  - The checks are regexes over idris-mlir-opt's print, e.g.
    `grep -cE '^ *idr\.program @(...) root\(@(...)\) stage\(higher\) \{$'`
    and an awk that pairs an `"idr.func"(` line with the next `})` at its
    own indentation.
  - The "forms" check greps for `"idr\.lambda"`, `"idr\.(data|ctor)"` and
    `idr.program` used as an attribute. These ops no longer exist, so a
    module holding one would not parse, and the earlier `parse:` line
    fails first. The check cannot fail on its own.
  - The instance check fails today (the idr.func lines shown carry no
    `instance = #idr.instance<`). Uncertain: whether every idr.func must
    name an instance (closures, lifted functions) is undecided in the code
    I read.
- **Guidelines:** RF MLIR-grain ("Declare, don't write ... a hand verify is
  a declaration not yet made"). AGENTS: "write the property once as an
  expressive check (a helper, a verifier-style assertion pass)".
- **Recommendation:**
  - If `instance` is required, make it a non-optional property in ODS; the
    verifier then holds it after every pass, and the check is gone.
  - Make "no func dialect before lowering", "every op located" and "no
    Idris-made block names in symbols" one idr-expect property (`emitted`)
    run by `universal` on every compilation.
  - Delete the old-forms check.

### AR-9: round-trip checks applied to hand-picked programs instead of every compilation
- **Category:** example-should-be-property. **Severity:** medium.
- **Path:** compiler/handoff-round-trip.
- **Evidence:**
  `for fixture in bench/rbtree tests/programs/data/shapes tests/programs/arrays/linarray-combinators`.
  properties.sh already reads every compilation's dumps ("A check added to
  every compilation is added here, and no transcript changes").
- **Guidelines:** TBS §1.1 (`DefaultConfigsArePrime` checks three numbers;
  state the property and feed it every input). TBS §8 (more inputs from the
  same distribution).
- **Recommendation:** Add "the emitted module prints, parses and reprints
  byte-identically, and its generic form equals the print's" to
  `compilation_properties`. Delete the test.

### AR-10: the universal oracle's IR tree dump fails on long symbols and may cause the timeouts
- **Category:** infrastructure-gap, perception. **Severity:** high (27 tests suite-wide; 5 here).
- **Paths:** accept/bounded-field, accept/bounded-method-own,
  registry/pointer-handles, registry/scalar-bytes (and fuzz/two-hosts and
  22 programs/ tests outside this lane).
- **Evidence:**
  `Error while creating directory .../idr_func_Prelude.IO.printLn[Prelude.Basics.List (Main.T Int), PrimIO.IO, ...];92529e598cb9870b: File name too long`.
  scalar-bytes ends `compile: exit 1` with nothing but these lines, so the
  observation changes the outcome. Several compiles hit the 60 s step limit
  (`compile: exit 124`): bounded-field, bounded-method-own, bounded-synonym,
  polymorphic-recursion-swapped, pointer-handles, and two-levels'
  primitives. Uncertain: I cannot tell from the outputs whether the
  per-pass dump at every pass (`--mlir-print-ir-after-all
  --mlir-print-ir-tree-dir`) or the compiler causes the timeouts.
- **Guidelines:** TBS §7 ("co-designed" testability; the instrument must
  not change the result). TBS §11 (a hidden input: the file system's
  NAME_MAX now decides pass or fail).
- **Recommendation:** Name the tree printer's directories from a bounded
  key, the symbol's content hash. MLIR's printer derives the path from
  `sym_name`, so per AGENTS that is an upstream patch, or the compiler
  keeps symbols bounded. Make a dump failure never fail the compilation.
  Measure one timed-out compile with and without dumps before deciding the
  timeouts are compiler bugs.

### AR-11: compiler/module-location pins the printed layout of the module's location
- **Category:** brittle-overspecified, redundant. **Severity:** low.
- **Evidence:** `if tail -n 1 "$work/module.mlir" | grep -qF '"Main.idr":5:'`.
  The output is `} loc(unknown)`. Meanwhile reject/cycle-array-knot (line
  15) and cycle-ioref-knot (line 16) show whole-program refusals at main's
  declaration, the behaviour this test exists for.
- **Guidelines:** TBS §1.1. AGENTS: "Not ... op order".
- **Recommendation:** Delete. The cycle fixtures state the contract by
  outcome.

### AR-12: comments claim properties the fixture does not check
- **Category:** perception. **Severity:** medium.
- **Paths:**
  - accept/fused-stored-string and recursive-string: "no string is built at
    runtime".
  - accept/action-*: "No closure of it survives to runtime".
  - accept/indexed-tags: "a value is only its constructor's tag".
  - accept/static-list.
  - accept/growing-specialization-function: "its closures are built on the
    heap".
- **Evidence:** profile_accept checks only compile status, artifacts,
  `universal`, exit, stdout and stderr. The `heap-free` mark exists only in
  e2e.sh (testutils.sh: "heap-free  no op of the lowered module allocates a
  heap cell").
- **Guidelines:** TBS §9.2 step 5 ("Otherwise the test can silently check
  nothing"). TBS §6.2.
- **Recommendation:** Where the claim is the point, state it with the
  existing vocabulary: the `heap-free` mark, or an `mlir.expect`
  property. Otherwise delete the sentence. This favours one harness (AR-2).

### AR-13: compiler/probe-names checks names, not probes, and pins their spelling
- **Category:** example-should-be-property, brittle-overspecified. **Severity:** low.
- **Evidence:**
  - `sameProbe p q = probeName p == probeName q`. The round trip compared
    is `probeName . probeOf . probeName`, so a non-injective `probeName`
    passes.
  - expected-stdout lines such as `ok {idris-mlir-binder:7}` and
    `ok 1:2:3:4:5:6:7:255:4:0:idris-mlir-held` pin each encoding's text.
  - There are 19 hand-picked values.
- **Guidelines:** TBS §1.1 (exact text is brittle where the contract,
  "reads back as itself", leaves it open). TBS §8 (exhaust small cases).
  RF "every string that names a thing is a missing type": the probes
  travel as Idris `Name`s built from literals, which registry-only flags
  (AR-15).
- **Recommendation:** Derive `Eq Probe`. Enumerate every constructor at
  small arguments (0..3, held bytes from a small alphabet) and check
  `probeOf (probeName p) == Just p`. Also check that `probeOf` is `Nothing`
  on a corpus of user-like names. Print one line with the count.

### AR-14: the "outside the language" rules test one table entry each by hand
- **Category:** example-should-be-property, distribution. **Severity:** medium.
- **Paths:** reject/threads-concurrency, signal-handler, process-system,
  finalizer-collect-any, raw-pointer-malloc, and deprecated-*.
- **Evidence:**
  - `Registry/Recognized.idr` rules out about 26 thread definitions,
    about 25 signal definitions and about 20 process definitions
    (`ruledOut ["System","Concurrency"] "makeMutex" Threads`, ...). The
    fixtures name one each.
  - The three deprecated fixtures all hit `deprecatedDef` entries; the
    `deprecatedForeign` entries are hit by none.
- **Guidelines:** TBS §5 (the distribution is chosen by nobody: the one
  entry someone thought of). TBS §1.1.
- **Recommendation:** Keep one fixture per rule as the smoke test that
  rules-covered asks for. Add a generated pool, one program per
  `Forbidden`/`Deprecated` entry, emitted by the runner from the registry
  table. Each program references the entry from a `main` that reaches it,
  and the test checks the rule and that the message names the entry.
  Uncertain: writing a well-typed reference for an entry whose shape is
  `Hole` may need the frontend to print each entry's type. Delete
  deprecated-buffer-data and deprecated-set-byte.

### AR-15: registry/registry-only is a grep lint whose patterns do not match its rule
- **Category:** brittle-overspecified, harness-representation. **Severity:** medium.
- **Evidence:** The output lists 10 hits: `foreign/idr/unittests/Cycles.cpp:82: ... function(prog, "Prog.main")` (test data),
  `compiler/src/IdrisMLIR/SyntaxSamples.idr:84: (Just ("Prelude.Types.List", ...))`
  (sample data), `Frontend/Walk.idr:264: probeName (ProbeHole i) = ... (UN (Basic "idris-mlir-hole"))`
  (compiler-made names, 6 lines), and `Frontend/Translate/Forced.idr:83: ... Con (UN (Basic "->"))`.
  The rule is "names the compiler knows of Idris's definitions are in the
  registry". The pattern is "any `Basic "` or any capitalised dotted
  literal".
- **Guidelines:** RF "every string that names a thing is a missing type".
  The fix is a type, not a regex. TBS §1.1 (the assertion distinguishes
  what the contract treats alike).
- **Recommendation:**
  - Give compiler-made names one home: a `Probe` table, or a generated
    names module next to the registry, so `Basic` with a literal appears in
    one allowed file.
  - Exclude test sources (`unittests/`, `SyntaxSamples.idr`) by stated
    category, not by allowlist line.
  - Decide whether `"->"` is a registry entry (it is Idris's own pi
    pattern).
  - The lint's own self-check ("the patterns find the registry's names:
    yes") is good: keep that shape.

### AR-16: two-levels has had one level since 08a065e4; its oracle is the compiler's own output
- **Category:** wrong-or-missing-oracle, redundant. **Severity:** medium.
- **Evidence:** In 08a065e4 the stock evaluator was removed as
  two-levels' upper level, and the corpora got golden files "from this
  compiler's output on a run Chez still agreed with". The mark says "add
  each 'no expected value' line the owner's build prints, after review".
  `Sem.idr` already computes the integer primitives' values "from what
  each primitive means, not from the compiler".
- **Guidelines:** TBS §7 (no oracle means no bug found). TBS preamble: "A
  golden transcript is right only where the contract fully determines it".
  Here the values are taken from what the compiler printed, not from what
  the contract says.
- **Recommendation:**
  - Fold the integer terms' edge vectors into Sem's table and delete them
    here.
  - Write String, Char, Double and Integer semantics as Sem does (a table
    computed from the runtime's documented meaning, with `libm-lines` for
    libm) and generate the tests.
  - Restate the Prelude corpus as laws over Gen-generated values:
    `reverse . reverse = id`, `length (xs ++ ys) = length xs + length ys`,
    `sort` sorted and a permutation, `show . read`.
  - Retire the name "two levels".

### AR-17: references to deleted or nonexistent tests, and a drifting acceptance list
- **Category:** stale-legacy. **Severity:** low.
- **Evidence:**
  - without-fixture: "as tests/registry/base-surface and
    tests/registry/broken-entry do".
  - accept/streams cites reject/runtime-data-partial-stream, and
    accept/static-integers cites reject/runtime-integer-partial; neither
    exists.
  - ACCEPTANCE.md lists 72 files in this lane, but only 24 still carry the
    mark. It lists registry/base-surface and string-iterator, which are
    deleted.
  - without-fixture cites source line numbers
    (`Translate/Closed.idr:1118, Translate/Keys.idr:791`).
- **Guidelines:** RF "one fact, one place". ACCEPTANCE.md calls itself
  "the tree's own list, `grep -rl NEEDS-ACCEPTANCE tests`", a copy of the
  tree.
- **Recommendation:** Generate ACCEPTANCE.md from the grep, or delete it
  and let the grep be the list. Make rules-covered fail on a
  without-fixture reason that names a path that does not exist. Cite
  definitions by name, not line.

### AR-18: output-only leftover directories
- **Category:** harness-representation. **Severity:** low.
- **Evidence:** `git ls-files` is empty for reject/layout-{256,512,768}-counted-fields,
  reject/primitive-shl, reject/program-base, registry/base-surface and
  registry/string-iterator. Each holds an `output` (`.gitignore`:
  `/tests/**/output`).
- **Recommendation:** Delete them. Have the runner write `output` under
  `tests/build/` (keyed by test path), so deleting a test deletes
  everything of it.

### AR-19: accept/action-after-effect cannot fail on what it claims
- **Category:** cannot-fail. **Severity:** low.
- **Evidence:** "the division is not moved before the write ... On empty
  stdin getChar returns character 255, so the division is 100 div 255 = 0
  and does not crash". A pure division hoisted above the write prints the
  same "ready\n0".
- **Guidelines:** TBS §9.2 steps 5-6 (the scenario must reach the
  situation the property is about).
- **Recommendation:** Have the division fault on the input (d = 0 on empty
  stdin) and expect "ready" on stdout before the crash's expected-crash.
  Move it to programs/semantics.

### AR-20: compiler/main-visible and compiler/frontend-command-line check wording and removed printing
- **Category:** brittle-overspecified, stale-legacy. **Severity:** low.
- **Evidence:**
  - main-visible greps `unsupported (program): main is ambiguous`. The
    refusal reads `unsupported (program): main: main is ambiguous: Helper.main, Main.main`.
    This is the same rewording that broke broken-entry.
  - frontend-command-line expects `Undefined name` from
    idris-mlir-front, but by design (Driver.idr header) the frontend
    "prints none" and writes the refusal into the module.
- **Guidelines:** TBS §1.1. RF "every string that names a thing" (a
  message's text is no identity; the report's `diagnostic: error <rule>
  <site>` is).
- **Recommendation:** Read the report (rule and site) and match a `message`
  only for the value the refusal must name. Split main-visible into
  fixtures (table). Check the frontend's refusal through the module it
  wrote, for example with `idris-mlir --report` on it.

### AR-21: redundant pairs and harness self-tests
- **Category:** redundant. **Severity:** low.
- **Paths:**
  - reject/pragma-inline is subsumed by pragma-default-with-inline.
  - accept/default-pragma is shown by pragma-default-with-inline.
  - reject/escape-hatch-phrase-in-comment equals escape-hatch-believe-me.
  - accept/runtime-data-list is a subset of runtime-data-first-of-two.
  - runtime-partial-* duplicate nonterminating.
  - compiler/elaboration-error duplicates reject/idris-* (it checks the
    same exit, report and artifacts through its own greps).
- **Guidelines:** TBS §1.1. The owner: "duplicates another ... deleted".
- **Recommendation:** As in the table.

---

## 4. Code bugs the tests reveal

These are failing tests whose expected behaviour is right and whose failure
is the compiler's or its test programs'. I report only what the output shows.

1. **accept/streams: wrong value.** `printLn (sum (take 10 (countFrom (the Int 1) (+ 1))))`
   printed `34`, expected `55`. This is a miscompile of a Stream (codata,
   `Inf`) consumer: some elements are skipped or repeated. 34 is not
   1+...+k for any k, so the error is not a simple off-by-one on the count.
   Likely the same cause as item 2.
2. **accept/partial-stream: run does not finish.**
   `sum (takeBefore (> 40) (countFrom 1 (* 2)))`: compiles, then
   `run: exit 124 ... timed out after 60s: Main`. It should stop at 64 and
   print 63. Probably the same stream miscompile: the elements never pass
   40 (for example the step is not applied, as `* 1` would behave), or the
   suspension is re-forced from the start.
3. **accept/string-primitive-runtime-match and two-levels/terms (prelude): ABI mismatch in lowering.**
   `'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr' for operand number 0`
   at `case prim__cast_IntString (prim__cast_CharInt c) of "97" => ...`. In
   two-levels it is reported as `idris-mlir: internal error:`. The likely
   reading: the call that compares a runtime string with a literal (or the
   cast) is lowered against a runtime declaration whose first parameter is
   an i64, while a string pointer is passed. The verifier catches it after
   lowering.
4. **accept/runtime-lazy-value-growing-choice: leak.** `idris-rt: live cells 48`
   with input `a` (97 levels; about half of them suspend). The Lazy
   suspensions chosen by the runtime recursion are not released when
   forced or dropped.
5. **registry/nat-operations: leak.** `idris-rt: live cells 1`. One cell
   (a big Nat or Integer, or a closure from `map (plus 1)`) is not freed.
6. **compiler/artifacts: stale object after a failed rebuild.**
   `stale artifacts after the failure: build/exec/Main.0306ec5431f877b2.o`.
   The bin objects are named by content hash (`NAME.<bin>.o`). A later
   compile that fails cannot know the earlier name and arms only its own
   names for removal, so the earlier object survives. The cleanup must
   cover the pattern `Main.*.o`, not the names of this build.
7. **compiler/handoff-round-trip (programs/arrays/linarray-combinators): verifier refusal.**
   `'linalg.generic' op consumes a view, which holds no reference; a reference of its own (idr.dup) is consumed, and an owned value's is given to a store (idr.own.give)`
   at `weighted` and `sumSquares`. Counting (rc) hands a borrowed view to a
   consuming linalg op. The programs lane will see the same failure.
8. **Compile timeouts at the 60 s step limit:** accept/polymorphic-recursion-swapped,
   accept/bounded-synonym, accept/bounded-field, accept/bounded-method-own,
   registry/pointer-handles, and two-levels primitives. Uncertain whether
   the compiler or the per-pass tree dumps cause them (AR-10).
   polymorphic-recursion-swapped and bounded-synonym show no FTL lines,
   which points at the compiler; bounded-synonym's output is only
   `compile: exit 124`.
9. **IR tree dump fails on long symbol names, and the compilation then fails.**
   In registry/scalar-bytes, `compile: exit 1` with only `File name too long`
   lines (AR-10). The specialised function names carry the full printed
   type arguments (for example `idr_func_Prelude.Types.(rangeFromTo_Range_$a).case0[Int, Builtin.MkPair (Prelude.Num.Integral Int) ...]`),
   which exceed NAME_MAX as directory names.
10. **compiler/dialect-syntax: test data in compiler/src.** `SyntaxSamples.idr`
    makes `@sample`, which has parameters and results, the program's root
    (`Idr.programOp "samples" "sample" Stage.Higher`). The verifier now
    requires a root of `() -> i64` or `(!idr.world) -> (...)`: "'idr.func'
    op is the root, so its type must be ...". The fix is to give the
    samples their own root function.
11. **compiler/handoff-readable: idr.func without `instance`.** Uncertain
    whether this is a bug: it is one only if every function must name its
    instance (AR-8).

Not code bugs: the 13 missing-import failures (AR-1), cycle-ioref-knot
(a contract choice), frontend-command-line and main-visible (stale
wording), module-location (stale layout), and registry-only (lint scope).

---

## 5. The scope rebuilt

**What stays as examples.** One fixture per refusal rule (the
rules-covered contract), and one per distinct cause where the frontend
extracts the fact differently:
- the five growth causes;
- the four runtime-closure causes;
- erased and runtime escape hatches;
- trust by package;
- source-checked pragmas.

Also the positive boundary fixtures that pair with a rule:
- `named-implementations` with `runtime-closure-implementation`;
- `erased-field` with `dependent-field`;
- `totality-past-depth` with the `%totality_depth` refusal;
- the `bounded-*` cases with `polymorphism-*`.

Their expected transcripts go (AR-2): a fixture is its sources and a
header. The header is
`-- expect: <rule>, <file>:<line>` (AR-4), or `-- expect: <rule> or stdout, <file>:<line>`
for a known limit (AR-6), plus `-- names: <value>` for what the refusal must
name, read from a structured field of the report rather than from prose.
The runner enumerates the fixtures, so there are no copied `run` scripts.
A fixture that does not elaborate is reported as such before anything else
(AR-1).

**Properties and generators that replace what is deleted:**

- **Growth, end to end.** Write a generator of small recursive programs
  from growth graphs (Box.idr's `Graph`: up to 3 positions, weights in
  {-1, 0, +1, +2}, caps, stuck arcs). Each graph becomes Idris source: a
  mutual group whose calls pass `S`/pred of a `Nat` index into a type
  family (`Pad`, `Ints`), a dictionary, or a pair.
  - Oracle: Box.idr's brute force on the generating graph. Assert
    "refused with polymorphism at the cycle's first definition" iff the
    brute force says it grows. Otherwise assert that it compiles, and runs
    with a stdout computed from the graph.
  - This replaces the hand `bounded-*` and `polymorphism-growth-*` cases
    as regression seeds, and keeps them as the generator's alphabet
    (TBS §1.2).
  - Swarm the weights per run (TBS §5).
- **Every forbidden or deprecated entry** (AR-14): a pool generated from
  the registry table, one program per entry, checking the rule, the site
  and the named entry.
- **Registry validation as a unit property** (AR-3): for every entry, each
  perturbation of its shape is refused naming the entry, and the true
  table validates. This runs against the installed fork, like growth-check.
- **Hook semantics by a second implementation** (TBS §7). For the
  NatOperation hooks, a user module copies the Prelude's unary definitions
  (`myPlus`, `myMult`, `myMinus`, `myCompare`) under other names. On
  Gen-drawn Nats up to 60, the hooked functions must agree with the unary
  copies, and on the big values with the Integer meaning. This replaces
  part of nat-operations' hand list.
- **Emitted-module properties in `universal`** (AR-8, AR-9): round trip
  (print, parse, print; generic forms equal), no func dialect before
  lowering, every op located, block symbols named `<parent>.case<k>` and
  `<parent>.with<k>`. These run on every one of the hundreds of
  compilations instead of four programs. `instance` becomes a required ODS
  property.
- **Probe names** (AR-13): enumerate every `Probe` at small arguments and
  check that `probeOf . probeName` is `Just`. This is exhaustive in the
  box (TBS §8).
- **Fork termination** (fork-loops-terminate): enumerate call graphs of up
  to 3 functions with size-change labels from {<, =, none}. Oracle: a
  brute-force size-change closure (compose every path up to a bound and
  look for an idempotent loop without a decrease). This is the
  growth-check pattern applied to `loopsTerminate`.
- **Primitives and Prelude** (AR-16): Sem-style specification tables for
  String, Char, Double and Integer, computed from the runtime's documented
  meaning. Prelude laws over Gen-generated lists, strings and naturals. No
  frozen snapshot of the compiler's own output.
- **Driver contracts** stay as they are, since they are exact and small:
  artifacts, frontend-beside, frontend-named-file, no-environment, and
  content-hash with its published vectors. Add one property to artifacts:
  for any sequence of {succeed, fail} compilations of one module, the
  build directory holds the artifacts of the last success exactly when the
  last compilation succeeded. Generate short sequences (TBS §4.2, a small
  command language).

**Fixtures from the deleted accept tests that still matter:**
- streams and partial-stream become one programs/eval stream program (the
  bugs in §4).
- fused-stored-string and recursive-string go to programs/io with the
  `heap-free` mark, and runtime-string-compared becomes its negative
  control if kept.
- action-after-effect becomes an ordering test with a fault
  (programs/semantics).
- The rest (fib, map-pair, pair-maybe, partial-application, division,
  runtime-*, static-*) are covered by programs/ and Sem, and go.
