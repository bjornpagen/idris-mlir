# Upstream Idris tests left outside the passes

The executable tests under the pinned Idris tree, in `prelude`, `base`,
`allschemes`, `allbackends` and `idris2`, that stay on the supported
prelude and base. Chez is the oracle. These are the ones a pass does not
own: the program is rejected before a pass runs, the disagreement is one
already decided, or the failure is the runtime's report of a partial
function. The refusals stay as they are.

## A fresh closure where a lazy value is shared

`Inf` and `Delay` are a zero-argument function. Each use builds a new
closure, so a chain of delayed computations is copied once per use.
`allschemes/memo002` is that chain. `idr-inline` expands it until the
compile does not finish. Memoizing the delayed value is a representation
of `Delay`, chosen when the program is emitted. Stopping the inliner
would leave the same chain to run.

## Already decided disagreements

`prelude/double001` and `allbackends/evaluator005` differ only in the
spelling of the infinities and NaN (`double-special-text`).
`allschemes/scheme001` is that spelling together with `cast-string-literal`:
a string Chez parses as a Scheme number is 0 here when it is not an Idris
literal. `allbackends/issue2362` prints a negative zero as `-0.0` and a
positive zero as `0.0`, so `show` differs while equality holds. That is
the sign of zero, which the printer already keeps.

## The runtime reports a partial function on stderr

`idris2/error/error027` is `mod 10 0`. Both programs exit 1. Chez writes
`ERROR: Unhandled input for Prelude.Num.case block in mod at Prelude.Num:...`
on standard output. This compiler writes `idris-mlir: unhandled input for
Prelude.Num.case block in mod` on standard error. The runtime is reporting that the case had no
alternative.

## Rejected before a pass

Each one is a refusal the frontend already prints.

- `idris2/basic/basic055` (`BitOps.idr`) stops at `prim__shr_Integer`.
  The compiler rejects that primitive before any pass.
- `base/data_bits002` matches an erased value with more than one
  alternative (`Data.Fin.strengthen`).
- `allbackends/evaluator004` puts `Type` in a runtime position.
- `base/sortedmap_001` has a field type that depends on another field.
- `idris2/basic/basic068`, `idris2/misc/namespace005` and
  `idris2/builtin/builtin009`, `builtin011`, `builtin012` use `%hide` or
  `%builtin`.
- `idris2/reflection/reflection014`, `reflection034`, `reflection034_2`
  and `reflection036` import `Language.Reflection`.
- `base/data_fin` (`Num.idr`), `base/data_string_parse_double`,
  `base/void_error` and `idris2/perf/perf008` reach `believe_me`.
- `allschemes/scheme002`, `base/data_ref_monadstate`,
  `base/system_directory`, `base/system_errno`, `base/system_info001`,
  `base/system_time001` and `base/system_signal001` through
  `system_signal004` reach `%foreign` or `%extern`.
- File, popen and `getEnv` tests reach a raw pointer
  (`prim__nullAnyPtr`, `prim__nullPtr`, `prim__getString`), which is
  outside the language, as are the thread tests excluded before the run.
- `allbackends/popen2` runs `Test.idr` at `main`, `main2` and `main3`.
  The `main` entry reaches `prim__nullPtr`. The other two keep the
  filename `Test.idr`, so the frontend reports that module `Main` has no
  source. An entry other than `main` is refused as well.
- `idris2/misc/import008` is a package whose source is not the file the
  invocation loads. Chez fails to load `Mod.idr` the same way when the
  test is run as that one file.

`idris2/basic/basic069` reports `__FILE__` and `__LINE__` of the source
it compiled. The comparison copied that source to `Main.idr` and inserted
`module Main`, so the file name is `Main` and each line is one greater.
