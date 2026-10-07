# Upstream bugs

Bugs we found in the pinned upstream projects (LLVM, MLIR, clang and lld
at `llvmorg-23.1.2`, Chez Scheme at the lock's tag, Idris at the gitlink
in `third_party/Idris2`), one directory each. A bug in a pinned upstream
is fixed where it is, by a patch to that upstream's source, which this
repository carries until the pin moves past upstream's own fix. Code of
ours that works around upstream behaviour is the last resort: it drifts
from the bug it hides, it hides it from upstream, and every pass written
after it has to know it.

Each directory holds:

- `README.md`: the report, written to be filed as it is: what happens, the
  smallest input that shows it, the command, what we expected, where in the
  upstream source it goes wrong, and a proposed fix. Then what we do about
  it: `## Patch`, what the patch changes and where it comes from, or
  `## Why there is no patch`; and `## Upstreaming plan`: where it goes
  (an issue, a pull request, or a comment on someone else's), the upstream
  test it adds, and how far it has got;
- the reproducer, which uses upstream dialects and tools only;
- `<project>.patch`, the fix, against the pinned source of one project:
  `llvm` (the llvm-project of `toolchain.lock.json`), `chez` or `idris`.
  A backport is the upstream commit as `git format-patch` writes it; a
  patch of ours is a message and a `git diff`.

`tools/bootstrap.sh` applies every project's patches, in the order of
their directories' names, to a copy of the pinned source it builds from
(`tools/patches.sh`); the checkout and `third_party/Idris2` are never
written to. The patches are inputs of the steps they change, so a new or
changed patch rebuilds them, and `tools/verify-pins.sh` refuses a tool
built without the patches the tree carries. `make check` checks that every
patch applies to the pinned source, alone and after the ones before it,
and that every directory has a plan (`tests/spec/upstream-patches`).

## Procedure

1. Reduce. When a pass or tool of ours meets upstream behaviour that is
   wrong, reduce it to upstream dialects and tools (`idris-mlir-reduce`,
   or by hand). If it does not reproduce there, the bug is ours: fix it.
   Otherwise add the directory, its report and reproducer, and
   `tests/upstream/<name>/run`, which shows the bug with the pinned tools.
2. Patch. Look at upstream's main first: a commit that fixes it is
   backported as it is; an open pull request is taken as it is; otherwise
   write the fix the report proposes, with the upstream test it needs, in
   the style of the code around it. One patch per project the fix
   touches; it applies to the pinned source alone and after the patches
   before it.
3. Test. Rebuild the toolchain (`tools/bootstrap.sh`) and run
   `make test-mlir-tools`: `tests/upstream/<name>` now checks that the
   patched tool no longer shows the bug, with the reproducer as its input.
   Delete the workaround it replaces, in the same change; its `PINS.md`
   entry then describes the patch.
4. Plan. Write the README's upstreaming plan: the issue or pull request
   (reusing one someone else filed), the upstream test, the status.
   Sending it is its own piece of work, done as the plan says; the table
   below is where its status is kept. A fix already on main is carried
   until the pin moves past it and is not filed. A backport that adds
   cases that fix did not test is rerun on trunk, then decided. A report
   with nothing to send yet is not ready.

A bug that cannot be patched yet (not reduced, or a fix upstream must
agree on first) says why in its README, keeps its workaround and its
`PINS.md` entry, and its check still shows the bug.

When the pin moves past upstream's fix, the patch goes, with the parts of
the report and test it covered; when nothing is left of the bug, the
directory, its test and its `PINS.md` entry go too.

In the Upstream column, `#N` is an issue or pull request of
llvm/llvm-project on GitHub, and a hash is a commit on its main; it was
last checked against main at ed390ca4 (October 2026). In the Patch column,
a backport is unchanged upstream code; a patch of ours was written here
against the pin. In the Upstreaming column, `carried backport, not filed`
is kept until the pin moves past it; `backport, retest on trunk` means
retest on trunk, then decide; `file upstream` is sent as the report's
plan says; `not ready` has nothing to send yet.

| Bug | Project | Patch | Upstream | Upstreaming | `PINS.md` |
| --- | --- | --- | --- | --- | --- |
| [remove-dead-values-unreachable](remove-dead-values-unreachable/README.md) | MLIR | `llvm.patch`: open #208881, the same for block arguments and results, with our tests | reported: #206920, #203226; fix in review: #208881 | file upstream: comment on #208881 and the issues with the reproducers | `remove-dead-values-unreachable` |
| [remove-dead-values-address-taken](remove-dead-values-address-taken/README.md) | MLIR | none: `remove-dead-values-unreachable`'s fixes it | not yet; fix in review: #208881 | file upstream: test offered to #208881 | `remove-dead-values-address-taken` |
| [inline-unreachable-terminator](inline-unreachable-terminator/README.md) | MLIR | `llvm.patch`: ours | not yet; same family: #206083 (`vector.yield`) | file upstream: new issue and pull request citing #206083 | `inline-unreachable` |
| [uplift-final-counter](uplift-final-counter/README.md) | MLIR | `llvm.patch`: backport of 6e714c8d9 | fixed on main (6e714c8d9, #225476) | carried backport, not filed | `uplift-final-counter` |
| [execution-engine-process-symbols](execution-engine-process-symbols/README.md) | MLIR | none: idris-mlir uses `LLJIT`, not `ExecutionEngine`; the fix is drafted as `pull-request.diff` | not yet | file upstream: pull request | none |
| [recursive-attribute-parser](recursive-attribute-parser/README.md) | MLIR | none: needs a design upstream agrees on | not yet | not ready | `mlir-recursion` |
| [bytecode-deferred-quadratic](bytecode-deferred-quadratic/README.md) | MLIR | `llvm.patch`: ours | not yet | file upstream: issue and pull request | `bytecode-deferred-quadratic` |
| [composite-fixed-point-sccp](composite-fixed-point-sccp/README.md) | MLIR | `llvm.patch`: ours (part 1 of the fix) | not yet | file upstream: issue and pull request | `simplify-structural-fixpoint` |
| [forward-dataflow-callee-lookup](forward-dataflow-callee-lookup/README.md) | MLIR | `llvm.patch`: ours | not yet (main at 155462f440f still scans) | file upstream: pull request, NFC | `forward-dataflow-callee-lookup` |
| [vectorize-precondition-body](vectorize-precondition-body/README.md) | MLIR | `llvm.patch`: ours | not yet | file upstream: issue and pull request | `vectorize-precondition-body` |
| [int-range-narrowing-exactness](int-range-narrowing-exactness/README.md) | MLIR | `llvm.patch`: backport of 44a4dbf32, and the remainders ours | shift fixed on main (44a4dbf32, #218495); remainders not yet (161d9dca) | backport, retest on trunk | `int-range-narrowing-exactness` |
| [while-move-if-down-duplicates](while-move-if-down-duplicates/README.md) | MLIR | `llvm.patch`: backport of a65eb8723 | fixed on main (a65eb8723, #219458) | carried backport, not filed | `while-move-if-down-duplicates` |
| [clang-module-layout-forward-declaration](clang-module-layout-forward-declaration/README.md) | clang | none: not reduced | not yet | not ready | `clang-module-layout-forward-declaration` |
| [clang-module-predeclared-new](clang-module-predeclared-new/README.md) | clang | none: not reduced | likely reported: #189252 | not ready | `clang-module-predeclared-new` |
| [ld64-lld-unknown-tapi-target](ld64-lld-unknown-tapi-target/README.md) | lld | `llvm.patch`: backport of 532fa5afb (`arm64e.x1`), and `SkipUnknownTriples` ours | not yet; `arm64e.x1` known on main (b8007a8e4, #222721) and in release/23.x after 23.1.2 (532fa5afb, #224185) | carried backport, not filed | `darwin-ld64-tapi` |
