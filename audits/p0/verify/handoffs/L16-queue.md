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
