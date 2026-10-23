<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L16: the queue after L16cb, L16cc and L16ca

What the frontend's running passes handed back, for the passes that follow
them (2026-10-22). Each item names the type that would carry the fact.

## From L16ca (D112's internal errors, Cases and the small modules)

- `Translate/Cases.idr:812`: `Defined.taken` keeps each binder's type.
- `Cases.idr:906`: `DictParam` holds its constructor and arguments.
- `Cases.idr:880, :926`: `request` returns its signature tied by type to
  the kinds requested (C234 sharpened); the parameters' runtime variables
  carried by position.
- `Cases.idr:900`: a `Static` entry carries its parameter's position.
- `Cases.idr:974`: the family's identity indexes its constructor layouts.
- `Translate/Types.idr:225`, `Keys.idr:93`: `Defined` holds its
  type-constructor facts and its nested-block name (the "split `Defined`"
  item L16bo left).
- `Translate/Shapes.idr:280`: `InstanceSig` keeps the binder types it
  admitted.
- `Keys.idr:1091`: a written reference holds an `Address`.
- `Errors.idr:335, :344`, `Profile.idr:127`: the driver or the checker
  hands over modules already located.
- `Program.idr:208`: `buildMain` returns the reloaded main module;
  `Program.idr:82` goes once Emit cannot fail (after L16cc).
- Kept as a run-time fact: `Keys.idr:1123`, two links sharing a key by a
  64-bit hash collision.

## From recheck 4

- C231 sharpened: `staticsOver` takes the instance's admitted telescope and
  loses its missing-binder branch (`Instances.idr:303, 327-328`).
- C234 sharpened: `request`'s signature indexed by the kinds it was
  requested with (`Instances.idr:803-804`).
- C222: translation requests carry their membership in the growth model's
  sites, so the run-time `unsound` goes (`Frontend/Finite.idr:172-194`).
- D112: the internal errors left in `Growth/`, `Translate/Closed.idr` and
  `Frontend/Finite.idr`.

## From L16cc (C228 and D112 in the term and Emit modules)

- `Translate/Shapes.idr:375`: `witnessTerm` still builds the old extent
  form; `AxisAt` carries its array's `ArrayType r` and the axis as a
  `Fin r` (a compile break until done).
- C228's remaining four Emit checks (`Bodies` about :692, :701, :729,
  `Tensors` :214): a lambda's result type, an application's function
  type and a force's operand type, which Idris's checker knows from
  context but the translation does not keep where it builds the term. The
  translation works against an expected type (checking mode), and
  `etaExpand`/`applyMaker` carry a result type, so the core term's values
  are typed by their scope.
- Internal errors kept in `Terms.idr` (446, 1379, 1494: held implementation
  values read twice; 1773, 1875 and `Choices.idr:88`: the family table;
  1784: two readings of a constructor's fields) and `Choices.idr` (453,
  468: a dispatch's choice and held positions), each needing a type the
  growth and instance modules hold.

## From L16ce (the growth builder's evidence), after L16cd lands

- C254: the graph draws the arc for a field read of an applied rank-2
  dictionary landing open with computing arguments; positions are
  numbered before landings are read, so `closedLands` is proved from a
  numbered table (`Growth/Graph.idr`, `Heads.idr`).
- `Template.rooted` returns its `SiteReading` beside the root, so Sites
  keeps the written-template equation (`asGiven k (r.template, root)`).
- The imports of L16cd's moved names in `Proof/Covers.idr`,
  `Growth/Heads.idr`, `Graph.idr` and `Sites.idr` (`Static`, `Chosen`,
  `markerOf`, `RunZero` and kin).
- The reading lemma's open steps, named in `Proof/Covers.idr`'s header.

## From L03z (generated builders against the frontend's calls)

The generator emits the right signatures; the frontend's calls are wrong:
- `natToExtentOp` takes no result type: `Emit/Tensors.idr:77` calls it under `const`.
- `arrayTabulateOp`'s `outs` is a list: `Tensors.idr:399,427,507,537`, `SyntaxSamples.idr:255`.
- `arrayFoldLastOp` takes `length` first: `Tensors.idr:545,547`, `SyntaxSamples.idr:259`.
- `arrayScanLastOp`: wrong order and no `outs` group, `Tensors.idr:549`.
- `Linalg.transposeOp` takes a region (`Tensors.idr:415`, `SyntaxSamples.idr:267`),
  once L12 admits `Linalg_YieldOp` from `Higher`.

## From L16ch (C254 as built)

- The `LandingTable` is a `Vect` updated once per writing, writings ×
  positions to build. Build it in one pass instead (the writings grouped by
  position, then the table made once), keeping `closedLandsOf`'s proof.

## From L16cg's follow-up (C228, C231)

- Tails in local-action regions (`Term.running`) still apply at the
  definition's declared result type, not the value's by construction.
- `libraryCall` compares the row's arity evidence with `Instances`' own
  count, which carries no evidence: the request's arity should come as the
  `Vect` length C249 gave it, so the two are one by type.
