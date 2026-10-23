<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A totality check drops a call to a definition its module does not import

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), a `total` function that reaches a non-terminating
`covering` function through another module is accepted as total, unless the
module that defines the loop is imported directly. The termination check
walks the reached calls. `resolveCall`
(`src/Core/Termination/SizeChange.idr:267-270`) looks each callee up in the
context, and when the lookup fails it logs "Not found" and drops the call.
A callee from a module that is not imported is not in the context, so the
path through it is never seen.

## Reproduce

Four modules in one directory, each with `%default total`:

```idris
module LA
export covering
loop : Nat -> Nat
loop x = loop (S x)

module LB
import LA
export covering
viaLoop : Nat -> Nat
viaLoop x = loop x

module LC
import LB
caller : Nat -> Nat
caller x = viaLoop x

module LD
import LA
import LB
caller : Nat -> Nat
caller x = viaLoop x
```

The results, measured on arm64 macOS on 2026-10-16:
- `idris2 --check LC.idr` exits 0, accepting `caller` as total;
  `--log totality.termination.calc:7` prints "Not found: LA.loop".
- `idris2 --check LD.idr` fails with "caller is not total, possibly not
  terminating due to function LA.loop being reachable via LB.viaLoop ->
  LA.loop".

The two `caller`s are the same function, and only the imports differ.

## Expected

Both are refused: totality is a property of what a function reaches,
whatever its module imports.

## Cause

A module is checked in a context that holds only what its imports make
visible. Reading an import's TTC, `readModule` (`Idris.ProcessIdr`) reads
the modules that import itself imports only when it re-exports them, or on
a full load (the REPL's, and the main file's when a program is built):
upstream's c88bf7af8 ("Fix import loading", 2020) stopped chasing the rest,
for load time and so that names a module does not import stay out of
scope. A definition an import holds still calls into the modules that
import reaches, and elaborating a module's own definitions can leave such a
name in them too, by unfolding a visible definition whose body names it. So
the termination check meets names the context has no definition of:
`resolveCall` drops the call, `totRefs` (`References.idr`) skips the name,
and the checker's `settle` counted it as settled. The check assumes every
callee is loaded, which since then holds only on a full load.

