# Upstream Idris tests and the runtime

The programs under `third_party/Idris2/tests` that compile here and stay
inside the language were run against the stock Chez backend. Where both
produced a result, the text and the exit status matched, except the
differences `tests/lib/chez-divergences` already names.

## Matched

Integers, strings and doubles that the compiler accepts:

- `base/data_integral`, `base/data_bits001`, `chez/chez021`, `node/node021`,
  `node/node022`, `refc/issue2452`, `idris2/basic/basic056`
- `refc/doubles`, `node/doubles`, `refc/stringcasts`, `node/stringcast`,
  `node/fastConcat`
- `base/data_string_lines001`, `base/data_string_unlines001`,
  `chez/chez009`, `node/node009`
- `refc/issue1778` (a Peano reverse of 100000), `chez/perf001`,
  `node/perf001`, `node/tailrec001`, `node/tailrec002`, `node/tailrec_libs`
- lists, snoclists and vectors: `base/data_list001`, `data_list002`,
  `data_list003`, `data_listone001`, `data_snoclist001`, `data_snoclist002`,
  `data_vect001`, `data_vect002`
- `chez/inlineiobind` (`getLine` on empty input), `prelude/bind001`,
  `allschemes/memo001` (strict constants), `refc/reuse`, `chez/reg002`,
  `node/reg002`

A program of the Integer operations `chez/integers` prints, written
without `imapProperty`, matched Chez as well: Euclidean `div` and `mod`
through values outside `Int`, negation and division of the minimum `Int8`
and `Int` by `-1`, and the wrapping casts. The suite itself does not
compile; see below.

## Already decided

- `prelude/double001` and `allschemes/scheme001` differ only by
  `double-special-text` (`inf` / `-inf` / `nan` against Chez's `+inf.0` /
  `-inf.0` / `+nan.0`). In `scheme001` the further numeric lines are
  `cast-string-literal`: `-1.`, `.1`, `+.1`, `+nan.0` and `+inf.0` are not
  Idris literals, so `cast` is 0.
- `chez/reg001` and `node/reg001` match through `cast {to = Double} "5.9"`.
  The last line is `cast {to = Int} "6.6" \`div\` cast "3.9"`. Chez's
  `string->number` truncates those to 6 and 3. This compiler's cast is 0,
  and `0 \`div\` 0` stops in `Prelude.Num.div`. That is
  `cast-string-literal`.
- Threads, `fork`, collector finalizers and raw pointers stay outside the
  language (`decision-threads-pointers.md`). `chez/constfold`,
  `constfold2`, `constfold3` and `chez/nat2fin` stop on
  `prim__nullAnyPtr`. File, directory, environment, signal, process and
  socket tests stop on the foreign calls that implement them.

## Compiler, left as it is

These are refusals, or a compile that does not finish. They belong to the
compiler.

- `unsupported (polymorphism): polymorphic recursion` of
  `Data.List.Quantifiers.All.imapProperty`, which is how
  `chez/integers`, `refc/integers` and `node/integers` apply one operation
  across every integer width.
- `unsupported (primitive): prim__shl_Integer` and `prim__shr_Integer`
  (`chez/newints`, `chez/chez032`, `idris2/basic/basic055`,
  `node/newints`, `node/node024`). Fixed-width shifts compile; `chez/integers`
  also shifts `Integer`.
- `unsupported (type): Type in a runtime position` (`chez/casts`,
  `chez/bitops`, `chez/chez006`, `chez/chez007`, `chez/chez015`,
  `refc/basicpatternmatch`, `refc/piTypecase001`, `node/bitops`,
  `node/casts`, `node/node006`, `node/node015`). `chez/chez015` is the
  large `Integer` division suite, written as `large : (a : Type) -> a`.
- `unsupported (escape hatch)`: `Builtin.believe_me`
  (`base/data_string_parse_double`, `base/data_fin`, `base/void_error`,
  `idris2/perf/perf008`), `Builtin.assert_total` (`refc/refc001`,
  `refc/refc002`), `%foreign System.prim__exit` (`chez/chez012`,
  `node/node012`, the `IOArray` programs), `%extern`
  `Data.IORef.prim__writeIORef` (`base/data_ref_monadstate`,
  `node/node003`), `%extern` `Data.Buffer.stringByteLength`
  (`chez/buffer001`, `refc/buffer`), `%foreign System.prim__getArgCount`
  (`node/args`, `refc/args`), `%foreign System.Clock.prim__osClockValid`
  (`refc/clock`), `%extern System.Info.prim__codegen` (`refc/prims`).
- `unsupported (pragma)`: `%inline` (`idris2/evaluator/spec001`,
  `chez/case001`), `%hide` (`idris2/basic/basic068`), `%builtin`
  (`idris2/builtin/builtin009`, `builtin011`, `builtin012`), `%nomangle`
  (`node/nomangle001`, `node/nomangle002`), `%extern`
  (`node/integer_array`).
- `unsupported (match)`: a match on an erased value with more than one
  alternative (`base/data_bits002`).
- `unsupported (dependent field)` (`base/sortedmap_001`).
- `unsupported (program)`: `--exec` (`idris2/basic/interpolation002`);
  an unexpected root term (`node/node025`, whose `main` is `HasIO io => io ()`).
- `idris2/basic/basic037` is a hole. Chez compiles it. This compiler
  stops with `internal error: a reference to Main.someFunction`.
- `allschemes/memo002` is a chain of `Lazy Nat` additions. Chez forces
  each suspension once. The compile did not finish in four minutes. The
  strict twin, `allschemes/memo001`, runs and matches. Forcing a `Lazy`
  runs its closure again; `lazy-constants.md` records that.
