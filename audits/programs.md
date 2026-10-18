<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane programs: `tests/programs/`

## 1. Header

- **Lane:** programs.
- **Scope:** every test under `tests/programs/`, all twelve topics: arrays, basic, data, eval,
  interfaces, io, linear, nat, partial, prelude, semantics, stack. For each I read the `Main.idr`
  and its other modules (`Prog.idr`, `Arith.idr`, `Lib.idr`, ...), the `run`, `expected`,
  `expected-stdout`, `expected-crash`, `expected-exit`, `stdin`, `mlir.expect`, `mlir.check`,
  `packages` and the marks (`heap-free`, `libm-lines`, `default-stack`, `constant-stack`,
  `live-cells`, `covers`). I also compared each last `output` with its `expected`.
- **What I read besides:**
  - Both guidelines in full: `.claude/skills/testing-by-search/SKILL.md`, cited **TBS §n** (TBS-pre
    is its preamble, on oracles and expected files), and `.claude/skills/representation-first/SKILL.md`,
    cited **RF** with the rule's name (1F1P = "One fact, one place", STR = "Every string that names a
    thing is a missing type", DEL = "Delete what the representation makes dead", SPOV2/3).
  - `AGENTS.md` (cited **AG**), `tests/README.md`, `tests/testutils.sh`, and these harness files:
    `tests/lib/{e2e,harness,compile,run,heap,mlir,expect,properties,prelude}.sh`,
    `tests/runner/one.sh` and `tests/Main.idr`.
  - The search and oracle sources: `Sem.idr`, the heads of `Gen.idr`, `Fuzz.idr` and
    `TwoLevels.idr`, the operation lists in `Prims.idr`, `tests/lib/bench.sh` and `tests/bench/*/run`.
  - The `idr-expect` property table (`foreign/idr/lib/Transforms/Expect/Lookup.cpp`),
    `Contracts.h`, and MLIR's `lib/Pass/IRPrinting.cpp` (the tree printer).
  - `tests/ACCEPTANCE.md` § tests/programs, git history of the fixtures, and the working-tree diff of
    `Specialization.cpp`.
- **Logs:**
  - `scratchpad/test.log`, the third full `make test`. It ended 16:47 and lists 128 programs passing
    and 252 failing, the 144 instances of `semantics/prim` among them.
  - The per-test `output` files, read 16:40 to 16:52.
  - A run of `only=programs/linear` was going on while I read (16:50 to 16:52). It ran after the
    unbuilt-in-git `Specialization.cpp` change, and its outputs replaced the linear ones. The linear
    statuses below are from that rerun.
  - Nothing was built or run for this audit.
- **Counts:**
  - **237 tests:** the 237 directories with a `run`. One of them, `semantics/prim`, runs as 144
    instances (`prim@<name>`). By topic: arrays 38, basic 20, data 28, eval 24, interfaces 13, io 16,
    linear 15, nat 5, partial 10, prelude 38, semantics 20 (prim included), stack 10.
  - 77 more directories hold only a stale `output` from tests that were deleted. They are not
    tests (PROG-20).
  - **Status at the last read:**
    - 140 directories pass. This counts the linear rerun and the two acceptances in the working
      tree (data/rbtree, io/system-info).
    - 97 fail. Among them is `prim`, whose 144 outputs each equal `expected` less its
      NEEDS-ACCEPTANCE line. The causes:

      | cause | tests |
      | --- | --- |
      | live cells at exit (a leak) | 36 |
      | compile timeout at 60 s | 20 |
      | `unsupported (polymorphism)` on a Linear.Vec / Array program | 12 |
      | compile exit 1 or 134 with the cause hidden behind tree-printer noise | 8 |
      | a pass property in mlir.expect fails | 7 |
      | `llvm.call` operand type mismatch | 6 |
      | heap-free mark broken | 5 |
      | the test's own source does not elaborate | 2 |
      | stack exhausted | 2 |
      | crash after main returned | 2 |
      | quantities-kept | 2 |
      | run-time hang | 1 |
      | covers | 1 |
      | rc verifier internal error | 1 |

      A test can have more than one cause. The hidden ones number 17 in all, 9 of them among the
      timeouts.
- **Verdicts:**

  | verdict | tests |
  | --- | --- |
  | keep | 117 |
  | rewrite-as-property | 41 |
  | rewrite | 19 |
  | merge-into | 43 |
  | delete | 17 |

## 2. Verdict table

**Status column:**

- **pass** means `output` equals `expected`.
- **mark** means the test carries a NEEDS-ACCEPTANCE line.
- **leak N** means `idris-rt: live cells N` was left on stderr.
- **hidden** means the compiler's own error is pushed out of the 40 lines `show` prints by
  tree-printer "File name too long" errors (PROG-1).

A test merged "into a generated fixture" names the fixture section 5 proposes: `data/layout@<n>`,
`data/adt` (the ADT and match generator, G1), `linear/lists` (G2), `arrays/vec-model` (G3),
`semantics/crash@<guard>` (G4), `prelude/double-text` (G5) and `eval/next-loop@<shape>` (the
parameterized latent-loop fixture).

