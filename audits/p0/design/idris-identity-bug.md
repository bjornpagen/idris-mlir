<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Stock Idris deletes a forged-world write (machine.md U-M1)

Written 2026-10-21 at e96bb991. Cut short when the coordinator asked for
an early report: no fix is built or tested yet. Scratch files are in
`/tmp/idris-identity-bug`.

## The reproducer, confirmed

- `/tmp/eg-machine/idbug/Bug.idr`, built by the stock Idris
  (`.toolchain/idris2`, 0.8.0-1c630e67c, Chez 10.4.1), prints `0`, not
  `7`, and exits 0 (*measured*).
- `set (MkArr d) i x = let () = unsafePerformIO (... prim__arraySet ...) in MkArr d`.
  The pattern `let ()` is elaborated to a case block. The case on `()` is
  compiled away, so the block's body is just its first argument, and the
  write is the block's fourth argument (*measured*,
  `--log compiler:10`).

## Where the write is deleted: the inliner, not the identity pass

machine.md puts the cause in `Identity.idr:31-38`. The log says
otherwise (*measured*):

```
Bug.set: (%let {eff:0} !{arg:0} (Bug.case block in set [!{eff:0}, !{arg:2}, !{arg:1}, (PrimIO.unsafePerformIO [...prim__arraySet...])]))
Inlined: (%let {eff:0} !{arg:0} !{eff:0})
```

The write is already gone after the first `inlineDef`, before
`setIdentity` runs (`Inline.idr:573-593`, *read*). The case block is
marked for inlining (`TTImp/ProcessDef.idr:741`, *read*). `tryApply`
(`Inline.idr:118-126`, *read*) binds each argument to a parameter by
substitution, so an argument the body never uses is never evaluated. The
`found identity flag for: Bug.set` line comes afterwards; it is a
symptom, not the cause.

The faulty condition is call-by-name substitution in `Compiler.Inline`
in two places: `tryApply`/`takeFromStack` for arguments, and
`eval (CLet _ _ YesInline val sc)` with `used First sc < 1`
(`Inline.idr:200-206`, *read*). Only `NotInline` lets are kept.

`Identity.idr` has its own copy of the fault, with the same effect once
it fires (*read*):
- `cexpIdentity (CLet _ _ _ val sc)` (`:31-38`) looks at `val` only
  through `isUnsucc`.
- The self-recursive case (`:39-43`) checks only the argument at
  `idIdx`.

Then `rewriteIdentityFlag` sets `Inline`, and the inliner drops the
remaining arguments. A fix to `Identity.idr` alone would not fix `Bug.idr`
(*conjecture*, from the log; not built).

## The fix (not built)

The inliner never drops an argument or a `YesInline` let value unless it
is a value: `CLocal`, `CPrimVal`, `CErased`, `CLam`, `CDelay`, or a
`CCon` of values. Anything else is bound with `NotInline`, so it is
evaluated before the body. `Identity.idr`'s `CLet` and recursive-call
cases apply the same test to `val` and to the other arguments. This
follows eager evaluation (AGENTS.md), and it costs the stock host's
output some unused dictionary and literal evaluations (*conjecture*,
unmeasured).

## Upstream

- Both files were last changed upstream on 2025-11-25 (acde1c926),
  before the pin (2026-09-08), so main has the same code (*read*,
  `gh api .../commits?path=`).
- Two issue searches found nothing (*measured*, `gh search issues`).
- Nothing is sent to Idris (upstream/README.md).

## libs/ today

`LArray` and the rest of `Array.Core` are bodiless `%extern`
(`libs/mlir-array/Array/Core.idr:200-245`, *read*). No `.idr` outside
third_party uses `unsafePerformIO` with `let () =` (*measured*, grep). The
shape arrives with the planned stock-host bodies (machine.md §6 step 1).

## The fork

`compiler/idris` deleted `Compiler.Inline` and `Opts.*`, and the frontend
reads TT, never CExp (`compiler/idris/README.md`, *read*). So programs
compiled by idris-mlir are unaffected. Only stock-host stage-0 code is
affected.

## upstream/<NN>-effectful-argument-inline/ (to write)

- **README:** this report.
- **Reproducer:** `Bug.idr`.
- **Patch:** `idris.patch`, against the pin. It is the first one: the
  bootstrap carries none today, and upstream/README.md says so.
- **Check:** `tests/upstream-effectful-argument-inline`, which builds
  `Bug.idr` with `.toolchain/idris2` and expects `7`.
- **PINS.md entry.**
- **When it goes:** when the pin includes an upstream fix, or when
  nothing stock-built reaches it.
