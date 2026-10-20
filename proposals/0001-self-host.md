<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Self-hosting: `make self` finishes

**Status (2026-10-19):** open; S3 is next, after one toolchain rebuild.

**Goal.** idris-mlir compiles the frontend (`compiler/src`) and the fork
(`compiler/idris`), stages 1 to 3, and stage 2 is the same as stage 3, on
the four targets. Nothing else is in this proposal: a code improvement
belongs here only when a stage cannot finish without it, and then it is
fixed as a bug (`audits/bugs.md`) or in the proposal that owns its
design (D4). Claims are marked *read* (the path), *measured* (the
record), *recalled*, *conjecture* or *decision*.

**Done.** S1 and S2: the frontend, running on Chez, compiles its own
sources and the fork with no refusal and no patch
(`bench/records/2026-10-15-self-s1.md`, `2026-10-16-self-emit.md`,
`2026-10-17-self-growth.md`; the stages' texts at 77eaa5b1). It last ran
on 2026-10-17, before the representation wave (2c042728): 345 s, 5.64 GB
peak, an 82 MB module (*measured*). Since then:
- the representation wave's frontend has not compiled itself;
- the pipeline has never run on the self module;
- `make self` has never finished.

## 1. What `make self` does (*read*)

`make self` (`Makefile`) runs three steps:
1. `self-fork` installs the fork into the checkout prefix as
   `idris-compiler`, again whenever a fork source changes.
2. `tools/verify-pins.sh built llvm sysroot` refuses a toolchain that is
   not the pinned one with every carried patch.
3. `tools/self.sh` runs the stages.

Each stage copies `compiler/src` afresh to `build/self/src` and runs two
halves, each alone, under its own `peak_memory` and timeout:
- **The frontend half** (limit 1800 s) writes the `.mlirbc` and the Core,
  and keeps the TTCs. Stage 1 uses the build's frontend, on Chez;
  stage N uses stage N-1's `idris-mlir-front`.
- **The pipeline half** (limit 7200 s; D10) is the release build's
  `idris-mlir` (`make self` builds it first: the self compile is a
  production compile, and the dev build the tests run is not optimized),
  which compiles that module to `idris-mlir-front`. The
  module is kept, so a failed pipeline half can be rerun by hand on it.

At stage 3, `self.sh` compares stage 2 with stage 3 byte for byte: the
executable, the module, the Core and every TTC. `tools/self.sh 1` runs
stage 1 alone. A stage keeps everything in `build/self/stageN/`.

## 2. The plan

1. **The shared toolchain with upstream 62 and 63** (the coordinator).
   The pin check refuses `make self` until the patches 4dde6b7f carries
   are built in. They are the greedy driver's and liveness's quadratics in
   a match's cases (234 s to 3.4 s at 4k cases, *measured*), and the self
   module's largest matches are of that shape (*conjecture*). Acceptance:
   `tools/verify-pins.sh built llvm sysroot` passes.
2. **S3: stage 1 on arm64 macOS.** `make self-fork`, then
   `tools/self.sh 1`, with the pipeline half unlimited (D10).
   - **The frontend half**, the first time on the representation wave's
     frontend. Watch its memory: a private run of the self compile once
     ran out of memory on a type-level 2^63 written in unary, and its fix
     (`Walk.capacity`, `compiler/src/IdrisMLIR/Frontend/Walk.idr`) has run
     only on small programs (*recalled*).
   - **The pipeline half**, the first time ever. Known at test scale: the
     label solve is near linear (65,536 labels in 10.4 s), and a function
     past 4096 LLVM instructions keeps its runtime calls out of line
     (`idr::target::inlineCallerInstructions`). Everything else at this
     scale is unknown. The first verification after `idr-defunctionalize`
     is where the knot check (rule `cycle`) first sees the fork's types.
   - **A failure** is fixed by D2: a refusal that names the frontend's or
     the fork's code is fixed in that code; any other failure is a bug of
     the pass that raised it, recorded in `audits/bugs.md` under the lane
     that owns the pass. The run goes on once it is fixed.
   - Acceptance: both halves exit 0. A record goes under `bench/records/`:
     the frontend's time, peak memory and module size; the pipeline's
     `-mlir-timing` per pass and peak memory. It is a record, not a gate
     (D4).
   - Waits on: step 1 and `make build` passing on main; not on green
     suites (D9).
3. **S4: `make self` on arm64 macOS,** stages 1 to 3.
   - Stage 2's frontend is the first run of a frontend idris-mlir
     compiled. Its heap is snmalloc's with no limit of ours (the first
     4 GiB in one aligned region, `runtime/Alloc/Cells.cpp`); its stack
     one 64 GiB reservation (`runtime/Start/Runner.cpp`).
   - `tests/static-linking` takes the native `idris-mlir-front` among the
     executables it checks (AGENTS.md: everything we build links
     statically); its comment leaves the frontend out "until the frontend
     compiles itself".
   - Acceptance: `make self` prints `stage 2 = stage 3`, on a tree whose
     suites pass on arm64 macOS; each stage's time and peak go under
     `bench/records/`.
   - Waits on: S3, and the suites green.
