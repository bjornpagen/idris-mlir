# U01 — An upstream patch instead of idr-dead-values

Mandatory findings: F-up-3

## Permitted outcome

`remove-dead-values` builds a new call for every call of a private
function that returns a value, even when it erases no result, so the
module's `OperationFingerPrint` changes. `idr-dead-values`
(`IDR/Simplify/DeadValues.cppm`, `IDR/Simplify/DeadValues/Pass.cc`) works
around it by running the pass on a copy. That behaviour becomes a bug of
its own under `upstream/`, with a reduced reproducer, a patch to the
pinned llvm-project and a check, as `upstream/README.md`'s Layout
requires, and the simplify round runs upstream `remove-dead-values`
itself (C11.2). Mandatory.

**The two clang crashes are no longer this lane's** (C11.1).

- `clang-module-predeclared-new` retired with the pin (20fcfadb), and
  `IDR/Driver/Retarget.cppm` is already plain: F-up-2 is done.
- `clang-module-layout-forward-declaration` crashes only the x86_64
  Linux build. The clangs of 23.1.2 and of 7208ba24 both compile its
  unit on arm64 macOS, this lane's host, and no x86_64 Linux toolchain
  exists at the pin. So the work this lane had for it (reduce the crash,
  patch clang, write `IDR/Stack/Escape.cppm` plainly) cannot run here.
  Instead, you leave `upstream/11-clang-module-layout-forward-declaration`,
  its check and `Escape.cppm` (its `func::FuncOp` sets and its `PIN`
  marker) exactly as they are. NotRun, recorded by the coordinator under
  F-up-1: the check on x86_64 Linux at the pin, the reduction, the fix
  and the plain `Escape.cppm`.

## Owner / exclusive writes

- `upstream/16-remove-dead-values-unchanged-call` (new)
- `T/upstream/remove-dead-values-unchanged-call` (new)
- `IDR/Simplify`

**Excluded:**

- `upstream/06-remove-dead-values-unreachable` and
  `upstream/02-composite-fixed-point-sccp`. Each is a pending LLVM
  submission that another agent sends. Their READMEs name
  `idr-dead-values`: return the replacement sentences, and the
  coordinator applies them.
- `upstream/README.md`, whose status table the upstreaming agent keeps,
  and every other `upstream/` and `T/upstream/` directory.
- `IDR/Stack/Escape.cppm` and `IDR/Driver/Retarget.cppm`.
- `PINS.md`, which is the coordinator's. Return the text of the new
  entry, and the changed lines of `remove-dead-values-unreachable` and
  `simplify-structural-fixpoint`.
- `INC/Passes.td`, where the coordinator deletes the `idr-dead-values`
  definition and renames the step in `idr-simplify`'s description.
- `tools/`: patches are applied by `tools/patches.sh` as they are.

## Read first

- `upstream/README.md`, its Layout: what a bug directory holds, and how
  `llvm.patch` is applied and checked. Its rules for sending and its
  Sending procedure are another agent's: you send and post nothing.
- `PINS.md`: `remove-dead-values-unreachable` and
  `simplify-structural-fixpoint`.
- `contracts.md` C11 and C13.
- `findings.md` F-up-3, and `findings/llvm-trunk-mechanisms.md`, "Every
  other entry, at 7208ba24", its first item.
- `upstream/06-remove-dead-values-unreachable/` in full, read only,
  especially the last paragraph of its `## Patch`, and how it checked
  its patch in a scratch `mlir-opt`.
- `upstream/02-composite-fixed-point-sccp/llvm.patch`, read only: its
  `sccp.mlir` RUN line is the model for your test.
- `IDR/Simplify/{Pass.cc,Round.cppm,DeadValues.cppm,DeadValues/Pass.cc,Simplify.cppm,CMakeLists.txt}`.
- The pinned sources, read only:
  `mlir/lib/Transforms/RemoveDeadValues.cpp:201-209` and `:720-735`,
  `mlir/lib/IR/PatternMatch.cpp:278-314` and
  `mlir/lib/Transforms/CompositePass.cpp:69-103`.

## Fixed decisions

- **The pin is llvm main 7208ba24** (`toolchain.lock.json`). The
  toolchain on this host, `.toolchain/llvm-macos`, carries the
  `llvm.patch` of 02 to 07, 09 and 15, applied in name order.
- **Your patch** is `upstream/16-remove-dead-values-unchanged-call/llvm.patch`:
  a plain `git diff` against 7208ba24 that would be the pull request,
  with its test in `mlir/test`. The commit message is not in the file
  (`upstream/README.md`, Layout). There are no backports: if main past
  the pin already fixes it, report the commit and do not move the pin.
