<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] What the frontend calls of Idris's compiler is not provably total

At the pin (third_party/Idris2 at 1c630e67), the compiler's modules are
`%default covering`, and much of what this repository's frontend calls
from them is beyond Idris's own totality checker, though it terminates:

- a term's binders, a metavariable's arguments and a case's alternatives
  are traversed through `map`, `traverse` or the interface method being
  defined (`insertNames`, `thinTerm`, `shrinkTerm` with `assert_total`,
  `substName`, `refsToLocals`, `addRefs`, `addMetas`, `trimNS` and
  `restoreNS` of a term and a case tree, `full` and `resolved` of a term
  and a case tree, `show` of a term, a case tree and an error, the hash of a
  term), so no recursive call is on a visible part of its argument;
- a TTC is decoded by `fromBuf`, which each instance calls again with the
  same buffer reference (`Ref Bin Binary`), so the recursion of a name, a
  term or a case tree has no argument that goes down, though every part is
  read after a tag, from a finite buffer;
- decoding a definition resolves it through the `HasNames` instances,
  whose `full` looks definitions up and so may decode, and resolving a
  decoded type's constructors makes their names full (`resolved` of a
  `TCon`, `src/Core/Context.idr`), so decoding one definition can look up
  and decode another;
- `lookupCtxtExactI` and `lookupContextEntry` call themselves on the index
  a name resolves to, and `lookupCtxtExact` repeats `lookupCtxtExactI`;
- `mkdirAll` recurses on the parent of a path string.

It also keeps code that says nothing: the evaluator's `fuel` and
per-name `reduceLimit` options (`src/Core/Value.idr`), which nothing sets,
with the branches that read them; `processDecls` and `processTTImpDecls`
(`src/TTImp/ProcessDecls.idr`), which return `True` whatever happens, an
error being thrown (`-- TODO: False on error`); and two copies of each name
traversal of a term (`full`, `resolved`), which upstream's own comment asks
to make one (`-- TODO: refactor via a single function`).

This is not a bug of Idris's: it is the bar this repository holds the fork
to, since the frontend is total and every operation of the fork it calls
outside one trusted record must be accepted by the checker.

## The change

`pull-request.diff`, against the pin:

- Each kind of node that holds terms is traversed by a function of its own
  (a binder's, a pi's information, a list of terms, a list of
  alternatives), so every recursive call is on a part of its argument. The
  output of each is upstream's: the shown text, the hash, the term.
- A term's names are made full or resolved by one traversal, given what
  becomes of a name and of a metavariable (`OnNames`). A namespace is
  stripped or restored by one traversal given the name's function
  (`onRefs`, `onTreeTerms`).
- `remaining` and `fewer` (`src/Core/Binary/Prims.idr`) are the bytes left
  to read, and the proof that they went down since a decoder began, which
  holds once it has read its tag. A name, a term and its parts, and a case
  tree and its alternatives are decoded by functions given the bytes left
  and their accessibility (`Control.WellFounded`), which they pass to their
  parts; the instances' `fromBuf` start them. A term and a case tree are
  written by functions of their own too (`encodeTerm`, `encodeTree`: an
  application of a function to several arguments is its head and the list
  of them, found by walking the spine), since a decoder that names an
  instance reaches its writer. The bytes of each TTC are unchanged.
- A decoded definition is resolved by `resolveGlobalDef` and the
  `resolve...` functions of its parts, which the instances' `resolved` are
  and which look up no definition: a name is resolved by the index the
  context gives it (`indexedName`), and a type's constructors are left as
  decoded, since a TTC holds them by their full names, which `full` there
  returned unchanged. `decode` is declared `total`. (In the fork since
  31013e5a the resolver is `storeDecoded`, which also freezes the
  definition's terms: PINS.md term-arena.)
- A name is looked up by turning it into its index once
  (`lookupContextEntry`); `lookupCtxtExactI` decodes that entry and
  `lookupCtxtExact` is its definition.
- `mkdirAll` is done at once when the directory exists, as upstream's is,
  and otherwise creates the path's prefixes, outermost first, as a walk
  over the path's body, passing a prefix that exists already
  (`FileExists`), so an ancestor that can only be searched is no obstacle.
- `fuel`, `reduceLimit` and `updateLimit` are gone; `processDecls` and
  `processTTImpDecls` return `()`.
- `SizeChange` (`src/Algebra/SizeChange.idr`) has `DecEq`, which the
  fork's own size-change decision (not in the pin) needs to keep each graph
  once.

## Why there is no patch

There is no `idris.patch`. The fork in compiler/idris carries the change as
its own code; the stock Idris only builds stage 0 and the benchmarks' Chez
baseline.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`). With it and the other `upstream/fork-*/pull-request.diff` applied in order to
a copy of the pin, the pinned compiler's 292 modules typecheck with the
toolchain's Idris (`idris2 --typecheck idris2api.ipkg`, arm64 macOS,
2026-10-15). No stock Idris has been built with it. The fork with the change
typechecks with the toolchain's Idris, and a module of `total` definitions
over the fork's operations checks with it (the operations each is reported
under in PINS.md).

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here (upstream/README.md, **Idris**).

- `pull-request.diff` is the record of what the fork changed against the
  pin, for a re-sync of compiler/idris (compiler/idris/README.md): where
  upstream has made a function total its own way, the fork takes upstream's;
  otherwise the change is carried forward onto the new base.
- The PINS.md text goes with the last part of it.
