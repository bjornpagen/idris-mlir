<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: the coordinator's decisions C1 to C80, against the live tree

HEAD at start f5736f12, at finish d4fc5e82 (lanes committed during the
read; none of the files cited below changed between the two, and no
commit in that range amends a decision of C1 to C80). Read only: nothing
was built or run. Every decision from line 1632 of
`proposals/0000-mlir-native.md` was checked, with its amendments
(C144 on C21, C157 on C39 and C65, C158 on C11, C162 on C21, C164 on C78,
C167 and C203 on C38, C168 on C40, C196 on C1 and C24, C200 on C52, C201
on C43). Paths are from the repository root. Grounds: read (the file was
opened at the cited lines) or measured (`git grep`, `find`, `ls`). Owners
from `ownership.json`. The generated outputs (the six stand-ins in
`include/idr/IR/Generated/` and the absent `.inc` files) are not
reported.

The D68 growth proof (L16: `Proof/`, `Frontend/Growth*`, `Finite.idr`,
the run-time re-check, C222, `TS.readings`) is in progress; it bears on
C56 and is not detailed here.

## L03

- **C7** `compiler/spec/spec.ipkg:83-94` — C7 puts the generator in
  `compiler/specgen/`; the tree has no `compiler/specgen` and builds
  specgen as `executable = specgen` of the specification's own package,
  its nine `IdrisMLIR.Spec.Generator.*` modules in the module list, so
  every package that depends on `idris-mlir-spec` (frontend, harness,
  syntax samples) installs the generator too. `ownership.json` gives
  L03 that layout; the proposal still says otherwise. Code and proposal
  disagree; which one moves is the coordinator's (read, measured).
- **C78** `compiler/spec/IdrisMLIR/Spec/Generator/Main.idr:5-7, 33-54` —
  C78: the fingerprint "covers the generator's own sources and hashes the
  specification's printed value". specgen hashes the specification's
  *source files*, found by parsing `spec.ipkg`'s text for its module list
  (`modulesOf`, a line scanner over `modules =`), so a comment edit
  changes the manifest and a change in the printed value is caught only
  through the text. Code and proposal disagree (read).
- **C144 (on C21)** `compiler/spec/IdrisMLIR/Spec/Pipeline/Stage.idr:82-85,
  121, 167-170` — C144: "No hold is ever undecided ... the grade has no
  undecided case and no meaning that depends on the stage." The stage
  table still has `StageHolds = HoldsUndecided | HoldsDecided`, printed
  as `Undecided` with the line "a hold may still be strengthened before
  counting", true at `Higher` and `First`, and two readers (L09, L12
  below) branch on it. The fact they want is "counting has not run",
  which `countingAt` already states (read).

## L04

- **C34** `foreign/idr/include/idr/IR/Layout.h:282-284` — a hand
  `isInvalidated` that returns `!pa.isPreserved<Layouts>()`, which is
  MLIR's default for an analysis with no such method
  (`.toolchain/llvm-project/mlir/include/mlir/Pass/AnalysisManager.h:89-96`).
  C34 deletes the hand `isInvalidated`s: an analysis that reads none
  needs none, and one that reads others takes `ReadsAnalyses` (read).

## L09

- **C144** `foreign/idr/lib/Transforms/Joins/YieldedFields.cpp:58-63` —
  `holdsUndecided` asks `holdsAt[stage] == StageHolds::Undecided`, and its
  comment says "the holds of `op`'s function are still undecided", the
  state C144 says does not exist (read).

## L11

