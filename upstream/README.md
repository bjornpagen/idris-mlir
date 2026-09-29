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
| [idris-linarray-escape](idris-linarray-escape/README.md) | Idris 2 (contrib) | not yet | `linarray-escape`: uniqueness is proved by the compiler, never taken from the library's signature |
| [execution-engine-process-symbols](execution-engine-process-symbols/README.md) | MLIR | not yet | `orc-lljit`: `idr-eval` uses ORC's `LLJIT` directly |
