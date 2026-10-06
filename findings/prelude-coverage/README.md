# Prelude coverage: what blocks the seven modules left

The coverage check (`tests/lib/prelude.sh`, `tests/spec/prelude-coverage`)
covers 7 of the 14 prelude modules. The fixtures written for the other
seven are kept here, outside the test tree, until what blocks them is
fixed; each compiles what it can and agrees with Chez on it, with and
without compile-time evaluation. Each is moved back to
`tests/programs/prelude/` with its transcript accepted once its module's
line says every export is used. Prelude (the top module) has no fixture yet.

## The compiler

- **`Show (DPair a p)` is refused** (`every-show-export`), as an
  implementation chosen at run time; Chez prints `(3 ** "x")`:

  ```idris
  main = printLn (the (DPair Int (\_ => String)) (3 ** "x"))
  ```

  The implementation takes `{y : a} -> Show (p y)`, a function from the
  index to a dictionary, which the frontend meets as a run-time closure
  although the type checker fixes the implementation at every index.

- **A solved postponed metavariable is refused**
  (`every-interfaces-export`), as `unsupported (laziness): hole or
  metavariable Main.{postpone:852}`; Chez prints `Right [2, 4]`:

  ```idris
  main = printLn (for (the (List Int) [1, 2]) (\x => if x > 0 then Right (x * 2) else Left x))
  ```

  `term` in `Frontend/Translate/Terms.idr` refuses every `Meta`; a solved
  one should be followed to its definition. The reason is mislabelled too.

- **Threads and pointers are not admitted** (`every-io-export`,
  `every-primio-export`): `fork`, `threadWait`, `prim__castPtr`,
  `prim__forgetPtr`, `prim__nullPtr` (`not admitted from its trusted
  module`, `admittedFromPrimIO` in `Registry/Libraries.idr`), and
  `onCollect`, `onCollectAny`, `prim__nullAnyPtr`, `prim__getNullAnyPtr`,
  `prim__getString`, base's `getEnv`. The library's `%foreign` calls among
  them are refused as `unsupported (escape hatch)`, although the program
  wrote none.

- **Escape hatches** that user code may not write, by design (AGENTS.md):
  Builtin's `believe_me`, `idris_crash`, `assert_smaller`, `assert_linear`,
  PrimIO's `unsafePerformIO`. The check must name these as such rather
  than as uncovered.

## The check

`core_uses` reads a definition as `MODULE.name` in Core, which misses:

- definitions in a namespace, which Core writes with it:
  `Prelude.Types.List.length[Int](`, `Prelude.Types.String.(++)(`,
  `Prelude.Types.Stream.Stream[Int]::::(`, and the named implementations
  of `Prelude.Interfaces` (`Prelude.Interfaces.Num.Semigroup.Additive`,
  `Bool.Lazy.Monoid.Any`, every `Compose`); and an overloaded name, whose
  copies the check cannot tell apart (`reverse`, `filter`, `length`);
- a record's projections and constructor (`Prelude.Types.<=>.leftToRight[`,
  `...]::MkEquivalence(`, Builtin's `.fst`, `.snd`, `MkDPair`);
- what the frontend turns into a primitive before Core is written (the
  `Nat` functions `plus`, `mult`, `minus`, `equalNat`, `compareNat`,
  `natToInteger`, `integerToNat` as `add_Nat` and the rest, `pack` and
  `fastPack`, `fastConcat`, `fastUnpack`), which the registry that maps
  them (`Registry/Recognized.idr`) should name, as the one record of it.

Coverage lines today (`make test only=...` with a fixture moved back):
Types 66 of 122 used; Interfaces 65 of 107 with the metavariable line
annotated away; IO 12 of 23; PrimIO 7 of 21; Builtin 20 of 47.
