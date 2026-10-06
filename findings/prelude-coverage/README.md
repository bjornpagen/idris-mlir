# Prelude coverage: what blocks the six modules left

The coverage check (`tests/lib/prelude.sh`, `tests/spec/prelude-coverage`)
covers 8 of the 14 prelude modules. The fixtures written for five of the
other six are kept here, outside the test tree, until what blocks them is
fixed; each compiles what it can and agrees with Chez on it, with and
without compile-time evaluation. Each is moved back to
`tests/programs/prelude/` with its transcript accepted once its module's
line says every export is used. Prelude (the top module) has no fixture:
it defines nothing and re-exports its submodules, so `:browse Prelude`
lists 356 names that Core writes under their defining modules
(`Prelude.IO.putStrLn`); the check has to leave re-exports out, each being
covered where it is defined.

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
  PrimIO's `unsafePerformIO`. The check names them as such.

## The check

`covers_prelude` reads each export by its full name, all from the pinned
Idris or the compiler, nothing written down in the script:

- `:browse MODULE` lists the exports without their namespaces; IDE mode's
  `name-at` lists every definition of a bare name with its full name and
  the module its location names (`:di` gives the full names of `(.)` and
  `(.:)`, which `name-at` reads as projections), and the copies of a name
  pair off with its definitions in Idris's order of names. An export
  defined in another module is left to that module: all 356 of `Prelude`'s.
- Core is read for the full name (`Prelude.Types.List.length[`,
  `Prelude.Types.<=>.(.leftToRight)[`,
  `Prelude.Interfaces.Num.Semigroup.Additive`) and for a constructor after
  a type of its namespace (`Prelude.Types.(<=>)[...]::MkEquivalence(`,
  `Builtin.DPair.DPair[...]::MkDPair(`).
- An export Core does not name is asked of the compiler under test: a
  program whose `main` only names it, refused as `the escape hatch NAME`,
  `NAME` or `uses NAME` (world), names an escape hatch. A `%foreign`
  refusal does not: that is a foreign function the compiler does not
  implement (`prim__fork`), a gap.
- Otherwise, if the compiler's registry gives it a faster lowering, it is
  named apart as lowered: the pinned Idris checks
  `compiler/src/IdrisMLIR/Registry.idr` from source and evaluates its
  `entries`, so the registry stays the one record of the map.

What the check cannot read is whether the program uses a lowered
definition: Core writes `plus` as `add_Nat`, which `S` and `+` on `Nat`
write too, and `natToInteger` as a cast, with no trace of the definition
the registry replaced. The smallest compiler-side addition that would let
the check ask lowered definitions of the program like any other: the
frontend's Core writing the entry it applied after the primitive, in
braces as it already writes an implementation after its method
(`add_Nat{Prelude.Types.plus}`, `pack<...>{Prelude.Types.fastPack}`).
Likewise `Z` and `S` count as used where Core names them, which is in the
indices of types only: their run-time uses are `0` and `add_Nat`.

Coverage lines today, each with its fixture moved back (Interfaces and
Show with the line that meets their bug removed): Builtin 47, each used,
4 escape hatches; Interfaces 107,
each used; Show 16, each used; IO 23, 12 used, not `fork`, `onCollect`,
`onCollectAny`, `prim__fork`, `prim__getString`, `prim__threadWait`,
`threadWait`; PrimIO 21, 7 used and `unsafePerformIO` an escape hatch, not
`prim__castPtr`, `prim__forgetPtr`, `prim__getNullAnyPtr`,
`prim__nullAnyPtr`, `prim__nullPtr`; Prelude exports nothing of its own.
