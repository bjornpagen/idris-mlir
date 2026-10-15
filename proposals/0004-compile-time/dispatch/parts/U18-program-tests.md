# U18 — The program, rejection, toolchain and spec suites on the cutover's compiler

## Permitted outcome

The suites that run whole programs, refusals, the toolchain and the
repository's rules (`make test` but `tests/idr` and `tests/upstream`, and
`make check`) state the cutover's compiler: what it accepts, what it
prints, what it leaves, and the rules it keeps by construction. Every
item is externally observable in a test's `run`, `expected` or fixture.

1. **Mandatory. The shared harness speaks the cutover's driver.**
   `tests/lib` passes no option the cutover deletes; every reader of a
   step's module reads upstream's IR tree printer; the readers of the
   objects read every bin object of a build; the artifacts of a build are
   named in one place and printed as kinds; the two e2e properties of
   deleted mechanisms (the budget line and the simplify idempotence line)
   are gone. Consumer adaptation of C12, C13, C22 and C24.
2. **Mandatory. Every expected transcript of the owned pools follows the
   harness** (the artifacts line, the two deleted property lines),
   mechanically, with no other change to it.
3. **Mandatory. The in-place promise is a fact of the library's types**
   (C14): the eleven `demand-in-place` marks are deleted, and the
   programs that carried them keep their expected files.
4. **Mandatory. Property and FileCheck files name the cutover's steps and
   properties**: every `mlir.expect` and `mlir.check` under the owned
   pools restated on C12's step names and C24's properties; no check
   reads a counter-made name.
5. **Mandatory. `tests/programs/arrays` on the new library** (C19): every
   program over the old linear array module ported with its
   `expected-stdout` and `expected-crash` kept byte for byte, or deleted
   where the typed library makes the program unwritable (four, named
   below); `in-place=@f` stated on the fannkuch and qsort ports.
6. **Mandatory. The acceptance change of the request-chain rule** (C20,
   0004 D40) listed, in this part and in the handoff, with the fixtures
   that state it: one new accept fixture of bounded polymorphic recursion,
   one new reject fixture of a rank that grows (0003 D25), and the two
   existing polymorphism fixtures kept refused.
7. **Mandatory. Spec tests for the cutover's rules**, run by `make check`
   with no build: no option selects behaviour; no generated name comes
   from a counter; no count refuses a program; a refusal's rule is data;
   facts live in types.
8. **Mandatory. The registry tests and `frontend-command-line` on refused
   inputs** (0004 D43): each break of a registry entry is a fixture whose
   own module defines the keyed name at another shape.
9. **Mandatory. Determinism at 1, 2 and 8 threads**, byte for byte, and
   the name-stability edit fixture (0007 S1): one definition edited, every
   other symbol unchanged.
10. **Mandatory.** `tests/upstream-idris/common.sh`'s `rejection_skip`
    reads the refusal's rule (C04), never its message.
11. **Mandatory.** A fixture for a partially applied `castPtr` (0002 D18).
12. **Mandatory. The bench's Chez column is timing only** (0002 D20, 0003
    §21 item 4): `bench/run.sh` compares only this compiler's and clang's
    outputs with the reference; `bench/README.md` says so, names the new
    library for the five ported programs and restates the ablation section
    without the deleted options.
