<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane `gaps`: the contracts no test states

**Scope.** The compiler's promises, not a directory of tests: the rules of
`AGENTS.md`; every pass's description in
`foreign/idr/include/idr/Transforms/Passes.td` (27 passes, their roles and
stages); the dialect verifier (`foreign/idr/lib/IR/Verify/*.cpp`, and the
op verifiers' diagnostics under `foreign/idr/lib/IR`); the runtime's
documented semantics (`runtime/idris_rt.h` and the property programs under
`tests/toolchain/runtime-*`); the frontend's refusal rules
(`build/dev/.../IdrRules.txt`, 28 rules, `tests/lib/rules.sh`,
`compiler/src/IdrisMLIR/Frontend/Profile.idr`, `tests/reject/without-fixture`);
and the guarantees proposals 0002 and 0004 state (0002 §1 I1 to I6, §4.1,
§4.2, §9; 0004 §1, §7, §8). For each contract: is it stated as a property
(grepped across `tests/`), only by examples, or not at all; and for the
missing ones, the property, its oracle and its generator.

**Read.** `.claude/skills/testing-by-search/SKILL.md` (TBS) and
`.claude/skills/representation-first/SKILL.md` (RF) in full;
`tests/README.md`; `tests/testutils.sh`; `tests/lib/{properties,e2e,run,
fuzz,compile,determinism,rules,lit}.sh`; `tests/{Fuzz,Sem,Gen,Prims}.idr`
headers and Sem's tables; `Passes.td` in full; `Contracts/Contracts.cpp`;
`Expect/Lookup.cpp` (the 80 idr-expect properties); `Expect/Named.cpp`,
`Expect/Quantities.cpp`; the headers of every `Verify/*.cpp` and of every
googletest box (`foreign/idr/unittests`); `Driver/Run.cpp`'s pipeline;
`Frontend/Profile.idr`'s reach walk; the spec tests' headers; the
`tests/toolchain/runtime-*` transcripts; the three logs (test.log,
test-idr.log on an older build, test-mlir-tools.log) and the `output` of
the tests cited here.

**Counts.**
- Contracts enumerated: 63 (19 from AGENTS.md, 26 from Passes.td, 5 from
  the verifier, 5 from the runtime, 5 from the refusal rules, 3 from the
  proposals).
- Stated as a property (over every compilation, every input of a box, a
  generated space, or the source): 24, of which 4 hold only on
  hand-written inputs or only relative to the emitted module.
- Stated only by examples where a property over generated inputs is
  possible: 24.
- Stated by examples, and examples are the right form (a rule's
  discriminator): 5.
- Not stated by any test: 10 (and the missing half of 3 more).
- Example tests cited as the only coverage of a contract, each given a
  verdict below: 97 (every row of section 2b).
- Verifier and op-verifier diagnostics in `foreign/idr/lib/IR` with no
  dialect fixture whose expected text holds their opening words: 41 of 93
  (measured by the first 28 characters of each literal; a composed message
  may be miscounted, so this is an estimate; two are confirmed by hand
  below).
- Generated role and stage lists (`IdrPassRoles.txt`, `IdrPassStages.txt`)
  that Passes.td says "the tests read": read by no test (0 consumers).

Section ids: TBS n.m is testing-by-search's section; RF names a bullet of
representation-first ("RF one fact", "RF parse at the boundary", RF SPOV1
to 3, "RF MLIR grain").

---

## 2. Verdict tables

### 2a. Contracts

Coverage: **P** = stated as a property (over every compilation, every
input of a box, or a generated space); **E** = examples only, and a
property is possible; **E-ok** = examples are the right form (a refusal
rule's discriminator); **N** = no test states it. "Finding" points to
section 3.

| contract | promised in | stated by | coverage | finding |
| --- | --- | --- | --- | --- |
| AG-1 nothing assumes x86, Linux, ELF, musl or a page size outside the target's entry and the platform layer | AGENTS.md "Two first-class targets" | no spec test searches for target predicates; per-host `expected.*` only in `toolchain/runtime-archive-check` | N | GAPS-17 |
| AG-2 everything static; no dlopen | AGENTS.md "linked statically" | `toolchain/static-linking`, `universal`'s object_imports on every e2e | P | - |
| AG-3 one thing, one representation | AGENTS.md | `spec/dialects-current`, `emit-dialects`, `facts-in-types`, `refusals-as-data` | P (source properties) | - |
| AG-4 the frontend consumes TT, never CExp | AGENTS.md | `spec/no-erased-inputs` | P | - |
| AG-5 no primitive has an Idris meaning; folders call the runtime | AGENTS.md | `spec/no-primitive-semantics`; Fuzz d-line against j/r/s lines; `folds-balanced` in 4 dialect files | P (2 fixed seeds) | GAPS-11 |
| AG-6 a closed call runs at run time; a partial closed call is never evaluated at compile time | AGENTS.md | `programs/partial/partial-divergent-call`, `partial-untaken-divergence` | E | GAPS-14 |
| AG-7 megamorphic refused, naming site and value; a bounded set compiles | AGENTS.md | `reject/polymorphism-*` (9), `reject/runtime-closure-*` (4), `accept/bounded-*` (13) | E | GAPS-15 |
| AG-8 a trusted unsafePerformIO's effects happen where demanded, in program order | AGENTS.md | `accept/action-after-effect`, `accept/action-run-at-once`, `programs/io/action-forced-twice` | E | GAPS-9 |
| AG-9 `%foreign` / `%extern` refused, naming them; never ignored | AGENTS.md "%foreign and the C ABI" | no fixture declares either in user code | N | GAPS-1 |
| AG-10 only Frontend imports the fork | AGENTS.md | `spec/frontend-imports` | P | - |
| AG-11 third_party/Idris2 pinned, unmodified | AGENTS.md | `spec/idris-pin`, `idris-pin-drift` | P | - |
| AG-12 refuse with `unsupported (<rule>)`, never miscompile silently | AGENTS.md | per fixture (exit 3 + one rule); nothing over generated programs beyond closed expressions | E | GAPS-3 |
| AG-13 no pass drops a quantity; `!idr.lin` checked after every pass | AGENTS.md | `universal` quantities-kept on every e2e (relative to the emitted module); verifier after every pass (`spec/verifier-every-pass`); `linear-kept` only on RUN lines | P (relative) | GAPS-4, GAPS-5 |
| AG-14 what Idris erased is no parameter, field or argument; quantity 1 is `!idr.lin` from Emit on | AGENTS.md | no oracle compares the emitted module to Idris's TT | N | GAPS-4 |
| AG-15 erased is not constant; a linear binder is not unique ownership; a Vect is not contiguous | AGENTS.md | `accept/erased-*` (4), `reject/uniqueness-shared-rebuild`, `programs/arrays/ioref-keeps-old-value` | E | GAPS-12 |
| AG-16 an upstream bug is a patch with reproducer | AGENTS.md | `spec/upstream-patches`, `tests/upstream/*` | P | - |
| AG-17 tests check behaviour, not SSA names or op order | AGENTS.md | `spec/dialect-text` | P | - |
| AG-18 every command times out | AGENTS.md | `spec/timeouts` | P | - |
| AG-19 a change passes on both targets | AGENTS.md | shared `expected-stdout` across hosts (the cross-target oracle); x86_64 has run none of the wave (proposals/README) | P by construction, unrun | GAPS-17 |
| PT-1 idr-target: triple, CPU, data layout, vector width from the target entry | Passes.td | 5 dialect files; `toolchain/runtime-triple` | E-ok | - |
| PT-2 role optimization: skipping any one transform, or the pass, keeps a valid module of the same behaviour (0002 I2) | Passes.td 24-27 | `tests/idr/actions/*` (10) check only that skipping *every* action is the identity; `inner-steps` only that a skip verifies and differs | N (the behaviour half) | GAPS-2 |
| PT-3 roles and stages are generated lists "the tests read" | Passes.td 20-22, 46-48 | no test reads `IdrPassRoles.txt` or `IdrPassStages.txt` | N | GAPS-6 |
| PT-4 idr-deduplicate: one of each class, transitive, locations fused | Passes.td | `idr/dedup/*` (3), `actions/deduplicate` | E-ok | - |
| PT-5 idr-defunctionalize: no closure left; finite label sets | Passes.td | the verifier past `higher` (Program.cpp); `no-closures` restated in 35 files | P (verifier) | GAPS-13 |
| PT-6 memo semantics: forced once and shared; Running crashes; a label reaching output is `by_name` | Passes.td defunctionalize | `programs/eval/memo-*`, `stream-share`, `lazy-*`, `programs/partial/self-forcing-caf`, `by-name` in 2 files | E | GAPS-9 |
| PT-7 idr-effects: declared effects cover the body; never widened | Passes.td; 0002 I1, I3 | verifier (Program.cpp) for coverage; `effects-not-widened` only on RUN lines | P (lit only) | GAPS-5 |
| PT-8 idr-knots: each knot refused once, at an array make, else a value built, else the program | Passes.td | `reject/cycle-array-knot`, `cycle-ioref-knot`; third placement untested | E-ok, one case missing | GAPS-16 |
| PT-9 idr-contify / idr-optimize: a budget only stops optimizing, no count rejects; specialization chains end (wqo) | Passes.td | `spec/totality`, `spec/no-fuel` (source); `accept/growing-specialization-function`, `eval/specialize-growing-accumulator`, `interfaces/implementation-a-hundred-definitions-deep` | E | GAPS-14 |
| PT-10 the program is the same at every thread count | Passes.td optimize; `lib/determinism.sh` | `determinism/*` (8 fixed programs) | E | GAPS-10 |
| PT-11 idr-columns: the same program held two ways; never refuses | Passes.td | `idr/actions/columns`, 2 RUN files | E | GAPS-8 |
| PT-12 idr-structure-loops: a float fold combines in index order, the same result on every target; never refuses | Passes.td | none states the order or cross-target equality | N | GAPS-8 |
| PT-13 idr-bufferize: each link of a linear thread in place, always; a copy there is an internal error | Passes.td | `in-place` in 8 dialect files and a few `mlir.expect` | E | GAPS-8 |
| PT-14 idr-accumulate / idr-trmc / idr-tail-loops / idr-tail-calls: constant stack, one frame per cycle crossing at most | Passes.td | `constant-stack` marks (8 programs), `constant-stack` / `tail-calls` properties (3 files each) | E | GAPS-7 |
| PT-15 idr-rc: every reference consumed exactly once on every path | Passes.td; Verify/Owned.cpp | the owned verifier after every pass | P | GAPS-18 |
| PT-16 idr-rc: nothing a program made is live at a normal exit, nothing used after free | Passes.td; runtime | `run_ours` live-cells 0 on every e2e exit with status 0; no use-after-free oracle | P (leaks on one path); N (UAF) | GAPS-18 |
| PT-17 idr-rc-stack: a cell over 256 bytes, a frame's cells past 1024 bytes (64 on a cycle) stay on the heap; a stack cell is never recycled nor exclusive | Passes.td | `idr/stack/*` (3) test only placement of a small cell | N (the bounds) | GAPS-19 |
| PT-18 idr-demand: a shared argument where the type promises in-place is `unsupported (uniqueness)` | Passes.td | `reject/uniqueness-shared-rebuild`, 1 dialect file | E-ok | - |
| PT-19 idr-narrow: a narrowed web computes what the bigs compute, across the small range's edge (2^62) | Passes.td; idris_rt.h | googletest boxes `Hooks`, `HooksCompare`, `Ranges`, `Words`, `Tagged*` (exhaustive per op); webs and versioned loops: `idr/narrow/*` (3), `programs/nat/*` (5) | P per op, E for webs | GAPS-11 |
| PT-20 idr-lower: each guard becomes its comparison and a crash naming its cause and site | Passes.td | `programs/basic/guards-messages-*` (5), `programs/arrays/bounds-*` (6), `semantics/crash-*` (4) | E | GAPS-7 |
| PT-21 idr-entry: a `() -> i64` root's value is the exit status, 0 to 255, any other a crash; an IO root returns 0 | Passes.td; runtime-start | `toolchain/runtime-start`, `programs/io/exit-with` | E (an exhaustive box is small) | GAPS-20 |
| PT-22 idr-narrow-lanes: the 32-bit version computes what the 64-bit one does under the bound | Passes.td | `programs/arrays/linarray-lanes-{exact,narrow,wide}`, `narrowed-lanes` (6 files) | E | GAPS-8 |
| PT-23 idr-returned-arguments: dropping a returned argument changes no behaviour | Passes.td | `idr/returned/*` (1), `actions/returned-arguments` | E (subsumed by GAPS-2) | GAPS-2 |
| PT-24 lowered module: linker-safe names, one public entry, aligned accesses, nothing of idr left | Passes.td lower/entry; idr-expect `linker-names`, `entry`, `aligned-access`, `lowered`, `in-llvm` | 4 to 8 hand-written dialect files each; never on a real compilation | E | GAPS-5 |
| PT-25 the contracts (quantities-kept, linear-kept, effects-not-widened, crash-sites-not-added, folds-balanced) hold at every pass (0002 I1) | Contracts.cpp; 0002 §4.1 | `--idr-contracts` on every idris-mlir-opt RUN line (`lib/lit.sh:79`); never on a program's pipeline | P (hand inputs only) | GAPS-5 |
| PT-26 idr-expect's properties report every place they fail and refuse an unknown name | Passes.td expect | `idr/expect/*` (47); names checked (`Arguments.cpp:51`) | P | - |
| VR-1 linearity: a value of quantity 1 used at most once on every path | Verify/Linearity.cpp | `idr/verify/*`, `idr/world/*`, `idr/func/*` | E | GAPS-21 |
| VR-2 owned stage: exactly once, views used while their owner lives | Verify/Owned*.cpp | `idr/verify/owned-stage`, `idr/rc/*` | E | GAPS-21 |
| VR-3 no `idr.*` discardable attribute | Verify/Attributes.cpp | `idr/verify/attributes` (every case listed) | E-ok | - |
| VR-4 each stage's facts (target, effects cover, containment acyclic, no closure past higher, buffers' globals) | Verify/Program.cpp | `idr/verify/program`, `idr/verify/cycle`; 41 of 93 lib/IR diagnostics have no fixture | E, partial | GAPS-21 |
| VR-5 every dialect input and every emitted module round-trips (generic form, bytecode) | lit.sh `--verify-roundtrip`; compiler/handoff-round-trip | every RUN line; emitted modules of 3 programs only; `dumps_verify` re-parses dumps (no byte round trip) | P (dialect), E (emitted) | GAPS-5 |
| RT-1 each runtime function is its model (bigs, strings, text, doubles, utf8, counting, start) | runtime/, idris_rt.h | `toolchain/runtime-{bigs,strings,text,doubles,utf8,counting,api,start}` | P | - |
| RT-2 a primitive in compiled code means what the runtime means | AGENTS.md; idris_rt.h | Sem (fixed widths, boundary tables), Fuzz runtime part (fixed widths, Double, Char; strings only as output fusion writes them; no Integer), TwoLevels (golden values) | P for fixed widths, E for Integer, Nat and strings at run time | GAPS-11 |
| RT-3 count saturation, persistent cells, stack cells never exclusive | idris_rt.h | `toolchain/runtime-api` (rc.c `saturation`), `runtime-counting` | P | - |
| RT-4 a crash writes the output so far, then `idris-mlir: <cause>`, exit 1 | idris_rt.h | `runtime-start`; `expected-crash` on 24 programs | E | GAPS-7 |
| RT-5 base's files, directories, env, clock, errno | idris_rt.h | `runtime-api` handles; `programs/io/*` examples | E | GAPS-22 |
| FR-1 every rule has a reject fixture or a written reason | spec/rules-covered | `spec/rules-covered`, `reject/without-fixture` | P, 3 rules owed, 1 reason stale | GAPS-16 |
| FR-2 a refusal is only of what is reached; an unreached definition costs nothing | Profile.idr checkReachable | `programs/basic/loads-untrusted-unreached` | E | GAPS-15 |
| FR-3 every refusal found is independent, each owner reported once | Profile.idr comment | none composes two refusals | N | GAPS-15 |
| FR-4 a refusal names its line in the user's file and its value | rules.sh; profile.sh | the `-- expect: <rule>, line N` header on 47 fixtures (five more directories under tests/reject hold only a stray `output`) | P over the corpus | - |
| FR-5 the verdict is the worst seen: Internal > Refused > Accepted (0002 I4) | Driver/Outcome.cpp; 0002 R1 | `idr/obs/report-*`, `idr/pipeline/reported-error-fails` | E (an exhaustive box is tiny) | GAPS-20 |
| PR-1 0002 §9: a typed program generator, swarm weights, EMI rewrites, a Good-Turing stopping rule | proposals/0002 §9 | none built | N | GAPS-3 |
| PR-2 0004 §1.3: acceptance is a property of the program; no change refuses what the base accepted | proposals/0004 | per-fixture; 16 non-reject tests are refused now | E | GAPS-3 |
| PR-3 0005: stage 2 = stage 3 on the new pins | proposals/README | not a test; self-hosting has never finished | N | GAPS-23 |

### 2b. The example tests that are a contract's only coverage

Status is from test.log (make test, this build) or test-idr.log (an older
build). "Mark only" means the given output equals the expected one but for
the `NEEDS-ACCEPTANCE` line.

| path | what it claims to check | verdict | reason | current status |
| --- | --- | --- | --- | --- |
| tests/programs/arrays/bounds-negative-index | a negative index crashes, array index out of bounds | merge-into:tests/programs/arrays/index-property | one point of `0 <= i < n`; TBS 1.1 (DefaultConfigsArePrime), TBS 4.4 (invalid cases by name) | pass |
| tests/programs/arrays/bounds-one-past | index n crashes | merge-into:tests/programs/arrays/index-property | as above | pass |
| tests/programs/arrays/bounds-negative-size | a negative size crashes | merge-into:tests/programs/arrays/index-property | as above | pass |
| tests/programs/arrays/bounds-unrelated-size | a guard against another array's size crashes | merge-into:tests/programs/arrays/index-property | as above; keep as a dictionary shape | pass |
| tests/programs/arrays/bounds-back-edge | a guard on a loop's back edge | merge-into:tests/programs/arrays/index-property | as above | pass |
| tests/programs/arrays/bounds-mixed-calls | guards across calls | merge-into:tests/programs/arrays/index-property | as above | pass |
| tests/programs/arrays/linarray-read-past-size | a linear read past the size crashes | merge-into:tests/programs/arrays/index-property | as above | fail: refused, `unsupported (polymorphism)` on `Builtin.DPair.(#)` |
| tests/programs/arrays/linarray-write-past-size | a linear write past the size crashes | merge-into:tests/programs/arrays/index-property | as above | fail: same refusal |
| tests/programs/arrays/linarray-generate-negative-size | generate with a negative size crashes | merge-into:tests/programs/arrays/index-property | as above | unknown (not in the cited failures) |
| tests/programs/basic/guards-messages-div-zero | the guard names its cause and site | merge-into:tests/programs/basic/guard-property | one operand per guard kind; TBS 1.1, TBS 4.4 | pass |
| tests/programs/basic/guards-messages-array-index | as above, array index | merge-into:tests/programs/basic/guard-property | as above | pass |
| tests/programs/basic/guards-messages-cast-nan | as above, cast of NaN | merge-into:tests/programs/basic/guard-property | as above | pass |
| tests/programs/basic/guards-messages-str-head | as above, head of "" | merge-into:tests/programs/basic/guard-property | as above | fail: internal error, `llvm.call` operand `i64` given `!llvm.ptr` |
| tests/programs/basic/guards-messages-str-index | as above, string index | merge-into:tests/programs/basic/guard-property | as above | fail: same internal error |
| tests/programs/semantics/crash-div-zero | division by zero crashes | merge-into:tests/programs/basic/guard-property | as above | pass |
| tests/programs/semantics/crash-mod-zero | mod by zero crashes | merge-into:tests/programs/basic/guard-property | as above | pass |
| tests/programs/semantics/crash-location | the crash names Prog.idr:6:1 | merge-into:tests/programs/basic/guard-property | the site is part of the property | pass |
| tests/programs/semantics/crash-integer-shift-huge | a huge Integer shift is out of memory | keep | a resource limit, not a generated space; RF limit | pass |
| tests/programs/semantics/closed-char-to-string | a closed cast folds as it runs | merge-into:tests/Fuzz.idr (dictionary) | Fuzz's d-against-r relation states it for every expression; the literal joins the alphabet; TBS 1.2 (alphabet from the unit tests) | pass |
| tests/programs/semantics/closed-double-infinity | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-double-subnormal | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-double-tie | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-integer-shift | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-literal-conversion | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-shift-negative | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/semantics/closed-string-to-int | as above | merge-into:tests/Fuzz.idr (dictionary) | as above | pass |
| tests/programs/prelude/double-basics | Double's prelude operations print their values | merge-into:tests/Fuzz.idr (dictionary) | agreement is Fuzz's relation; keep its literals as the alphabet | fail: `heap-free` mark, a delay cell allocates |
| tests/programs/prelude/double-ties | ties print to even | merge-into:tests/Fuzz.idr (dictionary) | `runtime-doubles` states show_f64 for every double; the compiled path is Fuzz's | pass |
| tests/programs/prelude/double-subnormals | subnormals print | merge-into:tests/Fuzz.idr (dictionary) | as above | fail: live cells 1 |
| tests/programs/prelude/double-infinities-nan | infinities and NaN | merge-into:tests/Fuzz.idr (dictionary) | as above | fail: live cells 3 |
| tests/programs/prelude/double-cast-nan | casting NaN crashes | merge-into:tests/programs/basic/guard-property | a guard | fail: `heap-free` mark, `idr.str.show_sint` allocates |
| tests/programs/data/layout-255-counted-fields | a constructor of 255 counted fields round-trips | merge-into:tests/programs/data/arity-property | one point each side of `IDRIS_RT_OBJS_WIDE`; TBS 8 (move the bug into the box), TBS 1.1 | pass |
| tests/programs/data/layout-256-counted-fields | 256 fields | merge-into:tests/programs/data/arity-property | as above | pass |
| tests/programs/data/layout-512-counted-fields | 512 fields | merge-into:tests/programs/data/arity-property | as above | pass |
| tests/programs/data/layout-768-counted-fields | 768 fields | merge-into:tests/programs/data/arity-property | as above | pass |
| tests/programs/nat/nat-loop | a Nat loop computes | merge-into:tests/programs/nat/nat-property | Nat's meaning is a model (Integer with monus) the harness may hold (0002 O4); TBS 9 | pass |
| tests/programs/nat/nat-sum | a Nat sum | merge-into:tests/programs/nat/nat-property | as above | pass |
| tests/programs/nat/nat-parity | Nat parity | merge-into:tests/programs/nat/nat-property | as above | pass |
| tests/programs/nat/nat-large | a Nat past the small range | merge-into:tests/programs/nat/nat-property | as above; the 2^62 edge belongs in the dictionary | fail: live cells 1 |
| tests/programs/nat/bits8-past-127 | Bits8 past 127 | merge-into:tests/Sem.idr | Sem's Bits8 tables hold 127/128 already (`pow2 (pred w.bits)`); redundant | pass (expected modified in the worktree) |
| tests/programs/arrays/linarray-lanes-exact | 32-bit lanes under the exact bound | merge-into:tests/programs/arrays/lanes-property | the bound B is a generated parameter; TBS 8 | fail: dump directory "File name too long" |
| tests/programs/arrays/linarray-lanes-narrow | lanes narrowed | merge-into:tests/programs/arrays/lanes-property | as above | fail: same |
| tests/programs/arrays/linarray-lanes-wide | lanes left wide | merge-into:tests/programs/arrays/lanes-property | as above | fail: same |
| tests/determinism/hello | the same bytes at 1, 3, 5, 13 threads and a second process | rewrite-as-property | one program of the corpus; the relation applies to every compilation; TBS 1.1 | pass |
| tests/determinism/leet-rotate | as above | rewrite-as-property | as above | pass |
| tests/determinism/rbtree | as above | rewrite-as-property | as above | fail (cause not read) |
| tests/determinism/shapes | as above | rewrite-as-property | as above | pass |
| tests/determinism/threads-linarray-lanes | as above | rewrite-as-property | as above | fail (cause not read) |
| tests/determinism/threads-rbtree | as above | rewrite-as-property | as above | fail (cause not read) |
| tests/determinism/threads-shapes | as above | rewrite-as-property | as above | pass |
| tests/determinism/name-stability | an edit of Main.step moves no other symbol | rewrite-as-property | the metamorphic edit applies to every program; TBS 9.3 | fail: `Main.main.lam.*` symbols moved after symbol-dce |
| tests/idr/actions/accumulate | skipping every action is the identity | merge-into:tests/idr/actions (one data-driven test over IdrPassRoles.txt) | one row of a table held in ten files; RF one fact; TBS 1.1 | pass (older build) |
| tests/idr/actions/columns | as above | merge-into:tests/idr/actions (data-driven) | as above | pass (older build) |
| tests/idr/actions/deduplicate | as above | merge-into:tests/idr/actions (data-driven) | as above | pass (older build) |
| tests/idr/actions/narrow | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build) |
| tests/idr/actions/narrow-lanes | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build) |
| tests/idr/actions/returned-arguments | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build) |
| tests/idr/actions/stack | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build): idr-rc-cells leaves "operation's operand is unlinked" |
| tests/idr/actions/tail-loops | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build): idr-rc leaves an unlinked operand |
| tests/idr/actions/trmc | as above | merge-into:tests/idr/actions (data-driven) | as above | fail (older build) |
| tests/idr/actions/inner-steps | skipping an inner step verifies and differs | rewrite-as-property | "differs" is incidental; the contract is "same behaviour" (GAPS-2); TBS 1.1 | fail (older build) |
| tests/idr/contracts/break | the instrumentation names a pass that widens effects | keep | the discriminator of the contract checker (TBS 9.2 step 5: check the checker) | pass (older build) |
| tests/idr/contracts/break-linear | as above, linear-kept | keep | as above | pass (older build) |
| tests/idr/contracts/crash-sites | as above, crash-sites-not-added | keep | as above | pass (older build) |
| tests/idr/contracts/nested-run | idr-rc keeps its contracts step by step | keep | the only contract run on a whole idr-rc | fail (older build): `@both` returns `!idr.box` where its signature says `!idr.own<...>` |
| tests/programs/eval/memo-lazy | a memo cell is forced once | rewrite-as-property | one trace of the call-by-need model; TBS 9 | fail: live cells 20 |
| tests/programs/eval/memo-shared-stream | a shared stream is forced once per cell | rewrite-as-property | as above | fail: live cells 358 |
| tests/programs/eval/stream-share | as above | rewrite-as-property | as above | fail: live cells 29 |
| tests/programs/eval/lazy-branch-loop | a lazy value in a loop's branch | rewrite-as-property | as above | fail: live cells 3 |
| tests/programs/eval/lazy-list-branches | lazy list branches | rewrite-as-property | as above | fail: live cells 3 |
| tests/programs/eval/thunk-consumes-list | a thunk that consumes a list frees it | rewrite-as-property | as above | fail: live cells 1000003 |
| tests/programs/io/action-forced-twice | a by_name action runs at each force | rewrite-as-property | as above, with the output trace | fail: live cells 12 |
| tests/programs/partial/self-forcing-caf | a suspension forcing itself crashes | merge-into:the laziness property (dictionary) | the Running state is one named case of the model; TBS 4.4 | pass |
| tests/accept/action-after-effect | a library action runs after the effect before it | merge-into:the IO-trace property | program order is a model of traces; TBS 9 | pass |
| tests/accept/action-run-at-once | a library action runs once | merge-into:the IO-trace property | as above | pass |
| tests/programs/stack/mutual-pure-tail-calls | a mutual tail recursion in 1 MiB | merge-into:tests/programs/stack/tail-graph-property | one call graph of a generated family; TBS 4.2 | pass (expected modified in the worktree) |
| tests/programs/stack/mutual-io-if-case-with | as above, through IO | merge-into:tests/programs/stack/tail-graph-property | as above | pass |
| tests/programs/stack/foldlm-deep | deep foldlM | keep | a library function over a long input, constant-stack mark; the property is the mark | pass |
| tests/programs/stack/for-long-list | `for` over a long list | keep | as above | fail: crashes at 250000 elements, stdout empty |
| tests/programs/linear/leet-reverse-list | reverse in place, no count test | rewrite-as-property | input from a generated stdin, output against a list model; `tests-nothing` stays; TBS 9 | fail (cause not read) |
| tests/programs/linear/leet-merge-sorted | merge in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-insertion-sort | insertion sort in place | rewrite-as-property | as above, oracle: sorted permutation | fail (cause not read) |
| tests/programs/linear/leet-partition | partition in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-remove-duplicates | dedup in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-rotate | rotate in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-kth-from-end | unlink in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-palindrome-list | palindrome by reversing half | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/linear/leet-max-subarray | Kadane in one pass | rewrite-as-property | as above, model: max over all subarrays | pass |
| tests/programs/linear/leet-valid-parentheses | a stack in place | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/data/sortedmap | SortedMap operations | rewrite-as-property | model-based against an association list; TBS 9.1 | fail: compile timed out after "File name too long" dumps |
| tests/programs/data/sortedmap-map-after-insert | map after insert | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/data/sortedmap-opaque-key | an opaque key | rewrite-as-property | as above | fail (cause not read) |
| tests/programs/data/sortedmap-one-ord-two-ways | one Ord two ways | keep | a dictionary-identity example, not a value space | pass |
| tests/programs/data/sorted-set | SortedSet | rewrite-as-property | model-based against a sorted list | fail (cause not read) |
| tests/programs/data/rbtree | red-black tree inserts | rewrite-as-property | model-based; the invariants (black height, order) as output relation | fail: given equals expected but for the mark |
| tests/compiler/handoff-round-trip | three emitted modules round-trip | rewrite-as-property | the relation holds of every emitted module; fold it into `universal`; TBS 1.1 | fail: linarray-combinators no longer compiles (owned verifier on `linalg.generic`) |
| tests/programs/basic/loads-untrusted-unreached | an unreached untrusted module costs nothing | rewrite-as-property | a metamorphic relation over every reject fixture (GAPS-15) | pass |

