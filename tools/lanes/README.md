<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lanes: how parallel work on idris-mlir is done

Every lane is one agent in its own clone of the repository on `main`, made by
`tools/lanes/setup.sh LANE` at `../idris-mlir-lanes/LANE` beside the main
checkout. The clone shares the main
checkout's toolchain (`.toolchain` is a symlink: never modify it) and builds
in its own `build/`.

## The owner's rules (binding)

- **Main only.** No branches, no worktrees. Commit on `main`; before each
  push, `git pull --rebase origin main`, resolve any conflict by keeping
  both intents, then `git push origin main`. Push after every step that
  builds and passes its tests. Unfinished work is committed too, never
  left behind: a commit whose message starts `WIP, unfinished:` and says
  exactly what remains. A WIP commit still builds: every lane builds from
  main, so one that breaks the build stops them all (keep unfinished code
  where the build does not reach it yet). Push at least whenever you stop
  to wait on a build or a suite. Never revert another lane's work; fix
  forward.
- **Hard cutover, representation first.** Read AGENTS.md and both skills
  in full before the first edit:
  `.claude/skills/representation-first/SKILL.md`
  and `.claude/skills/testing-by-search/SKILL.md`.
  Every fix changes the representation so the bug cannot be stated; the
  old path is deleted in the same change, never kept beside the new one.
  The owner loves unified data structures: one structure for one concept,
  shared by every reader, and two near-copies merged into one.
- **Cull legacy aggressively.** Every change deletes the dead code, dead
  tests and stale comments it leaves. A test that checks more than its
  contract, checks nothing, or cannot fail is rewritten or deleted.
- **Upstream bugs** are fixed by a patch in `upstream/<NN>-<name>/` (AGENTS.md),
  never by a workaround. A new LLVM patch is built into the shared toolchain
  only by the coordinator (the main session), once, with every lane's
  patches together: until then, test it on a private build (lane `upstream`).

## Building and testing in a clone

- One full suite at a time across all lanes: a full `make test`,
  `make test-idr` or `make test-mlir-tools` runs under the lanes' lock,
  `sh -c '. tools/host.sh; with_lock ../.suite-lock make test'` from the
  clone's root (the lanes' directory's `.suite-lock`, which the main
  checkout names `../idris-mlir-lanes/.suite-lock`), and waits its turn; targeted runs (`only=...`) need
  no lock. Five full suites at once overload the machine until compiles
  cross the harness's step limit and the runs fail for nothing.
- Limit parallelism, since several lanes build at once:
  `export IDRIS_MLIR_NCPU=3 CMAKE_BUILD_PARALLEL_LEVEL=3`, in every shell
  that builds or tests. Run one suite at a time per lane, never several
  `make test*` at once.
- Memory is bounded by construction for every program this compiler builds
  (07aeb299: a program's heap is one region, IDRIS_RT_HEAP, a gibibyte under
  the harness). The compiler process is not: a run of idris-mlir or
  idris-mlir-opt by hand on a large or diverging input goes under
  `ulimit -t` and a watch of its memory, and a pass that grows memory
  superlinearly is a bug to fix, recorded in audits/bugs.md when it is not
  yours. On 2026-10-19 a runaway took the machine down and every lane with it.
- Never wait without a bound. A wait for a background run (an `until
  grep ...; do sleep` loop, a poll of a log) has a deadline and checks that
  the run it waits for is still alive; a dead producer ends the wait. Kill
  what you start when you are done with it. Nothing kills your runs from
  outside: a long build or suite grinds to its end.
- `make build`, then the checks AGENTS.md names: `make check` always;
  `make test` after compiler changes; `make test-idr` and `make test-unit`
  after C++ changes; `make test-mlir-tools` after changing MLIR usage.
- While main does not compile (the `idr.memo.run` and array-role WIP commits
  at the head of 2026-10-19), lanes other than `ownership` and `arrays` read,
  design and edit, and build once those lanes push compiling commits
  (`git pull --rebase` and retry).

## Lanes

| Lane | Area (its files) | Spec |
| --- | --- | --- |
| ownership | memo cells, grades and lifetimes, the owned verifier, idr-rc, the runtime's counting (Transforms/Ownership, IR/Verify, IR/Grades except throughLinear, runtime) | audits/bugs.md (ownership); "Each fact once" (ownership) after self-hosting |
| defunc | the label solve and the quadratics on its path (Analysis/Labels, Defunctionalize, Verify/Program) | audits/bugs.md (defunc) |
| control | idr-trmc, raising, forcing, IO binds; `throughLinear` (Transforms/Tail, Transforms/Specialize) | audits/bugs.md (control) |
| arrays | the frontend's data keys and array shapes, and the array programs end to end (compiler/src, libs/mlir-array, libs/mlir-linear) | audits/bugs.md (arrays) |
| target | the one description of the target (CPU, features, runtime flags, retarget, the CPU test's bits), and the build-time check that the runtime inlines into programs (CMakeLists.txt target entries, Target/, Driver/ runtime linking) | the owner's directive: one place, the mismatch unrepresentable |
| upstream | new LLVM patches: linalg.index ranges, CSE of a nested linalg.index, affine.delinearize_index with an empty basis; the stale mlir.expect step names | audits/bugs.md (upstream) |

A lane that needs a change in another lane's area makes it if it is small
and says so in its commit; otherwise it records it in audits/bugs.md for
that lane.
