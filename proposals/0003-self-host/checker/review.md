<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Adversarial review of the checker packet

Three reviewers each read the whole packet through one lens:
- consistency, the only one of the three that wrote: it fixed stale
  shapes in lane bodies;
- soundness and termination, reporting only;
- executability and scope, against the swarm skill, reporting only.

Before them, every lane's drafter read the live source and returned
contract corrections. Those are folded into README §4 and listed under
"Drafting" below. What follows is each finding and where it now stands.

## Soundness and termination

The termination argument holds: every recursion descends on room, on
`Walked`, or on a structural count. The findings concerned the guarantee
that a correct program never raises the internal error, and one practical
hang:

| Finding | Severity | Resolution |
|---|---|---|
| A dictionary's root read two ways: the graph read the written head (`snd (MkPair x d)`), the request `implementationOf` | blocks | One `dictionaryRoot`, returning `Root`, computed in Core and stored in `Site.roots` and `Fields` (§4.3, §4.4, §4.7); fixture `bounded-dictionary-root` |
| A method function's leading positions had no arcs, since J's own call of M passes its method dictionaries as runtime values | fix | Weight-0 arcs from J's node into M's leading positions for every Dispatches edge (§4.6 step 4); fixture `bounded-method-own` |
| Types reached through a synonym got no `Builds` site | fix | Every type-constructor head in a template is a `Builds` site, Choice leaves and synonyms included (§4.4); fixture `bounded-synonym` |
| Literal heights at their token weight make K about 2^31 and the sizes take billions of steps | fix | Literals and holes are `Leaf 1`, their weight going to `Bounds.heaviest`. Sizes are erased, and `fitsWithin` decides them lazily (§4.2, §4.3) |
| With signatures as sites, `Ints n` is ω and refuses `type-level-shapes` | fix | A structural Nat recursion is bounded by its argument plus a constant (§4.3). D3 keeps ω for any other recursion |
| `Describes` not established for those three cases | blocks | It now holds by construction, as listed in §4.12. T2 holds a fixture for each |

## Executability and scope

| Finding | Severity | Resolution |
|---|---|---|
| Lanes copied a tree their siblings are writing | blocks | Every private copy comes from `git archive 1380a9d0 compiler tests` (parts/common.md) |
| P1 and P3 both defined the comparison lemmas | blocks | P3 deletes its copies and imports P1's |
| orchestrator.md missed integration steps | blocks | Added: the Profile export, the `git rm` of AlmostFull, ACCEPTANCE.md lines, Programs' comment, policies' empty header, gate 5 and the S1 prefix |
| Decisions left in lanes: `staticsOver`'s signature, G10's copy of classify's tests, `paramLayout`, G8's concrete listing and DecEq | fix | Each fixed in README §4.5, §4.7, §4.8 and §4.9 |
| G11 too large | fix | `Fields`/`fieldsOf` split into G12 (`Frontend/Growth/Implementations.idr`) |
| Gate 2 said T2 fixtures "compile", which needs the LLVM | fix | The frontend writes the module; compiling and running them is the owner's build |
| Stale acceptance pointing at growing-shape's `Ints` | fix | Pointed at `type-level-shapes` and `polymorphism-growth-recursion` |

The 12-lane frontier is honest: nineteen lanes, each typechecking against
stubs of §4, none waiting on a sibling's behaviour.

## Consistency

The reviewer fixed stale shapes in 16 lane bodies and found no import
cycle. Its README items are in §4:
- the constructors of `Positive` and `StuckArc`;
- `InFields`' checked comparisons;
- `dagPotential`;
- `Universe`'s listing argument;
- `staticsOver` sharing `keyingOf`;
- G6's `room` for G2.

## Drafting (contract corrections from the lane drafters, all in §4)

- **B1 is the head split on the requested projection,** not a substituted
  method function: `projection n` misses `>>=`, `pure`, `map` and `liftIO`.
- **Weights are `Finite Nat Nat` (gain, loss):** Integer cannot be reasoned
  about at the pin.
- **Theorem 1 needs `Describes`.** Without it the statement is false, as
  two machine-checked counterexamples show.
- **Each kind is read as its key writes it,** a dictionary as written. The
  holing rule is dropped.
- **`Proof.Generations` stays.** The worklist proves newness against the
  chain only: a flat list costs about 11 s per pass on the self compile.
- **`Potential.idr` is under `Frontend/Growth/`,** since no Proof module may
  import the fork.
- **The universe takes an abstract address listing,** since the concrete
  one does not typecheck (11 GB). It is bounded by `breadth`.

## Decided by the owner (2026-10-16)

- **D3, accepted:** a stuck type-level recursion that is not structural on
  a Nat is refused even from a bounded source, as in
  `polymorphism-growth-recursion`. Nothing in the tree or the accepted
  tests meets it (prototype Follow-ups 2 and 3).
- **The Idris coverage bug,** an erased function with nested constructor
  matches reported "not covering", is recorded as
  `upstream/50-erased-coverage-nested-match` and fixed later. Any upstream
  bug found is added under `upstream/` the same way.
