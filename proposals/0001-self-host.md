<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Self-hosting: `make self` finishes

**Status (2026-10-19):** open; S3 is next, and it waits on one toolchain
rebuild (§2, step 1). What is done: the frontend, running on Chez,
compiles its own sources and the fork with no refusal and no patch. That
was S1, the refusal census (`bench/records/2026-10-15-self-s1.md`), and S2,
the fixes. S2 was the TTC decoder at stock speed (da9492a9), no escape
hatch (4d190757), Nat keys by value (d1dc847e), each data type written
once (08647d2e, `bench/records/2026-10-16-self-emit.md`), the polymorphism
checker (3fc4d2e4), and the fork's `SyntaxInfo` and `DLY` knots as plain
data (2c042728). `tools/self.sh` runs each stage's two halves apart.

That frontend step last ran on 2026-10-18, before the representation wave
landed (2c042728): 345 s, 5.64 GB peak, an 82 MB module (*measured*,
`bench/records/2026-10-17-self-growth.md`). Nothing of self-hosting has run
since:
- the representation wave's frontend has not compiled itself;
- the pipeline has never run on the self module;
- `make self` has never finished.

The last texts of the done stages are at 77eaa5b1: the S2.1 bytecode
design, the polymorphism decision and the checker's swarm packet with its
integration record.

Goal: the frontend (`compiler/src`) and the fork (`compiler/idris`),
compiled by idris-mlir itself, stages 1 to 3, with stage 2 the same as
stage 3, on the four targets. Claims are marked *read* (the path),
*measured* (the record), *recalled*, *conjecture* or *decision*.

## 1. What `make self` does (*read*)

`make self` (`Makefile:254-265`) runs three steps:
1. `self-fork` installs the fork into the checkout prefix as
   `idris-compiler`, again whenever a fork source changes.
2. `tools/verify-pins.sh built llvm sysroot` refuses a toolchain that is
   not the pinned one with every carried patch.
3. `tools/self.sh` runs the stages.

Each stage copies `compiler/src` afresh to `build/self/src` and runs two
halves, each alone, under its own `peak_memory` and timeout:
- **The frontend half** (limit 1800 s) writes the `.mlirbc` and the Core,
  and keeps the TTCs. Stage 1 uses `make build`'s frontend, on Chez;
  stage N uses stage N-1's `idris-mlir-front`.
- **The pipeline half** (limit 7200 s) is `make build`'s `idris-mlir`,
  which compiles that module to `idris-mlir-front`. A module given to
  `idris-mlir` is never removed, so a failed pipeline half can be rerun by
  hand on the module that is kept.