- **Independent of 06.** `tests/spec/upstream-patches` checks that each
  patch applies to the pinned source alone and after the patches before
  it, so your hunks stay out of the lines 06's patch changes. A site
  such as `RewriterBase::eraseOpResults`, which builds a new op for an
  empty set, keeps the two patches independent. Your test hunk too:
  06's patch appends its cases to the end of
  `mlir/test/Transforms/remove-dead-values.mlir`
  (`@@ -918,3 +918,100 @@`), and a hunk that appends there as well has
  no trailing context, so `git apply` anchors it to the end of the file:
  it applies alone and fails after 06. Put your case before that file's
  last split (the `// -----` at `:899`, before
  `@callee_with_dead_return`), or in a test file of its own in
  `mlir/test/Transforms`.
- **The patch's test checks a fingerprint property.** The model is
  `upstream/02-composite-fixed-point-sccp/llvm.patch`: its second RUN
  line of `mlir/test/Transforms/sccp.mlir` runs
  `composite-fixed-point-pass{pipeline=sccp max-iterations=2}` under
  `-verify-diagnostics`, so the test fails unless the pass's output is
  its own fixed point.
- **The round.** `Round.cppm`'s `idr-dead-values` step becomes
  `remove-dead-values{canonicalize=false}` in the same place, after
  `idr-eval` and before `symbol-dce`. Its own canonicalization stays
  off, for the reason `DeadValues.cppm` gives: it folds region-branch
  patterns on the matches alone and leaves a dead constructor holding a
  world or a linear value. That reason moves to the step's comment.
- **You may run** the pinned `mlir-opt` (`.toolchain/llvm-macos/bin`)
  and `idris-mlir-reduce` as the last `make build` left it, on your own
  reproducers, as `T/upstream/*/run` do. You may not build the tree or
  the toolchain.
- **You may build a scratch `mlir-opt`** to check that your patch
  compiles and that its RUN line passes (C13). Compile the upstream
  files your patch changes (the pinned source with the patches before
  yours applied, 06's included, then yours) in a scratch directory
  outside the repository, and link them with an `mlir-opt` main against
  the static `libMLIR*.a` installed in `.toolchain/llvm-macos/lib`, as
  06's README records its own check. That build has no test dialect, so
  a case that uses it does not parse there; keep your case to upstream
  ops. It builds neither the tree nor the toolchain, and nothing of it
  enters the tree.
- **Write in the shared checkout; the coordinator sets it aside at
  integration** (C13). Write everything as usual, where it belongs, and
  list it in your handoff as one group. At integration step 3 the
  coordinator stashes the group before `make check` and `make build`,
  and brings it back at step 5, the patch first, around the toolchain
  rebuild: a new `llvm.patch` makes `tools/verify-pins.sh llvm` refuse
  today's toolchain, and `make build` with it; your check expects the
  patched `mlir-opt`; and the round needs the patched
  `remove-dead-values`, without which the simplify loop's fingerprint
  never repeats.
- **If it does not reproduce** with upstream ops alone, the bug is ours.
  Fix it in `IDR/Simplify`, say so, write no `upstream/` directory, and
  delete the workaround all the same. Then the coordinator sets nothing
  aside.

## Inputs

- C11.2 and C13.
- The pinned sources: `.toolchain/llvm-project` (read-only).

## Outputs

- **`upstream/16-remove-dead-values-unchanged-call/`**: a `README.md`
  with the report, `## Patch`, and `## Upstreaming plan` (status: not
  filed; `check-mlir` not run on main); the reduced reproducer; and
  `llvm.patch`.
- **`T/upstream/remove-dead-values-unchanged-call/{run,expected}`.**
  `run` uses the pinned `mlir-opt`, and `expected` records "no longer
  rebuilds", as the other checks record the patched tools.
- **`IDR/Simplify`**, whose round runs upstream `remove-dead-values`.
- **For the coordinator:** the PINS text, the `Passes.td` lines, and the
  replacement sentences for 06's and 02's READMEs.

## Implement

- **Reduce.** Take a module that `idr-dead-values` keeps unchanged, and
  reduce it to `func` and `arith` with `idris-mlir-reduce`. Show that
  `remove-dead-values` erases nothing from it and still changes it. For
  example, on a module at its fixpoint,
  `composite-fixed-point-pass{pipeline=remove-dead-values max-iterations=1 on-convergence-failure=error}`
  fails to converge. Keep the reproducer and its command in the
  directory.
- **Patch.** Write the smallest change that leaves an op as it is when
  the pass erases none of its results. Its `mlir/test` case checks that
  property, not an op order.
- **The check.** `run` runs the pinned `mlir-opt` on the reproducer as
  above, and says "no longer rebuilds" when it converges.
- **`IDR/Simplify`.** Change the round step as fixed above. `Pass.cc`'s
  `PIN(simplify-structural-fixpoint)` comment stops naming
  `idr-dead-values`. `Simplify.cppm` stops exporting `:deadvalues`, and
  `CMakeLists.txt` and its header comment drop the unit and its glue.

## Delete

- `IDR/Simplify/DeadValues.cppm`, `IDR/Simplify/DeadValues/Pass.cc`, and
  their entries in `IDR/Simplify/CMakeLists.txt`.
- Every use of `IdrDeadValues` and `createIdrDeadValues` in `IDR/Simplify`.

## NOT TO DO

- Do not patch anything but the pinned llvm-project, and do not move
  the pin.
- Do not edit anything under `upstream/06-remove-dead-values-unreachable`
  or `upstream/02-composite-fixed-point-sccp`, or `upstream/README.md`.
- Do not send, post or file anything.
- Do not edit `tools/bootstrap.sh` or `tools/patches.sh`.
- Do not add a workaround elsewhere in place of the one you delete.
- Do not touch `IDR/Stack/Escape.cppm`, its `PIN` marker, or
  `upstream/11-clang-module-layout-forward-declaration`.
- Do not change the simplify loop beyond the round's step. `Pass.cc`
  builds it as upstream's `composite-fixed-point-pass`
  (`"IdrSimplifyLoop"`, `ConvergenceFailureAction::Silent`) over
  `OpenRound`, the round and `CloseRound`. Its fixpoint test is that
  pass's `OperationFingerPrint`, and its budget is `max-rounds` (`limit`,
  `exhausted()`). None of these changes.