---

## 3. Findings

### GAPS-1 `%foreign` and `%extern` in user code have no refusal fixture
- Category: infrastructure-gap (missing test of a stated contract).
  Severity: high.
- Paths: `tests/reject/` (no fixture), `compiler/src/IdrisMLIR/Frontend/Profile.idr:370-381`.
- Evidence: AGENTS.md: "The refusal is `unsupported` and names `%foreign`
  or the extern; never ignore the pragma." The code does it: `ExternDef _
  => unless (meansExtern (hooksOf full)) $ reject ... EscapeHatch
  ("%extern " ++ key ++ via here)` and `ForeignDef _ specs => ... Left r =>
  rejectWith r`. A grep of `tests/` for `%foreign` or `%extern` outside
  helpers finds only `registry/broken-entry/run` (a library's spec broken
  on purpose), `lib/prelude.sh` and `lib/profile.sh`. The ten
  `escape-hatch-*` fixtures cover assert_linear, assert_total, believe_me,
  idris_crash and holes. `spec/rules-covered` passes because the rule
  `escape hatch` has other fixtures: it counts rules, not the cases a rule
  promises.
- Section: TBS 9.3 (a missing check has no branch to reward; only a
  specification aims at it), TBS 1.1.
- Recommendation: three fixtures under the existing rule: a user
  `%foreign "C:puts,libc" puts : String -> PrimIO Int` reached from main;
  the same declared and unreached (accepted: FR-2); a user `%extern`
  declaration reached. Each `-- expect: escape hatch, line N` with
  `-- message: %foreign` or `-- message: %extern`. Then make
  `rules-covered` read a second list, the cases a rule promises (a
  `cases` field per rule in the ODS record the rule list is generated
  from), so a case with no fixture fails as a rule with none does (RF one
  fact: the cases are data beside the rule).

### GAPS-2 Optimization is optional (0002 I2) is checked only as "skipping everything is the identity"
- Category: wrong-or-missing-oracle. Severity: high.
- Paths: `tests/idr/actions/*.mlir` (10), `foreign/idr/include/idr/Transforms/Passes.td:24-27`,
  `tests/spec/no-behaviour-options/run:9`.
- Evidence: Passes.td: "optimization: every transform it makes is
  optional, an MLIR action; skipping any one, or the pass, leaves a valid
  module whose behaviour is the same but for the stack and the heap it
  needs". Every actions test is the same shape:
  `-mlir-debug-counter=idr-accumulate-countdown-count=0,...` then
  `diff %t.none.mlir %t.skipped.mlir` and `not diff %t.none.mlir
  %t.done.mlir`. That checks that a counter of 0 skips (an MLIR
  mechanism), not that a partial skip keeps behaviour, which is the
  promise and the only part that can find a bug. `inner-steps` checks
  "leaves a module that verifies and differs": "differs" is incidental
  (TBS 1.1: stronger than the contract), and nothing runs the module.
  `idris-mlir registers no debug counter` (spec/no-behaviour-options), so
  no e2e test can skip one today.
- Section: TBS 7 (a second implementation we own: the pipeline with fewer
  transforms), TBS 5 (swarm over which tags are skipped), TBS 1.1.
- Recommendation: one property, `tests/compiler/optional-transforms`: for
  each program of a corpus (the e2e fixtures with `expected-stdout`, and
  Fuzz's programs), emit the module once (idris-mlir stops at the handoff),
  then for k draws run `idris-mlir-opt --idr-contracts` over the
  pipeline with `-mlir-debug-counter=<tag>-skip=S,<tag>-count=C` for tags
  drawn from the optimization passes' action tags (about 30, listed by the
  role table, GAPS-6), and link the lowered module with idris-mlir (the
  Lowered path `Driver/Run.cpp` already accepts). Oracle: the unskipped
  build's stdout, exit status and crash cause, and live cells 0, run on
  the default stack (the role's own "but for the stack and the heap"
  caveat). Generator: Gen over (tag subset, skip, count), with swarm
  weights per run so one run skips mostly inlining and another mostly
  narrowing. A failure shrinks to one tag and one count, which names the
  transform: this is the bisect `tools/bisect.sh` does by hand, made a
  test. Then delete the ten identity tests: the identity is the k=all
  point of this property.

### GAPS-3 No program generator beyond closed expressions (0002 §9, deferred), so "never miscompile silently" is checked on fixtures alone
- Category: distribution. Severity: high.
- Paths: `tests/Fuzz.idr:1-48`, `tests/lib/fuzz.sh:12`, `tests/fuzz/seed-{1,2}`, proposals/0002 §9.
- Evidence: Fuzz's cases are "closed expressions over every primitive";
  "The `runtime` part holds ... the fixed-width integers, Double, Char, a
  small sum type, and strings only as output fusion writes them".
  `fuzz_cases=30`, two fixed seeds. 0002 §9 defers "The typed program
  generator over the subset (`Tm sig ctx ty`, `Prog` over live
  resources), swarm feature weights, EMI-style rewrites that keep meaning,
  campaigns with a Good–Turing stopping rule". Nothing generates data
  types, matches, closures, laziness, recursion, linear arrays or IO, which
  is where this wave's failures are (40 leak failures, 8 internal errors,
  16 programs refused that the base accepted, in test.log).
- Section: TBS 4.1 (construct, do not filter), TBS 4.2 to 4.4 (index the
  harness's invariants, represent invalid cases by name), TBS 5 (swarm),
  TBS 8 (Good-Turing over features), TBS 9.
- Recommendation: build the deferred generator on Gen as section 5 lays
  out; its first oracle is the property every compilation must satisfy:
  exit 0 with the generated program's value (known by construction, or
  computed by a small evaluator in the harness, 0002 O4), or exit 3 with
  exactly one rule from IdrRules.txt naming a line of the generated file;
  an internal error or a timeout is a bug. Its second oracle is GAPS-2.

### GAPS-4 Emit's quantities are never compared with Idris's TT
- Category: wrong-or-missing-oracle. Severity: high.
- Paths: `tests/lib/properties.sh:46-63`, `foreign/idr/lib/Transforms/Expect/Quantities.cpp:3-19`.
- Evidence: `quantities_kept` checks "every parameter of an idr.func and
  every constructor field has the quantity ... it has in the emitted
  module": the reference is the emitted module itself. If Emit writes a
  quantity-1 binder as many, or emits a quantity-0 argument, every check
  agrees with it. No `mlir.expect` or `mlir.check` under `tests/programs`
  or `tests/accept` mentions `!idr.lin` (grep), and the only `.mlir`
  files outside `tests/idr` holding `lin<` are stray build products in
  `tests/programs/arrays/*/build/exec/`. AGENTS.md: "Quantity 1 is a type,
  `!idr.lin<T>`" and "the frontend emits no parameter, field or argument
  for it".
- Section: TBS 7 (a specification turned into a checker), TBS 9.2 step 5
  (check that the system entered the state the model claims).
- Recommendation: a universal check with an independent source: the
  program's Core (the `core` artifact every build keeps) lists each
  definition's binders with their quantities; a checker in the runner
  (the Idris side, which already reads Core for `covers`) pairs each
  user definition's runtime binders (quantity 1 or ω) with the emitted
  function of that definition (found by name, as idr-expect's `names`
  does) and says: the number of parameters is the number of non-erased
  binders, and each linear binder is `!idr.lin`. Add it to `universal`.

### GAPS-5 The per-pass contracts and the lowered module's universal facts never run on a real compilation
- Category: infrastructure-gap. Severity: high.
- Paths: `tests/lib/lit.sh:79`, `tests/lib/properties.sh:71-83`, `foreign/idr/lib/Transforms/Contracts/Contracts.cpp`,
  `tests/compiler/handoff-round-trip/run`.
- Evidence: `lit.sh:79` rewrites `idris-mlir-opt ` to `idris-mlir-opt
  --verify-roundtrip --idr-contracts `: only hand-written dialect inputs
  get the five relations (quantities-kept, linear-kept,
  effects-not-widened, crash-sites-not-added, folds-balanced). 0002 §4.1:
  "`--idr-contracts` (a `cl::opt` of `idris-mlir-opt` only, never
  `idris-mlir`'s)". `universal` is `object_imports` plus
  `compilation_properties` (dumps verify, quantities kept), and "A check
  added to every compilation is added here". Not added: `linker-names`,
  `entry`, `aligned-access`, `lowered` (after idr-lower), `in-llvm` (at
  the end), `direct-calls` (after defunctionalization), `stage` (each
  dump at the stage IdrPassStages.txt says), `folds-balanced`, a byte
  round trip of the emitted module (done for 3 programs by
  handoff-round-trip, which now fails because one of them no longer
  compiles). Each is stated only on 4 to 8 hand-written `.mlir` files.
  Fuzz's programs get none of `universal` (fuzz.sh runs `folded` only).
- Section: TBS 7 (universal oracles are the cheapest oracle), TBS 1.1
  (a property, once stated without an input, runs on every input).
- Recommendation: one universal pass over the dumps every e2e compile
  already writes: re-run each step's input through `idris-mlir-opt
  --idr-contracts --pass-pipeline=<that step>` and compare with the next
  dump (the contracts then run on real programs at the cost of one more
  pipeline), and `idr-expect` with the lowered-module properties on the
  last dump and `stage=` on each. Apply `universal` to Fuzz's builds too.
  Delete handoff-round-trip once the round trip is universal.

### GAPS-6 The generated role and stage lists, "the one fact the tests read", are read by no test
- Category: harness-representation. Severity: medium-high.
- Paths: `foreign/idr/include/idr/Transforms/Passes.td:20-22, 46-48`, `foreign/idr/tools/idris-mlir-tblgen.cpp`.
- Evidence: Passes.td: "Every pass of the dialect is an IdrPass, which
  states its role, the one fact the tests read of it (IdrPassRoles.txt,
  written by idris-mlir-tblgen -gen-pass-roles)"; "the tests read both of
  every pass (IdrPassStages.txt ...)". A grep of `tests/`, `tools/`,
  `Makefile` and `compiler/src` for `PassRoles`, `PassStages`,
  `gen-pass-roles` and `gen-pass-stages` finds only the generator, its
  CMake rule and Passes.td. The ten actions tests and `pipeline/stages.mlir`
  hand-list passes and stages instead: a second copy of the table (RF one
  fact).
- Section: RF one fact, RF "a switch on a tag is a polymorphism not yet
  named"; TBS 1.1 (Winters: brittleness is a missing vocabulary).
- Recommendation: drive GAPS-2's property and a stage property from the
  lists: for every `optimization` row, its action tags are skippable
  (GAPS-2); for every row, a module at a stage other than `requires` is
  refused naming both stages (today one example, idr-demand, in
  `stages.mlir`); every `analysis` row changes no op (compare before and
  after modulo the facts it writes); every `check` row changes nothing.
  The action tags belong in the same generated list (each pass's tags
  beside its role), so no test spells one.

### GAPS-7 Guards, crashes and constant stack are stated by examples, one operand each
- Category: example-should-be-property. Severity: medium.
- Paths: section 2b's `bounds-*`, `guards-messages-*`, `crash-*`, `stack/*` rows.
- Evidence: six `bounds-*` programs, three linear ones, five
  `guards-messages-*` and four `semantics/crash-*` each check one operand
  ("array index out of bounds at Prog.idr:9:1"). The contract is a
  predicate (in bounds iff `0 <= i < n`; a guard's crash names its cause
  and its site; output before it is flushed, `crash-after-output`).
  `constant-stack` marks are on 8 programs; mutual tail calls are two
  fixtures, though idr-tail-calls promises cases they do not reach:
  results the target returns in memory, calls that take a pointer into
  the caller's frame ("stays a call"), and "a call from one cycle to
  another adds a frame once at most".
- Section: TBS 1.1 (DefaultConfigsArePrime), TBS 4.4 (represent
  invalid cases by name), TBS 8 (exhaust the small cases).
- Recommendation: (a) `index-property`: Gen draws (n, i) from a
  dictionary {INT_MIN, -1, 0, 1, n-1, n, n+1, INT_MAX} plus uniform,
  reads them on stdin, and the oracle is the predicate: the element, or
  exit 1 with the named cause and the written prefix. (b)
  `guard-property`: one table of guard kinds (the ODS's `idr.check.*`
  ops, generated, RF one fact), each with a generator of failing and
  passing operands. (c) `tail-graph-property`: Gen draws a call graph of
  k functions (k up to 5), each with a tail call to another chosen by a
  weighted `Fin k`, arguments and results of chosen widths including a
  record the target returns in memory, a counter on stdin; oracle: by
  construction (the visit sequence's checksum, computed in the harness)
  and a 1 MiB stack.

### GAPS-8 The arrays stage's semantic promises have no property
- Category: example-should-be-property. Severity: medium-high.
- Paths: Passes.td idr-columns, idr-structure-loops, idr-bufferize, idr-narrow-lanes; `programs/arrays/*`.
- Evidence: idr-structure-loops: "each element combined in index order,
  so that a float fold gives the same result on every target": no test
  states order (a sum of `1e16, 1, -1e16` is 0 or 1 by order). idr-bufferize:
  "each link of a thread is bufferized in place, always, so a copy there
  is an internal error ... never a rejection": `in-place` is stated on 8
  dialect files. idr-narrow-lanes: B "is the largest power of two from
  2^31 down to 2^8 at which every elementwise integer op ... fits": three
  examples, all failing on the dump directory's "File name too long".
  idr-columns: "the program is the same, held two ways at that boundary".
  `linarray-*` programs compute fixed inputs.
- Section: TBS 4.2 (the Cmd/Prog model), TBS 4.3 (do not type away the
  bug: encode the harness's invariants, not the compiler's), TBS 8 (move
  the bug into the box: randomize the bound).
- Recommendation: the flagship generator of section 5, a typed command
  model of linear arrays (`Cmd n m` over sizes, indices `Fin n`, plus
  `Stale` and `Wild` indices by name), run as one program per draw against
  a list model in the harness; with record elements for idr-columns,
  order-sensitive doubles for the fold order, and sizes drawn around 2^8,
  2^16, 2^31 boundaries (values, not lengths) for narrow-lanes. Oracles:
  the model's output; `in-place` on the bufferized dump; no internal
  error.

### GAPS-9 Laziness and effect order are stated by single traces
- Category: example-should-be-property. Severity: high (the leaks cluster here).
- Paths: section 2b's `eval/memo-*`, `stream-share`, `lazy-*`,
  `thunk-consumes-list`, `io/action-forced-twice`, `accept/action-*`.
- Evidence: idr-defunctionalize promises a memo cell forced once and
  shared, `idr.crash` on Running, and `by_name` for a label that "reaches
  an observable output"; AGENTS.md promises a trusted library's action
  runs "where the value is demanded, in program order with every other
  effect". The tests are single programs; seven of them fail now with
  live cells (20, 358, 29, 3, 3, 1000003, 12), which only the e2e leak
  check sees.
- Section: TBS 9.1 (a state machine you can search), TBS 6.2 (features:
  (thunk state, holders) is the right granularity).
- Recommendation: a call-by-need model in the harness (a term with `Delay`,
  `Force`, `Share`, an output action), generated by Gen; oracle: the
  model's output trace and its force counts (each memo label's body runs
  once, a `by_name` one at each force), crash on a self-force, and live
  cells 0. The fixtures above become the generator's dictionary of shapes.

### GAPS-10 Determinism and name stability are checked on eight fixed programs
- Category: example-should-be-property. Severity: medium.
- Paths: `tests/determinism/*`, `tests/lib/determinism.sh`, `spec/content-names`.
- Evidence: idr-optimize: "Each body is a function of its own body and its
  callees' final bodies, so the program is the same at every thread
  count." `determinism_runs='1 3 5 13 13'` on 8 programs. spec/content-names:
  "a name must not move when an unrelated definition changes", checked by
  one edit of one program (name-stability, failing: two
  `Main.main.lam.*` move).
- Section: TBS 1.1, TBS 9.3 (metamorphic relations need no oracle).
- Recommendation: as a sampled universal: each Fuzz and generated program
  compiled at its drawn thread count and at 1 (the fuzzer already draws a
  count, `--fuzz-program threads`, and compares nothing); and an edit
  relation: add an unreached definition to any program, then every symbol
  not made from it is unchanged and stdout is equal.

### GAPS-11 Integer, Nat and run-time strings are outside the fuzzer's runtime part
- Category: distribution. Severity: medium-high.
- Paths: `tests/Fuzz.idr:47-50`, `tests/Sem.idr:45-120`, `foreign/idr/unittests/{Hooks,Ranges,Words,Tagged}.cpp`.
- Evidence: Sem's tables are fixed widths only (`fixedTys`); Fuzz's runtime
  part has no Integer and "strings only as output fusion writes them, so a
  string anything takes apart is a literal". The runtime's bigs and
  strings are exhaustively boxed in C++ (runtime-bigs, runtime-strings),
  and idr-narrow's per-op rules in googletest; but a compiled web that
  idr-narrow narrows, its versioned loops, and string ops on strings read
  at run time are only examples (`programs/nat/*`, `string-functions`).
  `nat-large` leaks a cell now.
- Section: TBS 5 (distribution: what the search tries often), TBS 8 (the
  small-scope edge: 2^62 is the small range's bound, idris_rt.h).
- Recommendation: add Integer and Nat to Fuzz's runtime part, with leaves
  read from stdin (`s` lines) drawn from a dictionary around ±2^62, ±2^63,
  ±2^64 and the model the harness already computes for the static part;
  add `String` leaves read from stdin (the strings.cpp alphabet: a,
  U+00E9, U+20AC, U+1F600), with the scalar model of runtime-strings
  restated on the Idris side for the cases it covers.

### GAPS-12 "A linear binder does not imply unique heap ownership" has no adversarial test
- Category: example-should-be-property. Severity: medium.
- Paths: `reject/uniqueness-shared-rebuild`, `programs/arrays/ioref-keeps-old-value`, `accept/erased-*`.
- Evidence: AGENTS.md: "Erased does not mean constant. A linear binder does
  not imply unique heap ownership." idr-rc-exclusive's promise is the
  safety half: an exclusive grade only where the value holds the only
  reference ("never a dup, a constant other than a nullary one, or a stack
  cell"). One reject fixture and one IORef example state it.
- Section: TBS 4.3 (generate the legal histories the optimizer might
  mishandle).
- Recommendation: in the program generator, a `Share` command that keeps a
  second holder of a value before it is passed linearly, and an output
  relation: every holder still reads its old contents (no in-place write
  is observable through another holder). Erased: generate an erased index
  whose run-time witnesses differ between calls.

### GAPS-13 `no-closures` after defunctionalization restates the verifier in 35 files
- Category: cannot-fail / redundant. Severity: low.
- Paths: the 35 files besides its own test that state `no-closures` (26 under `idr/defunc`,
  `programs/eval/lazy-branch-loop/mlir.expect`, `lazy-list-branches/mlir.expect`).
- Evidence: Verify/Program.cpp's header: "past the higher stage ... no
  closure or suspension in a body"; the verifier runs after every pass.
  A module that idr-defunctionalize leaves at stage first with a closure
  fails verification before idr-expect reads it.
- Section: TBS (preamble: a universal oracle already covers it), RF "delete
  what the representation makes dead".
- Recommendation: keep `no-closures` only where it reads a module the
  verifier does not hold to the first stage (a stage `higher` input whose
  closures were all folded); drop it from the rest. The idr lanes decide
  per file.

### GAPS-14 Termination of compilation is stated by source search and a few examples
- Category: example-should-be-property. Severity: medium.
- Paths: `spec/totality`, `spec/no-fuel`, `accept/growing-specialization-function`,
  `eval/specialize-growing-accumulator`, `programs/partial/partial-divergent-call`.
- Evidence: idr-optimize: "A key that embeds a key on its own request
  chain is not made ... so every chain of requests ends"; "A budget only
  stops optimizing: no count rejects a program". AGENTS.md: a partial
  closed call runs at run time. The spec tests search the C++ for counts;
  behaviour is three programs. `fuzz/seed-1` timed out compiling today
  ("1: compile exit 124 | timed out after 60s"), as did two-levels'
  primitives.
- Section: TBS 3 (cliffs), TBS 8 (the small-scope hypothesis).
- Recommendation: a generator of growing static arguments (a recursion
  whose argument grows a constructor each call, at depth and width drawn
  per run) and of untaken divergent closed calls; oracle: the compile ends
  within the step limit (a timeout is the failure), the program prints the
  same as with `idr-specialize-clone` and `idr-optimize-node` skipped
  (GAPS-2). Also record each compile's wall time per generated size so a
  superlinear compile is a visible trend (`lib/timing.sh` records it, no
  test reads it).

### GAPS-15 The refusal corpus is not used metamorphically
- Category: example-should-be-property. Severity: medium.
- Paths: `tests/reject/*` (47 fixtures), `programs/basic/loads-untrusted-unreached`,
  `Frontend/Profile.idr:283-296`.
- Evidence: Profile.idr: "Every user definition that reaches a rejected
  definition is reported, each once, and the walk goes on ... so that
  every rejection found is independent of the others." Nothing composes
  two refusals. Reachability is one example. The polymorphism checker's
  classification (grown without bound vs bounded) is 9 reject and 13
  accept examples; 8 of the `accept/bounded-*` fail now (cause not read).
- Section: TBS 9.3, TBS 4.1 (generate with the answer known by
  construction).
- Recommendation: three relations over the reject corpus, no new oracle:
  (a) a fixture's offending definition kept but unreached from main
  compiles (exit 0); (b) two fixtures' offending definitions both reached
  give exactly the two refusals, each at its line; (c) a growth-scheme
  generator (a recursion whose type argument grows by k per round through
  a chain of m functions or families, with k drawn from {0, 1, 2} and the
  cycle shape drawn) whose verdict is known by construction: k = 0 on
  every edge of a cycle is accepted, any k > 0 on a cycle is
  `unsupported (polymorphism)` at the recursion's line.

### GAPS-16 Rules and cases owed or stale in the refusal coverage
- Category: stale-legacy / infrastructure-gap. Severity: medium.
- Paths: `tests/reject/without-fixture:14`, `reject/cycle-ioref-knot`, `reject/polymorphism-nested-data`.
- Evidence: `without-fixture` keeps `static argument`, `match` and
  `elaboration` as `owed`; `hook` is "elsewhere ... as
  tests/registry/base-surface and tests/registry/broken-entry do", while
  `tests/registry/base-surface` is staged for deletion in this worktree
  (git status `D tests/registry/base-surface/run`). idr-knots promises a
  refusal "where the program's own code makes one of its arrays, or else
  builds a value of a type on it, or else at the program": the third
  placement has no fixture; `cycle-ioref-knot` reports line 16 where its
  header says 18. `polymorphism-nested-data` fails as an Idris elaboration
  error ("Undefined name Builtin.Pair", "Undefined name Bool"): the fixture
  does not import Prelude under `--no-prelude`, so it tests nothing about
  polymorphism.
- Section: TBS 9.2 step 5 (a test must check it reached the state it
  claims), RF one fact.
- Recommendation: repoint `hook` to `registry/broken-entry` only (or keep
  base-surface); write the owed fixtures from 0002 §9's program for
  `static argument`; fix `polymorphism-nested-data`'s imports; add the
  third knot placement.

### GAPS-17 No spec test confines per-target cases
- Category: infrastructure-gap. Severity: medium.
- Paths: `foreign/idr/lib/IR/OpsPlatform.cpp:21-26`, `runtime/Platform/Posix/Files.cpp:61`.
- Evidence: AGENTS.md: "Nothing may assume x86, Linux, ELF, musl or a page
  size outside the one place the target is decided ... Per-target cases
  elsewhere are bugs." The tree's predicates today are the fold of the OS
  name from the module's triple and one `#if defined(__APPLE__)` in the
  POSIX platform layer, both defensible; nothing keeps the next one out.
  `spec/no-fuel` and `spec/zones` show the shape such a search takes.
- Section: TBS 9.3 (a specification aims at code that should not exist).
- Recommendation: `spec/target-confined`: the target predicates (`__x86_64__`,
  `__aarch64__`, `__APPLE__`, `__linux__`, `Triple::is*`, `isOS*`,
  literal triples, `4096`, `16384`) are allowed only in the target entry
  of CMakeLists.txt, `tools/bootstrap.sh`'s target section,
  `runtime/Platform/` and `lib/Target/`, each further use a failure
  naming its line.

### GAPS-18 Reference counting has a leak oracle on one path and no use-after-free oracle
- Category: wrong-or-missing-oracle. Severity: medium-high.
- Paths: `tests/lib/run.sh:16-45`, `runtime/Io/Ending.cpp:17-38`.
- Evidence: `run_ours`: "A crash writes no count, and nor does an exit
  with a status of the program's own (exitWith)". The owned verifier
  states "exactly once" statically; dynamically only the count at a
  normal exit is read. A freed cell read again, or a count decremented
  past zero on a persistent or freed cell, is caught only if it happens to
  crash. The leak oracle is doing real work: about 40 tests of this run
  fail on `idris-rt: live cells N`.
- Section: TBS 7 (a universal oracle, AddressSanitizer's role), TBS 11
  (co-design the system for testing).
- Recommendation: a checked runtime, chosen by the build, never by an
  option of the compiler (spec/no-behaviour-options): freed cells
  poisoned and quarantined, every decrement asserting a live counted
  cell, every take and recycle asserting its exclusivity claim
  (`idris_rt_is_unique`), live cells reported on every exit path. Run
  every e2e and generated program against it in `make test`.

### GAPS-19 idr-rc-stack's size bounds are untested
- Category: example-should-be-property. Severity: low-medium.
- Paths: Passes.td idr-rc-stack, `tests/idr/stack/*` (3).
- Evidence: "A cell of more than 256 bytes stays on the heap, and so do a
  function's cells past 1024 bytes, or 64 bytes for a function on a cycle
  of calls." The three stack tests place a small cell; no test reaches a
  bound. These bounds are what keeps a recursive function's frame small
  under the 1 MiB stack the constant-stack marks rely on.
- Section: TBS 8 (exhaust the small cases at the boundary).
- Recommendation: an idr-expect property `stack-bytes<=N` per function,
  universal with N = 1024 and 64 on cycles; and a generator of records of
  drawn sizes around 256 bytes in recursive and non-recursive functions.

### GAPS-20 Two small finite spaces are tested by examples where an exhaustive box is cheap
- Category: example-should-be-property. Severity: low.
- Paths: `toolchain/runtime-start`, `programs/io/exit-with`, `idr/obs/report-*`, `Driver/Outcome.cpp`.
- Evidence: the exit-status rule is "main's value is the exit status from 0
  to 255, and any other is a crash that names it" (runtime-start). The
  verdict rule (0002 R1) is "`Accepted < Refused < Internal`, the worst
  seen wins".
- Section: TBS 8 ("checking every input up to some small size turns 'no
  bug at this size' into a genuine theorem").
- Recommendation: a googletest box over every sequence of up to three
  diagnostics of the three severities (27 cases) against `max`; a
  runtime-start box over the root values {-1, 0, 1, 254, 255, 256,
  INT64_MIN, INT64_MAX}.

### GAPS-21 The verifier, the oracle every other test leans on, has no adequacy test
- Category: wrong-or-missing-oracle. Severity: medium-high.
- Paths: `foreign/idr/lib/IR/Verify/*.cpp`, `foreign/idr/lib/IR/*.cpp`, `tests/idr/verify/*` (20).
- Evidence: 41 of 93 diagnostics in `foreign/idr/lib/IR` have no dialect
  fixture whose expected text holds their opening words (estimate); two
  confirmed by hand: `OpsOwnership.cpp:211` "hands its reference to more
  than one use" and `Verify/Program.cpp:106` "recycles a token that no
  idr.take made" appear in no `.mlir` under `tests/idr`. The verifier is
  the universal oracle of `spec/verifier-every-pass`; a rule that never
  fires on a bad module is a hole every pass test inherits.
- Section: TBS 7 (the quality of testing is the quality of the oracle),
  TBS 9.2 step 5, TBS 4.4.
- Recommendation: a test pass, like `test-idr-break-contract`, that
  mutates a valid module by named operators (`drop-a-drop`, `dup-a-dup`,
  `use-linear-twice`, `grade-own-to-borrow`, `recycle-foreign-token`,
  `add-idr-attribute`, `closure-past-higher`, `effects-narrower-than-body`),
  each tied to the diagnostic it must produce; applied to the dumps of the
  e2e corpus at each stage, every mutant must be refused with its
  diagnostic. A diagnostic no operator reaches is listed, as rules are in
  `without-fixture`, with why.

### GAPS-22 Base's IO primitives have no simulated platform
- Category: infrastructure-gap. Severity: low-medium.
- Paths: `runtime/Platform`, `programs/io/*`, proposals/0002 §9 ("a
  simulated platform layer for the runtime's IO").
- Evidence: `programs/io/directory-listing`, `environment-arguments`,
  `files-roundtrip` fail now (directory-listing with live cells 7); each
  is one interaction with the real file system.
- Section: TBS 11 (bind the hidden inputs).
- Recommendation: the deferred simulated platform layer: the runtime's
  `Platform` interface backed by an in-memory file system whose failures
  (ENOENT, EACCES, short reads) are named `EnvChoice`s drawn by seed; the
  property is the errno and result contract of `idris_rt.h` per call.

### GAPS-23 The bootstrap fixed point is not a test
- Category: other. Severity: medium (future).
- Paths: proposals/README ("0005, the toolchain bump, whose strongest check
  is stage 2 = stage 3"), proposals/0003.
- Evidence: `make self` "has never finished"; the strongest differential
  oracle this compiler can have (itself compiled by itself compiles itself
  to the same bytes) is outside `make test`.
- Section: TBS 7 (a second implementation we own).
- Recommendation: once 0003 lands, a `make test` pool that compiles the
  frontend with stage 2 and compares stage 3's artifacts byte for byte, the
  same relation as determinism.

### GAPS-24 The fuzzer reports a relation as holding when nothing was compiled
- Category: cannot-fail (perception). Severity: high.
- Paths: `tests/lib/fuzz.sh:56-96`, `tests/fuzz/seed-1/output`.
- Evidence: test.log: "runtime: every build compiles, runs, exits 0 and
  writes nothing on stderr: failed / 1: compile exit 124 / ... / runtime:
  each case prints one value, whoever computes it: ok / runtime: every d
  line is folded: ok / runtime: each case over integers prints its
  documented value: ok". `fuzz_check` returns before the agree, folded and
  model checks when the compile fails, so their files stay empty and
  `fuzz_report` prints `ok`.
- Section: TBS 9.2 step 5 ("Otherwise the test can silently check
  nothing"), TBS 1.1.
- Recommendation: each relation reports the number of cases it judged and
  fails at zero (`agree: ok over 30 cases`); the search lane owns the fix.

### GAPS-25 The dump tree printer breaks compilation on long names
- Category: infrastructure-gap. Severity: medium-high.
- Paths: `tests/lib/mlir.sh` (`dump_options`), `tests/lib/e2e.sh:56-60`.
- Evidence: 27 tests fail with "Error while creating directory
  .../prog.dump/.../idr_func_Prelude.Interfaces.foldMap[Bits64, Bits64,
  Array.Core.Array (...)]...: File name too long"; `sortedmap`'s compile
  then times out. Every e2e compile dumps every step because `universal`
  reads the dumps, so a property harness choice decides whether a program
  compiles.
- Section: TBS 11 (the harness is co-designed: it must not change the
  system's behaviour), RF parse at the boundary.
- Recommendation: dump by step into one file per step (MLIR's
  `-mlir-print-ir-after-all` to a file, or the tree printer keyed by a
  hash of the symbol), so a symbol's length never reaches the file
  system; the machinery lane owns the fix.

---

## 4. Code bugs the tests reveal

Only what the outputs show; the cause is a reading, marked as such.

1. **A guard on strings lowers to a mistyped runtime call.**
   `programs/basic/guards-messages-str-index`, `guards-messages-str-head`,
   and two-levels' `prelude` part: "idris-mlir: internal error:
   'llvm.call' op operand type mismatch: expected operand type 'i64', but
   provided '!llvm.ptr' for operand number 0". Reading: idr-lower calls a
   runtime string entry (index or head, or the guard's crash with its
   site) with a pointer where the ODS-generated declaration takes an i64
   (a string handle or a length). The verifier catches it, so it is no
   silent miscompile.
2. **Memo cells, IORefs and arrays leak.** About 40 e2e tests end with
   `idris-rt: live cells N`, concentrated in laziness (`memo-lazy` 20,
   `memo-shared-stream` 358, `thunk-consumes-list` 1000003,
   `action-forced-twice` 12), IORefs (`ioref-closures` 1001, `ioref-counter`
   1) and records past the cell (`records-past-the-cell` 7). Reading: a
   forced memo cell's value, and an IORef's (an array of rank 0) element,
   are not released when their cell dies; `ioref-closures` leaking one per
   iteration fits a missing drop of the old element on write.
3. **The owned verifier refuses a `linalg.generic` that consumes a view.**
   `compiler/handoff-round-trip` (linarray-combinators): "'linalg.generic'
   op consumes a view, which holds no reference; a reference of its own
   (idr.dup) is consumed". Reading: idr-rc-grades does not give a linalg
   op's tensor operand a reference of its own at the boundary with
   upstream's ops; the exactly-once rule (VR-2) catches it.
4. **idr-rc-cells leaves an unlinked operand** (older build, test-idr.log):
   `idr/actions/stack`, `idr/actions/tail-loops`: "operation's operand is
   unlinked ... %2 = "idr.cell.init"(<<UNKNOWN SSA VALUE>>, ...)". Reading:
   the cell's `idr.cell.new` is erased or replaced before its
   `idr.cell.init` user is rewired. Commit a7bf77b4 ("Stack cells and
   recycles are built where their cells were") may have fixed it; not
   confirmed on this build.
5. **idr-rc under --idr-contracts leaves a function half graded** (older
   build): `idr/contracts/nested-run`: "'idr.return' op returns
   '!idr.box<...>' as result 0, but @both returns '!idr.own<...>'".
   Reading: the signature was graded before the body was placed; commit
   4c87dcc5 ("idr-rc-grades places every body under the grades it writes:
   no verifier runs on a half-graded program") describes this fix; not
   confirmed on this build.
6. **Acceptance regressions.** 16 tests outside `tests/reject` are refused
   with `unsupported`, e.g. `linarray-read-past-size`: "unsupported
   (polymorphism): Builtin.DPair.(#): a shape whose rank no analysis
   fixes: [__]", against 0004 §1.3 ("No change here refuses a program the
   base accepts"). Reading: the growth check, or the shape analysis it
   reads, treats a dependent pair whose first component is an array's size
   as unbounded.
7. **Two lambdas' names move when an unrelated definition changes.**
   `determinism/name-stability`: "symbols moved by an edit of Main.step:
   symbol-dce: Main.main.lam.b3fe1b35bfddebff Main.main.lam.fcf07a71f74952cf".
   Uncertain: if those lambdas call `Main.step`, a content hash over the
   callee's content legitimately moves them, and the test's exclusion
   (`grep -v '^Main\.step'`) is too narrow; otherwise the hash reads
   something order-dependent.
8. **`for` over a long list crashes.** `programs/stack/for-long-list`:
   "run: exit 1, expected 0" with no output. Reading: a loop that should
   run in constant stack does not (its stack exhausts at the repeated
   input), a constant-stack regression in idr-tail-loops or idr-tail-calls.

---

## 5. What a rebuilt scope looks like

The contracts above become a small number of properties, each over every
compilation or over a generated space, and the examples that only sample
them become the generators' dictionaries (TBS 1.2: the alphabet from the
unit tests).

**Universal, on every compilation (the e2e corpus, Fuzz's and the program
generator's builds).** One `universal` line, from data (RF one fact):
- the verifier after every pass (already), and `--idr-contracts`'s five
  relations replayed per step on the dumps (GAPS-5);
- Emit's quantities against the program's Core (GAPS-4);
- the lowered module's facts: `linker-names`, `entry`, `aligned-access`,
  `lowered`, `in-llvm`, `direct-calls` after defunctionalization, `stage`
  per IdrPassStages.txt, `stack-bytes` bounds (GAPS-19);
- the emitted module's byte round trip (generic form and bytecode);
- objects import nothing a program may not (already);
- run against the checked runtime: live cells 0 on every exit path, no
  use after free, every exclusivity claim true (GAPS-18).

**Relations over the corpus (metamorphic, no new oracle).**
- Optional transforms: any skip set of the optimization passes' action
  tags gives the same observable behaviour (GAPS-2), driven by
  IdrPassRoles.txt with the tags generated beside the roles (GAPS-6).
- Thread counts and process: byte-identical artifacts (sampled, GAPS-10).
- Unrelated edit: an unreached definition added moves no symbol and no
  output (GAPS-10, FR-2).
- Refusals: unreached offending code compiles; two refusals compose
  (GAPS-15).

**Generators (on Gen; swarm weights drawn per run; every case replayable
from its tape, shrunk by it; Good-Turing over named features to say when a
campaign stops, TBS 8).**
1. Closed expressions (Fuzz), widened: Integer, Nat and stdin strings in
   the runtime part, a dictionary around the small range's edges, the
   `closed-*` and `double-*` literals (GAPS-11). Oracle: the four forms
   agree; the integer model; the folded check.
2. Programs over data, matches, closures, laziness and recursion
   (`Tm sig ctx ty`, 0002 §9): data types of drawn arity (the 255/256/512
   boundaries, GAPS-7), closures through data, memo cells with a `Share`
   and an output action (GAPS-9, GAPS-12), growing static arguments
   (GAPS-14), tail-call graphs with in-memory results (GAPS-7). Oracle: a
   small evaluator in the harness (call-by-need with traces; the integer
   model for primitives, 0002 O4) or a value known by construction.
   Feature for coverage: (construct kind, stage reached, grade of the
   values involved), the TBS 6.2 middle granularity.
3. Linear arrays as a typed command model, `Cmd n m` with `Live`,
   `Stale` and `Wild` indices by name (TBS 4.2 to 4.4): reads, writes,
   push, pop, reserve, generate, map, fold over records and doubles.
   Oracle: a list model; the guard predicate on `Stale` and `Wild`; `in-place`
   on the bufferized dump; fold order; lane narrowing at drawn bounds
   (GAPS-8, GAPS-7's index property).
4. Growth schemes for the polymorphism rule, verdict known by
   construction (GAPS-15).
5. Verifier mutants, each operator tied to its diagnostic, over the
   corpus's dumps (GAPS-21).
6. Simulated platform `EnvChoice`s for base's IO (GAPS-22).

**Exhaustive boxes where the space is small (TBS 8).** The verdict lattice
(27 sequences), root exit values, the runtime's boxes (already), the
googletest boxes over ranges and words (already).

**What goes.** The ten action-identity tests (GAPS-2), `inner-steps`'s
"differs", `no-closures` where the verifier holds it (GAPS-13),
handoff-round-trip (GAPS-5), and the example programs of 2b marked
`merge-into` once their property runs and their inputs sit in its
dictionary. **What stays as examples:** one fixture per refusal rule and
per promised case of a rule (GAPS-1, GAPS-16), the contract checker's own
discriminators (`idr/contracts/break*`), resource-limit cases
(`crash-integer-shift-huge`, `stack-exhausted`), and long-input library
programs whose property is their constant-stack mark.
