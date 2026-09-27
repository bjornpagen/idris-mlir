# v3 entry: the stock Prelude

The roadmap's v3 admits the Prelude's dependencies layer by layer. This note
records what compiling real Prelude code showed, what is implemented, and
what remains before `VERSION = v3`. Every claim was checked by compiling a
program with this compiler and, where it ran, diffing its output with the
stock Chez backend.

## Method

A small IO program that uses the Prelude the ordinary way (`Num`, `Ord`,
`if`, `&&`, `Maybe`, `show`) was compiled with a scratch build that trusted
the Prelude's modules. Each failure was traced to its cause, fixed in the
compiler where the fix was general, and the probe repeated.

## What each probe hit, and the fix

| Blocker | Where | Fix | Rule |
| --- | --- | --- | --- |
| Integer literals: `Num Int` elaborates `48` as `fromInteger 48`, and `Integer` had no representation | every numeric literal | `Integer` exists at compile time only; its primitives fold with Idris's own | `SEM-BIG-1` |
| `Nat` inside `Prec` (`User Nat`), which every `showPrec` takes | `show` | recursive data is compile-time data | `SEM-REC-1` |
| `firstCharIs p "" = False`, a match on a string, in a branch that is statically dead | `show` for numbers | string matches are decided during specialization | `PROF-PRIM-4` |
| `div x y = case y == 0 of False => ...`, a case with a missing alternative | `Integral Int` | missing cases crash, as the reference's "Unhandled input" does | `SEM-CRASH-2` |
| `compare` on `Prec` calls `compare` on `Nat`: flagged as polymorphic recursion | `Ord Prec` | growth is an embedding of static arguments, not a longer name | `PROF-POLY-1` |
| `d >= PrefixMinus` was specialized, not evaluated, so its `Bool` was a runtime value and both branches of `&&` were compiled | `primNumShow` | calls with known arguments, or with a known constructor argument, are evaluated; constructors of known values stay known; library `%inline` is honored | `ELIM-G-12`, `ELIM-G-2`, `ELIM-G-13` |
| `assert_total` inside the Prelude | `firstCharIs` | a library's own `assert_total` is trusted | `PROF-ESC-1` |

With these, `tests/e2e/v3/prelude` compiles and matches Chez: `Num`, `Neg`,
`Integral`, `Eq`, `Ord`, `Bool`, `if`, `&&`, `||`, `Maybe`, pairs, `cast`,
`div` and `mod`, and `show` on runtime `Int`, `Double` and `Bool`. The
benchmarks in `bench/` did not change.

## What still fails, and what it needs

1. **A string built inside a runtime branch** (`maybe "none" show m`,
   `show (n, m)`): done, as string join points (`ELIM-G-14`). A residual
   match whose alternatives yield strings is itself a static string that
   keeps each alternative's code; `putStr` of it writes the match with the
   output at the end of each alternative. `show (Just n)` for integers is
   done too (`ELIM-G-15`): the Prelude parenthesizes a shown number that
   starts with `-`, and the first character of an integer shown at runtime
   is computed, and for a `Double` the printer's helper gives it
   (`idr.double_head`).
2. **The Prelude's own IO**: done (`PROF-IO-4`, `SEM-IO-7`). Its
   `prim__putStr` and `prim__putChar` are the `idr.io` output ops, and its
   `prim__getChar` is a new `idr.io.get_byte`, because the reference reads
   it with C `getchar`: bytes, not UTF-8 scalars, and 255 at the end of
   input. A program can now use the Prelude alone
   (`tests/e2e/v3/prelude-io`, `tests/e2e/v3/prelude-input`).
3. **`Foldable` over a list literal with a runtime element**
   (`sum [1, 2, n]`): done. `sum = concat @{Additive}` passes a named
   implementation, and the `Foldable List` dictionary's `foldMap` field is a
   lambda over its `Monoid` (`\@{m} => ...`); translation now substitutes a
   lambda over an implementation like one over a type (`FE-TR-6`). Two
   instances of one type up to binder names (`IO ((x : ()) -> ())` and
   `IO (() -> ())`) were also told apart, so a constructor of one did not
   match the other; instance names are now alpha-invariant (`ELIM-MONO-4`).
   Lists are built strictly where they are written (`SEM-REC-2`), with
   runtime elements, and `Inf` codata is a compile-time value, so ranges
   work (`tests/e2e/v3/prelude-lists`).
4. **Diagnostics inside unfolded library code** point at the library's
   line (`Prelude.Types:181`), not the user's call. `Simplify` should keep
   the nearest user location while it unfolds library definitions.
5. **Recursion over known values**: done (`ELIM-G-16`). A call whose
   arguments are all known is evaluated completely at compile time within a
   budget of 20000 unfoldings, and the attempt is undone if it would leave
   code behind (`tests/e2e/v3/compile-time-evaluation`).
6. **`(*>)`, `for_` and `traverse_` in `IO`** are rejected (`PROF-HEAP-1`,
   `tests/profile/v3/reject/PROF-HEAP-1-applicative-io.idr`). The Prelude's
   `(*>)` for IO is the Applicative default, `map (const id) a <*> b`:
   running `a` yields an `IORes` holding a function. Two defects on this
   path are fixed: such a result was read field by field, which ran the
   action twice (caught by the Core checker as a world used twice,
   `CORE-INV-9`), and it was deferred past the effects that followed it.
   It is now run once and unfolded in place, re-entering a function at
   most 64 times, as a string join point does. One specialization still
   returns it, and it is rejected there. `do` and `>>` work.
7. **`main : Int` programs cannot import the Prelude**: they are compiled
   per module (`--inc`), and the Prelude package has no incremental `mlir`
   data (`PROF-PROG-1`). IO programs, which are compiled whole, can.

## Exit criteria for `VERSION = v3`

- Every v3 rule tested (`TEST-SPEC-1` with `VERSION = v3`).
- A Prelude-using version of the math showcase and the benchmarks, diffed
  against Chez, with benchmark times no worse than the `IdrisMLIR`-only
  versions.
