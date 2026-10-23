<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A record update of a variable waits for the type it is expected to have to name its record

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris,
unpatched and with the toolchain's series (96 and 104 to 114), refuses
`Catchall.idr` (*measured*, scratch builds on Chez 10.4.1):

```
Error: While processing right hand side of step. Can't infer type for this record update.
```

```idris
step : S -> Bool -> S
step st b =
  let st' = { flag := True } st
  in case b of
       True => { flag := False } st'
       _ => st'
```

`st : S` is a variable of the environment, so the update's record is `S`'s
record. The tutorial gives the update as a function of the record it
updates: "The syntax `{ field := val, ... }` generates a function that
updates the given fields in a record", and "Updates are allowed to change
the type of a field, provided the result is well-typed"
(`docs/source/tutorial/typesfuns.rst:1080-1090`); a record's parameters
may change with it (1185-1192), its name never. The test runner met the
shape in `harness/Covers.idr`'s `scanLine` (`st' = { inString := True,
text := [<], kind := kind } st` before a case on the string's kind with a
catch-all).

## Cause

*read* at 89ba32eb, `src/TTImp/Elab/Record.idr`. `checkUpdate` takes the
record's type from the type the update is expected to have, and infers it
from the record only when there is none (`expected` is `Nothing`, 245 to
249); `recUpdate` reads the record's name off that type (209 to 211) and
fails with `RecordTypeNeeded` while it is a metavariable, which
`checkUpdate` turns into a delay (`delayOnFailure ... needType
RecordUpdate`, 253). A let without a signature gives its value a fresh
metavariable as its type, so the update waits for the let's type to be
solved by what uses it. In `Catchall.idr` nothing can: the type is
applied to `b`, the case splits `b`, and its first clause, where the
metavariable stands applied to `True` (outside the pattern fragment, the
family 108 patches for a case whose every clause splits), needs it for
its own update of `st'` before the catch-all after it, which leaves `b`
as it is and would solve it, is checked. The variable's type, which
names the record, is in the environment throughout.

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches
the file), changes `checkUpdate` alone: where the type the update is
expected to have is not yet a type constructor's, and the record is a
variable of the environment, the record's name is read off the
variable's type, which the environment holds. Only the name is read
there: the update is still checked against the type it is expected to
have, as before, so an update that changes the record's parameters
(`Change.idr`, `Sized n` to `Sized (S n)`) has the type its use gives it.
Nothing is elaborated again (the environment is read, so a linear record
is used once), and an update of anything but a variable, or of a
variable whose own type is not yet known, waits as before.

In `Catchall.idr` the update of `st` is then a `case` on `st` at once,
whose one clause splits `st` and gives `S`; with 108 the let's type,
applied to the unsplit copy of `st`, is solved there, and the case on
`b` meets `st'` at `S`.

Our type checker (compiler/checker), Idris's copied into our tree, has
the same `checkUpdate` (its `src/TTImp/Elab/Record.idr`, 277 to 281,
and `checkUpdateDelayed`, 256 to 261, which reads the name through
`recUpdate`); its fix is its own code, as every fix there is.

## Testing

On a full bootstrap of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine at load average 45 to 50 from
other work) with the series 96 and 104 to 114 and this patch, which built
itself and all its libraries, `make bootstrap install`, and then ran
`make install-api`: 579 s wall, 225 s user, 0.43 GiB peak RSS (rusage)
for `install-api`, three warnings of unreachable clauses and no error
(*measured*). With the patch, Idris's own source, which `install-api`
checks, and its libraries check. Beside it, an unpatched bootstrap of
89ba32eb (`make bootstrap install`), and the toolchain's Idris (96 and
104 to 114, built 2026-10-23). The series did not hold 115, carried
since, which changes only the size-change graph's `knownOr` in another
file; a build of the whole series with both has not been run, and the
series applies in order with both (`git apply`, 96 and 104 to 116, at
the gitlink).

- `Catchall.idr` checks; unpatched and with the toolchain's series it is
  refused as above.
- `Change.idr` checks with the patch, unpatched and with the toolchain's
  series.
- `tests/upstream-case-split-pattern-fragment`,
  `upstream-let-delayed-elaborator-dropped`,
  `upstream-do-local-definition-scope`,
  `upstream-type-implicit-binding-order`,
  `upstream-coverage-nested-empty-type`,
  `upstream-coverage-erased-index-first`,
  `upstream-delayed-retry-doubling`,
  `upstream-case-tree-fallthrough-copies`,
  `upstream-coverage-repeated-split` and
  `upstream-size-change-call-paths`, run against the patched build, print
  their expected output.
- the test runner (`harness/`, at 4ff3e293 with L19v's changes) builds
  past `Covers.idr`, where the toolchain's Idris refuses `scanLine`'s
  update as above; with two other refusals of the stock Idris's, which
  this patch does not touch, set aside in a scratch copy, all 31 modules
  and the executable build.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in the built tree (its
  failures file listing the groups; four threads): 731 of 733 pass, the
  two failing `casetree/heuristics001` (105's) and `literate/literate006`
  (108's), the same two 114's README reports for the series without this
  patch (*measured* with the patch; the comparison *read*, not run again
  here).

`tests/upstream-record-update-variable-type` checks that the pinned
Idris accepts `Catchall.idr` and `Change.idr`. Its run script, run
directly against each scratch build (`IDRIS_MLIR_TOOLCHAIN` naming a
directory whose `idris2` is that build's prefix), prints its expected
output with the patch, and without it the `Catchall` line that says the
bug still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch; upstream main has the same `checkUpdate` on 2026-10-23), or
when nothing of ours meets the shape. Until then the bootstrap applies
the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which `tests/upstream-record-update-variable-type`
shows by passing on an unpatched pin.
