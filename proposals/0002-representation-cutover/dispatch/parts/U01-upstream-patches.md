# U01 — Upstream patches instead of workarounds

Mandatory findings: F-up-1 F-up-2 F-up-3

## Permitted outcome

Three workarounds for upstream behaviour become patches to the pinned
LLVM, each reported, reproduced and checked as `upstream/README.md`
requires. The code that worked around them is written plainly.

1. **Clang's "Cannot get layout of forward declarations".** Its
   workaround is the `func::FuncOp` sets in `IDR/Stack/Escape.cppm`.
2. **Clang's "predeclared global operator new/delete is missing".** Its
   workaround is the `llvm::SmallString` feature string in
   `IDR/Driver/Retarget.cppm`.
3. **`remove-dead-values` rebuilding a call when nothing is erased.**
   Its workaround is `idr-dead-values`, `IDR/Simplify/DeadValues.cppm`
   and `IDR/Simplify/DeadValues/Pass.cc`.

All are mandatory.

## Owner / exclusive writes

- `upstream/clang-module-layout-forward-declaration`
- `upstream/clang-module-predeclared-new`
- `upstream/remove-dead-values-unreachable`
- `T/upstream/clang-module-layout-forward-declaration`
- `T/upstream/clang-module-predeclared-new`
- `T/upstream/remove-dead-values-unreachable`
- `IDR/Stack/Escape.cppm`
- `IDR/Driver/Retarget.cppm`
- `IDR/Simplify`

**Excluded:**

- `PINS.md`, which is the coordinator's. Return the text of each entry's
  new `retire:`/`workaround:` lines.
- `INC/Passes.td`, where the coordinator deletes `idr-dead-values`'s
  definition.
- Every other `upstream/` and `T/upstream/` directory.
- `tools/`: patches are applied by `tools/patches.sh` as they are.

## Read first

- `upstream/README.md`, all of it: the report format, the procedure,
  how patches are applied and checked.
- `PINS.md`, the three entries.
- `contracts.md` C11 and C13.
- `findings.md` F-up-1, F-up-2 and F-up-3.
- The two `upstream/clang-module-*/README.md` files and their reduction
  plans.
- `upstream/remove-dead-values-unreachable/` in full.
- `IDR/Simplify/{Pass.cc,Round.cppm,DeadValues.cppm,DeadValues/Pass.cc}`.

## Fixed decisions

- **Patches are `llvm.patch`**, against the pinned llvm-project
  (`toolchain.lock.json`), applied by `tools/patches.sh` in directory
  order. A backport is `git format-patch` output; a patch of ours is a
  message plus `git diff`.
- **You may run** the pinned clang, `mlir-opt` and `idris-mlir-reduce`
  on your own reproducers, as `T/upstream/*/run` do. You may not build
  the tree or the toolchain.
- **Held out until the rebuild** (C13). Your three C++ changes, the two
  sites and the `IDR/Simplify` deletion, need the patched toolchain: the
  clang fix for the first two, and the patched `remove-dead-values` for
  the third, without which the simplify round's fingerprint fixpoint
  never settles. Write them as usual. The coordinator keeps them out of
  the tree until integration step 5 and applies them after
  `make bootstrap`. List them in your handoff as one group.
- **If a crash does not reproduce** outside our tree at the pin, or the
  dead-values behaviour does not reproduce with upstream ops alone, the
  bug is ours. Fix it in your owned files instead, say so, and delete
  the workaround all the same.

## Inputs

- C11.1 and C11.2.
- The pinned sources: `.toolchain/llvm-project` (read-only).

## Outputs

- **Three upstream directories**, each with a complete `README.md`:
  report, `## Patch`, and `## Upstreaming plan`. Each has its
  reproducer, its `llvm.patch`, and its `T/upstream/<bug>/{run,expected}`
  reporting "no longer crashes" (or "no longer rebuilds") against the
  patched tools.
- **`IDR/Stack/Escape.cppm` and `IDR/Driver/Retarget.cppm`**, written as
  C11.1 says.
- **`IDR/Simplify`**, whose round runs upstream `remove-dead-values`.
- **For the coordinator:** the PINS text, and the line for `Passes.td`.

## Implement

- **Reduce each clang crash** to the smallest unit that still aborts the
  pinned clang, using the units in the READMEs. Search llvm-project's
  history after the pin for a fix, starting with #189252 for the
  predeclared-new one. Backport it if it exists; otherwise write the
  smallest patch to clang's module code that removes the abort, with a
  regression test in clang's own lit format inside the patch.
- **Reduce the dead-values behaviour.** Take a module that
  `idr-dead-values` keeps unchanged, and reduce it to `func` and `arith`
  with `idris-mlir-reduce`. Show `remove-dead-values` rewriting a call
  without erasing anything. The fix is a hunk in the existing patch: an
  op that loses no operand and no result is left as it is. Add the
  reproducer `.mlir` and its `RUN` line beside the others.
- **Write the three sites plainly.** `Escape.cppm` uses
  `SetVector<Operation *>` and `DenseSet<Operation *>`, as the escape
  analysis means; its `PIN` comment and workaround comment go.
  `Retarget.cppm` builds its feature string as `std::string`, with no
  `PIN` comment.

## Delete

- The `PIN(clang-module-layout-forward-declaration)` and
  `PIN(clang-module-predeclared-new)` markers, with their workarounds.
- `IDR/Simplify/DeadValues.cppm`, `IDR/Simplify/DeadValues/Pass.cc`, and
  their entries in `IDR/Simplify/CMakeLists.txt`.
- Every use of `IdrDeadValues` and `createIdrDeadValues` in `IDR/Simplify`.

## NOT TO DO

- Do not patch anything but the pinned llvm-project.
- Do not move the pin.
- Do not edit `tools/bootstrap.sh` or `tools/patches.sh`.
- Do not add a workaround elsewhere in place of the one you delete.
- Do not touch the other `upstream/` entries.
- Do not change the simplify loop's order, fixpoint test or budget
  beyond replacing the pass.

## Acceptance

- Each `T/upstream/<bug>/run`:
  - shows the abort (or the rebuild) with the unpatched tool, as its
    `expected` records it today;
  - shows "no longer crashes" against the patched tool when the
    coordinator rebuilds it.
- `tests/spec/upstream-patches` passes when run alone (common
  obligations): every patch applies to the pinned source alone and after
  the ones before it, and every directory has a plan. Run it; it builds
  nothing. Do not run `make check`.
- `grep -n PIN IDR/Stack/Escape.cppm IDR/Driver/Retarget.cppm` finds no
  marker for either crash.
- `grep -rn DeadValues IDR/Simplify` finds nothing.
- **Tempting partial:** keeping the old workaround "until the toolchain
  is rebuilt". Rejected: the coordinator rebuilds at integration, and a
  kept workaround is the thing this lane deletes.
- **Tempting partial:** a patch with no reduced reproducer. Rejected:
  `upstream/README.md` requires the reproducer and the check.

## Escalate if

- A crash needs a clang change larger than a local fix in the module
  code; report it with the reduced unit.
- The dead-values reduction shows the rebuild is required by upstream's
  design; report the evidence and keep the deletion pending the
  coordinator's ruling.

## Stop and return

You are done when:

- the three directories are complete;
- the three sites are written plainly;
- the Simplify deletion is done;
- `tests/spec/upstream-patches`, run alone, passes.

Return the changed paths, the PINS text, the `Passes.td` line,
the held-out group (C13), `Verification: spec/upstream-patches (run) /
builds NotRun (swarm policy)`, and any seams.