13. **Mandatory. The other owned files follow:** `tests/README.md`,
    `tests/testutils.sh`, `tests/Main.idr`'s pool text,
    `tests/compile-times.sh` (the optimizer's row, no rounds), and the
    `tests/compiler` tests that read the handoff, the artifacts or the
    data declarations.
14. **Mandatory. The hash every generated name is made from** (C21):
    `tests/compiler/content-hash` compiles the frontend's own
    `IdrisMLIR.Ids` into a program that prints `xxh3_128` of the sanity
    buffer at each length of C21's first table and of its three texts;
    the expected lines are the published values.
15. **Mandatory. The runtime's two new properties** (C17 §1, §3, §4):
    `tests/toolchain/runtime-api/rc.c` checks that a new array's object
    slots are NULL from birth and that `idris_rt_memref_copy` counts each
    object it copies before it releases what it overwrites (onto a fresh
    cell, onto a live one, onto itself, at size 0, at rank 0, and doubles
    through a strided view).
16. **Mandatory. C13's code generation tests:** the record of which kind
    of module-level inline assembly the runtime brings, on both targets
    (0004 §5.3 item 5); a generated program over two bins whose tail-call
    cycles, called from another bin, would overflow the stack without
    their tail calls (D33); the edit fixture whose unrelated bins keep
    their members (D41).

## Owner / exclusive writes

ownership.json's U18 entry, each path named:

- `tests/programs`: every topic. Deleted: the ten `demand-in-place` marks
  under `tests/programs/linear`; four array programs (below). Changed:
  ported array programs, `mlir.expect`, `mlir.check`, every `expected`.
  New: `tests/programs/basic/partial-cast-pointer`.
- `tests/reject`: deleted `tests/reject/uniqueness-shared-rebuild/demand-in-place`;
  new `tests/reject/polymorphism-growing-rank`; headers of the two
  polymorphism fixtures as C20 words them.
- `tests/accept`: new `tests/accept/polymorphic-recursion-swapped`; every
  `expected`.
- `tests/compiler`: `artifacts`, `handoff-readable`, `handoff-round-trip`,
  `dialect-syntax`, `frontend-command-line`, `elaboration-error`,
  `module-location`; new `tests/compiler/content-hash`.
- `tests/registry`: `broken-entry`, `string-iterator`, `base-surface`
  rewritten on fixtures; every `expected`.
- `tests/toolchain`: `runtime-api` (`rc.c`, `run`, `expected`); new tests
  for item 16. `runtime-container`'s `-c` links the archive unchanged.
- `tests/determinism`: every test; new `tests/determinism/name-stability`.
- `tests/fuzz`, `tests/two-levels`, `tests/bench`: only where they read
  an artifact name or a deleted option.
- `tests/lib`: `compile.sh`, `e2e.sh`, `profile.sh`, `determinism.sh`,
  `timing.sh`, `mlir.sh`, `heap.sh`, `properties.sh`, `expect.sh`.
- `tests/spec`: new `tests/spec/no-behaviour-options`,
  `tests/spec/content-names`, `tests/spec/totality`,
  `tests/spec/refusals-as-data`, `tests/spec/facts-in-types`; changed
  `tests/spec/verifier-every-pass` (comment) and
  `tests/spec/dialects-current/expected`.
- `tests/templates`, `tests/runner`: only where they name a deleted mark.
- `tests/upstream-idris`: `common.sh`.
- `tests/Main.idr`, `tests/Runner.idr`, `tests/Sem.idr`, `tests/Fuzz.idr`,
  `tests/Lock.idr`, `tests/TwoLevels.idr`, `tests/tests.ipkg`: only
  `tests/Main.idr`'s arrays pool text changes.
- `tests/testutils.sh`, `tests/compile-times.sh`, `tests/README.md`.
- `bench/run.sh`, `bench/report.sh`, `bench/README.md`.

**Excluded:** `tests/idr` and `foreign/idr/lib/Transforms/Expect` (U17;
`tests/idr/stack/hot-loop/expected` is an e2e transcript there, which item
2 changes, and U17 edits it); `tests/upstream` (U16); `tools/compile.sh`
(U06); `libs/` and the five bench programs' `Main.idr` (U13);
`compiler/src` (U01, U14, U15); `foreign/idr` (U01 to U12, U16, U17);
`runtime/` (U19); `Makefile`, `tools/dialects.sh`, `README.md`,
`AGENTS.md`, `HANDOFF.md` (the coordinator); `bench/c`, `bench/runs`,
`bench/profiles` (records, the owner's machine).

## Read first

- `contracts.md`: C04, C12, C13, C14, C19, C20, C21, C22, C24.
- 0004 `README.md`: §2.5 (what is still refused), §4 stage 1 and the
  determinism rules (lines 670-1024), §5.3 items 3 and 6 (D32), §6's
  deletion table and the registry table (lines 1229-1328), §10's L8 row,
  D18, D28, D29, D32, D36, D40, D42, D43, D45, D46.
- 0003 `README.md`: §3.1-§3.2 and §3.8 (the library, `LArray`), §8 (the
  in-place promise is `LArray`'s, never a refusal of a program), §15's
  tests paragraph, §17 stage 1's proof, §21 item 4, D19, D25, D27, D37.
- 0012 "What stays refused" and feature 2 (the rule, what it deletes, what
  it refuses that is bounded); 0002 §2 step 6, §3 (the bench, the
  upstream-idris scan, `castPtr`), D18, D20.
- `array-drafts.json` entry 1 ("TESTS and BENCH"): §2.3's substitution
  rules and §2.4's deletions hold; its `idr-raise` is `idr-structure-loops`
  (0003 D27); its `demand-in-place` mark and `uniqueness-thaw-read-again`
  fixture do not hold (a thaw copies, 0003 §8; the mark is gone, D19); its
  step and property names give way to C12 and C24.
- The harness: `tests/testutils.sh`; `tests/lib/compile.sh:4-64`,
  `e2e.sh:28-130`, `profile.sh:37-139`, `determinism.sh`, `timing.sh:23-57`,
  `mlir.sh:23-88`, `heap.sh:57-104`, `properties.sh`, `expect.sh`.
- The tree printer: `.toolchain/build/llvm-project/mlir/lib/Pass/IRPrinting.cpp:200-345`
  (file names `<count>_<pass>.mlir` under `builtin_module_<symbol>/`,
  nested passes one directory down, adaptors never printed),
  `include/mlir/Pass/PassManager.h:390-427`,
  `lib/Pass/PassManagerOptions.cpp:61-131`; the driver registers these
  options today (`foreign/idr/lib/Driver/Main.cpp:94-99`, `Run.cpp:118`).
- `tools/compile.sh` (options pass through; a later `--num-threads` wins).
- `foreign/idr/lib/Driver/Options.cpp:22-130`,
  `foreign/idr/include/idr/Transforms/Passes.td:611-696, 856`,
  `foreign/idr/include/idr/IR/IdrBase.td:53-58`: what the spec tests
  read.
- `compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr:25-125`,
  `Recursion.idr:120-155` (today's refusals the rule replaces);
  `compiler/src/IdrisMLIR/Frontend/Resolve.idr:200-260`,
  `Registry/Entry.idr:355-410` (what a registry validation checks).
- `tests/upstream-idris/common.sh:110-127`; `bench/run.sh:150-290`;
  `bench/README.md:1-21, 63-75, 117-194`.

## Fixed decisions

1. **Dumps.** A test that reads a step's module compiles with
   `--mlir-print-ir-after-all --mlir-print-ir-tree-dir=<dir>`, `<dir>`
   being `build/exec/<name>.dump` beside the build. The module after a
   top-level step `S` is the file `<n>_S.mlir` directly inside the one
   `builtin_module_*` directory of `<dir>` with the least `<n>` among
   those of `S`; the steps' order is the numeric order of `<n>`. Files in
   deeper directories are one function's prints and are never a step's
   module. A step that left no such file fails the check; nothing falls
   back to another step. One function, `step_dumps DIR`, lists the
   top-level dumps in order; `step_module`, `dumps_verify`,
   `quantities_kept` and `heap_free` read only it.
2. **Step names** are C12's arguments of top-level passes (C12 §3: a pass
   in a `pm.nest` group prints one function and is no step). Today's
   steps map so: `idr-simplify` is `idr-optimize`; the outlining step's
   module is `emitted` (the frontend writes the symbol form); the
   in-bounds step's lines are deleted; `idr-tail-loops` (row 16, nested)
   is read at `idr-narrow`, the next step; `structured-loops` (row 7,
   nested) at `eliminate-empty-tensors`; `in-place` at `idr-bufferize`;
   `vectorized` and `narrowed-lanes` (row 20, nested) at
   `idr-returned-arguments`. The default step of an `mlir.check` with no
   `// input:` line is `idr-optimize`.
3. **Artifacts.** `tests/lib/compile.sh` holds the one table of a build's
   artifacts, `artifact_patterns KIND NAME` over `artifact_kinds='core
   module objects executable'`: the Core `NAME.core`, the handoff
   `NAME.mlirbc` (C22), one object per bin `NAME.<bin>.o` (C13) and the
   executable `NAME`; `artifact_files` and `artifact_file` find them.
   Every transcript prints them as kinds: `artifacts: core module objects
   executable`. `no_artifacts`, the timing record (which keeps the
   handoff's extension), `determinism` and `tests/compiler/artifacts`
   read the same table.
4. **Objects.** `object_imports` reads every object of the build (and an
   archive's every member, for `-c`), and its undefined symbols are the
   union of the members' undefined symbols less the union of their defined
   ones. The transcript line stays `object: ...`.
5. **The e2e properties** are `dumps: parse and verify` and `quantities:
   kept`, both over `step_dumps`, quantities up to the lowering step's
   dump (C12's name). The budget line and the simplify idempotence line
   are deleted from the harness and from every transcript.
6. **The promise.** No harness function and no fixture passes or names
   the promise option; the mark `demand-in-place` is deleted from the
   marks `tests/testutils.sh` documents.
7. **Determinism.** `determinism FIXTURE` compiles three times, with
   `--num-threads=1`, `2` and `8` (each after `tools/compile.sh`'s own,
   so it wins), and compares the Core, the handoff, every object, the
   executable and the whole dump tree byte for byte. Its transcript:
   `compile at 1 thread: exit 0`, `compile at 2 threads: exit 0`,
   `compile at 8 threads: exit 0`, then `core: identical at 1, 2 and 8
   threads`, the same for `module`, `objects`, `executable`, and `dumps:
   identical at 1, 2 and 8 threads`. `determinism_threads` stays on
   `idris-mlir-opt` and C12's registered pipeline, its remark filter
   `idr-narrow-lanes` alone.
8. **Name stability.** `tests/determinism/name-stability` holds one
   program in two versions, `Main.idr` and `edited/Main.idr`, differing in
   the body of one definition, `Main.step`. Both are compiled; the symbols
   of each handoff, printed through `idris-mlir-opt`, and of each
   top-level dump before lowering are listed; every symbol of one that is
   not in the other starts with `Main.step` (names from content carry
   their owner, C21). The transcript says so in one line per module kind.
9. **The acceptance change (D40).** Accepted now, refused before: a
   recursive group whose static arguments change but reach a finite set
   (`checkComponent` refused it), a chain where one static position
   deepens while another shrinks, and any program past the instance
   bound. Refused before and after: `tests/reject/polymorphism-nested`
   (a type that grows) and `tests/reject/polymorphism-growing-shape` (a
   needed shape that grows); their `-- expect:` line keeps the rule
   `polymorphism`; growing-shape keeps line 19 and its message (C20 §9),
   nested moves from line 6 to line 8, the recursive call. Refused, new:
   `tests/reject/polymorphism-growing-rank` (an array whose rank grows at
   each call, 0003 D25), refused at its recursive call. Accepted, new:
   `tests/accept/polymorphic-recursion-swapped` (two type and two
   implementation arguments swapped at each call: a finite set).
10. **The array programs.** Ported, outputs kept: `linarray-bubble`,
    `linarray-fannkuch`, `linarray-fill-sum`, `linarray-push-pop`,
    `linarray-qsort`, `linarray-read-past-size`, `linarray-reserve`,
    `linarray-unionfind`, `linarray-write-past-size` (on `Linear.Vec`);
    `linarray-combinators`, `linarray-lanes-exact`, `linarray-lanes-narrow`,
    `linarray-lanes-wide`, `linarray-spectral-norm`,
    `linarray-rows-crash-order` (on `Array`). Directory names are kept (the
    determinism and handoff tests name two of them). Each ported fixture's
    `packages` is C19's package list. Deleted, whole directories, because
    the typed library makes the program unwritable:
    `linarray-generate-bounds` (a read one past the array is no
    `Index`), `linarray-generate-fill-once` and `linarray-rows-effects`
    (mutation seen through an array shared unrestricted, which no
    `LArray` is), `linarray-generate-negative-size` (an extent is a
    `Nat`). The `IOArray`, `IORef`, `Buffer` and ST programs keep their
    source.
11. **Registry fixtures.** One helper, `registry_shadowed` in
    `tests/lib/profile.sh`, builds each case at test time: a `Main.idr`
    and, as the program's own module named as the module the entry's
    `site` resolves to (`Registry/Entry.idr:369-375`), the pinned source
    of that module (under `third_party/Idris2/libs` or `libs/`) with one
    edit to the definition: `shape` gives its declaration a leading
    `{default MkUnit shadowed : Unit} ->`, which every use fills, so the
    module still checks and the shape is another; `gone` removes the
    paragraph of its last declaration, for a ruled-out entry, whose shape
    is a hole. Nothing of the pinned modules is committed. The run keeps
    today's checks: the hook rule with the entry, what it expects and
    what was found; no artifact. The unbroken case compiles the test's
    own `Main.idr`.
    `frontend-command-line`'s `no-entry` case is deleted: the frontend has
    no option that names an entry, and an internal error is a broken
    invariant, never an input a test can give.
12. **`rejection_skip RULE-TEXT`** takes the rule of the first
    `unsupported (<rule>)` in the output, the phrase C04 renders, and
    answers by the rule alone: `threads`, `finalizer`, `raw pointer` and
    `world` each skip under the rule's own name; any other rule is no
    skip. The message after the rule is never read.
13. **Spec tests** read sources with `git grep` and need no build; each
    spells the names it must not find in pieces, as `spec/time-trace`
    does, so it is not its own hit:
    - `no-behaviour-options`: every `cl::opt` or `cl::list` under
      `foreign/idr/lib` and `foreign/idr/tools` names a flag of the kept
      set (0004 §6 "Kept": `o`, `c`, `p`, `package-path`, `prefix`,
      `no-prelude`, `log-actions-tags`, `runtime`,
      `runtime-bitcode-section`, `print-runtime`, `prepare-runtime`,
      `print-target-triple`, `print-link-flags`, `print-target-cpu`,
      `num-threads`, the positional input, and `time-trace` in
      `lib/Support/Profile.cpp`); every `Option<` or `ListOption<` in the
      ODS under `foreign/idr/include` is idr-expect's `holds`; the driver
      registers no debug counter (D46).
    - `content-names`: no string literal under `foreign/idr/lib` or
      `compiler/src` builds a counter-made name (the suffixes and prefixes
      0004 §6's names row lists); the frontend's printed-key repeat is
      gone (`Emit/Index.idr`).
    - `totality`: the rule enum's ODS (C04) declares no rule whose
      refusal is a count; no source under `foreign/idr`, `compiler/src`
      or `runtime` spells the budget refusal; the hand-written
      `compiler/src/IdrisMLIR/Rule.idr` does not exist (generated, C04).
    - `refusals-as-data`: the phrase's opening inside a string literal
      appears under `foreign/idr` only in `lib/IR/Attrs.cpp` (C04 §2), and
      in one Idris file of `compiler/src`; `compiler/src/IdrisMLIR/Rule.idr`
      is gone.
    - `facts-in-types`: no ODS under `foreign/idr/include` declares a
      discardable attribute (`discardableAttrs` absent or empty); no
      `declarationOf`, `constructorOf`, `DataOp` or `CtorOp` is left under
      `foreign/idr/lib` (D29, D31).
14. **Bench.** `bench/run.sh` keeps its three columns and its labels; a
    second list, `compared='this compiler|clang -O2'`, is the columns whose
    output is held to the reference; the Chez column is timed and never
    compared. `bench/report.sh` is unchanged.
15. **`tests/compile-times.sh`**: the `simplify` column is the optimizer
    segment, the `idr-optimize` row (its class name per C12); the rounds
    column, its remark read and its report section are deleted; `--against`
    reads records of this layout.

## Inputs

- C04: the rule enum, its phrases as rendered (`unsupported (<phrase>)`),
  the one rendering place, the generated Idris module's path.
- C12: the top-level pass names (the optimizer, the structuring, the
  bufferization pass, the step after the vectorization schedule, the
  lowering step), the registered pipeline name for `idris-mlir-opt`, and
  the driver's kept options.
- C13: a build without `-c` leaves `<base>.<bin>.o` per bin; `-c` writes
  one archive at `-o`; the codegen tests of item 16.
- C14: the in-place promise as `mlir-linear`'s type fact, checked on every
  program.
- C19: `libs/mlir-array` and `Linear.Vec`: module names, the package list
  a fixture names, the functions the ports call (`tabulate`, `(!!)`,
  `shape`, `withArray`, `read`, `write`, `freeze`, `thaw`, Vec's
  `size`, `capacity`, `push`, `pop`, `reserve`, its crash text).
- C20: the request-chain rule's site and message; the frontend's
  registry validation after the shape-breaking hook goes.
- C21: a generated name is `<owner>.<kind>.<hex16>`; checks read the
  owner and the kind, never the digits; the test vectors of item 14.
- C22: the handoff `<base>.mlirbc`, bytecode, read by `idris-mlir-opt`;
  `syntax-samples OUT.mlirbc`; identified types' assembly.
- C17: the array cell's NULL slots and `idris_rt_memref_copy`.
- C24: the property names and argument form (`structured-loops`,
  `typed-reads`, `in-place`, `vectorized`, `narrowed-lanes`,
  `no-closures`, `not-called`, `one-clone`, `counts-nothing`, the rest),
  and how `=@f` finds a function.

## Outputs

No contract. Files supplied, by consumer:
- the coordinator and the owner's machine: the suites above, each test's
  `expected` the specification, and the list of `NEEDS-ACCEPTANCE` files;
- U17: `tests/lib` as fixed above (its `lit.sh` interface unchanged), and
  the new e2e transcript shape for `tests/idr/stack/hot-loop/expected`.

## Implement

- **`tests/lib/compile.sh`.** The artifact table (decision 3) and
  `artifacts DIR NAME` printing kinds; `no_artifacts DIR` over the same
  table; `compile_program`'s comment lists the options a test may pass
  (`-p`, the tree printer's two options, `--num-threads=N`).
- **`tests/lib/e2e.sh`.** `e2e_io` passes the packages and the tree
  printer's options, no promise; checks `artifacts` by kinds; calls
  `object_imports` on the build's objects, `heap_free`, `module_checks`
  and `compilation_properties` with the dump tree.
- **`tests/lib/mlir.sh`.** `step_dumps DIR` and `step_module STEP
  EMITTED DIR` by decision 1; `emitted` is the handoff, which
  `idris-mlir-opt` reads whatever its encoding; the default step is
  `idr-optimize`; the comment restated on the tree printer.
- **`tests/lib/properties.sh`.** `compilation_properties` keeps
  `dumps_verify` and `quantities_kept` over `step_dumps`; the budget
  check and the simplify idempotence check are deleted.
- **`tests/lib/heap.sh`.** `object_imports` by decision 4; `heap_free`
  over `step_dumps`, up to the lowering step.
- **`tests/lib/profile.sh`.** No promise; accept's artifacts by kinds.
- **`tests/lib/determinism.sh`.** Decision 7.
- **`tests/lib/timing.sh`.** `record_time` leaves out the tree printer's
  options and `--num-threads` when naming what was compiled, and keeps
  the handoff by the table's name.
- **Expected files.** One mechanical edit over every `expected` the
  harness prints into (tests/programs, tests/accept, tests/registry):
  the artifacts line by kinds, the two deleted property lines removed.
  Nothing else in them changes.
- **`mlir.expect`.** `idr-simplify:` lines move to `idr-optimize:`. The
  breaks-last and every-cycle-has-breaker properties are deleted; a file
  left with no property is deleted with its `mlir.expect: holds` line in
  `expected`; `lazy-branch-loop` keeps `no-heap-allocation=@Main.next` at
  `idr-optimize`. The in-bounds lines are deleted (`ioarray-ends` loses its
  file, `ioarray-fannkuch` its last line and comment). `pure-array-loops`
  becomes `structured-loops`; the vectorize step's `vectorized` and
  `narrowed-lanes` move to C12's step; `linarray-fannkuch` and
  `linarray-qsort` gain `in-place=@f` on their thread functions.
  `leet-valid-parentheses` names its function as C24 finds a copy made
  by `idr-rc` (never `.excl`).
- **`mlir.check`.** `// input: after idr-simplify` becomes `after
  idr-optimize`; `lambda-terminates` reads `emitted` and finds the
  lambdas as functions whose names extend `Main.main`; every
  `{{[0-9]+}}` after `.spec`, `.raise` or `.lam` becomes the owner, the
  kind and `.{{[^(]+}}` (C21: owner and kind, never the digits); the
  three checks of `{idr.program}` check the root as the
  one public function instead (D28); `data/shapes`' declaration lines
  check the identified type's body in C22's assembly.
- **Array programs.** Decision 10, by `array-drafts.json` entry 1 §2.3's
  substitution rules, renamed to C19's names; each header comment
  rewritten for the new library; `mlir.expect` per C24.
- **Reject and accept.** Decision 9's fixtures; the growing-rank fixture's
  `packages` is C19's list.
- **`tests/compiler`.** `artifacts` lists by the table; `handoff-readable`
  reads the handoff through `idris-mlir-opt` and checks every
  `idr.func` and every identified data type for its `instance` (C22);
  `handoff-round-trip` prints the handoff (bytecode) and compares the
  generic forms; `dialect-syntax`'s `expected` is the samples' print in
  C01's and C22's syntax (NEEDS-ACCEPTANCE); `elaboration-error` and
  `frontend-beside` check no artifact of the table.
- **Spec tests.** Decision 13, five new directories, each `run` and
  `expected`; `verifier-every-pass`'s comment lists the passes that run
  nested pipelines after the cutover (C12); `dialects-current/expected`
  is NEEDS-ACCEPTANCE (the generator's modules after C04 and the tensor
  dialects).
- **Registry.** Decision 11, today's entries kept one case each.
- **`partial-cast-pointer`.** A program that maps `prim__castPtr` (a
  partial application of the identity hook) over a list of handles and
  prints what it reads back; its expected output is the meaning; compiled
  without refusal.
- **`tests/upstream-idris/common.sh`.** Decision 12.
- **Bench.** Decision 14; `bench/README.md` lines 5-7, 17-21, 63-75 and
  the per-program entries of the five ported programs, and the ablation
  item restated: the table is the 2026-10-13 record's, the compiler has
  no option that leaves a step out, and a comparison is two binaries
  built from two commits.
- **Docs.** `tests/README.md` (marks, dumps, steps, the arrays pool);
  `tests/testutils.sh`'s list of marks; `tests/Main.idr:143`'s pool text.

## Delete

- The `--demand-in-place` mark files: `tests/programs/linear/leet-*/demand-in-place`
  (ten) and `tests/reject/uniqueness-shared-rebuild/demand-in-place`; the
  option's readers at `tests/lib/e2e.sh:38, 63-64`, `tests/lib/profile.sh:38, 47`,
  `tests/lib/compile.sh:5`, `tests/testutils.sh:36-39`, `tests/README.md:38-39`.
- Every `--dump-dir` reader in owned files: `tests/lib/e2e.sh:71`,
  `tests/lib/determinism.sh:19, 80`, `tests/lib/timing.sh:33`,
  `tests/lib/mlir.sh:36`, `tests/lib/compile.sh:6`; the `[0-9]*-<step>.mlir`
  file pattern everywhere it is read.
- `--break-shape` in `tests/registry/broken-entry/run`,
  `string-iterator/run`, `base-surface/run`,
  `tests/compiler/frontend-command-line/run:70` with its `no-entry` lines,
  `tests/lib/compile.sh:6`.
- `budget_kept` (which greps `compile-time budget`) and
  `simplify_idempotent` in `tests/lib/properties.sh`, and their lines in
  every transcript.
- The breaks-last and every-cycle-has-breaker properties in the six
  `mlir.expect` files (`eval/latent-loop`, `latent-loop-accumulator`,
  `latent-loop-delay`, `lazy-branch-loop`, `interfaces/show-rose-breakers`,
  `partial/loop-breakers`).
- The `idr-in-bounds` lines (`arrays/ioarray-ends`, `ioarray-fannkuch`),
  the `idr-vectorize` step and `pure-array-loops` in array `mlir.expect`
  files; `idr-vectorize` from `determinism_threads`' remark filter and
  `threads-linarray-lanes`.
- `// input: after idr-isolate` (`partial/lambda-terminates`); the
  `.lam<n>`, `.spec<n>`, `.raise<n>` patterns of the `mlir.check` files;
  `idr.program` checks.
- The `Linear.Array` programs `linarray-generate-bounds`,
  `linarray-generate-fill-once`, `linarray-generate-negative-size`,
  `linarray-rows-effects`; every `import Linear.Array` and `IArray` in the
  ported programs.
- `rejection_skip`'s match on `unsafePerformIO` in a message.
- The Chez column's output comparison in `bench/run.sh:277-294`;
  `--without` and the `reuse`/`sink` toggles in `bench/README.md:156-181`.
- The rounds column, `rounds()` and its report in `tests/compile-times.sh`.

## NOT TO DO

- Do not edit `tests/idr`, `tests/upstream`, `idr-expect` or any
  `foreign/idr` file (U17, U16, the C++ lanes); report what they need.
- Do not edit `tools/compile.sh` (U06): options reach it as arguments.
- Do not write a library function or edit `libs/` (U13): a port that needs
  a missing function reports it against C19.
- Do not change an `expected-stdout` or `expected-crash` of a kept or
  ported program: a difference on the owner's machine is a miscompile.
- Do not keep a reader of a deleted option as a guard ("if the option
  exists"), nor a second dump layout beside the tree printer's.
- Do not make the Chez column compare outputs again, nor drop it.
- Do not add the stage-2 and later array fixtures (static extents,
  fusion, scans, sparse) or the new benchmarks of 0003 §17.
- Do not reintroduce `--demand-in-place` or a `demand-in-place` mark for
  arrays: a copy at a link is an internal error, never a fixture of a
  program refused (0003 §8).

## Tempting partial solutions

- **Keep `budget: kept` with a grep that never matches.** Rejected: a line
  that cannot fail states nothing; acceptance 2 finds no such line.
- **Keep reading `[0-9]*-<step>.mlir` and have a driver option write it.**
  Rejected: the driver keeps no dump option (C12, D2); acceptance 1.
- **Keep `idr-simplify:` lines by aliasing the step.** Rejected: one name
  per step; acceptance 4 greps for none.
- **Replace every-cycle-has-breaker with "idr-optimize is idempotent".**
  Rejected: the ready set does not promise idempotence (call counts are
  frozen per run, so a second run may inline more); a property the pass
  does not guarantee is a brittle test.
- **Match clone names by a hash width** (`{{[0-9a-f]{16}}}`). Rejected:
  the check would test C21's format, not the property; owner prefix only.
- **Port the four deleted array programs with `Maybe` lookups.** Rejected:
  their expected crash and mutation outputs would change, and the program
  would no longer mean the same (0003 §15).
- **Write `uniqueness-thaw-read-again` as a reject fixture.** Rejected: a
  thaw copies when its argument is read again (0003 §8); the program is
  accepted and means two arrays.
- **Keep the shape-breaking hook in tests as a hidden option.** Rejected:
  D43; acceptance 8 greps for it.

## Acceptance

1. A `grep -rn` for each option, step and file name listed under
   `## Delete`, and for `idr-simplify`, over `tests/lib`,
   `tests/testutils.sh`, `tests/programs`, `tests/reject`, `tests/accept`,
   `tests/registry`, `tests/compiler` and `tests/determinism`, prints
   nothing.
2. No owned `expected` holds `budget: kept`, `simplify: idempotent` or an
   `artifacts:` line naming files; every e2e and accept transcript holds
   `artifacts: core module objects executable`.
3. `find tests -name demand-in-place -not -path 'tests/idr/*'` is empty.
4. No owned `mlir.expect` names `every-cycle-has-breaker`, `breaks-last`,
   `in-bounds`, `pure-array-loops`; no owned `mlir.check` holds
   `{{[0-9]+}}` after a generated-name suffix or `idr.program`.
5. A `grep -rl` for the old linear array module and its frozen type
   (named under `## Delete`) over `tests/programs` and `bench/README.md`
   prints nothing; the four deleted directories are gone; every ported
   program's `expected-stdout` and `expected-crash` equal HEAD's
   (`git diff --stat` shows none of them).
6. `tests/spec/*/run` for the five new tests pass on this checkout's
   sources once the C++ and Idris lanes land, and fail on HEAD's
   (each prints what it found).
7. `sh -n` on every changed `run` and `tests/lib/*.sh`; the Idris
   typecheck of `tests/tests.ipkg` with a private build dir (only if a
   `.idr` changed).
8. `bench/run.sh` compares only `this compiler` and `clang -O2` (read the
   loop); `sh -n bench/run.sh`.
9. The handoff lists every NEEDS-ACCEPTANCE file: the two polymorphism
   fixtures' `expected` (C20's line and message), `polymorphism-growing-rank`,
   the registry fixtures (that Idris loads a shadowing module under
   `--no-prelude`, D43's conjecture), `dialect-syntax`,
   `dialects-current`, `data/shapes`' check, and every array port (it
   type-checks against C19 only on the owner's machine).

## Stop and return

Return when items 1 to 13 are written and acceptance 1 to 5, 7 and 8 hold
on the tree. Report, without stopping: any C12 step a test reads that is
not a top-level pass (its check then has no module to read); C13's and
C22's file names if they differ from the artifact table; any C19 function a
port needs and the contract lacks; `tests/idr/stack/hot-loop/expected`
(U17's) and any other U17 file that prints the e2e transcript; the
`Makefile` installing `mlir-array` for the bench's Chez build (the
coordinator's).