- **C24** `runtime/Io/Io.h:40`, with
  `compiler/src/IdrisMLIR/Registry/Primitives.idr:366-371` (L16) — C24:
  `handle.is_null` is `arith` "over encodings held in `Spec.Clocks` and
  `Spec.Handles`". No `Spec.Handles` exists (`ls
  compiler/spec/IdrisMLIR/Spec/Runtime/`: Clocks, Declarations, Endings,
  Helpers, Layout). The null handle is held twice: the runtime's
  `nullHandle = -1` and the registry's literal `18446744073709551615`,
  written twice (`idris2_isNull`'s comparison, `idris2_getNull`'s handle)
  (read, measured).
- **C44** `foreign/idr/lib/Driver/ReadRuntime.cpp:69-89`, with
  `CMakeLists.txt:231, 316` (INT) — C44: "The prepared runtime's bitcode
  lives beside the object on every target. Deletes `BitcodeHome`, its
  switch, both CMake branches, the section path." `BitcodeHome` and the
  switch are gone, but the bitcode is inside each archive member (ELF
  `-flto=full -ffat-lto-objects`, Mach-O `-fembed-bitcode=all`) and read
  out of the object's section by `IRObjectFile::findBitcodeInMemBuffer`:
  the section path stays, as two target-entry flag sets. Code and
  proposal disagree (read).

## L12

- **C39** `foreign/idr/lib/Conversion/Elements.cpp:113-133` — C39
  deletes the lowering's uniqueness branches (`Elements.cpp:64-82` then)
  and says "Moves and counts are IR; the lowering lowers primitive ops
  only." `takeOut` still emits, in the lowering, an `scf.if` on
  `isUnique` of a boxed element whose shared arm increments the value,
  decrements the box and allocates a fresh one (`:125-133`); the counts
  and the fresh cell are decided below the IR (read).
- **C144** `foreign/idr/lib/IR/OpsArrayFusion.cpp:78-85` — `uncounted`
  ("the program counts no reference yet") reads `holdsAt[...] ==
  StageHolds::Undecided`, which is false at `Graded`, a stage before
  counting (`countingAt` gives `Uncounted` there). The name says one
  stage fact and the code reads another, through the case C144 removes
  (read).

## L14

- **C34** `foreign/idr/include/idr/Analysis/Solver/ProgramGraph.h:98-100`,
  `foreign/idr/include/idr/Analysis/Solver/TypeGraph.h:50-52` — two more
  hand `isInvalidated`s restating MLIR's default, beside the
  `ReadsAnalyses` template C34 asks for (`Decision.h:54-59`) (read).
- **C32** (with L08) `upstream/77-dataflow-state-storage/README.md:33-36`
  — C32: Borrows "leaves the framework for C1's marking only on the
  patched framework's number, taken first". The numbers (Ranges and
  Borrows on patch 77, bytes per anchor, four targets, stage 1) are not
  recorded, while Borrows already runs on the solver layer's marking
  (`foreign/idr/lib/Analysis/Ownership/Borrows.cpp:41-43`, no
  `DataFlowSolver`). The measurement needs a build; the order C32 states
  was not kept (read, measured).

## L16

- **C23** `compiler/src/IdrisMLIR/Types.idr:69-81, 445-449` — the frontend
  declares its own `data Signedness = Signed | Unsigned` and
  `signedness`, which Emit reads (`Emit/Operations.idr:266-275`), beside
  the specification's `Signedness` (`compiler/spec/IdrisMLIR/Spec/Ops/Numeric.idr:33`,
  L13), which nothing in `compiler/src` imports: one enum held twice.
  Its comment names the old mnemonics (`divs` or `divu`), C11's rename
  (read, measured).
- **C50** `compiler/src/IdrisMLIR/MLIR.idr:184-185, 200-201, 214-217` —
  the text printer answers states the type still allows with dummy text:
  an idr type prints `none`, an idr attribute or a location `unit`, a
  float `0 : <type>`, each with a comment that it is never read. C50: no
  idr text crosses the handoff and a double crosses as its bits; the
  text-crossing attribute (`Spelled`) can still hold them, so the guard
  is a comment, not the representation (read).
- **C55** `compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr:59-90` — C55:
  once the TTC keeps a block's typed parent (C129, now `CaseBlock : Name
  -> Nat`), "a case block is emitted in place as a region of its parent".
  Case blocks are still translated as definitions of their own, named
  `<parent>.case<k>` (`typedBlock`, `keyOrigin`, `nameIdentity`
  `:978-984`); every `CaseBlock` reference in `compiler/src` is a naming
  or parent site (`Closed.idr:524`, `State.idr:151`, `Boundary.idr:162,
  477`, `Keys.idr:64, 144`), and no translation step puts a block's tree
  into its caller (read, measured).
- **C80** `compiler/src/IdrisMLIR/Registry/Entry.idr:304-308, 384, 432`,
  `compiler/src/IdrisMLIR/Registry/Faster.idr:108-116` — C80: "list and
  numeral are derived shapes ... Deletes ... `ListType` as a kind
  source." The registry keeps a `ListType` hook on
  `Prelude.Basics.List`, a Faster row on a data type, whose comment says
  "its kind is the registry's, never guessed from its shape". It sets
  `sumShape = IsList`, which nothing reads (`IsList` appears only at its
  declaration and that one write); the hook's doc names a
  `Term.DataShape`'s `BaseListSum` that does not exist. Dead code and a
  comment contrary to C80 (read, measured).

## L17

- **C55** `compiler/idris/src/Core/Case/CaseBuilder.idr:40-49` — with the
  run-time phase gone, `data Phase = CompileTime RigCount` is a
  one-constructor sum around a `RigCount`, with its own `Eq`, matched
  wherever the builder took a phase: the vestige of the deleted
  alternative (read).
- **C66** (with L19) absent: `git grep 'Cons2\|natToFinLT 3'` outside
  `proposals/`, `audits/`, `sources/` finds nothing — C66 names its
  discriminator, `natToFinLT 3 {n = 10}` elaborating while `Cons2.idr`
  is still refused. The path rule is in `Core/AutoSearch.idr:45-46,
  143-146`; no test holds either side of it (`tests/linarray-bubble`
  passes `natToFinLT`'s proof explicitly) (measured, read).

## L19

- **C12** `tests/contracts-quantities-kept/contracts-quantities-kept.mlir:23-24`,
  `tests/expect-constant-stack/expect-constant-stack.mlir:66`,
  `tests/linear-cast-forgets-claims/linear-cast-forgets-claims.mlir:37`,
  `tests/linear-fields-each-once/linear-fields-each-once.mlir:41` — five
  prose `expected-error`s ("is many, and Idris proved it once", "the
  stack grows with the recursion of @back", "whose hold claims more or is
  freed otherwise", "uses a value used once that is already used on the
  same path"); C12 deletes the prose `expected-error`s. The other 29
  name the property only (measured, read).
- **C60** `tests/io-buffer/run:4-21, 73` — the test rebuilds every IO unit
  with `-DIDRIS_RT_IO_BUFFER_SIZE=4` and `=7` and compares with the
  default build. C60 deletes `IDRIS_RT_IO_BUFFER_SIZE`: no source under
  `runtime/` reads it (0 hits), the buffer is `bufferSize =
  rt::platform::pageSize()` (`runtime/Io/Io.h:23`), so the "small buffer"
  builds are the default build and the relation is checked against
  itself. C60: "The IO test writes past the shipped buffer" (read,
  measured).
- **C7** `tests/registry-only/run:36-46` — C7's amendment: the test "gains
  `compiler/spec/` as a second home". It scans `compiler/src` and
  `foreign/idr` only; `compiler/spec` is not read at all (under C6's
  replacement the specification spells no base name, which the test
  could hold) (read).
- **C33** `foreign/idr/lib/Transforms/Expect/Continuations.cpp:27-28` —
  `contified` builds a `SymbolTableCollection` and a `SymbolUserMap` of
  the program to find callers; C33 deletes caller-only
  `SymbolUserMap`s, the program graph's callers table being the one
  index of calls (read).
- **C72** `foreign/idr/lib/Transforms/Expect/Report.cpp:15-16` — "after
  it a func.func or an llvm.func": C72 deletes the `func.func` stage; the
  lowering builds `llvm.func` directly. Stale comment (read).

## L21

- **C39** `foreign/idr/lib/Conversion/Lower/Counting.cpp:105-153` —
  `LowerTakeInto`, where the type proves nothing of sharing, emits in the
  lowering an `scf.if` on `isUnique` (`:131-132`) whose shared arm
  increments every field (`:141`), decrements the cell (`:143`) and
  allocates a fresh one (`:144`). C39: "Moves and counts are IR; the
  lowering lowers primitive ops only", with `idr.count.match_unique` the
  one run-time test (lowered at `:155-197`). This restates the
  match's shared arm below the IR (read).
- **C42** (with L03) `foreign/idr/lib/Conversion/Lower.cpp:1-23, 262-271`,
  `compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr:455-456` — C42:
  "Two program passes ... then the lowering as a function pass." The two
  program passes exist (`lower-runtime`, `lower-statics`); `lower` is an
  `OnProgram` pass with four phases on the program and its own
  `failableParallelForEach` over functions, not a pass the pass manager
  nests on functions. No worker-and-merge scheduler remains. Code and
  proposal disagree (read).

## INT

- **C43, C201** `CMakeLists.txt:177-222` — the target entries now declare
  `IDRIS_MLIR_TOOL_STACK_BYTES`, `_TOOL_SIGNAL_BYTES` and
  `_OUTSIDE_STACK_BYTES` as unmeasured, and configure refuses until they
  are given. The per-target measurement and its record in each entry
  remain (stage 1, on each target; with L11) (read).
- **Hand stand-ins outside `Generated/`**
  `compiler/src/IdrisMLIR/Dialect/Idr.idr:1-5`,
  `compiler/src/IdrisMLIR/Encoding/Wire.idr:1-5` — both say "Generated by
  specgen ... `make check` regenerates it ... Do not edit", and both were
  written by hand (27b7c5bc, 005b9d6c, 257e80c0, a7bc3107) and since
  edited by L16 commits (66838a75, 5d8044cd). They are two more
  stand-ins beside the six in `include/idr/IR/Generated/`, in L16's tree;
  the specgen run must replace them (C50, C51, C78) (read).
- **Qualification measurements not recorded**: C35 (per-function
  `remove-dead-values` with U1 and U2, into the patches' `upstream/`
  record), C36 (reached pairs, copies, code size, solve time and
  footprint), C53 (the precompiled header "measured as built", after the
  `-ftime-trace` baseline), C54 (release cost of extensive hardening).
  Each needs a build (measured: no record found in `upstream/`,
  `audits/`, `PINS.md`).

## Outside the area, seen in passing

- **L06** `tools/check-units.py:1-20` — a Python tool of ours (syntax-checks
  C++ units from `compile_commands.json`); AGENTS.md: anything of ours
  above the C++ is Idris, shell only as glue (read).

## Count

91 items checked (C1 to C80, and the 11 amendments listed at the top).
65 found done: 56 of C1 to C80 with nothing remaining, and 9 of the
amendments (C157, C158, C162, C164, C167, C168, C196, C200, C203). Open:
C7, C12, C21 (by C144), C23, C24, C32, C33, C34, C35, C36, C39, C42,
C43 (by C201), C44, C50, C53, C54, C55, C56 (growth, in progress), C60,
C66, C72, C78, C80. Closed since recheck 2 among them: C53's
precompiled header (`foreign/idr/lib/IR/CMakeLists.txt:128-131`,
`CMakeLists.txt:446`), C77's three `.txt` rules, the 98 stale CMake
sources, and the name-keyed function maps in Contify, Demand and
Deduplicate.