### arrays (38)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| arrays/array-of-arrays | an IOArray of IOArrays compiles (no knot) and reads back | keep | stdout fully determined (TBS §1.3); distinct feature | fail: leak 5 |
| arrays/bounds-back-edge | a size grown round a loop keeps the read's check, crashes past the end | rewrite-as-property | one of six hand-picked (size, index) relations; a generator over those relations with the model "in range iff 0 ≤ i < len" covers all (TBS §1.1 Winters' prime example, §4.4, §8) | pass |
| arrays/bounds-mixed-calls | one function called with a true and a false size keeps its check | rewrite-as-property | same family as bounds-back-edge (TBS §8 exhaust small cases) | pass |
| arrays/bounds-negative-index | an index below 0 passes a size-only test, is caught | rewrite-as-property | same family (TBS §4.4 name the invalid case) | pass |
| arrays/bounds-negative-size | a negative-size array is empty, index 0 caught | rewrite-as-property | same family | pass |
| arrays/bounds-one-past | `i > size` lets i = size through, caught | rewrite-as-property | same family | pass |
| arrays/bounds-unrelated-size | a size of another array proves nothing | rewrite-as-property | same family; scaffolding (Arr, newArr, readInt) copied six times (RF 1F1P) | pass |
| arrays/buffer-bytes | Buffer as bytes: zeroed, Bits8 get/set, rawSize | keep | contract-determined stdout (TBS §1.3) | fail: leak 1 |
| arrays/buffer-ops | every Buffer width and kind, little-endian | keep | runtime contract; but `expected-stdout is a little-endian target's` is a target fact outside the target entry (PROG-19, AG) | fail: compile 124, hidden |
| arrays/buffer-range | a word past the buffer crashes with its cause | merge-into:semantics/crash@<guard> | one guard of the runtime's table, restated as text (RF 1F1P, PROG-14) | pass |
| arrays/ioarray-ends | first/last reads; "the access's own check is gone" | rewrite | the claim is unchecked: add `no-guards` (an idr-expect row) or drop it (TBS §1.1, PROG-6) | fail: leak 1 |
| arrays/ioarray-fannkuch | bench/fannkuch-redux prints, counts-nothing in its loops | merge-into:tests/bench (bench/fannkuch-redux/mlir.expect) | duplicates bench/smoke's stdout check (RF 1F1P, PROG-10) | fail: mark; compile 124 |
| arrays/ioarray-sieve | sieve; counts-nothing=@Main.mark @Main.count | rewrite | fails with "no function @Main.mark, and no copy of it": the property pins an inlining decision (TBS §1.1, PROG-4) | fail: leak 1; mlir.expect |
| arrays/ioref-closures | an IORef of composed closures becomes one sum | keep | stdout determined; a closure sum through a reference | fail: leak 1001 |
| arrays/ioref-counter | newIORef/modify/read/write | keep | smallest IORef program | fail: leak 1 |
| arrays/ioref-keeps-old-value | a kept read is not rebuilt in place (moves-out) | keep | the stdout itself is the oracle for the aliasing bug (TBS §7); moves-out is a Roots property | fail: leak 3; moves-out fails |
| arrays/ioref-modify-in-place | modifyIORef moves the record out | merge-into:arrays/ioref-record-in-place | same 32-field record and loop, one more spelling (RF 1F1P) | fail: leak 2; moves-out fails |
| arrays/ioref-record-in-place | read/rebuild/write moves out and reuses the cell | rewrite | "no function @Main.loop, and no copy of it": names a function the pipeline removed (PROG-4) | fail: leak 2; mlir.expect |
| arrays/lazy-elements | an array of suspensions forced twice | keep | memo semantics of Lazy through an array | fail: leak 4 |
| arrays/linarray-bubble | Linear.Vec bubble sort: no counts, no allocation | keep | real program with Roots-able properties | fail: mark; unsupported (polymorphism) MkBang/(#) |
| arrays/linarray-combinators | tabulate/map/zipWith/foldl as linalg, vectorized | rewrite | reads properties at `eliminate-empty-tensors` and `idr-returned-arguments`, "the first step after its group" (PROG-5) | fail: compile 1, hidden |
| arrays/linarray-fannkuch | bench/fannkuch-linear in place, count-free | merge-into:tests/bench (bench/fannkuch-linear/mlir.expect) | duplicates bench/smoke (PROG-10) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-fill-sum | Linear.Vec fill then sum: loops, no counts | keep | smallest Linear.Vec loop | fail: mark; unsupported (polymorphism) |
| arrays/linarray-lanes-exact | 64-bit lanes kept where 32 would be wrong | rewrite | output is a sharp oracle (TBS §7); its mlir.expect steps are pipeline-order incidental (PROG-5) | fail: compile 1, hidden |
| arrays/linarray-lanes-narrow | narrowed lanes below the bound give 64-bit results | rewrite | one source with two inputs: make it one fixture run on both stdins (RF 1F1P); steps (PROG-5) | fail: compile 1, hidden |
| arrays/linarray-lanes-wide | same above the bound | merge-into:arrays/linarray-lanes-narrow | byte-identical Main.idr (`diff` empty) (RF 1F1P) | fail: compile 1, hidden |
| arrays/linarray-map-fold-traverse | in-place map/foldl/traverse in row-major order | keep | order is observable in stdout (TBS §1.3) | fail: unsupported (polymorphism) (#) |
| arrays/linarray-push-pop | stack on Linear.Vec: growth policy, pop on empty | rewrite-as-property | a command sequence against a List model (TBS §4.2–4.4, §9; PROG-13) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-qsort | bench/qsort in place, count-free | merge-into:tests/bench (bench/qsort/mlir.expect) | PROG-10; its mlir.expect also pins "(partition itself is inlined into its one caller)" (PROG-4) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-read-past-size | a read at the size inside capacity is Nothing | rewrite-as-property | an invalid index by name in the vector model (TBS §4.4) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-reserve | reserve's growth rule, pushes into room | rewrite-as-property | vector model (TBS §9) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-rows-crash-order | a crashing fold step is not reordered by tiling | keep | crash order is a contract the stdout and stderr fully decide (TBS §1.3) | fail: compile 1, hidden |
| arrays/linarray-spectral-norm | bench/spectral-norm-linear structured, vectorized | merge-into:tests/bench (bench/spectral-norm-linear/mlir.expect) | PROG-10, PROG-5 | fail: mark; unsupported (polymorphism) MkPair |
| arrays/linarray-unionfind | bench/unionfind count-free | merge-into:tests/bench (bench/unionfind/mlir.expect) | PROG-10; "(union itself is inlined into the merging pass)" (PROG-4) | fail: mark; unsupported (polymorphism) |
| arrays/linarray-write-past-size | a write at a popped slot is Nothing | rewrite-as-property | vector model, invalid index by name (TBS §4.4) | fail: mark; unsupported (polymorphism) |
| arrays/st-sum | runST through unsafePerformIO | keep | the trusted-library rule (AG) end to end | fail: leak 1 |
| arrays/transpose-last-two-axes | transpose swaps the last two axes; twice is identity | keep | stdout determined; the involution is already stated in-program | fail: compile 134 (abort), hidden |
| arrays/vec-pop-then-push | pop clears its slot; push reuses it | rewrite-as-property | vector model (TBS §9) | fail: mark; unsupported (polymorphism) |

### basic (20)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| basic/base-trace | Debug.Trace's IO runs where the value is demanded | keep | the trusted-library effect-order rule (AG); order fully determined | pass |
| basic/chars | Char primitives; invalid scalars cast to 0; getChar is a byte | rewrite-as-property | the cast cases belong in Sem's computed table (TBS §7, §9); comment cites "the reference" (PROG-8) | pass |
| basic/do-let | let types dropped by TTC are inferred | merge-into:basic/hello | two-line smoke of the same path (TBS §1.1, RF 1F1P) | pass |
| basic/erased-argument-to-a-variable | a 0-quantity argument through a function variable | keep | erasure through higher order (AG "what Idris erased is no value") | pass |
| basic/force-delay | Lazy arguments, chosen branch | merge-into:basic/laziness | laziness checks the same choice plus a crashing unchosen branch | pass |
| basic/guards-messages-array-index | crash text and definition location for arrayGet | rewrite-as-property | one row of the runtime's guard table (PROG-14) | pass |
| basic/guards-messages-cast-nan | crash text for DoubleInt of NaN | rewrite-as-property | PROG-14 | pass |
| basic/guards-messages-div-zero | crash text for div by 0 | rewrite-as-property | PROG-14; duplicates semantics/crash-location byte for byte in its crash line | pass |
| basic/guards-messages-str-head | crash text for strHead "" | rewrite-as-property | PROG-14 | fail: llvm.call operand mismatch |
| basic/guards-messages-str-index | crash text for strIndex past end | rewrite-as-property | PROG-14 | fail: llvm.call operand mismatch |
| basic/hello | a program compiles, links, runs | keep | the smoke test; determinism also builds it | pass |
| basic/high-chars | putChar writes UTF-8 | keep | IO encoding contract, determined | pass |
| basic/laziness | the unforced branch never runs | keep | Lazy semantics with a crash as the witness (TBS §7) | pass |
| basic/let-after-output | a let after output is computed after it | keep | effect order; crash text and stdout decide it | pass |
| basic/loads-untrusted-unreached | loading modules with foreign functions is no refusal | keep | a refusal-boundary contract (AG `%foreign`) | pass |
| basic/multi-module | three modules | keep | the only multi-module e2e outside the Prog.idr pattern | pass |
| basic/numbers | fixed-width casts and prints | delete | covered by Sem's Convert tables and prelude/every-cast-export (TBS §1.2, RF 1F1P) | pass |
| basic/partial-cast-pointer | pointer casts below arity are closures | keep | runtime handles; note AG lists raw pointers outside the language, the handle reading is prelude.sh's | pass |
| basic/state-monad | a function-valued state monad 1000 binds deep | keep | defunctionalization of a non-interface monad | pass |
| basic/string-loop-one-value-twice | the scf.while forwarding regression | keep | stdout depends on the second value (a sharp oracle); no `upstream/` entry exists for WhileMoveIfDown | fail: llvm.call operand mismatch |

### data (28)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| data/bubble-sort | contified bubble reuses every cell | keep | self-checking (`sorted`, digest) plus a Roots-able property | fail: llvm.call operand mismatch |
| data/cfold | bench/cfold rebuilds in place | merge-into:tests/bench (bench/cfold/mlir.expect) | PROG-10 | pass |
| data/complete-split | a covering match has no default | rewrite-as-property | one enumeration of three; the ADT generator covers every arity (G1, TBS §4.1 construct, don't filter) | pass |
| data/dependent-pair-family-eta | eta-equal families are one instance | rewrite | no `import Prelude`: "Undefined name Nat", never elaborated (PROG-9) | fail: mark; frontend error |
| data/identity-weakening | index-erased identities are not called | keep | good vacuity guard: `one-clone` at emitted before `not-called` (TBS §9.2 step 5, "check the state was reached") | fail: leak 25 |
| data/layout-255-counted-fields | 255 refs fit the header count | rewrite-as-property | one point of a boundary; generate `data/layout@<n>` over n around 2^8 as the 70000-constructor test already generates its source (TBS §8; PROG-12) | pass |
| data/layout-256-counted-fields | 256 refs spill to a word | rewrite-as-property | PROG-12 | pass |
| data/layout-512-counted-fields | 512 refs | rewrite-as-property | PROG-12; 512 and 768 add nothing over 256 unless the count wraps, which a generator would search | pass |
| data/layout-768-counted-fields | 768 refs | rewrite-as-property | PROG-12 | pass |
| data/nbody | user-interface Double arithmetic, heap-free | keep | the user-dictionary numeric shape bench/nbody lacks | fail: heap-free (show_double allocates) |
| data/pidigits | bench/pidigits prints | merge-into:tests/bench/smoke | no mlir.expect at all: a pure duplicate of bench/smoke (PROG-10) | fail: mark; leak 90 |
| data/rbtree | bench/rbtree rebuilds in place | merge-into:tests/bench (bench/rbtree/mlir.expect) | PROG-10 | pass (accepted in working tree) |
| data/records | records in sums, closed | rewrite-as-property | closed tiny program; the ADT generator (G1) | pass |
| data/records-nested-past-the-cell | 3840 refs over nested records | rewrite-as-property | PROG-12 | fail: leak 9 |
| data/records-past-the-cell | 257 refs via two records | rewrite-as-property | PROG-12 | fail: leak 7 |
| data/shapes | erased witness and countdown "reduced all the same" | delete | stale compile-time-evaluation claim (PROG-7); erased argument covered by semantics/erased-witness | pass |
| data/sorted-set | Data.SortedSet operations | keep | base library contract, determined | fail: compile 124, hidden |
| data/sortedmap | Data.SortedMap operations, map in a record | keep | base library contract | fail: compile 124 |
| data/sortedmap-map-after-insert | one instance identity under map/keySet | keep | regression for a silent miscompile (TBS §1.2 "an escaped bug is a bug in the tests") | fail: mark; compile 124 |
| data/sortedmap-one-ord-two-ways | one Ord reached two ways | keep | implementation identity regression | pass |
| data/sortedmap-opaque-key | an opaque key with a hidden Ord | keep | export boundary regression | fail: compile 124 |
| data/spin-atom | a field read stays after the tag test | keep | regression whose oracle is a read past an atom (TBS §7) | pass |
| data/sum-of-seventy-thousand-constructors | tags past 16 bits | keep | already a generated boundary fixture (TBS §8) | pass |
| data/type-level-shapes | instances take as much shape as the type needs | keep | distinct specialization contract, determined | pass |
| data/vect | Vect from base, indices erased | keep | the inductive-family contract (AG "indexed vectors do not imply contiguous storage") | pass |
| data/vect-runtime-length-accumulator | one instance for any length | keep | instance-count regression | pass |
| data/vect-runtime-length-match | same, ended by a match | keep | distinct path | pass |
| data/void-field | a field of an empty type is never read | rewrite-as-property | G1 with Never fields (TBS §4.4) | pass |

### eval (24)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| eval/arity-raising | raised countdown writes output fused | keep | states `output-fused`; stdin reason in the comment is stale (PROG-7) | pass |
| eval/call-pattern | ack specialized for m = 3, 2, 1; "m = 0 folds" | rewrite | the specialization claim is unchecked and "folds" is stale (PROG-6, PROG-7) | pass |
| eval/closure-result-roundtrip | "evaluation gives the whole list as one constant" | rewrite | stale claim (PROG-7); keep the program, it now hangs (code bug) | fail: run timeout 124 |
| eval/compile-time-evaluation | closed calls run at run time | rewrite | name contradicts body; rename (closed-calls) and keep the generic Integer/Double recursions | pass |
| eval/dead-static | unused lets are dropped | delete | prints "only this": checks nothing it claims (TBS §1.1) | pass |
| eval/deep-list-constant | a 100000-element compile-time constant | delete | stale: no static evaluation (AG; PROG-7); what is left is a stack/ loop | pass |
| eval/deep-result | a closed call's deep result read linearly | delete | stale reading-depth claim; duplicates stack/list shapes | pass |
| eval/known-constructor | apply meets a known constructor | delete | stdout only; the defunctionalization suite owns the property (TBS §1.1) | pass |
| eval/latent-loop | specialization terminates on a latent loop breaker | merge-into:eval/next-loop@<shape> | five programs share get/set/fill/next (RF 1F1P); the shape of "the rest of the loop" is the parameter | fail: leak 3 |
| eval/latent-loop-accumulator | same with a growing accumulator | merge-into:eval/next-loop@<shape> | same | fail: leak 11 |
| eval/latent-loop-delay | same with a let-bound Delay | merge-into:eval/next-loop@<shape> | same | fail: leak 3 |
| eval/lazy-branch-loop | if-branch recursion builds no cell | keep | host of the parameterized fixture; states `no-heap-allocation=@Main.next` | fail: leak 3; mlir.expect (idr.con allocates in @Main.next) |
| eval/lazy-double | Lazy memoizes (2^40 otherwise) | keep | the timeout is the oracle for sharing | pass |
| eval/lazy-list-branches | a list of Lazy actions defunctionalized | merge-into:eval/next-loop@<shape> | same scaffolding | fail: leak 3 |
| eval/memo-lazy | top-level Lazy CAFs forced once | keep | CAF sharing, distinct from lazy-double's let | fail: leak 20 |
| eval/memo-shared-stream | stream cells keep their value; 3 cells of a cycle live | rewrite | the live-cells count 3 is representation-incidental; state "live cells do not grow with input" (PROG-16, TBS §1.1) | fail: leak 358 |
| eval/shared-result | let shares a 2^41-node tree | keep | timeout oracle for sharing | pass |
| eval/specialization | one copy per static function argument | delete | stdout only; specialization suite owns it (TBS §1.1) | pass |
| eval/specialize-growing-accumulator | a growing constant is generalized | rewrite | add `grows-nothing`/`specialized-once` so the property is stated and not only a timeout | pass |
| eval/static-evaluation | conditions "decided at compile time" | delete | stale-legacy (AG "Static normalization ... is not built"; PROG-7) | pass |
| eval/static-let | a let-bound lambda applied twice | delete | checks nothing (TBS §1.1) | pass |
| eval/stream-share | a self-referential stream forced once | merge-into:eval/memo-shared-stream | same contract, same live-cells pin | fail: leak 29 |
| eval/strings-at-compile-time | string primitives "at compile time" | delete | stale name; covered by fuzz and two-levels (RF 1F1P) | pass |
| eval/thunk-consumes-list | a forced thunk's list is reused in place | keep | states `reuses-in-place`; the leak check is the right universal oracle (TBS §7) | fail: leak 1000003 |

### interfaces (13)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| interfaces/auto-runtime-argument | an auto-implicit non-interface is a runtime argument | keep | distinct contract | pass |
| interfaces/choice | runtime choice of static values; "none needs the heap" | rewrite | add the `heap-free` mark or drop the claim (PROG-6) | pass |
| interfaces/implementation-a-hundred-definitions-deep | a 100-link chain reduces | keep | generated depth past an old cap (TBS §8) | pass |
| interfaces/implementation-index-function | Show (DPair a p) at erased indices | keep | distinct | pass |
| interfaces/implementation-runtime-length | Foldable (Vect n) at a runtime n | keep | distinct | pass |
| interfaces/implementation-runtime-scope | an implementation closing over a runtime scope | keep | the fork's own shape | fail: leak 1 |
| interfaces/implementation-shape-value | MkSize n built at a call | keep | distinct | pass |
| interfaces/interface-option-monad | a user Functor/Applicative/Monad | keep | user hierarchy with its own `>>=` | pass |
| interfaces/interface-ring-power | generic power over a Ring of matrices, heap-free | keep | numeric dictionary code with a stated mark | fail: heap-free (show_sint, str.append) |
| interfaces/interface-state-monad | higher-kinded interface with a default method | keep | distinct | pass |
| interfaces/interface-superclass | superclass field read, "no dictionary survives" | delete | claim unchecked; subsumed by every-interfaces-export (TBS §1.1) | pass |
| interfaces/method-runtime-implicits | runtime implicits reach the method function in place | rewrite | no `import Prelude` (and no `packages base` for Data.IORef): never elaborated (PROG-9) | fail: mark; frontend error |
| interfaces/show-rose-breakers | Show through a dictionary cycle; where it breaks | keep | program is sound; the comment's loop-breaker and "registry's column" claim is unchecked (PROG-6) | pass |

### io (16)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| io/action-forced-twice | a suspended IO forced twice runs twice | keep | effect semantics, determined by the counts | fail: leak 12 |
| io/clock-monotonic | monotonic, GC clocks Nothing | keep | prints only properties of host values (TBS §1.1 done right) | pass |
| io/directory-listing | createDir/openDir/nextDirEntry/removeDir | keep | sorted output, host-independent | fail: bus error after main returned; leak 7 |
| io/echo | getChar/putChar round trip | merge-into:io/prelude-input | same byte-reading path; comment cites "the reference" (PROG-8) | pass |
| io/environment-arguments | getArgs count, setEnv/getEnv/unsetEnv | keep | host-independent output | fail: compile 124, hidden |
| io/exit-with | exitWith status 3, stdout flushed | keep | exit contract | pass |
| io/file-bytes-echo | readBufferData/writeBufferData, fEOF | keep | byte-exact IO | pass |
| io/file-lines-eof | fEOF set after a read meets the end | keep | documented C-like semantics | pass |
| io/files-roundtrip | write, read back by line and chars, remove | keep | file contract | fail: compile 124, hidden |
| io/getline-ill-formed | maximal-subpart U+FFFD decoding | keep | contract-determined; a seed for a decoder model (G5) | pass |
| io/mandelbrot-pbm | bench/mandelbrot-pbm prints | merge-into:tests/bench/smoke | no mlir.expect: a pure duplicate (PROG-10) | fail: mark; leak 1 |
| io/output-fusion | getChar then one fused putStrLn | delete | no `output-fused` stated; arity-raising and char-list-pipeline state it (TBS §1.1) | pass |
| io/prelude-getline | getLine's line ends, `\r`, U+FFFD | keep | documented semantics | pass |
| io/prelude-input | getChar gives bytes, 255 at EOF | keep | documented semantics; host of echo | pass |
| io/prelude-io | printLn/putChar/print with runtime values | merge-into:prelude/every-io-export | every-io-export uses each export (RF 1F1P) | pass |
| io/system-info | os, isWindows, codegen, nproc | rewrite | its run script maps `*" macos "*) os=darwin` — a per-target case outside the target entry (AG; PROG-19) | pass (accepted in working tree) |

### linear (15)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| linear/leet-insertion-sort | insert moves cells, no count test | rewrite-as-property | a linear-list pipeline with a List model (G2, TBS §9) | pass (rerun) |
| linear/leet-kth-from-end | count by reversing in place, unlink | merge-into:linear/leet-reverse-list | the same rev/countRev scaffolding and property (RF 1F1P) | pass (rerun) |
| linear/leet-max-subarray | Kadane frees each cell, no test | rewrite-as-property | G2 | pass (rerun) |
| linear/leet-merge-sorted | merge relinks cells, TRMC under the constructor | keep | seed of G2's corpus (TBS §1.2 "alphabet from existing tests") | pass (rerun) |
| linear/leet-palindrome-list | half reversed in place | merge-into:linear/leet-reverse-list | same rev property | pass (rerun) |
| linear/leet-partition | both parts relinked in place | rewrite-as-property | G2 | pass (rerun) |
| linear/leet-remove-duplicates | kept cells reused, dropped freed | rewrite-as-property | G2 | pass (rerun) |
| linear/leet-reverse-list | rev reuses every cell, no test | keep | seed of G2; its mlir.expect says "The small example is evaluated at compile time" (PROG-7) | pass (rerun) |
| linear/leet-rotate | split and append relink in place | merge-into:linear/leet-reverse-list | rev/countRev again | pass (rerun) |
| linear/leet-valid-parentheses | linear stack push/pop move cells | rewrite-as-property | G2; its mlir.expect knows about "the copy of check specialized on the grade" (PROG-4) | fail: compile 124 |
| linear/linear-catch-all | a catch-all naming a linear scrutinee | keep | small linear match regression | fail: quantities-kept (bound field of @Main.f.case0 after defunctionalize) |
| linear/linear-library-lists | LList and LNat from libs/mlir-linear | keep | the shipped library's contract | pass (rerun) |
| linear/linear-lollipop | `-@` constructors equal explicit binders | keep | distinct | pass (rerun) |
| linear/linear-nested-match | nested patterns on a linear binder | keep | distinct | fail: quantities-kept (bound field of @Main.g) |
| linear/linear-string-iterator | the string iterator, heap-free loop | keep | the shipped library's contract | fail: compile 124 |

### nat (5)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| nat/bits8-past-127 | a Bits8 of 200 as Nat/Integer, no poison | keep | regression with a sharp oracle | pass |
| nat/nat-large | Nat crossing the small/big boundary | rewrite-as-property | Nat operations against an Integer model, exhausting values around 2^62, 2^63, 2^64 (TBS §8 exhaust the box) | fail: leak 1 |
| nat/nat-loop | Nat plus is linear, not quadratic | keep | timeout oracle for complexity | pass |
| nat/nat-parity | "mlir.expect states that some loop of the program holds no big" | rewrite | there is no mlir.expect: the claimed property is unchecked; add `word-loop=@Main.parity` (PROG-6) | pass |
| nat/nat-sum | natToInteger does not recurse per unit | keep | regression; comment "tri 500 ... is evaluated at compile time" stale (PROG-7) | pass |

### partial (10)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| partial/crash-after-output | output before a crash is written | merge-into:basic/let-after-output | same contract, let-after-output is the stronger case | pass |
| partial/deep-recursion | a million frames fit the reserved stack | keep | stack contract | pass |
| partial/lambda-terminates | lifted lambdas are total while main is not | rewrite | FileCheck regexes over printed attributes (`attributes {{[{].*}}total{{.*}}`); state with idr-expect `total` / `not-total` (TBS §1.1, AG "a brittle test means a missing test API") | pass |
| partial/loop-breakers | an SCC's breaker makes the other inlined | delete | claim unchecked; even/odd duplicates semantics/mutual-recursion and stack/mutual-pure-tail-calls | pass |
| partial/missing-case | a missing case crashes naming the definition | keep | crash contract | pass |
| partial/partial-divergent-call | closed partial calls stay calls | rewrite | `// CHECK: call @Main.spin(` breaks on any clone name; use `calls=@Main.main,@Main.spin` (TBS §1.1) | pass |
| partial/partial-untaken-divergence | closed partial calls run | merge-into:partial/partial-divergent-call | same spin/collatz pair | pass |
| partial/self-forcing-caf | a self-forcing suspension crashes, named | keep | runtime contract | pass |
| partial/stack-exhausted | stack exhaustion is a named crash after buffered output | keep | runtime contract | pass |
| partial/tail-loop-deep | 10^8 self tail calls in constant stack | keep | comment "Compile-time evaluation stops it" stale (PROG-7) | pass |

### prelude (38)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| prelude/cast-from-string | String casts read Idris literals; anything else 0 | rewrite-as-property | the grammar is documented: generate literals from it, model the parse, keep the named invalid cases (`.5`, `1E3`, `" 1"`) as seeds (TBS §4.4, §9) | pass |
| prelude/char-list-accumulated | reverse in place on accumulated lines | keep | Roots-able rc property on a real text shape | fail: compile 124 |
| prelude/char-list-pipeline | Benchmarks Game text shapes in place, output fused | keep | same | fail: compile 124 |
| prelude/double-basics | Double arithmetic/libm on a runtime value, heap-free | keep | the libm-lines mechanism's one user that needs it | fail: heap-free (cell.new in main.delay) |
| prelude/double-cast-nan | NaN to Int crashes after output | merge-into:semantics/crash@<guard> | one guard row (PROG-14) | fail: heap-free (show_sint/str.append) |
| prelude/double-infinities-nan | inf/-inf/nan text and reading back | rewrite-as-property | `prelude/double-text`: round trip and spelling over generated specials (PROG-15) | fail: leak 3 |
| prelude/double-subnormals | shortest text of subnormals | rewrite-as-property | PROG-15 | fail: leak 1 |
| prelude/double-ties | ties round to even | rewrite-as-property | PROG-15 | pass |
| prelude/every-basics-export | every Prelude.Basics export used and right | keep | `covers` is a real coverage oracle (TBS §6.2 features) | pass |
| prelude/every-builtin-export | every Builtin export | keep | same | fail: compile 124 |
| prelude/every-cast-export | every Cast implementation | keep | same | fail: llvm.call operand mismatch |
| prelude/every-eqord-export | every Prelude.EqOrd export | keep | same | fail: compile 124, hidden |
| prelude/every-interfaces-export | every Prelude.Interfaces export | keep | same | fail: compile 124, hidden |
| prelude/every-interpolation-export | every Prelude.Interpolation export | keep | same | pass |
| prelude/every-io-export | every Prelude.IO export | keep | same; host of prelude-io | fail: compile 124 |
| prelude/every-num-export | every Prelude.Num export | keep | same | pass |
| prelude/every-ops-export | every fixity of Prelude.Ops | keep | same | fail: compile 124 |
| prelude/every-prelude-export | the re-exports | keep | same | pass |
| prelude/every-primio-export | every PrimIO export | keep | covers now says `unsafePerformIO` unused where it said escape hatch (PROG-23) | fail: covers |
| prelude/every-show-export | every Prelude.Show export | keep | same; host of show-values and prelude-show | fail: compile 124, hidden |
| prelude/every-types-export | every Prelude.Types export | keep | same; its live-cells 2 is a pinned count (PROG-16) | fail: compile 124, hidden |
| prelude/every-uninhabited-export | every Prelude.Uninhabited export | keep | same | fail: internal error (idr-rc-exclusive on idr.yield) |
| prelude/integer-bits | Integer shifts and Data.Bits on runtime values | rewrite-as-property | Prims has the shift model (`bigShifted`); give the fuzzer's Integer part these amounts (TBS §7, §8) | pass |
| prelude/map-deep | map through a destination, constant stack | keep | constant-stack mark plus property; step `idr-narrow` chosen as "the next step" (PROG-5) | pass |
| prelude/math-showcase | numerical methods over a user Arith, heap-free | merge-into:prelude/prelude-math | same Mandelbrot/Newton/complex programs, and a second copy of data/nbody's Arith.idr (RF 1F1P) | fail: heap-free (cell.new) |
| prelude/negate-fixed-width | prim__negate at every width | merge-into:semantics/prim | add Neg to Sem's tables, whose values are computed from meaning (TBS §7, §9) | pass |
| prelude/postponed-lambdas | solved metavariables compile as their solutions | keep | distinct elaboration shape | fail: compile 1, hidden |
| prelude/prelude | Num/Eq/Ord/if/Maybe/cast/show basics | delete | subsumed by every-*-export; "evaluated at compile time" stale (PROG-7) | pass |
| prelude/prelude-lists | sums, folds, ranges, comprehensions | delete | subsumed by every-types-export and every-interfaces-export; stale claim (PROG-7) | fail: compile 1, hidden |
| prelude/prelude-math | complex numbers through Prelude interfaces, Mandelbrot, Newton | keep | the "written the way an Idris programmer would" program | pass |
| prelude/prelude-show | Show on composite runtime values | merge-into:prelude/every-show-export | subsumed (RF 1F1P) | fail: leak 3 |
| prelude/prelude-traverse | `*>`, for_, traverse_, sequence_ over IO | merge-into:prelude/every-interfaces-export | subsumed | pass |
| prelude/prelude-user-types | user Show/Eq/Ord/Monoid/Functor | merge-into:prelude/every-interfaces-export | every-*-export already defines user types with defaults; stale claim (PROG-7) | fail: compile 124, hidden |
| prelude/show-values | show parenthesizes negatives | merge-into:prelude/every-show-export | every-show-export covers each precedence | fail: leak 8 |
| prelude/split-prefixes | static empty pair keeps results exclusive | rewrite | "putChunks itself is inlined into the root by idr-optimize, so its body is checked there": pins inlining (PROG-4) | fail: leak 18; tests-nothing |
| prelude/string-functions | strings "still written straight to the output" | delete | the claim is unstated (no output-fused) (TBS §1.1) | pass |
| prelude/string-pack | pack/fastPack/fastConcat with non-ASCII | keep | base string builders, determined | fail: llvm.call operand mismatch |
| prelude/traverse-deep | traverse_ is a loop, constant stack | keep | constant-stack property; step `idr-narrow` (PROG-5) | fail: stack exhausted; constant-stack (io_bind, foldr recursion) |

### semantics (20 + prim)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| semantics/absurd-body | an impossible body never runs | merge-into:data/void-field | the same `data T = A Int \| B Never` shape; stale "Compile-time evaluation reduces it" (PROG-7) | pass |
| semantics/closed-char-to-string | `'\233'` writes UTF-8 | merge-into:tests/two-levels | a closed primitive term: two-levels' primitive corpus is its home (add the argument if absent) | pass |
| semantics/closed-double-infinity | 1.0/0.0 prints `inf` | merge-into:prelude/double-text | PROG-15; the Scheme comparison in its comment is no oracle (TBS-pre) | pass |
| semantics/closed-double-subnormal | 4.9e-324 prints 5e-324 | merge-into:prelude/double-text | PROG-15 | pass |
| semantics/closed-double-tie | the even tie | merge-into:prelude/double-text | PROG-15 | pass |
| semantics/closed-integer-shift | Integer shifts on constants | merge-into:tests/two-levels | closed primitive terms; fuzz's static part holds Integer | pass |
| semantics/closed-literal-conversion | literals through user FromString/FromDouble | keep | the literal desugaring at a user type is not a primitive term | pass |
| semantics/closed-shift-negative | Int8 shr by -1 shifts left and wraps | delete | Sem's `shiftAmounts` already holds -1 and -3 for signed types (`prim-int8-shr`) | pass |
| semantics/closed-string-to-int | "12.7" casts to 0 | merge-into:prelude/cast-from-string | the same row is line 47 of cast-from-string | pass |
| semantics/crash-div-zero | an unused quotient still crashes in program order | keep | effect-order contract, determined | pass |
| semantics/crash-integer-shift-huge | 1 << 2^64 is out of memory | keep | a runtime contract no table holds | pass |
| semantics/crash-location | division crash names Prog.idr:6:1 | merge-into:semantics/crash@<guard> | identical crash text to guards-messages-div-zero (PROG-14) | pass |
| semantics/crash-mod-zero | Bits8 mod by 0 crashes | merge-into:semantics/crash@<guard> | PROG-14 | pass |
| semantics/enum-stepping | next/index on an enum | rewrite-as-property | G1 | pass |
| semantics/erased-witness | proofs and linear args cost nothing | rewrite-as-property | G1 with 0 and 1 fields; quantities are universal's; stale comment (PROG-7) | pass |
| semantics/impossible-branch | an impossible clause is never taken | keep | a frontend shape G1 would not produce (impossible clauses come from proofs) | pass |
| semantics/literal-match | Int literal patterns with a default | rewrite-as-property | G1's literal patterns | pass |
| semantics/mixed-widths | four widths in one constructor | rewrite-as-property | G1/layout generator's field widths | pass |
| semantics/mutual-recursion | even/odd | merge-into:stack/mutual-pure-tail-calls | the stack test is the same pair, ten million deep, with a property | pass |
| semantics/prim | each Sem table's cases agree with the computed meaning, heap-free | keep | the model-based oracle (TBS §7, §9) | fail: mark only (all 144 equal) |

### stack (10)

| path | claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| stack/foldlm-deep | left-nested binds a million deep fit the program stack | keep | `default-stack` documents why | pass |
| stack/for-long-list | for_ in constant stack | keep | the constant-stack mark is a real perception of stack growth (TBS §6.2) | fail: stack exhausted |
| stack/forever-until-crash | forever runs until a missing case | keep | expected-stdout restates the factor 1100 as 1100 dots (PROG-17) | pass |
| stack/io-loop-through-helper | IO loop through mutual functions and a helper | keep | expected-stdout restates the factor 10000 as 10000 lines (PROG-17) | fail: segfault after main returned; leak 30017 |
| stack/list-length | length is a loop | keep | step `idr-narrow` "the next step" (PROG-5) | pass |
| stack/mutual-io-if-case-with | tail calls through if/case/with in IO | keep | distinct shapes | pass |
| stack/mutual-pure-tail-calls | mutual pure tail calls are guaranteed tail calls | keep | host of semantics/mutual-recursion | pass |
| stack/replicate-take-deep | TRMC replicate and take | keep | the leak is the bug (TBS §7 universal oracle) | fail: leak 10000000 |
| stack/sequence-deep | sequence_ builds deep, runs flat | keep | `default-stack` documents why | pass |
| stack/when-unless-loops | when/unless loops | keep | distinct shapes | pass |

## 3. Findings

**PROG-1. The tree printer's noise hides the compiler's error.**
- **Category:** perception. **Severity:** high.
- **Paths:** 17 tests, all marked "hidden" in the table:
  - arrays/buffer-ops, linarray-combinators, linarray-lanes-exact, linarray-lanes-narrow,
    linarray-lanes-wide, linarray-rows-crash-order, transpose-last-two-axes;
  - data/sorted-set; io/environment-arguments, io/files-roundtrip;
  - prelude/every-eqord-export, every-interfaces-export, every-show-export, every-types-export,
    postponed-lambdas, prelude-lists, prelude-user-types.
- **Evidence:** in `tests/programs/prelude/prelude-lists/output`:
  ```
    | Error while creating directory .../prog.dump/builtin_module_no-symbol-name/idr_program_$idris-mlir.root/idr_func_Prelude.IO.printLn[Builtin.Pair Prelude.Basics.Bool Prelude.Basics.Bool, PrimIO.IO, ...];5f82a588bb0a2447: File name too long
  ```
- **Why the real error is lost:**
  - `dump_options` turns on `--mlir-print-ir-after-all --mlir-print-ir-tree-dir`. MLIR's
    `FileTreeIRPrinterConfig` (IRPrinting.cpp:253-296) makes one directory per symbol, and a
    specialized instance's name is longer than NAME_MAX.
  - The error is not fatal: `createTreePrinterOutputPath` returns nullptr and the pass goes on. So
    the exits (1, 124, 134) are the compiler's own.
  - But `show` (`head -n 40`) is full of printer lines, so the test never says why the compile failed.
    For transpose-last-two-axes the exit is 134, an abort, and its cause is invisible.
- **Guidelines:** TBS §6 (what the harness can notice); TBS §12 ("a testing failure is
  information about the testing infrastructure").
- **Recommendation:**
  - Print only the top-level steps a fixture reads (`--mlir-print-ir-after=<the passes mlir.expect names>`),
    never the function-nested passes. README says a nested pass "is no step", so those dumps are
    never read.
  - Show the tail of `compile.err` with printer lines filtered.

**PROG-2. The universal quantities check keys binders by source location.**
- **Category:** harness-representation. **Severity:** high.
- **Paths:** `tests/lib/properties.sh` (`quantities_kept`), the linear topic, and
  `foreign/idr/lib/Transforms/Specialize/Specialization.cpp`.
- **Evidence:**
  - properties.sh: "A binder is found by its source location, the name the frontend gave it over
    its definition's span".
  - The last full run failed 12 linear tests with lines like "parameter 1 of
    @Main.isort.spec.6453848ad597e4db has quantity w, and Idris proved 1".
  - The working-tree fix to the *compiler* moves the locations so the check stops misreading them:
    "a hole inside a pattern is a binder of the pass's, at the function's location, which no binder
    of Idris's has, so no check reads it as the parameter it was taken out of". After it, 10 of the 12
    pass.
  - linear-catch-all and linear-nested-match still fail with "bound field 0 of @Main.f.case0 has
    quantity w" after idr-defunctionalize.
- **What is wrong:**
  - The oracle's notion of identity is a location, which is a discardable attribute. AG: "A fact
    kept in a discardable attribute can be dropped silently; do not keep one there."
  - The same relation is checked twice: in-process by `ContractInstrumentation` (Contracts.h:
    "compare each function the pass kept with its copy"), and from dumps by properties.sh.
- **Guidelines:** RF 1F1P ("one analysis computed in two places"); RF STR (a location used as a
  name); TBS-pre (the verifier and pass contracts are the universal oracles).
- **Recommendation:**
  - Give idris-mlir a test switch that installs `ContractInstrumentation`, which "idris-mlir never
    does" today.
  - Delete the dump-based `quantities_kept` and `dumps_verify`. A binder's quantity is its type
    (`!idr.lin<T>`); compare it pass to pass by the function and position the instrumentation
    holds, not by location.

**PROG-3. The universal check re-runs the tools once per dump.**
- **Category:** harness-representation. **Severity:** medium.
- **Paths:** `tests/lib/properties.sh` (`dumps_verify`, `quantities_kept`), `tests/lib/e2e.sh`.
- **Evidence:**
  - "every module dumped after a step parses and verifies again" runs `idris-mlir-opt` once per
    dump, and `expect_holds` runs again per dump.
  - The timing record shows `programs__basic__hello` compiling in 2606 ms with dumps, while
    bench/smoke's whole programs compile in 1238–1751 ms without them.
  - 20 program compiles hit the 60 s `step_limit`.
- **Guidelines:** TBS §7 (universal oracle in-process: a sanitizer, not a re-parse); RF "Use the
  infrastructure: PassInstrumentation".
- **Recommendation:** as PROG-2. Measure the timeouts with `tools/compile-times.sh` before blaming
  the compiler.

**PROG-4. Properties are stated of helper functions the inliner may remove.**
- **Category:** brittle-overspecified. **Severity:** high.
- **Paths:**
  - These fail on it today: arrays/ioarray-sieve, arrays/ioref-record-in-place.
  - These encode inlining in their comments: prelude/split-prefixes, arrays/linarray-qsort,
    arrays/linarray-unionfind, linear/leet-valid-parentheses.
- **Evidence:**
  - From the outputs: "expected counts-nothing: no function @Main.mark, and no copy of it" and
    "expected moves-out: no function @Main.loop, and no copy of it".
  - From the comments:
    - split-prefixes/mlir.expect: "putChunks itself is inlined into the root by idr-optimize, so its
      body is checked there".
    - linarray-qsort: "(partition itself is inlined into its one caller)".
    - unionfind: "(union itself is inlined into the merging pass)".
    - leet-valid-parentheses: "the call on the generated input goes to the copy of check specialized
      on the grade".
- **What is wrong:** README promises that "a function a property is stated of is named by its Idris
  definition, which names every copy made of it". Inlining leaves no copy. So these tests check the
  inliner's choices, which the contract leaves open.
- **Guidelines:** TBS §1.1 (an assertion stronger than the contract); Winters' second point (the
  vocabulary is too weak).
- **Recommendation:** give `counts-nothing`, `tests-nothing` and `reuses-in-place` a Roots form ("in
  everything reachable from @root, wherever it was inlined"), as `no-heap-allocation` has. Then state
  the rc properties of a program of its root.

**PROG-5. Properties are read at the step after a group, because a group dumps nothing.**
- **Category:** brittle-overspecified. **Severity:** medium.
- **Paths:**
  - arrays/linarray-combinators, linarray-lanes-exact, linarray-lanes-narrow, linarray-lanes-wide,
    linarray-spectral-norm (they read at `eliminate-empty-tensors` and `idr-returned-arguments`);
  - stack/list-length, stack/replicate-take-deep, prelude/map-deep, prelude/traverse-deep (they read at
    `idr-narrow`).
- **Evidence:**
  - "The structuring runs over the functions in a group, which dumps no module, and so does the
    vectorization: each property is read at the first step after its group."
  - "idr-tail-loops runs over the functions in a group, which dumps no module; idr-narrow, the next
    step, is the first to show them."
- **What is wrong:** a pass added or moved between the group and that step changes what is read,
  or fails the lookup ("no module dumped after").
- **Guidelines:** TBS §1.1; RF 1F1P (the pipeline order is held by the pipeline and again by
  the tests).
- **Recommendation:** dump, or check, at group boundaries. The contract instrumentation already
  treats "a pass on each function ... as the group its nest runs on the program". Or name the
  stage (`stage`, an idr-expect row) rather than a pass.

**PROG-6. The property a test claims is not stated anywhere.**
- **Category:** checks-nothing. **Severity:** medium.
- **Paths and the unchecked claim:**

  | test | what it claims |
  | --- | --- |
  | nat/nat-parity | "mlir.expect states that some loop of the program holds no big at all", but there is no mlir.expect |
  | arrays/ioarray-ends | "the access's own check is gone" |
  | interfaces/choice | "none needs the heap", with no heap-free mark |
  | eval/call-pattern, eval/specialization, eval/known-constructor | specialization and known-constructor rewrites |
  | eval/dead-static, eval/static-let | output only |
  | io/output-fusion, prelude/string-functions | output fusion, never stated |
  | partial/loop-breakers | loop-breaker choice |
  | interfaces/interface-superclass | "no dictionary survives" |
  | interfaces/show-rose-breakers | where the cycle breaks |

- **What is wrong:** each passes on its stdout alone. The thing its comment names can regress
  unseen.
- **Guidelines:** TBS §1.1; TBS §9.2 step 5 ("Otherwise the test can silently check nothing").
- **Recommendation:**
  - State the claim where idr-expect has the row: `word-loop`, `no-guards`, `output-fused`,
    `one-clone`, `specialized-once`, `applies`.
  - Otherwise delete the test, as the table does for eight of them.

**PROG-7. Comments and names describe compile-time evaluation, which is not built.**
- **Category:** stale-legacy. **Severity:** medium.
- **The rule:** AG says "A closed call runs at run time. Static normalization (proposal 0007) is
  what would fold one, and it is not built."
- **Paths:**
  - eval/static-evaluation, deep-list-constant, deep-result, strings-at-compile-time,
    closure-result-roundtrip, call-pattern, arity-raising, compile-time-evaluation (named so);
  - prelude/prelude, prelude-lists, prelude-user-types, prelude-math; nat/nat-sum;
    partial/tail-loop-deep;
  - semantics/absurd-body and erased-witness, data/shapes ("Compile-time evaluation reduces it all
    the same");
  - data/identity-weakening; linear/leet-reverse-list's mlir.expect ("The small example is evaluated
    at compile time").
- **A related idiom:** about 40 programs read a single digit from stdin "so that the call is not
  evaluated at compile time". The reason is gone, though the inputs still do no harm.
- **Guidelines:** TBS §1.1 (a test whose stated contract is not the code's); RF DEL ("the test
  that checked the impossible state").
- **Recommendation:**
  - Delete the five whose whole subject was static evaluation.
  - Rewrite the comments of the rest. The eval topic's pool line ("closed calls, specialization and
    arity raising") becomes "specialization and arity raising".

**PROG-8. Comments still appeal to the Chez reference.**
- **Category:** wrong-or-missing-oracle. **Severity:** low.
- **Paths:** basic/chars, io/echo, basic/let-after-output, semantics/closed-double-infinity.
- **Evidence:**
  - "The Prelude's putChar agrees with the reference only on ASCII".
  - "as the stock backend computes it".
  - "not the `+inf.0` of the Scheme that runs Idris's evaluator".
  - basic/chars' claim also contradicts basic/high-chars, which checks putChar writes UTF-8.
- **Guidelines:** TBS-pre (Chez is no oracle; the runtime's documented semantics is).
- **Recommendation:** state each expectation from the runtime's documentation, and remove the
  comparisons.

**PROG-9. Two tests were never compiled.**
- **Category:** stale-legacy (never ran). **Severity:** high.
- **Paths:** data/dependent-pair-family-eta, interfaces/method-runtime-implicits.
- **Evidence:**
  - Both lack `import Prelude`, which every other Main.idr has. The output shows:
    ```
    Main.idr:11:10: error: ... Undefined name Nat
    data Q : Nat -> Nat -> Type where
    ```
  - method-runtime-implicits also imports Data.IORef with no `packages` file.
  - Commit 3934cc0c says of these fixtures "On every fixture through the frontend on Chez: status,
    stdout and stderr identical".
- **What is wrong:** each guards a fixed silent miscompile, and neither can run as written.
- **Guidelines:** TBS §1.2 (an escaped bug's test must be able to find it); RF DEL.
- **Recommendation:** add the imports and accept on a build. Until then the two miscompiles are
  unguarded.

**PROG-10. The fixtures built from bench/ duplicate bench/smoke.**
- **Category:** redundant. **Severity:** medium.
- **Paths:**
  - data/cfold, data/pidigits, data/rbtree;
  - io/mandelbrot-pbm;
  - arrays/ioarray-fannkuch, linarray-fannkuch, linarray-qsort, linarray-spectral-norm,
    linarray-unionfind.
- **Evidence:**
  - Each `run` copies `$root/bench/<name>/Main.idr` and checks stdout on a small input.
  - `bench_smoke` does the same for every benchmark: "builds with this compiler and, on a small
    input, prints the output recorded for it".
  - pidigits and mandelbrot-pbm add nothing else at all.
- **Guidelines:** RF 1F1P (the program's recorded output in two places).
- **Recommendation:**
  - Move each fixture's mlir.expect beside its benchmark (`bench/<name>/mlir.expect`).
  - Have `bench_smoke` run `e2e_io` on each, so the universal checks and the properties run there.
  - Delete the nine fixtures.

**PROG-11. Hand-picked primitive examples duplicate the oracles that already cover them.**
- **Category:** redundant / example-should-be-property. **Severity:** medium.
- **Paths:** semantics/closed-* (8), prelude/negate-fixed-width, basic/numbers, prelude/integer-bits,
  basic/chars.
- **Evidence:**
  - Sem's tables include `shiftAmounts ... if t.signed then within ++ [-1, -3]`, which is
    closed-shift-negative's case.
  - two-levels' corpus is "every primitive of `Prims.prims`, applied to each of its argument sets".
  - The fuzzer writes every closed expression "four ways", the direct `d<n>` form being
    "literals ... so the folders compute it".
- **Guidelines:** TBS §7 (a computed or second-implementation oracle beats a recorded value);
  RF 1F1P.
- **Recommendation:**
  - Add Neg and the Char casts to Sem's computed tables.
  - Give two-levels the few argument values these tests hold (`'\233'`, the huge Integer shifts).
  - Delete the examples.

**PROG-12. The cell-header boundary is tested at four hand-picked points.**
- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:**
  - data/layout-255-counted-fields, layout-256-counted-fields, layout-512-counted-fields,
    layout-768-counted-fields;
  - data/records-past-the-cell, data/records-nested-past-the-cell;
  - semantics/mixed-widths.
- **Evidence:**
  - "A cell's header counts its object slots in 8 bits", stated in four nearly identical files of
    254 to 768 hand-written `String` fields.
  - sum-of-seventy-thousand-constructors already generates its declaration with awk from one
    number.
- **Guidelines:** TBS §8 (exhaust small cases at the boundary; "move a bug into the box", by
  randomizing the constant rather than fixing it); RF 1F1P.
- **Recommendation:**
  - One parameterized fixture, `data/layout@<n>`, as `semantics/prim@` is, whose source is
    generated for n in {1, 254, 255, 256, 257, 511, 512, 513, 768}.
  - Field kinds and nesting depth are drawn by Gen.
  - The oracle is the value the generator read back.

**PROG-13. The Linear.Vec API is tested by five hand-written sequences.**
- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:** arrays/linarray-push-pop, linarray-reserve, linarray-read-past-size,
  linarray-write-past-size, vec-pop-then-push.
- **Evidence:** each is one sequence of push/pop/reserve/read/write printing sizes and capacities,
  for example `[(1, 4), (2, 4), (3, 4), (4, 4), (5, 8), ...]`.
- **Guidelines:** TBS §4.2–4.4 (commands indexed by state, with invalid cases named: the SockPuppet
  model); TBS §5 (swarm weights); TBS §9 (a model as oracle).
- **Recommendation:** a generated command sequence.
  - The harness's commands are indexed by the size.
  - Out-of-range indices are named (`AtSize`, `PastSize`, `InCapacity`, `Wild`).
  - The oracle is a List model with the documented capacity rule.
  - Per run, Gen draws Weights over the commands.

**PROG-14. The runtime's crash messages are restated in fixture after fixture.**
- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:**
  - basic/guards-messages-* (5);
  - semantics/crash-location, semantics/crash-mod-zero;
  - prelude/double-cast-nan; arrays/buffer-range;
  - the six arrays/bounds-* repeat `array index out of bounds`.
- **Evidence:**
  - `expected-crash` holds `division by zero at Prog.idr:6:1` in both
    basic/guards-messages-div-zero and semantics/crash-location.
  - The texts are the runtime's strings, spelled again in more than ten files.
- **Guidelines:** RF 1F1P, RF STR (a cause written as text in many places); TBS §8 (exhaust a
  small table).
- **Recommendation:** a parameterized `semantics/crash@<guard>`, generated from the runtime's guard
  table, as Sem.names drives `prim@`. Each guard is run with and without output before it, and the
  text is read from the runtime's one table.

**PROG-15. Double text is tested by examples where a round-trip property belongs.**
- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:** prelude/double-subnormals, double-ties, double-infinities-nan;
  semantics/closed-double-infinity, closed-double-subnormal, closed-double-tie.
- **Evidence:** "with the fewest significant digits that read back as it", and "the one whose last
  digit is even is written".
- **Guidelines:** TBS §1.1 ("the property he actually cares about"); TBS §7 (a specification
  turned into a checker).
- **Recommendation:** `prelude/double-text`, over Doubles that Gen draws from named classes
  (subnormal, tie, power of two, inf, nan, signed zero), checks:
  - `cast (show d)` is bit-identical to d, nan excepted;
  - no shorter digit string reads back as d;
  - ties are even.

**PROG-16. Live-cell counts are pinned to exact numbers.**
- **Category:** brittle-overspecified. **Severity:** low.
- **Paths:** eval/memo-shared-stream (3), eval/stream-share (3), prelude/every-types-export (2).
- **Evidence:** "The top-level stream is a cycle, and reference counting does not collect it, so
  these cells are live when main returns".
- **What is wrong:** how many cells a cycle holds is the representation's. Fusing a suspension into
  its cons cell would change 3 to 2 with no defect.
- **Guidelines:** TBS §1.1.
- **Recommendation:** run the program at two input sizes and require equal live counts. A leak that
  grows with the input is the bug; a constant CAF cycle is not.

**PROG-17. The tests' own code is held twice.**
- **Category:** harness-representation. **Severity:** low.
- **Evidence:**

  | what | where it is repeated |
  | --- | --- |
  | `readInt = go 0` | 45 Main.idr files |
  | get/set/fill/next | eval/latent-loop*, lazy-branch-loop, lazy-list-branches, io/action-forced-twice |
  | the bounds scaffolding (`record Arr`, `newArr`) | six times |
  | `Arith.idr` | data/nbody and prelude/math-showcase |
  | linarray-lanes `Main.idr` | narrow and wide, byte-identical |
  | the repetition factor | `expected-stdout` restates it: 10000 lines of `61` in stack/io-loop-through-helper, whose `constant-stack` says 10000; 1100 dots in forever-until-crash |

- **Guidelines:** RF 1F1P.
- **Recommendation:**
  - A small test package (`tests/lib/idris`, passed with `-p`) holding readInt and the IOArray
    helpers.
  - Repeat `expected-stdout` by the `constant-stack` factor, as `repeated` already does for stdin.

**PROG-18. The `expected` transcript only restates the fixture's marks.**
- **Category:** harness-representation. **Severity:** medium.
- **Paths:** every e2e `expected`.
- **Evidence:**
  - 138 programs share one 6-line `expected` byte for byte, and 42 another.
  - Its lines follow from which marks the fixture holds (`heap-free` adds "heap: nothing is
    allocated on the heap", `mlir.expect` adds "mlir.expect: holds").
  - The NEEDS-ACCEPTANCE line makes 24 program tests fail by construction until someone edits them
    by hand.
- **Guidelines:** RF 1F1P; RF PARSE (the verdict is computed once).
- **Recommendation:**
  - The e2e harness computes the verdict from the fixture files and prints lines only for the
    checks that fail.
  - `expected` disappears for e2e fixtures.
  - Acceptance is of `expected-stdout` and the marks alone.

**PROG-19. Target facts live outside the target entry.**
- **Category:** infrastructure-gap. **Severity:** low.
- **Paths:** io/system-info/run, arrays/buffer-ops.
- **Evidence:**
  - `case " $host_names " in *" macos "*) os=darwin ;; *" linux "*) os=unix ;;`
  - "expected-stdout is a little-endian target's, as both targets are".
- **Guidelines:** AG ("Nothing may assume ... outside the one place the target is decided ...
  Per-target cases elsewhere are bugs").
- **Recommendation:** the build writes the target's OS name and byte order as runtime facts, as it
  does `codegen-symbols` and `symbol-prefix`. The run reads them.

**PROG-20. Outputs of deleted tests stay in the source tree.**
- **Category:** infrastructure-gap. **Severity:** low.
- **Paths:**
  - 77 directories under tests/programs with only an `output`;
  - arrays/buffer-byte-range, linarray-generate-bounds, linarray-generate-fill-once,
    linarray-generate-negative-size, linarray-rows-effects;
  - 72 directories `semantics/prim-<type>-<family>-<k>` from an older Sem naming.
- **Evidence:** linarray-generate-bounds/output still reads `artifacts: prog.core prog.mlir prog.o
  prog`, an artifact list long gone. Untracked `build/` directories also sit in basic/hello,
  arrays/ioarray-fannkuch and linear/leet-valid-parentheses.
- **Guidelines:** RF DEL.
- **Recommendation:** one.sh writes outputs under `tests/build/output/<test>`, not beside the
  fixture.

**PROG-21. Every program runs one fixed input, and Gen drives no program generator.**
- **Category:** distribution. **Severity:** high.
- **Paths:** all of tests/programs.
- **Evidence:**
  - Each fixture has one `stdin`, mostly a single digit.
  - Gen.idr's seeded, replayed and exhaustive tapes and its shrinking are used by the fuzzer only,
    whose cases are "closed expressions over every primitive".
  - Nothing generates a data type, a match, a recursion shape, a linear pipeline or a sequence of IO
    or vector commands.
- **What is wrong:** the topics where the wave's representation changes landed are layout, rc,
  matches, stack and lanes. There the search is a list of examples.
- **Guidelines:** TBS §4.1 (construct, don't filter); TBS §5 (an explicit distribution and swarm);
  TBS §8 (small scope).
- **Recommendation:** section 5.

**PROG-22. Crashes after main returns are caught only by exit status.**
- **Category:** perception. **Severity:** medium.
- **Paths:** io/directory-listing, stack/io-loop-through-helper.
- **Evidence:** `idris-rt: live cells 7`, then `Bus error: 10`; `idris-rt: live cells 30017`, then
  `Segmentation fault: 11`.
- **What is wrong:** the harness sees exit 138 and 139. It has no sanitizer build of the runtime
  that would name the bad access.
- **Guidelines:** TBS §7 (a universal oracle turns a silent memory error into a named crash).
- **Recommendation:** an ASan/UBSan build of the runtime for one pool. Note that the teardown runs
  after the live-cell count.

**PROG-23. The `covers` machinery scrapes the REPL's text.**
- **Category:** harness-representation. **Severity:** medium.
- **Paths:** `tests/lib/prelude.sh` (497 lines), prelude/every-primio-export.
- **Evidence:**
  - It reads `:browse` through awk (`NF >= 2 && $1 !~ / /`), and "An escape hatch, which user code
    may not write, is asked of the compiler".
  - every-primio-export now prints "21 exports; 12 used, these not: unsafePerformIO", where it
    printed "1 escape hatch ... unsafePerformIO".
- **Guidelines:** RF STR (names and kinds as scraped text).
- **Recommendation:**
  - Compute the export list in Idris (the runner) from the pinned context as data.
  - Have the compiler's refusal rules list escape hatches as data the check reads.
  - Find out whether the classification or the compiler changed (section 4).

**PROG-24. Two FileCheck fixtures match printed op text.**
- **Category:** brittle-overspecified. **Severity:** low.
- **Paths:** partial/lambda-terminates/mlir.check, partial/partial-divergent-call/mlir.check.
- **Evidence:**
  - `// CHECK-DAG: idr.func @Main.main.lam.{{[^(]+}}({{.*}}) -> {{.*}} attributes {{[{].*}}total{{.*}} {`
  - `// CHECK: call @Main.spin(`. A clone `@Main.spin.spec...` breaks it.
- **Guidelines:** AG ("Not clone numbers, function order or SSA names ... write the property
  once"); TBS §1.1.
- **Recommendation:** use the idr-expect rows `total`, `not-total`, `calls` and `never-calls`.

## 4. Code bugs the tests reveal

Only what the outputs show. These are readings, not diagnoses.

1. **Reference-count leaks.**
   - 36 programs end with live cells at exit:

     | where | live cells left |
     | --- | --- |
     | IORef and IOArray programs: ioarray-ends, ioref-counter, st-sum, buffer-bytes, implementation-runtime-scope | 1 each |
     | arrays/ioref-closures | 1001 |
     | stack/replicate-take-deep | 10000000 |
     | eval/thunk-consumes-list | 1000003 |
     | eval/memo-lazy | 20 |
     | eval/memo-shared-stream (3 allowed) | 358 |
     | eval/stream-share (3 allowed) | 29 |
     | data/pidigits | 90 |
     | data/identity-weakening | 25 |
     | data/records-past-the-cell | 7 |
     | data/records-nested-past-the-cell | 9 |
     | prelude/show-values | 8 |
     | prelude/split-prefixes | 18 |

   - The live-cells check is the right oracle (TBS §7).
   - replicate-take-deep frees none of a list two consumers share. ioref-closures keeps every
     composed closure. Each IORef or IOArray keeps its own cell. These point at drops the counting
     step no longer places on those paths. The recent commits 423d9760 and 9696ecc5 changed exactly
     what counting grades and when an unpack releases.
2. **`llvm.call` operand type mismatch.**
   - The error: `'llvm.call' op operand type mismatch: expected operand type 'i64', but provided
     '!llvm.ptr' for operand number 0`.
   - The tests: basic/guards-messages-str-head, guards-messages-str-index,
     string-loop-one-value-twice, prelude/string-pack, every-cast-export, data/bubble-sort.
   - Most of them touch a string primitive (strHead, strIndex, a string match, pack). The wave split
     the string and show operations by signedness. The likely reading is a runtime function declared
     with an i64 first parameter that is called with a string pointer.
3. **`unsupported (polymorphism)` on the Linear.Vec and Array programs.**
   - The refusals: `Linear.Notation.MkBang: a shape whose rank no analysis fixes: [__]`,
     `Builtin.DPair.(#)` and `Builtin.MkPair`.
   - The tests: 12 arrays programs, every NEEDS-ACCEPTANCE "port to the size-indexed vector" among
     them.
   - Either the growth check now refuses `Res`/`#` pairs carrying a `!*`, or the ported libraries
     leave the subset. The ports were never built, so this is uncertain.
4. **A program that hangs at run time.** eval/closure-result-roundtrip runs out the 60 s limit and
   prints nothing (`run: exit 124`). It maps a partial application over `filter` of the range
   `[1 .. 9]`.
5. **Constant stack lost.**
   - prelude/traverse-deep and stack/for-long-list exhaust the 1 MiB stack.
   - mlir.expect says "the stack grows with the recursion of @PrimIO.io_bind[Builtin.Unit,
     Builtin.Unit].lam... @Prelude.Interfaces.foldr[PrimIO.IO Builtin.Unit, Int, ...].lam".
   - That is traverse_ and for_, through foldr and io_bind, no longer tail calls.
6. **Crashes after main returns.** io/directory-listing (bus error) and
   stack/io-loop-through-helper (segfault). Both print the live-cell count first, so the fault is in
   teardown or after it: freeing the leaked cells, or the runtime's exit.
7. **The rc verifier rejects its own output.** prelude/every-uninhabited-export fails with
   "internal error: 'idr.yield' op idr-rc-exclusive: gives a value of
   '!idr.own<!idr.box<...List[String]...>>' where the solver proved '!idr.excl<...'". The exclusive
   step's output contradicts its solver.
8. **Heap-free broken.**
   - The tests: data/nbody, interfaces/interface-ring-power, prelude/double-basics,
     prelude/math-showcase, prelude/double-cast-nan, and eval/lazy-branch-loop's
     `no-heap-allocation=@Main.next`.
   - The allocations: `idr.str.show_double` and `idr.str.show_sint`/`idr.str.append` "allocates in
     @Main.main.delay..."; `idr.cell.new` in main.delay; `idr.con allocates in @Main.next`.
   - Output fusion of shows inside a delayed main, and the if-branch suspension, no longer avoid the
     heap. This may follow the show-op split.
9. **rc properties fail.**
   - arrays/ioref-keeps-old-value and ioref-modify-in-place: "expected moves-out: no element of an
     array is rebuilt in its place".
   - prelude/split-prefixes: "expected tests-nothing: idr.take in @Data.List.span[Char].spec... tests
     a value of '!idr.own<...>', which is not exclusive".
   - A Roots property failing on its own is a regression of the rc placement, not brittleness.
10. **Quantities after defunctionalization.**
    - linear/linear-catch-all: "bound field 0 of @Main.f.case0 has quantity w, and Idris proved 1"
      after idr-defunctionalize. linear/linear-nested-match fails the same way on @Main.g.
    - This is either a real widening, or the same location-identity confusion that the
      Specialization change just worked around (PROG-2).
11. **Covers classification changed.** prelude/every-primio-export: unsafePerformIO is no longer
    reported as an escape hatch. Either the compiler's escape-hatch list lost it in the wave
    ("elaboration owed; io primitive and identity hook gone", 57f60426), or the query broke.
12. **Undetermined.**
    - 20 compile timeouts at 60 s. It is not known how much is dumping (PROG-3).
    - 8 compile failures, exit 1 or 134 (an abort in arrays/transpose-last-two-axes), whose message
      PROG-1 hides.

## 5. The scope rebuilt

**Keep a small golden core where the contract fully determines the output (TBS §1.3).** It is about
100 programs:

- the IO and runtime contracts: io/*, basic/high-chars, laziness, let-after-output, the crash
  tests that are not table rows;
- the library contracts: SortedMap/Set, Vect, Buffer, the string iterator, LList;
- the effect-order and sharing contracts (timeouts as oracles): lazy-double, shared-result,
  memo-lazy, nat-loop;
- the regressions of silent miscompiles: spin-atom, sortedmap-*, identity-weakening,
  dependent-pair-family-eta, method-runtime-implicits once fixed;
- the stack shapes with their `constant-stack` marks;
- the `every-*-export` coverage set.

Each states its pass properties of its root (PROG-4), at a stage, not at "the step after a group"
(PROG-5).

**Generators, on Gen.idr's tapes (seeded, replay, exhaustive, shrink), each a parameterized
directory like `prim@`:**

- **G1, ADTs and matches (`data/adt`, with `data/layout@<n>` its boundary slice).**
  - What it generates:
    - data declarations with constructor counts drawn around 1, 2, 2^8 and 2^16;
    - field counts around the header's 255/256;
    - field kinds Bits8 to Int64, Double, String, nested records, Never, quantity 0 and quantity 1;
    - values built by construction (TBS §4.1);
    - matches with literal, nested, catch-all and absurd clauses.
  - The oracle is the generator's own evaluation of the value it built, printed in Idris.
  - Universal checks: leaks 0, heap-free where nothing boxes.
  - It replaces the semantics match family, layout-*, records-*, complete-split, enum-stepping,
    void-field and mixed-widths.
- **G2, linear-list pipelines (`linear/lists`).**
  - Random compositions of build, rev, merge, partition, dedup, insert, take and drop over `LList
    (!* Int)`.
  - The oracle is a model on `List Int`.
  - Properties over the root: `tests-nothing`, `counts-nothing`, `reuses-in-place`; live cells 0.
  - The leet programs are its corpus seeds (TBS §1.2, the alphabet from the tests).
- **G3, Linear.Vec command sequences (`arrays/vec-model`).**
  - Commands are indexed by size. Out-of-range indices are named cases with weights (TBS §4.3–4.4,
    §5).
  - The model is a List plus the documented capacity rule.
  - It replaces push-pop, reserve, read/write-past-size and pop-then-push, and the six bounds-*
    examples as IOArray commands.
- **G4, the crash table (`semantics/crash@<guard>`).**
  - One row per runtime guard, generated from the runtime's table (RF 1F1P).
  - Each guard is run with output before it and with an unused result (the program order
    contract).
- **G5, text (`prelude/double-text`, and the cast-from-string grammar).**
  - Round trip and shortest digits over named Double classes.
  - Literal strings generated from the documented grammar, with a model parse.
  - getline-ill-formed's maximal-subpart rule as a model decoder over generated byte strings.
- **G6, Nat and Integer boundaries.**
  - An exhaustive small scope around 2^62, 2^63 and 2^64 (TBS §8), checked against Prims'
    Integer model.
  - It takes nat-large and integer-bits.
- **G7, recursion shapes.**
  - Self and mutual tail calls through if/case/with/when/unless; TRMC constructors; binds.
  - Each is run at sizes N and 10N on the 1 MiB stack.
  - The oracle is the closed form the generator computes. The perception is stack exhaustion
    (`constant-stack`) and `constant-stack` stated at a stage.
- **G8, leak growth.** Every kept program is run at two input sizes, with equal live counts
  required (PROG-16).

**Harness:**

- Install the pass contracts in-process and delete the dump-based universal checks (PROG-2,
  PROG-3).
- Dump only the steps a fixture names, and the group ends (PROG-1, PROG-5).
- Compute the verdict from the fixture files (PROG-18).
- Write outputs under tests/build (PROG-20).
- Read target facts from the build (PROG-19).
- Keep a shared test package for helpers (PROG-17).
- Move the bench-built fixtures' properties into `bench/<name>/` and run them from bench/smoke
  (PROG-10).
- Run one pool on an ASan runtime (PROG-22).

**Swarm:** each generator draws its Weights per run (TBS §5). Record the tapes of failures as
replayable fixtures (TBS §2, the corpus), and report the Good–Turing residual from each
generator's feature counts (TBS §8).
