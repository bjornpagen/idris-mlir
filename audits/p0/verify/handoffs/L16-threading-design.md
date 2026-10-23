<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The threading pass: C257's obligation 2 to 6 and C258 (L16ej's design)

L16ej wrote this at 1bc9c325, after obligation 1 (the site table below
`State`), NoKey's evidence, D128's walk and D131's frontend half had
landed. It is the plan for a fresh lane; nothing below is in the tree.

1. **Place steps per constructor.** Terms' and Cases' walks take exactly
   the steps Sites takes:
   - an application's function is `AppFunction`, an argument `AppArgument m`
     in the walk's mode;
   - a `let` or lambda's value is `BinderValue m`, its type `BinderType`,
     its scope `BinderScope`;
   - a delay is `DelayValue`, `Lazy` is `LazyOf`, an as-pattern
     `PatternOfAs`, a metavariable's solution `MetaSolution`, a settled form
     `SettledForm`;
   - a definition's type is `DefinitionType`, its tree `DefinitionTree`, a
     constructor's type `OfConstructor n`;
   - in a case tree, alternative k is `CaseAlternative k`, a default's
     expansion `Expansion cn`, a leaf `LeafTerm m`.
2. **The parameter's shape.** `Ctx` holds the model's subtree at the walk's
   place, `here : Grown (Entry t.entries)`, rather than a place to look up
   later. Every recursive call into a part steps it to that child (empty
   where the model wrote nothing). Cases' tree walk does the same.
3. **`request` takes the entry and its membership** among the subtree's
   entries at that place. Several sites can sit at one place (a call and the
   types its arguments build), so the entry is selected by what it reaches
   (calls, builds, dispatches, applies, makes, repacks, keeps). A miss means
   the two walks diverged, which is designed away, never caught at run time.
4. **Node readings indexed.** The trees map keyed by node becomes a vector
   of readings. For each entry and each visit, the table records the callee
   readings the growth walk reached (from Graph's walk), so a requester
   passes its callee's index down. The request carries its reading's index,
   and at quantity 0 that the index's node is its own.
5. **Each keyed argument computed from its site's term.**
   - A run-time copy of `Host.putIn`, equal to it by `Refl` in each case,
     puts in the instance's values for the writer's markers and the site's
     stand-ins; a stand-in's value is the part of the instance's shape at
     its path.
   - For a shape, solving, skeleton and cut each return their piece of
     `HeldAs`; the other kinds hold the term whole.
   - Code generation keeps `closeNormalise`.
   - Closed's `Part` records the steps a method resolved in place took (the
     settled form, then the field's argument path).
6. **C258.**
   - The holes are rewritten into the callee's telescope through
     `callIndices`' level map, written as a second component of the
     dictionary's written argument.
   - One hole reader (`Sites.holedAt`'s) serves both walks, reached through
     the site.
   - The universe raises a node's dictionary parameter by its held
     position's bound; `boundsOf` skips held positions today.
7. **The request's `DrawnFrom` and `HeldAs`.** `State.Request` moves below
   `SiteTable` and gains, per keyed position at quantity 0, its `DrawnFrom`
   (from `membersOf`, at its entry's number) and its `HeldAs` for the term
   with values put in.
8. **The lemma's induction**, over Covers' open steps:
   - from the site's normal form to its form;
   - under a binder: the induction over a scope, putting values in under the
     binder;
   - a call read beside its unfolding: the trace's stuck walks and taken
     alternatives, putting values in commuting with the normaliser's steps.
     If that needs the normaliser idempotent beyond D68, stop for the owner;
   - shapes: the request's skeleton against the site's, and a proof that
     `closeNormalise` cuts at least where the host's normal form does;
   - dictionaries and shapes read as written: contraction carried through
     putting values in.

   Then `Finite.requestedUnder` builds `Under` from each request's universe
   membership instead of deciding it.
9. **What obligation 6 deletes.** `Finite.unsound`, `heightWithin`,
   `sizedWithin` and their internal error; `Types.boundsHold`; `TS.bounds`
   and `TS.sizes` (the universe kept at quantity 0); `Requests`'
   `lteThrough`, `climb`, `fitsWithin` and `within`, and the tower deciders
   if nothing else uses them.

Outside the threading: `Finite.idr:224` needs an instance table whose
lookup returns evidence (base's `SortedMap` states no lookup-after-insert
facts); D131's `indexTerm` reading of base's `plus` waits on the checker's
vocabulary gaining `KPlus`, read at the boundary into `Reading.natPlus` as
`ioType` is.
