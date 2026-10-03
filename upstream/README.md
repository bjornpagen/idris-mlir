# Upstream bugs

Bugs we found in the pinned upstream projects (LLVM and MLIR at
`llvmorg-23.1.2`, Idris at the gitlink in `third_party/Idris2`), one
directory each. Each one holds:

- `README.md`: the report, written to be filed as it is: what happens, the
  smallest input that shows it, the command, what we expected, where in the
  upstream source it goes wrong, and a proposed fix;
- the reproducer, which uses upstream dialects and tools only.

Every bug here has a workaround in this repository, recorded in `PINS.md`
under the same name; the workaround is debt, and this is how we pay it
back. `tests/upstream/<name>/run` (`make test-mlir-tools`) checks that the
bug still reproduces with the pinned tools, so a toolchain bump that fixes
one fails that test: then delete the workaround, the `PINS.md` entry, this
directory and the test, in one change.

When a pass or tool of ours has to work around upstream behaviour, first
reduce it to upstream dialects (`idris-mlir-reduce`, or by hand); if it
still reproduces, add it here, with its test, in the same change as the
workaround. If it does not, the bug is ours.

| Bug | Project | Filed | Our workaround (`PINS.md`) |
| --- | --- | --- | --- |
| [remove-dead-values-unreachable](remove-dead-values-unreachable/README.md) | MLIR | not yet | `prune-before-remove-dead-values`: `idr-prune` and `symbol-dce` run first |
| [remove-dead-values-address-taken](remove-dead-values-address-taken/README.md) | MLIR | not yet | `remove-dead-values-address-taken`: `idr-prune` passes `ub.poison` for parameters an address-taken function never reads |
| [inline-unreachable-terminator](inline-unreachable-terminator/README.md) | MLIR | not yet | `inline-unreachable`: no function body ends in `ub.unreachable` |
| [uplift-final-counter](uplift-final-counter/README.md) | MLIR | not yet | `uplift-final-counter`: `idr-tail-loops` uplifts only loops whose counter's final value is unused |
| [execution-engine-process-symbols](execution-engine-process-symbols/README.md) | MLIR | not yet | `orc-lljit`: `idr-eval` uses ORC's `LLJIT` directly |
| [recursive-attribute-parser](recursive-attribute-parser/README.md) | MLIR | not yet | `mlir-recursion`: `idris-mlir-cc` and the evaluation child run on a reserved stack as large as the address space allows |
| [bytecode-deferred-quadratic](bytecode-deferred-quadratic/README.md) | MLIR | not yet | `bytecode-deferred-quadratic`: `idr-eval` sends its results as a flat table of their parts |
| [composite-fixed-point-sccp](composite-fixed-point-sccp/README.md) | MLIR | not yet | `simplify-structural-fixpoint`: `idr-simplify` is its own loop and decides its fixpoint by a structural hash of the module |
| [vectorize-precondition-body](vectorize-precondition-body/README.md) | MLIR | not yet | `vectorize-precondition-body`: `idr-vectorize` checks the ops of every loop's body before it tiles the loop |
| [int-range-narrowing-exactness](int-range-narrowing-exactness/README.md) | MLIR | not yet | `int-range-narrowing-exactness`: `idr-narrow-lanes` versions only loops whose wide ops all compute the same in 32 bits |
| [while-move-if-down-duplicates](while-move-if-down-duplicates/README.md) | MLIR | fixed on main | `while-move-if-down-duplicates`: an idr canonicalization has the after region read a value the condition forwards twice through one argument, before `WhileMoveIfDown` runs |
