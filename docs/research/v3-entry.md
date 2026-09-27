# v3 entry: the stock Prelude

The roadmap's v3 admits the Prelude's dependencies layer by layer. This note
records what compiling real Prelude code showed, what is implemented, and
what remains. Every claim was checked by compiling a
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
4. **Diagnostics inside unfolded library code**: done (`DIAG-LOC-1`). An
   error inside the Prelude is reported at the innermost user definition
   that reached it, with the library location in parentheses.
5. **Recursion over known values**: done (`ELIM-G-16`). A call whose
   arguments are all known is evaluated completely at compile time within a
   budget of 20000 unfoldings, and the attempt is undone if it would leave
   code behind (`tests/e2e/v3/compile-time-evaluation`).
6. **`(*>)`, `for_`, `traverse_` and `sequence_` in `IO`**: done. The
   Prelude's `(*>)` for IO is the Applicative default,
   `map (const id) a <*> b`: running `a` yields an `IORes` holding a
   function. Three defects on this path are fixed: such a result was read
   field by field, which ran the action twice (caught by the Core checker
   as a world used twice, `CORE-INV-9`); it was deferred past the effects
   that followed it; and a match on a runtime `IORes` whose alternative
   yields it was made a residual match, which would return it at runtime.
   One constructor is not a choice, so that match now reads the fields in
   place (`ELIM-G-2`), and the function stays a compile-time value
   (`tests/e2e/v3/prelude-traverse`).
7. **`Show` on composite values**: done. Tuples of three or more work (the
   implementation for the inner pair was a solved metavariable left in the
   elaborated term; it is now filled in, `FE-TR-6`), and so do lists
   (`SEM-REC-2`) and any nesting of them (`tests/e2e/v3/prelude-show`). The
   `where` function that shows a list receives its `Show` implementation as
   an explicit argument; a parameter is now an implementation when its type
   is an interface (Idris declares an interface's record with unique
   search), not only when its argument is one visibly.
8. **User types with the Prelude's interfaces, and showing characters and
   strings**: done (`tests/e2e/v3/prelude-user-types`). String primitives
   on literals fold (`ELIM-G-6`), and a specialization that cannot be built
   for a runtime value is built for the literal it was given
   (`ELIM-G-17`): the Prelude's `show` for `Char` compares the character's
   code as an `Integer`, which exists only at compile time.
9. **Inductive families and the base library**: done (`SEM-IDX-1`,
   `FE-TR-7`, `PROF-LIB-3`, `tests/e2e/v3/vect`). `Data.Vect` works with
   its indices at compile time only. Not yet: `transpose`, which takes its
   length at runtime quantity (`{n : _}`), so an implementation that
   mentions it is rejected as chosen at runtime.
10. **`main : Int` programs cannot import the Prelude**: they are compiled
   per module (`--inc`), and the Prelude package has no incremental `mlir`
   data (`PROF-PROG-1`). IO programs, which are compiled whole, can.

## Exit criteria for `VERSION = v3`: met

- Every v3 rule is tested (`TEST-SPEC-1` with `VERSION = v3`).
- `tests/e2e/v3/prelude-math` is the math showcase against the Prelude
  (complex numbers through `Num`, `Neg`, `Fractional` and `Show`,
  Mandelbrot, Newton basins), diffed against Chez; the benchmarks import
  only the Prelude and are no slower (`bench/README.md`).

What remains is items 9 (in part) and 10 above, and everything that needs a heap.
