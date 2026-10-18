<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The checker's cleanup: what it left across its areas

The hard cleanup of the polymorphism checker (2026-10-17) worked area by
area; each area reported duplicates and Bools that crossed into a sibling's
files and so were not its to change. They are one lane's here, since every
file named is L22's.

### cleanup-1: the checker's remaining duplicate readings, Bools and parallel data

| Field | Content |
|---|---|
| Evidence | From the cleanup handoffs. (1) The address-to-definition lookup is written about eight times across `Frontend/Growth/*.idr` and `Growth.idr`; `Sites.readingOf` re-reads a definition `Graph.kindOf` already holds. (2) "the first binder, normalising when hidden" is written six times. (3) `Template.closedRun` restates `Keys.successorRun` (now exported with `writerOf`). (4) `Proof.Requests.sameName` (private) duplicates `Graph.sameRoot`; Heads' `sameBytes` and Graph's `sameNode` rebuild proofs from the Bool `sameAddress`, where exporting Requests' `decideAddress` gives them directly. (5) `Growth.idr`'s `boundAt`/`boundIs` duplicate `Proof.Growth.bound`, and its `padded` is a different function from Requests' `padded` under one name. (6) A cap is held twice in `Proof.Growth`'s graph (`caps` and an origin arc). (7) An arc's weight may be `Absent`, so every reader rules it out by hand (Check twice, Potential, the T3 box): a label type without `Absent`, keeping `Weight` for `plus`/`join`. (8) `Arc.from` is a `Maybe` whose `Nothing` means the origin. (9) `Cycle` carries two lists matched by position, tied only by its `Ring`. (10) `Template`'s `Formal` has a middle field that is always 0, and `Computing` is reachable only from `Graph.withClosedFamilies`. (11) `TS.datas` and `TS.newtypes` are two maps with disjoint keys. (12) `Types.pushes` and `Finite.freshEnds` state one lemma twice. (13) Bools that are sums: `ArgValue.dictionary`, the `(ClosedTerm, Bool)` given to `staticsOver`, `TS.loops`. |
| Counterexample | each is a second copy that can drift, a guard every reader repeats, or a flag whose cases are unnamed |
| Root cause | the areas were cleaned one at a time, and each stopped at its files' edge |
| Correction | one exported lookup (State) for a definition by address, read once per node; one helper for the first binder; `closedRun` through `successorRun`; `decideAddress` exported and `sameName`, `sameAddressSound`, `sameAddressSelf` deleted; `Proof.Growth.bound` used and `padded` renamed apart; the cap held once; `Arc` labelled by a type without `Absent` and its origin a sum; `Cycle` as one list of edges carrying their ring; `Formal` without its middle field and `Computing` handled only where it is built; one map for data and newtypes; one lemma; the three Bools as sums |
| Deletion | the duplicate lookups, helpers, lemma and map; `sameName`; the hand `Absent` arms; the `Maybe` origin; the second list in `Cycle`; the always-zero field |
| Consumers | `compiler/src/IdrisMLIR/Frontend/Growth/*.idr`, `Frontend/Growth.idr`, `Frontend/Finite.idr`, `Frontend/Translate/{State,Types,Keys,Instances}.idr`, `Proof/{Growth,Requests}.idr`, and `tests/compiler/growth-check/Box.idr` (L22 adapts it in its handoff text: tests/compiler is L20's) |
| Discriminator | outputs byte-identical on Chez (every fixture's status, stdout, stderr, Core and module; the self compile's verdict); T3's box agrees with brute force; nothing asserted |
| Verification here | Chez, as common obligations say; the box |
| Size and risk | behaviour unchanged by construction; the proofs move with the types |
| Insight | 4, 5, 6, 7 |
