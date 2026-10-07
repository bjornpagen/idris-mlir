# Prelude coverage

The coverage check (`tests/lib/prelude.sh`, `tests/spec/prelude-coverage`)
reads every prelude module from the pinned package and every export from
the pinned Idris. A fixture under `tests/programs/prelude/` marked
`covers MODULE` uses the module's run-time exports, and Chez checks the
program. All 14 modules have a fixture.

`Prelude.IO` and `PrimIO` name threads, collector finalizers and raw
pointers. Those exports are decided exclusions
(`decision-threads-pointers.md`): the check accepts exactly

- `fork`, `prim__fork`, `threadWait`, `prim__threadWait`
- `onCollect`, `onCollectAny`
- `prim__getString`
- `prim__castPtr`, `prim__forgetPtr`, `prim__nullPtr`, `prim__nullAnyPtr`,
  `prim__getNullAnyPtr`

and nothing else by name. `unsafePerformIO` stays an escape hatch, which
the check asks of the compiler. An export the compiler cannot handle, and
which is not one of those names, still fails the fixture.

`System.getEnv` is the same raw-pointer decision. It is not a prelude
export, so the prelude check does not list it; the compiler refuses it.
