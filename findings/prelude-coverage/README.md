# Prelude coverage: what blocks the four modules left

The coverage check (`tests/lib/prelude.sh`, `tests/spec/prelude-coverage`)
covers 10 of the 14 prelude modules. The fixtures written for the other
four are kept here, outside the test tree, until what blocks them is
fixed; each compiles what it can and agrees with Chez on it, with and
without compile-time evaluation. Each is moved back to
`tests/programs/prelude/` with its transcript accepted once its module's
line says every export is used: Interfaces and Show now that a
`Show (DPair a p)` chosen at run time and a solved metavariable compile,
IO and PrimIO once threads and pointers are admitted or ruled out.

## The compiler

- **A nested traversal that chooses a constructor stops `idr-simplify`**
  with `null operand found` on a specialized lambda's call; Chez prints
  `Right [[10]]`. Without the inner `if`, or with the inner lambda a named
  function, it compiles:

  ```idris
  main = do
    c <- getChar
    let n = the Int (cast (ord c) - 48)
    printLn (for [n] (\x => for [x] (\y => the (Either Int Int) (if y > 0 then Right (x + y) else Left y))))
  ```

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
  `Prelude.Interfaces.Num.Semigroup.Additive`), for a constructor after
  a type of its namespace (`Prelude.Types.(<=>)[...]::MkEquivalence(`,
  `Builtin.DPair.DPair[...]::MkDPair(`), and for a definition the
  compiler's registry lowers another way in braces after what its call
  became, as Core writes an implementation after its method
  (`add_Nat{Prelude.Types.plus}(`, `pack<...>{Prelude.Types.fastPack}(`,
  `Prelude.Types.unpack{Prelude.Types.fastUnpack}(`): so a lowered
  definition is asked of the program like any other.
- An export Core does not name is asked of the compiler under test: a
  program whose `main` only names it, refused as `the escape hatch NAME`,
  `NAME` or `uses NAME` (world), names an escape hatch. A `%foreign`
  refusal does not: that is a foreign function the compiler does not
  implement (`prim__fork`), a gap.

`Z` and `S` count as used where Core names them, which is in the indices
of types only: their run-time uses are `0` and `add_Nat`, which no registry
entry writes.

Coverage lines today, each fixture run from `tests/programs/prelude/`:
Interfaces 107 exports, each used; Show 16, each used; IO 23, 12 used, not
`fork`, `onCollect`, `onCollectAny`, `prim__fork`, `prim__getString`,
`prim__threadWait`, `threadWait`; PrimIO 21, 7 used and `unsafePerformIO`
an escape hatch, not `prim__castPtr`, `prim__forgetPtr`,
`prim__getNullAnyPtr`, `prim__nullAnyPtr`, `prim__nullPtr`.