How often it happens: checking the checker's own sources with the pinned
Idris, 52 checks of total functions, in nine modules, meet a callee the
context does not hold (`Data.Buffer`, `Control.Monad.ST`, `Data.Nat`'s
lemmas, the checker's `Libraries.Data.String.Extra`), every one dropped.

## The fix

Our type checker (compiler/checker) has the change as its own code:

- The context holds, beside its definitions, the modules a module it
  imports imports and no import of this context reads (`Unimported`, a
  field of `Defs`): `readModule` names each import it does not follow
  (`addUnimported`) rather than forgetting it.
- The termination check reads a name the context does not hold from those
  modules (`lookupReached`, `Core.Termination.References`): the first time
  it needs one, it reads the definitions of every named module and of every
  module those import in turn, skipping what the context imports
  (`unimportedDefinitions`), into a table by full name. The elaborator never
  reads that table: name resolution, the evaluator, the hints and the
  suggestions for an undefined name see only the context, so what a module
  means is unchanged, and a module whose check needs no such name reads
  nothing more.
- `resolveCall`, `totRefs`, `addCases` and, in the checker, `settle` look
  names up through it, and a verdict on a definition held there is recorded
  there (`setReachedTerminating`), so `setPrefixTerminating`, the loop a
  failed check reports and `settle` treat such a definition as they treat
  the context's.
- No call is dropped. A call is to a definition (a function, a
  constructor or a case block), and a module's definitions name only what
  its own imports reach, so the context and the modules its imports reach
  hold every definition a loaded definition calls: `resolveCall` refuses a
  callee neither holds (`UndefinedName`), which marks a context out of step
  with its TTCs, not a program. `totRefs`, `addCases` and `settle` read a
  definition's references, which also hold the variables it binds in
  patterns and types (contrib's `Data.List.Views.Extra` refers to
  `{pat2::7}`); a name no loaded module defines is such a variable, has no
  totality and waits on nothing, so they pass it over, and only a full name
  is looked for among the unimported definitions. `settle` no longer counts
  a definition it cannot find as settled: it finds it. The `Defs` the
  lookups took is dead and goes from `addFunctions`, `initWork`, `totRefs`,
  `totRefsIn` (and so `Positivity`'s two calls), `addCases` and `settle`.
- A TTC holds its extra data (Idris's `SyntaxInfo`) as a blob of its own,
  so `Core.Binary` reads a module's definitions without knowing that type
  (`readDefinitions`, sharing `readTTCFileWith` with `readTTCFile`), and
  `ttcVersion` moves.

Why not the two fixes the report first named:
- Refusing a call whose callee the context does not hold is sound, but
  makes a verdict depend on what the module imports: each of the 52 checks
  above would be refused, while the same function in a module that imports
  the callee's is accepted, and the checker's own sources still check total
  with this fix, so no callee among them is on a loop.
- Loading every module the imports reach into the context, as a full load
  does, puts their names in scope (ambiguity, shadowing warnings, the
  suggestions for an undefined name, the evaluator unfolding what the
  module does not import), which is what c88bf7af8 removed, and makes every
  build read about three times the TTCs: 16,877 module loads against 5,589
  for the checker's and the frontend's sources, and 2,221 against 826 for
  base, at about 9 ms for a base TTC here.

The checker carries the change in its own `Core.Termination.References`,
`Core.Termination.SizeChange`, `Core.Termination.Positivity`,
`Core.Context`, `Core.Binary` and `Idris.ProcessIdr`; 21-termination-closure's
`settle` is unchanged but for its lookups, and its closure over
components is gone from the checker since 31013e5a, whose check searches
each component (`loopsTerminate`; upstream/21-termination-closure).

`tests/upstream-totality-unimported-callee` checks it through the
frontend, on the files of `total033`, a test laid out for upstream's
suite beside the change: its `Main.idr` imports neither `Loop` nor `Count`: its `caller` reaches `Loop.loop`
through `ViaLoop.viaLoop` and is refused; its `counted` reaches the total
`Count.count` through `ViaCount.viaCount` and is accepted, which a fix that
refused unseen callees would not do.

## Testing

The checker had the bug before the change: at b81f48dd its frontend's
`--check` accepts the reproducer's `LC` and refuses `LD`. With the change,
built by the pinned Idris on Chez into private prefixes (arm64 macOS,
2026-10-16):
- `LC` is refused with `LD`'s message, and `total033` gives its
  `expected`;
- prelude, base, linear, network, contrib, test, mlir-linear, mlir-array
  and the checker's own package (204 modules, 130 s against 171 s before)
  build with the checker, so no definition among them that
  claims to be total is newly shown not to be; and the frontend's own
  sources check as before;
- the 385 programs then in tests/programs, tests/accept and tests/reject
  give the same exit status, stdout and stderr as before, and the 329
  accepted give byte-identical Core dumps and modules;
- the case that found the bug, `program` in `Frontend/Program.idr` without
  `covering`, is accepted by the checker before the change and refused after
  it: `translateIOProgram` reaches a loop in `Finite.translateFrom`,
  through a module `Program` does not import.

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug.
The Idris that elaborates what this compiler consumes is our type checker
in compiler/checker, Idris's checker copied into our tree, which has the
change as its own code. The stock Idris only builds stage 0 (the checker,
the frontend and the test runner) and the benchmarks' Chez baseline, and
it still has the bug.

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in their own
words and from their own understanding; nothing here is drafted for it. The
report goes when the Idris pin carries upstream's own fix; the checker
keeps its own, which `tests/upstream-totality-unimported-callee` checks.