4. **S5: `make self` on the three Linux targets** (x86_64, arm64 at 4 KiB
   and at 16 KiB pages). Acceptance: as S4, there. Waits on S4 and on
   0002's builds and suites passing on each target.

## 3. Alternatives rejected

- **A compiler case for the fork.** That would exempt a trusted library
  from a rule (the static-argument rule, the knot rule, the pragma rule).
  Each exemption is a branch by origin, the subset is deliberate
  (47f97059), and the fork is ours.
- **An `assert_total` at a refused site.** A trust is stated once
  (AGENTS.md, `Idris.Host`), and an assertion at the site would be a
  second copy of it.
- **Comparing stage 1's module with stage 2's.** Stage 1's frontend runs on
  Chez, so that comparison would make Chez's meaning a gate (no oracle).
- **Breaking a knot S3 finds with a weak reference or a collector.** The
  memory model keeps the heap acyclic, and counting rests on that.

## 4. Decisions

- **D2.** A refusal is fixed in the code it names, never in the
  compiler's rules. In the fork, a definition is made total where its
  recursion is the fork's own; where the recursion is Idris's theory's (a
  call of the evaluator or the elaborator, or a recursion on what the
  evaluator returns), it rests on the one stated trust, `Idris.Host`'s,
  extended there, never on a new assertion at the site. Reason: one
  thing, one representation.
- **D4.** Time and memory are a record, not a gate. The exception is a
  stage that does not fit the machine or does not finish: then the cause
  the record names is fixed first, as a bug of its pass, or, when the fix
  is a design, by the proposal that owns it (the frontend's memory:
  0011; LLVM's size: 0008's split), taking only the part the stage needs.
- **D5.** `make self` compares at the default thread count. Thread
  independence is the determinism tests' (`tests/determinism-*`) and
  G1's (0006).
- **D8.** `make self` holds when stage 2 = stage 3 on the four targets,
  recorded under `bench/records/`. This proposal is deleted then.
- **D9.** S3 runs before the suites are green; S4 is accepted only on a
  green tree. S3, like S1, is a census: every refusal, internal error and
  superlinear pass it finds goes to the lane that owns it while the lanes
  fix `audits/bugs.md`. A stage 2 that differs from stage 3 is debugged
  across some 70,000 functions, while a wrong output in the suites
  reproduces in seconds, so those are fixed first.
- **D10.** S3's pipeline half runs without `tools/self.sh`'s 7200 s limit:
  its first run is a census whose time nothing has measured, and a run cut
  short records nothing. The frontend half keeps its 1800 s, which it has
  met (345 s). From S4 on, both halves take limits set from S3's record.
  Reason: a limit is a fact measured, not guessed.