- Do not touch `IDR/Simplify/Breakers.cppm`. The loop breakers end the
  loop, and since ccc3e1dc a clone of a breaker keeps `no_inline`
  through `idr-specialize`, as its header says (C11.2).

## Acceptance

- `T/upstream/remove-dead-values-unchanged-call/run` shows the rebuild
  with today's pinned `mlir-opt`. Run it once and put its output in your
  handoff. Its `expected`, "no longer rebuilds", holds with the rebuilt
  toolchain, and the coordinator runs it then.
- Your patch's `mlir/test` RUN line passes on your scratch `mlir-opt`,
  if you built one; say so, with the command. The coordinator runs that
  RUN line by hand at integration step 5, with the rebuilt `mlir-opt`
  and `FileCheck`.
- `tests/spec/upstream-patches` passes when run alone (common
  obligations): your patch applies to the pinned source alone and after
  02 to 07, 09 and 15, and your directory has a `## Patch` and a
  `## Upstreaming plan`. Run it; it builds nothing. Do not run
  `make check`.
- `grep -rn DeadValues IDR/Simplify` finds nothing.
- `git status --short upstream/06-remove-dead-values-unreachable upstream/02-composite-fixed-point-sccp`
  shows nothing.
- **Tempting partial:** keeping the old workaround "until the toolchain
  is rebuilt". Rejected: the coordinator rebuilds at integration, and a
  kept workaround is the thing this lane deletes.
- **Tempting partial:** a hunk in 06's `llvm.patch`. Rejected: 06 is a
  pull request another agent is sending, and a change to it goes to the
  owner first (Escalate if).
- **Tempting partial:** a patch with no reduced reproducer. Rejected:
  `upstream/README.md` requires the reproducer and the check.

## Escalate if

- The fix cannot be made without changing 06's `llvm.patch`, or applies
  only after it. Report the diff. The coordinator tells the owner before
  anything under 06 changes, and records it in 06's README.
- The reduction shows that upstream's design requires the rebuild.
  Report the evidence, and keep the deletion pending the coordinator's
  ruling.
- Main past 7208ba24 already fixes it. Report the commit.

## Stop and return

You are done when:

- `upstream/16-remove-dead-values-unchanged-call/` and its check are
  complete;
- the Simplify deletion is done;
- `tests/spec/upstream-patches`, run alone, passes.

Return the changed paths, the PINS text, the `Passes.td` lines, the
README sentences for 06 and 02, the group the coordinator sets aside
(C13), the check's output with today's `mlir-opt`, the scratch RUN
line's result or `NotRun`,
`Verification: spec/upstream-patches (run) / builds NotRun (swarm policy)`,
and any seams.