At stage 3, `self.sh` compares stage 2 with stage 3 byte for byte: the
executable, the module, the Core and every TTC. `tools/self.sh 1` runs
stage 1 alone. Everything a stage keeps is in `build/self/stageN/`
(`self.sh`'s header).

## 2. The plan

1. **The shared toolchain with upstream 62 and 63** (the coordinator; the
   lanes may not rebuild it, `tools/lanes/README.md`).
   - Why: the toolchain built on 2026-10-19 carries the LLVM patches through
     61. `make self`'s pin check refuses it until 62 and 63 (4dde6b7f) are
     built in, as the suites' checks do.
   - What they fix: the two are the greedy driver's and liveness's
     quadratics in a match's cases. Before them, the tag-limit program took
     234 s at 4k cases; with them it takes 3.4 s (*measured*, 4dde6b7f).
     The self module's largest matches are of that shape (*conjecture*).
   - Acceptance: `tools/verify-pins.sh built llvm sysroot` passes.
2. **S3: stage 1 on arm64 macOS.** `make self-fork`, then `tools/self.sh
   1`.
   - **The frontend half**, for the first time on the representation
     wave's frontend. Watch its memory. Lane L22's private run of the self
     compile ran out of memory on a type-level 2^63 written in unary. The
     fix (`Walk.capacity`, `compiler/src/IdrisMLIR/Frontend/Walk.idr`) has
     run only on small programs (*recalled*, the 2026-10-18 checkpoint at
     77eaa5b1).
   - **The pipeline half**, for the first time ever.
     - Known at test scale since the cutover (*measured*):
       - the label solve is near linear: 65,536 labels in 10.4 s
         (the label solve's audit, last at 77eaa5b1);
       - a function past 4096 LLVM instructions keeps its runtime calls
         out of line (`idr::target::inlineCallerInstructions`), so LLVM's
         live ranges stay tractable;
       - IdrRcGrades went from about 3.5 s to 21 s on
         every-interfaces-export (`audits/bugs.md`, the ownership lane's,
         unbisected).
     - Unknown: everything else at this scale.
     - The first verification after `idr-defunctionalize` is where the
       knot check (`foreign/idr/lib/IR/Verify/Knots.cpp`, rule `cycle`)
       first sees the fork's types. It confirms the knots of S2 as plain
       data, which a scratch analysis over the Core alone has checked so
       far.
   - What happens to a failure: a refusal or an internal error is fixed by
     D2. A refusal that names the frontend's or the fork's code is fixed in
     that code; any other failure is a bug of the pass that raised it. Such
     a bug goes to `audits/bugs.md` under the lane that owns the pass, and
     the run goes on once it is fixed.
   - Acceptance: both halves exit 0. A record goes under `bench/records/`
     with:
     - the frontend's phases, peak memory and module size;
     - the pipeline's `-mlir-timing` per pass and its peak memory;
     - the label solve against 10 s and the optimizer against 600 s (the
       pipeline cutover's margins, at 484d6403).

     Per D4, these figures are a record, not a gate.
   - Before it: idr-optimize's wave count and largest component as pass
     statistics (0008 §10), so the record holds them; and the pipeline
     half's limit raised (D10).
   - Waits on: step 1, and `make build` passing on main. It does not wait
     for green suites (D9).
3. **S4: `make self` on arm64 macOS.** Stages 1 to 3.
   - Stage 2's frontend is the first run of the frontend that idris-mlir
     compiled. Its heap is snmalloc's, with no limit of ours: the first
     4 GiB in one aligned region, then whatever the machine gives
     (`runtime/Alloc/Cells.cpp`); its stack is one 64 GiB reservation
     (`runtime/Start/Runner.cpp`). A stage that runs out of memory is
     fixed by D4, in the stage's design.
   - Then `tests/static-linking` takes the native `idris-mlir-front` among
     the executables it checks. Its comment leaves the frontend out "until
     the frontend compiles itself".
   - Acceptance: `make self` prints `stage 2 = stage 3`, on a tree whose
     suites pass on arm64 macOS. Each stage's halves (time and peak) and
     D5's record go under `bench/records/`.
   - Waits on: S3.
4. **S5: `make self` on the three Linux targets.** The same steps, on
   x86_64 Linux and on arm64 Linux at 4 KiB and at 16 KiB pages.
   - Acceptance: as in S4, there. `make self` holds then (D8).
   - Waits on: S4, and on 0002's builds and suites passing on each
     target.

After it, not in it:
- the test machinery under both hosts (D7);
- `make self` as a test ("The test suite the audit planned", §7);
- G1 (0006), which starts on the tree `make self` leaves;
- the toolchain bump (0005);
- 0014's features.

## 3. Alternatives rejected

- **A compiler case for the fork.** That would exempt a trusted library from
  a rule (the static-argument rule, the knot rule, the pragma rule). Each
  exemption is a branch by origin, the subset is deliberate (47f97059), and
  the fork is ours.
- **An `assert_total` at a refused site.** A trust is stated once
  (AGENTS.md, `Idris.Host`), and an assertion at the site would be a second
  copy of it.
- **Comparing stage 1's module with stage 2's.** Stage 1's frontend runs on
  Chez, so that comparison would make Chez's meaning a gate (no oracle).
- **Breaking a knot S3 finds with a weak reference or a collector.** The
  memory model keeps the heap acyclic, and counting rests on that.

## 4. Decisions

- **D2.** A refusal is fixed in the code it names, never in the
  compiler's rules.
  - In the fork, a definition is made total where its recursion is the
    fork's own.
  - Where the recursion is Idris's theory's (a call of the evaluator or the
    elaborator, or a recursion on what the evaluator returns), the
    definition rests on the one stated trust, `Idris.Host`'s, extended
    there. It never gets a new assertion at the site.
  - Reason: one thing, one representation.
- **D4.** The memory and time figures are a record, not a gate. The
  exception is a stage that does not fit the machine or does not finish:
  then the stage the record names is fixed first, where its design is.
  - the frontend's memory: 0011;
  - the optimizer and the labels: S3;
  - LLVM: 0008's split.

  The frontend's peak and the pipeline's are recorded apart.
- **D5.** `make self` compares at the default thread count. Thread
  independence is shown two ways:
  - `tests/determinism-*`, on every suite run;
  - one record of stage 3 compiling itself at the counts
    `harness/lib/determinism.sh` names, read from there.

  Reason: the counts are one fact, in one place.
- **D7.** The test machinery also builds and runs under idris-mlir, while
  the stock host keeps running it (AGENTS.md: two hosts). What blocks it
  today (*read*):
  - `harness/Runner.idr` calls `system` (`:53, 69, 73`);
  - `harness/Main.idr` and `Runner.idr` import `Test.Golden`;
  - `harness/Lock.idr` imports `Language.JSON`;
  - `harness/harness.ipkg` depends on `contrib` and `test`, packages this
    compiler does not ship.

  The fix: process creation moves into sh glue, and the imports move to
  base. The generators (`Gen`, `Sem`, `Fuzz`, `TwoLevels`, `Prims`,
  `Lazy`) are written for both hosts already, and `tests/fuzz-two-hosts`
  compiles them with idris-mlir. That test fails on main today, with
  internal errors from idr-rc-exclusive (`audits/bugs.md`).
  - When: after `make self`.
  - Owner: the coordinator, as a lane of its own when it starts.
  - Acceptance: `make test` runs with a runner that idris-mlir built.
- **D8.** `make self` holds when stage 2 = stage 3 on the four targets,
  recorded under `bench/records/`. This proposal is deleted then.
- **D9.** S3 runs before the suites are green. S4 is accepted only on a
  green tree.
  - Reason for S3: like S1, it is a census. Every refusal, internal error
    and superlinear pass it finds belongs to some lane's work, and the
    lanes need that list while they fix the bugs `audits/bugs.md` holds.
  - Reason for S4: a stage 2 that differs from stage 3 is debugged across
    some 70,000 functions. A known wrong-output bug in the suites
    reproduces in seconds, so it is fixed there first.
- **D10.** S3's pipeline half runs without `tools/self.sh`'s 7200 s
  limit: its first run is a census whose time nothing has measured, and a
  run cut short records nothing. The frontend half keeps its 1800 s, which
  it has met (345 s). From S4 on, both halves take limits set from S3's
  record. Reason: a limit is a fact measured, not guessed.
