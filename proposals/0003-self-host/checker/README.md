<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The polymorphism checker: refuse only a type grown without bound (0003 S2.2)

The swarm packet for option C of [0003 §7](../README.md), decided by the
owner on 2026-10-16. It replaces the request relation, which refuses any
growth on a chain, with a check on the program's finite graph of static
positions. The check refuses a cycle that grows a static argument on every
round, and admits everything else with an explicit bound on every position.
The proof is written in Idris, with no stated trust point. Each claim is
marked *read* (path), *measured* (a run), *proved* (on paper, here),
*conjecture* or *decision*.

## 0. Engagement

- **Checkout:** `/Users/bjorn/Documents/idris-mlir`, `main`, HEAD
  `1380a9d0` (2026-10-16T18:19Z), clean before this packet. The
  investigation it rests on is in `/tmp/s22/`, with its scripts and dumps
  in `/tmp/s22/proto/`:
  - `frontend.md`: how the frontend makes requests, *read*;
  - `algorithm.md`: the algorithm and its proof;
  - `prototype.md`: the criterion on the self compile's real requests, *measured*.
- **Authorised:** writing this packet, and dispatching it. The owner said
  "go" on 2026-10-16, and all nineteen lanes were dispatched from
  `a50824e1`. The owner accepted both recommendations:
  - D3, as written;
  - the Idris coverage bug, recorded as
    `upstream/50-erased-coverage-nested-match`.

  The owner then ruled, on 2026-10-16, that any bug found is fixed at once
  by its own subagent: an Idris bug in the fork, as the fork's own code.
  The fixes run beside the lanes:
  - 50, the coverage bug;
  - 51, `totality-unimported-callee`, found by G4.
- **The owner's rules:**
  - no stated trust point: the proof is written (2026-10-16);
  - hard cutover, with no backwards compatibility;
  - representation first: `parts/representation.md` heads every dispatch,
    verbatim;
  - upstream first, and as little of our own code as possible;
  - two hosts;
  - the scratch backdoor that admitted polymorphism refusals is dead and
    banned from every gate;
  - whatever the new checker refuses is refactored later, never admitted;
  - self-hosting's other work waits until the checker lands.
- **Verification on this machine:** everything builds except LLVM. The
  frontend runs on Chez, so the checker's behaviour is verified here, on
  the test programs and the self compile's sources (§7). Lanes never
  commit; the coordinator integrates, commits and pushes.

## 1. Invariants

- **C1.** Every program the frontend admits has finitely many instances,
  and each static position has a checked bound:
  `bound(p) = min(cap p, K + π p)`.
- **C2.** A refusal of rule `polymorphism` names a cycle of definitions
  whose static argument grows on every round, and how much per round, in the
  caller's terms. Nothing else is refused as polymorphism.
- **C3.** Translation ends by construction. The worklist recurses on the
  room left in the finite universe of keys within the bounds. A request
  outside its bound is an internal error ("the growth check is unsound"),
  never a refusal and never a hang.
- **C4.** No `assert_total`, `covering`, `believe_me` or postulate stands
  for the check, its bound or the worklist. `Finite.translateFrom` becomes
  total.
- **C5.** The old relation is gone. Nothing admits by growth on chains
  any more: `admit`, `chainsEnd`, `AlmostFull`, `GrownAt`, Finite's `Older`
  and its judging are all deleted. Two things stay, because they are
  generic and still carry the descent:
  - the chains themselves, which `chooser` and `exiting` read;
  - `Proof.Generations`, the multiset argument for a first-in, first-out
    worklist, which is generic in its relation.

## 2. Rules (in addition to AGENTS.md)

- **Representation first.** A position of the checked graph is a `Fin n`.
  A weight is `Absent | Finite Nat Nat | Stuck` (gain, loss), a sum, never a flag. A
  verdict carries its certificate (a cycle or a potential), built by a
  decision that returns evidence.
- **One height.** The arcs, the caps and every bound check read one
  `Template` and its `height` (§4.3), so that they cannot drift.
- **The check is pure.** These import nothing of Core, so the exhaustive
  box (T3) builds them from source, with `-p idris-compiler`:
  - `Proof/*` imports base only, since no Proof module may import the fork
    (`tests/spec/frontend-imports`);
  - `Frontend/Growth/Check.idr` and `Frontend/Growth/Potential.idr` import
    base and the fork's pure `Libraries.Data.List.Finite`.
- **Exact for structural flow.** Admit every program whose static arguments
  grow only boundedly by structure. Refuse every cycle that adds at least
  one constructor per round. §9 lists what remains conservative.

## 3. Findings

| ID | Evidence | Counterexample | Correction | Owner |
|---|---|---|---|---|
| F01 | `Proof/Requests.idr` `admit`; `Frontend/Finite.idr:144-172` | `Maybe ContextEntry`, then `Maybe (Bool, Nat)` (`Core/Context.idr:92`), is refused, 1 symbol against 3; S1 counts 394 such refusals, *measured* | The check on positions (§4.10) | G3 |
| F02 | `Translate/Terms.idr:1001-1026` (`resolveMethod` only before settling) | `TTC Term` calls `toBuf` at `List (Name, Term)`, refused as one method growing | B1: a method request's node is its projection split by the dictionary's root, the implementation that runs (§4.5) | G5 |
| F03 | `Translate/Types.idr:600-659` (`dataInstanceIn` on `Chained`) | 44 data refusals in S1, such as `List DefFlag` against `List (Name, Nat)` | Data registration descends on room within the bounds (§4.11) | G7 |
| F04 | `Frontend/Finite.idr:282-325`, `translateFrom` `covering`, a TRUST POINT | The passes' end rests on a sentence | Recursion on room within the bounds (§4.11) | G6 |
| F05 | `Proof/AlmostFull.idr` (490 lines), Requests' `Decision`..`admit` and the AF proof | Dickson's lemma on written sizes, the measure that misfires on F01 | Deleted; the identity and the listing stay (§4.2). `Proof/Generations.idr` stays: it is generic in its relation | P3 |
| F06 | `tests/reject/polymorphism-{nested,growing-rank}` headers name lines 8 and 14 | TT from a TTC has no call-site location, so the refusal is at the definition (6, 12), *measured* | Each fixture states C's cycle and its line (D4) | T1 |
| F07 | No test admits S1's forms | A regression to the old rule would pass every test | Accept fixtures of bounded growth (§7) | T2 |
| F08 | The check is new, with no oracle | A Bellman-Ford or potential bug admits a growing cycle | An exhaustive box against brute force on every small graph | T3 |
| F09 | No Idris statement of C's bound exists | C1 would rest on paper | Lemma 1 and Theorem 1 in Idris (§4.12) | P2 |
| F10 | `Frontend/Program.idr:184-200` has no phase between reachable and translate | No place to refuse before translating | The `growth` phase (§4.13) | G4 |
| F11 | `prototype.md`, *measured*: one cycle through `(<$>)`, `map_Functor_(EitherT e m)`.a at `Either e a` +1 | Every `EitherT` is over `IO`, so the real chain ends. The graph merges `(<$>)` at EitherT's dictionary with `(<$>)` at IO's, and refuses the self compile | Nodes split by the roots of their dictionary arguments (§4.7) | G8 |
| F12 | `prototype.md` Follow-up, *measured*: 8 ω arcs off every cycle, such as `clockTime`'s `isClockMandatory` and `allSplits`'s `length` on a runtime list | ω off a cycle gives a finite position no explicit bound, so the worklist has no total measure | Unfold a stuck non-recursive type definition to the maximum over its leaves, and read each kind as its key writes it, a dictionary as written (§4.3). P3 deletes 2, and none stays live among calls' arcs (D3) | G1 |
| F13 | `tests/reject/polymorphism-nested-data` is refused at HEAD as `dependent field` at `L`, *measured* | `a` is an index of `T` (`N` changes it), so data positions built from `typeParams` never see the nesting | A data type's positions are its represented type arguments, indices included (§4.8) | G9 |
| F14 | No statement that a graph without a positive cycle has a potential | The check could find neither a cycle nor a potential, a case with no defined outcome | A verified heaviest-path Bellman-Ford (§4.12) | P4 |
| F15 | `algorithm.md` §0.4; `tests/programs/data/type-level-shapes` | Without caps, `count`'s `S m ↦ S (S m)` is +1 on a cycle, and an accepted program is refused | Caps read off the callee's type, consistent with `neededShape` (§4.9) | G10 |
| F16 | The site walk does not exist; the prototype read templates off a dump | Arcs from concrete instances refuse 9 accepted programs (`sortedmap`, `vect`), *measured* | Definition-level sites over markers, with leaf matches substituted (§4.4) | G11 |

## 4. Selected representations

These are fixed: every lane writes against them, and a lane that needs one
changed escalates. Paths below are under `compiler/src/IdrisMLIR/`.

### 4.1 `Proof.Growth` (P1): the graph and its certificates

```idris
public export
data Decision : Type -> Type where     -- moved here from Proof.Requests, unchanged
  Holds : p -> Decision p
  Fails : (0 _ : Not p) -> Decision p

public export
data Weight = Absent | Finite Nat Nat | Stuck
-- Finite gain loss weighs gain - loss. Naturals, not Integer: Integer is a
-- primitive no proof at this pin can reason about, and every comparison is
-- by cross-addition (a - b <= c - d iff a + d <= c + b). Ordered Absent <
-- Finite < Stuck. `weigh` writes one side 0, and nothing compares two
-- Finite weights for equality.
public export plus : Weight -> Weight -> Weight   -- Absent absorbs; Stuck absorbs Finite; Finite adds componentwise
public export join : Weight -> Weight -> Weight   -- the maximum in that order, by cross-addition

public export
data Present : Weight -> Type where   -- a weight an arc can carry: not Absent
  Measured : Present (Finite g l)
  Unmeasured : Present Stuck

public export
record Arc (n : Nat) where
  constructor MkArc
  from : Maybe (Fin n)   -- Nothing: the origin (a cap's one arc)
  to : Fin n
  weight : Weight
  0 present : Present weight   -- not Absent, by its type: an absent label is no arc

public export
record Graph where
  constructor MkGraph
  size : Nat
  arcs : List (Arc size)
  constant : Nat                 -- K: the tallest constant c(j) of any template
  caps : Vect size (Maybe Nat)   -- cap(p) = d + 1 when p's type inspects d levels of it

-- The positions in order, closing back to the first, and the Finite arcs
-- between each consecutive pair (by index), whose gains exceed their losses.
-- Indexed by both, so the evidence names its arcs. A Stuck arc is never part
-- of a Positive cycle; it is a StuckArc cause of its own.
public export data Positive : (g : Graph) -> List (Fin g.size) -> List (Fin (length g.arcs)) -> Type
-- An arc of weight Stuck: a type-level recursion stuck on a static argument (D3).
public export data StuckArc : (g : Graph) -> Fin (length g.arcs) -> Type
-- One arc satisfied: pot from + gain <= pot to + loss, the origin read as 0.
-- Only a Finite arc has the constructor, so no Stuck or Absent arc is
-- feasible, by construction.
public export
potentialAt : Vect n Nat -> Maybe (Fin n) -> Nat
potentialAt pot = maybe 0 (\q => index q pot)
public export
data Satisfies : Vect n Nat -> Arc n -> Type where
  MkSatisfies : (0 _ : LTE (potentialAt pot q + gain) (index p pot + loss)) ->
                Satisfies pot (MkArc q p (Finite gain loss) pr)
public export
data Feasible : (g : Graph) -> Vect g.size Nat -> Type where
  MkFeasible : All (Satisfies pot) g.arcs -> Feasible g pot

public export positive : (g : Graph) -> (c : List (Fin g.size)) -> (as : List (Fin (length g.arcs))) -> Decision (Positive g c as)
public export stuckArc : (g : Graph) -> (a : Fin (length g.arcs)) -> Decision (StuckArc g a)
-- The machine's comparisons on naturals and their lemmas (lteSo, notLtSo, equalSo, ...)
-- live here once; Proof.Requests imports them.
public export feasible : (g : Graph) -> (pot : Vect g.size Nat) -> Decision (Feasible g pot)
public export
bound : (g : Graph) -> Vect g.size Nat -> Fin g.size -> Nat
bound g pot p = maybe (g.constant + index p pot) (min (g.constant + index p pot)) (index p g.caps)
```

`Positive`'s sum is stated the same way: every arc of a `Positive` is
Finite (`All IsFinite`), and its gains exceed its losses. The constructors
consumers match on:

```idris
Sums : (0 _ : Ring g p p ps as) -> (0 _ : All IsFinite (weights g as)) ->
       (0 _ : LT (losses g as) (gains g as)) -> Positive g (p :: ps) as
ItIsStuck : (0 _ : (arc g a).weight = Stuck) -> StuckArc g a
```

The comparisons are the machine's, and the proofs are erased. The module
imports base and nothing else.

### 4.2 `Proof.Requests` after the cutover (P3): identity, listing, universe

What stays (*read*: Recursion, Profile, Programs, Keys, State and Forms use
it): `Listed`, `listedFin`, `listedEither`, `listedVia`, `Numbered`,
`listedVect`, `Address`, `addresses`, `lowBits`, `Token`, `weight`,
`weighs`, `Fits`, `Written`, `Link`, `argumentSize`, `sizes`, `sameAddress`
(with its soundness), `writtenAt`, `argumentsAt` and `fibre` (with their
completeness), and the comparators that `Ord`/`Eq` on links rely on. The
module imports `Proof.Growth` for `Decision`. It adds:

```idris
public export
record Bounds where
  constructor MkBounds
  heightAt : Address -> List Nat   -- per parameter, the height a static argument stays within; a parameter
                                   -- past the list's end, or at 0, keys nothing (so [] for a definition with no position)
  arity : Nat                      -- A: the most children of any template's node
  heaviest : Nat                   -- L: the heaviest literal or hole token any template holds
  breadth : Nat                    -- above every link's length, constructor index and argument index of the
                                   -- reachable program (G2 measures it): without it, padding admits a link of any
                                   -- length, and the universe is infinite

-- Every link within the bounds, over an abstract listing of the addresses:
-- at each address, at most breadth arguments, of every size vector pointwise
-- at most sizeAt. Erased, never computed. Callers pass `addresses`. A proof
-- over the concrete 256^8 listing never finishes (*measured*: 11 GB, then
-- killed), and HEAD states its own over an abstract one (Requests.idr:933-940).
-- A type names the listings through aliases defined on a right-hand side: a
-- lower-case global written in a type is silently bound as a new implicit.
public export 0 Universe : Listed form -> Listed Address -> Bounds -> List (Link form)
public export
record InUniverse (0 forms : Listed form) (0 names : Listed Address) (b : Bounds) (l : Link form) where
  constructor MkIn
  0 short : LTE (length l.arguments) b.breadth
  0 sized : Pointwise (sizes l) (map (\h => sizeWithin b.arity h b.heaviest) (heightAt b l.definition))
                                                          -- the comparisons within made, padded with 0
  0 member : Elem l (Universe forms names b)
export within : (0 forms : Listed form) -> (0 names : Listed Address) -> (b : Bounds) -> (l : Link form) ->
                Decision (InUniverse forms names b l)
export sameLink : DecEq form => Link form -> Link form -> Bool              -- made exported, with its soundness
export DecEq (Link form)                                                    -- made exported
export elemLink : DecEq form => (l : Link form) -> (ls : List (Link form)) -> Decision (Elem l ls)
public export 0 sizeWithin : (arity, height, heaviest : Nat) -> Nat
-- (2 * height + heaviest) * sum [max 1 arity ^ k | k < height]. A key of that height, no node with more children
-- than arity, weighs no more: a Nat run's token weighs at most twice its height (a Fin run's, Keys.idr:550-563,
-- is the heaviest), and any other literal's or hole's at most heaviest. Erased: never computed.
export fitsWithin : (size, arity, height, heaviest : Nat) -> Decision (LTE size (sizeWithin arity height heaviest))
-- Sums the terms until they exceed size, so it never builds the number: at most min height (log size) steps.

-- The fields translateFrom learns: a data link in the universe, a constructor
-- index and an argument index, both below breadth.
public export 0 FieldUniverse : Listed form -> Listed Address -> Bounds -> List (Link form, Nat, Nat)
public export
record InFields (0 forms : Listed form) (0 names : Listed Address) (b : Bounds) (f : (Link form, Nat, Nat)) where
  constructor MkInFields
  0 link : InUniverse forms names b (fst f)         -- the comparisons inFields made, so that its Fails
  0 index : LT (fst (snd f)) b.breadth              -- needs no soundness proof of the listing
  0 argument : LT (snd (snd f)) b.breadth
  0 member : Elem f (FieldUniverse forms names b)   -- erased, as InUniverse's: a runtime Elem cannot be built
export inFields : (0 forms : Listed form) -> (0 names : Listed Address) -> (b : Bounds) -> (f : (Link form, Nat, Nat)) ->
                  Decision (InFields forms names b f)
```

`within` decides by the machine's comparisons of `length l.arguments`
against `breadth`, and of each `sizes l` entry against `sizeWithin` of
`heightAt l.definition`'s entry, through `fitsWithin`. It builds
the membership from `fibreComplete`. Its `forms` is erased, since building
`Forms.forms` costs about 4.2 million entries (`Forms.idr:242-258`). The
room lemma lives in Finite (G6), over the fork's `NoDup` and `pigeonhole`,
since no Proof module may import the fork.

### 4.3 `Frontend.Growth.Template` (G1): one language for every static argument

```idris
public export
data Static = AType | ADictionary | AForm | AShape   -- as classify's PKind: TypeParam, DictParam, FormParam, ValueParam

public export
data Template
  = Var Nat Nat                         -- the writer's parameter i, bound by its pattern at depth d (0: unmatched)
  | Head (Maybe Address) (List Template) -- a head: a type or data constructor, an implementation, an interface's
                                        -- constructor (Just), a binder or primitive type former (Nothing)
  | Leaf Nat                            -- a closed part of that height: a Nat literal's run (n: n + 1), a primitive type,
                                        -- a bound variable, an Erased placeholder (1)
  | Token Nat                           -- any other literal, or a hole marker: height 1, carrying its key token's weight
                                        -- for Bounds.heaviest
  | Choice Template (List Template)     -- a stuck non-recursive definition, unfolded: what it matched on, then its leaves
  | Opaque Address (List Template)      -- a recursive definition, stuck on what its arguments hold
  | Field Nat Template                  -- field k (a method or a superclass) of a dictionary not yet a constructor
  | Held Address Nat                    -- the dictionary data constructor C holds at field p, matched out of a value
                                        -- (SortedDMap's Ord, Data/SortedMap/Dependent.idr:218-220)

export markerAt : (i, d : Nat) -> ClosedTerm    -- the marker Var i d reads back from
export templateOf : {auto c : Ref Ctxt Defs} -> Static -> ClosedTerm -> Core Template
export height : Template -> Nat                 -- Var and Field 0; Leaf h; Head, Opaque 1 + max; Choice the max of its leaves
export arity : Template -> Nat                  -- the most children of any node
export weigh : (i : Nat) -> Template -> Weight  -- Absent; the max of d_t - d over Var i d outside Field, as Finite (d_t - d) 0 or Finite 0 (d - d_t); Stuck under Opaque
public export
data Root = Implementation Address   -- the implementation (or interface constructor) at the root
          | Parameter Nat Nat        -- a marker Var i d: the writer's own dictionary
          | Unrooted                 -- neither, as a lambda's result (\_ => __Impl_Eq_Int)
export dictionaryRoot : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Root
-- what implementationOf names at a dictionary's root, over markers, never its written head: snd (MkPair x d)
-- is d's root. The one root function. closedHeight's root (G5's heads), Argument.root and Field.root (G8's
-- roots) are all its result, computed where Core is, so that G8 stays pure.
export fieldsIn : Template -> List (Template, Weight)    -- each Field or Held, with its projection-rule arc weight: Finite (e + 1) 0
                                                         -- at depth e, Stuck under an Opaque
export fieldAt : (i, d : Nat) -> (path : List Nat) -> ClosedTerm   -- a match on a dictionary marker's field, a field of a field by its path
export heldAt : Address -> Nat -> ClosedTerm             -- what a match binds a held dictionary to
export markerOf : Name -> Maybe (Nat, Nat)               -- G1's markers read back, so that sites can show binder names
export closedHeight : {auto c : Ref Ctxt Defs} -> Static -> ClosedTerm -> Core (Nat, Root)   -- a request's argument, read as its key
```

`templateOf k` reads an argument exactly as its key writes it at kind k (*read*:
`Instances.idr:125-135, 164, 199, 216-223`). This is one representation,
the key's, not a second reading:
- **`AType`:** normalised by `Closed.normaliseClosed`. A stuck definition
  application is unfolded: its case tree's leaves, with the arguments'
  matches substituted (a match on `Var i d` with `S k` binds `k` to
  `Var i (d + 1)`), joined as `Choice` behind what they matched on.
- **`ADictionary`:** as its key holds it, from the same decision
  `classify` makes (`Instances.idr:199, 216-223`):
  - a closed dictionary as written, with metavariables solved and nothing
    normalised, a definition applied in it being a `Head` of its arguments;
  - a runtime-dependent one in `implementationOf`'s form.

  So `allSplits`' `Functor (Vect (S (length {P15} xs)))` weighs +3, finite.
- **`AShape`:** the skeleton, as `argumentShape` makes it.
- **`AForm`:** the form, as `classify` writes it.

In each:
- a marker is a `Var`;
- a constructor, type constructor, implementation or Π is a `Head`;
- a string is a `Head` of its characters;
- a Nat literal is a `Leaf (n + 1)`, its run's tree height, so that a
  template `S (S (Var i 1))` is no shorter than the run it becomes;
- any other literal, and a hole marker, is a `Token`: height 1, carrying
  its key token's weight (`Keys.writeConstant`, `Keys.idr:538`), which goes
  to `Bounds.heaviest`, never to a height. A primitive type is `Leaf 1`. *Read* (soundness review): a height at a literal's
  weight makes K about 2^31 for `So (x < 2147483647)`, and the sizes take
  billions of steps;
- a projection left on a non-constructor is a `Field`;
- an `Erased` placeholder (an unbound binder, a runtime part) is `Leaf 1`.

Markers are G1's own family, a name that is not an `MN` name. The fork's
quotation rebinds exactly the bound `MN` names, by their number
(`Core/Normalise/Quote.idr:108-123`), so an `MN` marker would be captured.
G1's acceptance probes this. They are distinct from
`holeMarker`, whose holes are real parts of request keys.
`normaliseKeeping` is private to Closed, which no lane owns, so it is not
used.

Unfolding stops at a definition already being unfolded, by `Walk`'s
measure over the names on the unfolding stack. At that point:
- **A structural Nat recursion is bounded.** This is a recursion on one
  Nat-like argument, each recursive call taking that argument's
  predecessor (matched one level deeper), whose recursive result sits under
  at most one head per level. Its other arguments pass unchanged, and its
  base leaves and other children are closed. A branch such as
  `F a Z = a` grows by a sum of two heights, which no template states. It reads as `Choice` of its non-recursive
  leaves and of the argument raised by those leaves' height c (c levels of
  `Head Nothing` above it). By induction on the argument, its height is at
  most the argument's plus c. `Ints (S k) = (Int, Ints k)` reads as weight
  0 from n, so `type-level-shapes`' `second` is admitted.
- **Any other recursion is `Opaque`, ω.** That is a deeper step, a
  recursion on a non-Nat value, or several heads per level.

### 4.4 `Frontend.Growth.Sites` (G11): what each definition writes

```idris
public export
data Reach = Calls Address               -- a definition, an implementation's function, a method function
           | Builds Address              -- a type constructor (also for a data constructor's application)
           | Dispatches Template Root Nat  -- method k of the dictionary the template is (Var, or Field of one), with the
                                          -- dictionary's dictionaryRoot, so that no root is ever read off a written head

public export
record Argument where                       -- one argument a site writes, whole: nothing about it is looked up by index
  constructor MkArgument
  position : Nat                             -- the target's parameter j (for Dispatches: the method's own j-th,
                                             -- in the field's lambda order)
  kind : Static
  template : Template
  root : Root                                -- dictionaryRoot for an ADictionary, made by G11 in Core; Unrooted otherwise
  shown : String                             -- the template in the writer's binders, for messages

public export
record Site where
  constructor MkSite
  writer : Address                           -- whose parameters the Vars are
  within : Address                           -- whose text holds it, for messages: the definition, or a field's constructor
  reach : Reach
  arguments : List Argument
  fc : FC

export sitesOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Core (List Site)
export sitesIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> (writer, within : Address) -> ClosedTerm -> Core (List Site)
-- Frontend.Growth.Implementations (G12), which Sites, Heads and Graph import:
public export
data Field : Type where
  -- an eta-wrapped method field: its method function m, its template, and where each argument lands in m.
  -- own: for each of the method's own arguments (the field's lambdas, in order), its parameter index in m;
  -- leading: for each implementation parameter p, its index in m. Its root is m, by construction.
  Method : (m : Address) -> Template -> (own : List Nat) -> (leading : List (Nat, Nat)) -> Field
  -- any other field: a hand-built dictionary's lambda, a superclass dictionary, with its dictionaryRoot
  Plain : Template -> Root -> Field
public export
record Fields where
  constructor MkFields
  arity : Nat                    -- the implementation's own parameters
  fields : List Field            -- in the interface constructor's order
-- *Read* (G12, on the fork): M's parameters do not start with J's. A method's own implicit type variables come
-- first: map_Functor_(EitherT e m) is {b} {a} {e} {m} {Functor m} func x (the fork's Idris/Elab/Implementation.idr
-- :435-440 binds them outside). In prelude and base, 528 of 2,051 method fields are so (measured, G12). The eta wrapper places
-- each argument exactly, so the placement is read off it, never assumed.
export fieldsOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Core (Maybe Fields)
```

- `sitesOf d` walks d's signature (each parameter's type and the result
  type, with the parameters marked) for every reachable definition,
  primitives and constructors included. The translation registers data
  instances from callee types (*read*: `Instances.idr:234`,
  `Programs.idr:64`, `Terms.idr:1185-1195, 1291, 1357, 1577`), so those
  are sites of the callee.
- `sitesOf d` walks d's case tree:
  - its parameters are marked (`markerAt i 0`);
  - each leaf has its matches substituted, `Var i d` at match depth `d`. A
    default case is first expanded into the constructors it stands for, so
    that each leaf knows its match. *Read* (T1's drafter, `:di second`):
    `type-level-shapes`' default branches would otherwise read as a +1 loop
    and an opaque `Ints n`;
  - case and with blocks are nodes of their own, since the translation
    requests each block as its own instance. d's call of its block is a
    `Calls` site;
  - solved metavariables and the fields it settles are included
    (`Programs.idr:57-69, 117-129`).
- Every application in every term, at any depth, is a site, including one
  written inside a static argument:
  - a call to a definition is `Calls`, its static arguments decided by
    `Instances.staticsOver` (§4.5). That is `classify`'s decisions, made
    without registering or refusing, so they can run over markers;
  - a data constructor applied with dictionary arguments is also a `Calls C`
    at them, so that the flow sees what a `Held` reads;
  - every type-constructor `Head` in an argument's template is a `Builds`
    site at its children (at the type's represented arguments, §4.8). That
    includes the heads in `Choice` leaves and in unfolded synonyms. So
    `List (Nat, Vector1 a)` builds `List1` and `Pair` at `(Nat, a)`; the
    written term alone misses them (*read*, soundness review). A data
    constructor applied is `Builds` of its type likewise.
  - A `Builds` site's arguments are read with each type constructor's
    unrepresented arguments erased, keyed on `represented` (G11's
    `eraseIn`). They are never read through `eraseIndices`, which is keyed
    on `typeParams` and would erase a represented index: nested-data's
    `T (a, a)` would become `T _` and lose its +1 arc (*measured*, G9).
    The data key erases more than this, so its heights stay within these
    bounds. Each argument is first read through `canonicalTypeArg`
    (`Closed.idr:1172`). A function's type parameter, which its key holds
    in full normal form, is read in full;
  - an implementation applied is `Calls` of its function;
  - a method call is the projection's `Calls`, at the projection's
    parameters. Beside it is a `Dispatches t r k`, carrying the method's own
    static arguments, the ones past the projection's arity (*read*:
    `Terms.idr:912, 1012-1018`, `drop parity`), indexed from the method's
    first own parameter;
  - a projection function's own body (one case on the interface's
    constructor, returning field k, applied or not) is the single site
    `Dispatches (Var i 0) (Parameter i 0) k`, carrying its later parameters. This is how B1
    reaches the method function (§4.5).
- A head is attributed to the site that writes it, never to a dispatch.
- Sites declares its own walk phase. Terms' `Phase` is plain `export`, so
  its constructors are hidden.
- A constructor's arguments are bound by reading its normalised type with
  each binder probed as `Types.paramLayout` probes it (`Types.idr:60-62,
  72-90`). G7 exports `paramLayout` and its probe, so there is one reading.

### 4.5 Nodes and requests (G5: `Translate/State.idr`, `Translate/Instances.idr`)

```idris
-- Translate.State
public export
record Node where                 -- a definition as the check splits it
  constructor MkNode
  definition : Address            -- the requested definition: a function, a projection, a method function, a type constructor
  heads : List (Nat, Address)     -- each dictionary parameter whose value has an implementation (or an interface
                                  -- constructor) at its root, by parameter index, ascending
-- Eq and Ord: lexicographic.
export nameAt : Context -> Address -> Maybe Name   -- addressOf's inverse, for messages
public export
Position : Type
Position = (Node, Nat)

-- TS gains (written by the growth phase, read by the worklist):
  bounds : SortedMap Position Nat   -- each static position's height bound
  sizes : Bounds                    -- P3's, from the bounds, the graph's arity and its breadth;
                                    -- initState's is MkBounds (const []) 0 0 0, which the growth phase replaces
-- Request gains:
  node : Node
```

`request` computes `node`:
- `definition` is always the requested definition's address, the one the
  link names. Nothing is substituted.
- `heads` holds the root that `closedHeight` gives each `DictParam`,
  keyed by its index. A dictionary with no root (`\_ => __Impl_Eq_Int` in
  `tests/accept/higher-order-dictionary`) contributes none, here and in the
  graph alike.

B1 is the head split itself. A method call is requested as its projection
at the dictionary, so `MkNode toBuf [(0, TTC_List)]` is "toBuf, keyed by
the implementation that runs". G11 reads a projection's body (its case on
the interface's constructor, returning field k) as one `Dispatches (Var i
0) (Parameter i 0) k` site carrying its later parameters. G8 then takes the node to J's
method function k: the prototype's `method@impl` node and its pass-through
hop. *Measured*: `projection n` alone misses `(>>=)`, `pure`, `map`,
`foldMap` and `liftIO`. Splitting the requested definition itself makes
that recognition unnecessary.

`nextPass` (`State.idr:304-308`) keeps `bounds` and `sizes`, which the
growth phase wrote before the first pass.

```idris
export staticsOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     (owner : String) -> (arity : Nat) -> (callee : ClosedTerm) ->
                     List (Maybe (ClosedTerm, Bool)) -> Core (List (Maybe Static), ClosedTerm)
-- Per argument, its closed written value and whether it is a dictionary (Nothing: a runtime value);
-- it gives each parameter's kind and the rest of the type, registering nothing and refusing nothing.
```

G5 also exports `staticsOver` from Instances.idr: `classify`'s decisions
of which parameters are static, and how, made without registering a data
instance or refusing. *Read*: `classify` registers data instances at
marker types through `coreBinder` (:234) and `coreType` (:226), and
refuses a form passed straight through (:180-181), so it cannot run over
markers. `classify` and `staticsOver` decide through one `keyingOf` and
one `needsShape`: one representation of the decisions.

The link stays the identity, and nothing is rekeyed. Recursion.idr's
private `Node` (:37-42) is renamed `Member` to free the name.

### 4.6 The graph (G2: `Frontend/Growth/Graph.idr`)

```idris
public export
data Wrote = FromArgument Site Argument   -- the site and the argument whose template gave the arc
           | FromField Address Nat         -- a leading arc: implementation J's method field k placed J's parameter
           | FromCap Position              -- a cap's origin arc into this position: no site wrote it

public export
record Built where
  constructor MkBuilt
  graph : Graph
  position : Vect graph.size Position          -- what each Fin is
  wrote : Vect (length graph.arcs) Wrote       -- what made each arc
  arity : Nat                                  -- A: the most children of any template's node
  parents : SortedMap Node Node                -- the node that first reached each, on the walk from main
  breadth : Nat                                -- above every reachable definition's parameter count and data type's
                                               -- constructor and field counts, for Bounds.breadth
  heaviest : Nat                               -- the heaviest literal or hole token any template holds, for Bounds.heaviest

export build : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> (main : Name) -> Core Built
```

1. Walk the reachable definitions from `main` under `Walk`, over `sitesOf`,
   G9's data sites and `fieldsOf`'s targets. A written implementation
   reaches every method function and superclass application of it.
2. Compute G8's flow over those sites.
3. Walk the nodes from `MkNode main []` over G8's `reaches`. The universe is
   finite: the reachable definitions times their heads.
4. For each site in a node W, at each argument `(j, _, t)` and each callee
   node T it reaches:
   - an arc `(W, i) → (T, j)` of weight `weigh i t`, wherever that is not
     Absent;
   - for each `Field k s` occurring at depth `e` in t, and each root J that
     G8's `roots` gives `Field k s`, an arc from every position of every
     node of J's to `(T, j)`, of weight `e + 1`. This is the projection
     rule: the root J was written by whoever built the dictionary. A Field
     under an `Opaque` gives those arcs weight `Stuck`, as `weigh` does for a
     Var there. `fieldsIn` stops at a Field: a field of a field is reached
     through the outer one, by `roots`.
   - for each `Dispatched m placed j k leading`, an arc of weight 0 from
     `(J-node, p)` to `(m, q)` for each `(p, q)` in `leading`, from each
     node of J whose heads agree, attributed `FromField j k`. G2 never
     recomputes J, the field or a placement, and never searches J's body
     for its call of M. It comes from each node of J whose heads
     agree with M-node's leading heads. M's leading positions hold J's
     arguments, which the writers of `J u⃗` gave J. J's own call of M passes
     its method dictionaries as runtime values, with no roots, so it reaches
     another M-node (*read*, soundness review: `Terms.idr:1001-1026`).
5. K is the maximum of `height t` and of each Field's `e + 1`, over every
   argument.
6. A capped position (G10) drops its incoming arcs for one origin arc of
   weight `cap - K`.
7. A position is any `(T, j)` an argument names, and every represented
   argument of a reachable data type.

### 4.7 The heads (G8: `Frontend/Growth/Heads.idr`)

```idris
export record Flow                                   -- opaque: the unsplit head sets
export flow : SortedMap Address Fields -> List Site -> Flow   -- the least sets, on room over a NoDup list of (position, head) pairs
-- The room is over an erased, abstract listing, as P3's universe is: a concrete 256^8 listing of addresses
-- hangs the checker (measured, P3's drafter). Novelty is by `sameAddress`, never base DecEq on Fin bytes,
-- which costs O(value) per byte.
export roots : Flow -> (writer : Node) -> Template -> List Address
export rootsOf : Flow -> (writer : Node) -> Template -> Root -> List Address   -- the Root first, then the template:
                                                                            -- what G2 reads at a Dispatches
public export
record Placed where                -- an argument and the callee parameter it lands at: never looked up again
  constructor MkPlaced
  argument : Argument
  parameter : Nat
public export
data Reached : Type where
  -- Calls and Builds: each argument at its own position
  Called : Node -> List Placed -> Reached
  -- through implementation j's Method field k: its own placement applied, its leading placement carried
  Dispatched : Node -> List Placed -> (j : Address) -> (k : Nat) -> (leading : List (Nat, Nat)) -> Reached
export reaches : Flow -> (writer : Node) -> Site -> List Reached
```

`roots` of a template:
- an argument's root is its `Argument.root` (§4.3's `dictionaryRoot`,
  never its written head): `Implementation J` is `[J]`; `Parameter i 0` is
  the writer's head at i; `Unrooted` is `[]`;
- `Field k s` is, for each root J of s, the root of J's field k
  (`fieldsOf`), with the flow only where that field is one of J's own
  variables. A projection of the writer's dictionary is resolved through the
  writer's head, never by the flow set first. *Measured* (prototype
  Follow-up), the flow set first refuses `pure_Applicative_(StateT s m)` at
  +2 per round, and this rule refuses nothing;
- `Held C p` is the flow's set at `(C, p)`;
- `Choice` is the union of its leaves' roots;
- `Leaf`, `Opaque`, `Head Nothing`, and a dictionary parameter whose writer
  has no head there give `[]`.

*Measured* (G8's drafter, prototype data): the flow on the self compile
has 661 slots, 1,723 pairs and 322 heads, and settles in 4 rounds.

`flow` is the least solution of the same rules on unsplit definitions:
writing `J u⃗` puts the roots of `u⃗`'s dictionaries into J's positions and
into J's method functions' leading positions.

`reaches` splits each callee by the roots of its dictionary arguments, one
node per combination:
- `Dispatches t r k` reaches, for each root J that r gives, J's method function k (no
  node where J is an interface's constructor);
- `Builds T` reaches `MkNode T []`.

### 4.8 Data (G9: `Frontend/Growth/Fields.idr`; G7 exports `represented`)

```idris
-- Translate.Types (G7) exports:
export represented : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Nat)   -- typeParams without the parameter filter
export tyConFacts                                                                  -- made exported, for G10's natLike
export eraseIndices                                                                -- made exported: G11 reads a Builds site's arguments
                                                                                   -- as the data key does
export paramLayout                                                                 -- made exported, with its binder probe (:60-62),
                                                                                   -- for G11's reading of a constructor's arguments
-- Frontend.Growth.Fields (G9):
export fieldSites : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Core (List Site)
```

A data type's positions are its represented arguments:
- every argument in `typeParams`, unchanged, so that keys do not change;
- every non-parameter argument whose kind is a universe and that the values
  hold. That is the least set where a constructor holds a value of the
  argument itself, or holds it at a represented position of a field's type
  constructor.

*Measured* (G9's drafter's probe, 378 fixtures and the self compile): this
adds a position only to `polymorphism-nested-data`'s T. Every `typeParams`
is HEAD's, and no type of arity 0 has a position. The least set reads
another type's positions as its `typeParams`, so there is no fixpoint
across types. `PCons : P (a, a) -> P a`, whose index no value
holds, is one instance, as at HEAD. `fieldSites T`:
1. marks T's represented arguments;
2. matches each constructor's return type against them (an index pattern
   `(a, b)` binds `a` and `b` at depth 1);
3. gives `sitesIn` each field type.

A field type `T (a, a)` is then `T.a → T.a` at +1, and
`polymorphism-nested-data` is refused as polymorphism at its declaration.
The translation still keys data instances by `typeParams` (G7). Positions
beyond those are checked, never keyed.

### 4.9 Caps (G10: `Frontend/Growth/Caps.idr`)

```idris
export capOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> (j : Nat) -> Core (Maybe Nat)
```

For a parameter that `staticsOver`, run over markers, gives `Just AShape`
and whose type is a `Chain` (`tyConFacts`' `natness`), take the callee's type
with j marked and every earlier parameter given `classify`'s placeholder
(`Erased EmptyFC Placeholder`), under `templateOf AType`'s unfolding.
- **`natness`:** `TyConFacts`' two `Bool`s become one sum, so that a chain
  that is not Nat-like cannot be stated. G5 declares it, and G7 computes it:

  ```idris
  data Natness = NotNat     -- not Nat-like
               | Numeral    -- Nat-like (Idris's ZERO/SUCC), but a constructor takes an erased argument
               | Chain      -- Nat-like, every constructor argument at run time: a shape is a chain of S
  ``` *Measured* (G10, on HEAD): `Fin` is
  Nat-like, but a key keeps `FS`'s erased index, so
  `f[FS (S^5 Z) _, …]` has height 7 against a cap of 3.
- **The placeholder:** a match on an earlier parameter given a marker never
  reduces, and the stuck application still holds all of j, which
  `neededShape` then keys whole. *Measured*: `probe/stuck-dictionary` is
  admitted with a key of height 6 against a cap of 2. With the
  placeholder, that j is loose, and so uncapped. G10
never re-derives `classify`'s tests: there is one reading of which
parameter is a shape. The cap is `d + 1`, where d is the deepest
match on `Var j _` recorded in a `Choice`'s first field. There is no cap
(`Nothing`) when `Var j _` occurs anywhere but as a match's scrutinee: as a
leaf's part, or under an `Opaque`. *Read* (G1's drafter): a branch that
holds j outside a match (`F (S k) = Foo k`) makes `neededShape` key the
whole shape (`Instances.idr:112`), which a cap would exceed. A non-Nat
shape is uncapped. The cap must be at least every depth
`Instances.neededShape` keeps of j (*read*: `Instances.idr:106-117`). G10
proves this by construction, reading the same type the same way, or
escalates. Every other kind is uncapped.

### 4.10 The check (G3: `Frontend/Growth/Check.idr`; pure)

```idris
public export
data Cause : Graph -> Type where
  Cycle : (c : List (Fin g.size)) -> (as : List (Fin (length g.arcs))) -> Positive g c as -> Cause g
  Unbounded : (a : Fin (length g.arcs)) -> StuckArc g a -> Cause g
public export
data Verdict : Graph -> Type where
  Grows : List1 (Cause g) -> Verdict g                  -- at least one cause, by its type
  Bounded : (pot : Vect g.size Nat) -> Feasible g pot -> Verdict g
export check : (g : Graph) -> Verdict g
export dagPotential : (g : Graph) -> Vect g.size Nat   -- step 4's potential, for T3
```

1. Every Stuck arc is a `StuckArc` (D3).
2. Strongly connected components of the positions, by a total Tarjan over
   `Fin g.size`.
3. In a component with no negative arc, each arc of weight ≥ 1 is a
   one-arc-closing positive cycle (found by a path back inside the
   component), and π is constant on it. Otherwise P4's `heaviest` runs on
   the component.
4. Potentials over the DAG of components, callers first: `π p = max 0
   (π q + w)`.
5. The DAG's potential (`dagPotential`, exported for T3) is checked by
   P1's `feasible`. A graph with no Stuck arc reaches this step.
   - If it holds, that is `Bounded`.
   - If it fails, which is a bug in G3, `heaviest` runs on the whole graph
     from it and still yields a certificate, a cycle or a potential.

   So the pure check never lacks evidence and has no internal case. T3's box
   checks two things on every Bounded graph, so a bug in G3's potential
   shows in the box, never as silent cost:
   - `feasible g (dagPotential g)` holds;
   - the potential is the least one.

   *Measured* (G3/T3's drafter): a floor mutation fails 9,621 box graphs
   under this check, and none under a `heaviest`-only recheck, which hides
   it. The whole check takes 1.5 s at 7,000 positions and 14,000 arcs.

Components and reachability follow every arc between positions, Stuck
included. Cycles are made of Finite arcs only, and a Stuck arc is only ever
reported as `Unbounded`.

Reported causes, so that one cause gives one refusal (the reject harness
counts exactly one, `tests/lib/profile.sh:91,104`):
- one positive cycle per component that holds one;
- each `StuckArc` whose source no positive cycle reaches. A position a
  growing cycle reaches is unbounded already, so its opaque arcs are
  consequences of that cycle, not other causes.

### 4.11 The worklist (G6: `Frontend/Finite.idr`; G7: `Translate/Types.idr`)

- When the worklist takes a request, it checks two things:
  - for each static parameter j: `closedHeight` of the static value, against
    `bounds (node, j)`; a missing entry or an excess is `internal "the
    growth check is unsound: …"`;
  - then `within` on the link, with the same internal error if it fails.
- The worklist keeps its generational pass over chains (`Proof.Generations`,
  unchanged), with a new relation. `Fresh` extends a chain by a request
  new to it (`elemLink` against the chain, which is short) that lies in the
  universe (`within`'s erased membership).
  - A chain is accessible under `Extends Fresh` by room: a chain is `NoDup`
    and inside `Universe forms addresses st.sizes`, so `pigeonhole` bounds its
    length. G6 writes that lemma over the fork's `NoDup` in Finite, and
    exports it for G7's data chain and G2's node walk:

    ```idris
    export 0 room : {u : List a} -> NoDup (x :: kept) -> All (\y => Elem y u) (x :: kept) ->
                    LT (minus (length u) (length (x :: kept))) (minus (length u) (length kept))
    ```
  - Global newness stays the runtime `seen` set's (`request`). The proof
    never searches all instances.
- `translateFrom` recurses on room in P3's `FieldUniverse`: a data link in
  the universe, a constructor index and an argument index, both below
  `breadth`. Each pass learns a new field (`learnt`), proved new against
  the short list of fields learnt so far. It is total, and the TRUST POINT
  sentence goes.
- `dataInstanceIn` checks the same two things for a data instance, at
  `MkNode T []`, and recurses on room. `Repeated` stays, as the membership
  test that declares recursive types.

### 4.12 The proofs (P2: `Proof/Bound.idr`; P4: `Frontend/Growth/Potential.idr`; both pure)

P2 works over a model:
- trees `T` of heads with children, and variables `y` with a depth `d_t(y)`
  in a template;
- `height`, substitution and subterms;
- the least family `V` closed under a graph's sites, where the values at
  each source position are matched by patterns that bind `y` at depth
  `d_p(y)`.

It proves:
- **Lemma 1:** `h(tσ) ≤ max(c t, max_y (h(σ y) + d_t y))`, and
  `h(σ y) ≤ h(v) − d_p y` for the value v that y is bound in.
- **Theorem 1:** `bounded : Describes g ss -> Feasible g pot -> InV g ss p
  v -> LTE (height v) (bound g pot p)`, by induction on V's derivation.
  `Describes g ss` says how the sites ss sit in g:
  - a listed site's target is uncapped;
  - K is at least the site's template's own height;
  - every occurrence of a variable is carried by an arc of weight at least
    e − d, where e is its depth in the template and d its match depth;
  - every capped position has its origin arc, of weight at least cap − K.

  Sites into capped positions are not listed (§4.6 step 6). *Proved*, by a
  machine-checked counterexample in P2's sketch: without `Describes`, the
  statement is false (a cap of 5 with no origin arc, or a constant taller
  than K). `Describes` is what construction establishes, and G6's internal
  error checks it at run time:
  - `carried` holds by G2's arcs (the weigh arcs, the projection rule, and
    the J→M leading arcs) and by G11's `Builds` from every type-constructor
    head;
  - the request's position is the graph's because one root function
    (`dictionaryRoot`) gives G5's heads and G8's roots alike.

  T2 holds one fixture for each of these three, which the soundness review
  found missing.

P4 (`Frontend/Growth/Potential.idr`, which uses the fork's `NoDup` and
`pigeonhole`) exports:

```idris
heaviest : (g : Graph) -> (inner : List (Fin (length g.arcs))) -> (0 _ : All IsFinite (weights g inner)) ->
           (start : Vect g.size Nat) ->
           Either (c ** as ** Positive g c as) (pot ** All (Satisfies pot) (map (arc g) inner))
```

This is Lemma 2, constructively: Bellman-Ford over the arcs `inner`, from
`start`, for `length inner` rounds, by structural recursion.
- The cycle comes in g's own indices, so no subgraph is renumbered: G3
  passes one component's arcs as `inner`.
- One more round that relaxes yields a positive cycle, recovered from the
  predecessors.
- Otherwise the distances satisfy every inner arc, because a longer walk
  holds a cycle of sum ≤ 0.
- `heaviest` returns `start` unchanged when `start` already satisfies
  every inner arc. T3's least-potential check relies on this.
- P1 exports the helpers: `IsFinite`, `finite`, `arc`, `weights`,
  `everyArc`, `everyFits : All (Satisfies pot) (map (arc g) (everyArc g))
  -> Feasible g pot`, and the sums and comparison lemmas. `everyArc`'s
  indices are built in one pass (`natToFinLT`), not by mapping `FS` at
  every level: *measured*, 0.13 ms against 328 ms at 14,000 arcs.

### 4.13 The phase (G4: `Frontend/Growth.idr`, `Frontend/Program.idr`)

```idris
export checkGrowth : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> (main : Name) -> Core Bool  -- True: admitted
```

`growth` is timed like the other phases. It runs after `reachable`, and
the program goes on to `translate` only if it is admitted:
1. `build main`.
2. `check`.
3. On `Bounded pot _`, write:
   - `TS.bounds` from `bound`;
   - `TS.sizes`: at each address, the per-parameter maximum over its nodes
     of `bound p`, as `heightAt`, with the graph's `arity`, its `heaviest`
     token and its `breadth` from `Built`. No size is computed.
4. On `Grows`, report each cycle and each opaque arc once under `noting`,
   as rule `Polymorphism`, then stop before translate (D5).

The messages are located at the cycle's user definition with the least
source position (file, then line), at the definition's `location`
(`bestFC` is private to Terms and falls back to the same; D4). A cycle with
no user definition on it is located where it is reached: follow
`Built.parents` from its first node to the first user definition, as
`checkReachable` names the user definition that reaches library code. The backquotes
below are this document's: a message prints names bare.
- a cycle: "`<f>` passes `<x>` as `<template>` to `<g>`, growing it by `<k>`
  each round[ through <path>], and nothing bounds how far it grows";
- data: "`<T>` holds `<T>` at `<template>` in `<constructor>`, growing
  `<x>` by `<k>` each level…";
- an opaque arc: "`<f>` passes `<x>` through the type-level recursion
  `<F>` to `<g>`, and nothing bounds what it computes".

## 5. Library first

| Responsibility | Owner | What disappears |
|---|---|---|
| Room descent | fork `Libraries.Data.List.Finite` (`NoDup`, `pigeonhole`), used in Frontend only: `tests/spec/frontend-imports` forbids a Proof module to import the fork | Dickson, AlmostFull |
| The worklist's descent | `Proof.Generations` (`Follows`, `generations`), unchanged | — |
| The listing | `Proof.Requests` (`writtenAt`, `argumentsAt`, `fibre`, `fibreComplete`) | — |
| Walking definitions | `Frontend.Walk` (`enter`, its measure) | a second measure |
| Normalisation over markers | `Closed.normaliseClosed`, `implementationOf`, `projected`, with G1's own marker names | a second evaluator |
| Static positions | `Instances.classify` | a second classification |
| Reporting refusals | `Profile`'s `noting`; `Errors.reject` | a second reporter |
| Components | none fits: Recursion's Tarjan is private, over names and in Core. G3 writes a pure one over `Fin n` | — |

## 6. Lanes (all start at dispatch)

| Lane | Exclusive writes | Contracts | Findings |
|---|---|---|---|
| P1 The graph's certificates | `Proof/Growth.idr` (new) | §4.1 | — |
| P2 Lemma 1 and Theorem 1 | `Proof/Bound.idr` (new) | §4.1, §4.12 | F09 |
| P3 Requests: cutover and universe | `Proof/Requests.idr`; deletes `Proof/AlmostFull.idr` | §4.1, §4.2 | F05 |
| P4 Lemma 2: heaviest paths | `Frontend/Growth/Potential.idr` (new; it uses the fork, so it is not under Proof/) | §4.1, §4.12 | F14 |
| G1 Templates | `Frontend/Growth/Template.idr` (new) | §4.1, §4.3 | F12 |
| G12 Implementations' fields | `Frontend/Growth/Implementations.idr` (new): `Fields`, `fieldsOf` | §4.3, §4.4 | — |
| G11 Sites | `Frontend/Growth/Sites.idr` (new); `Frontend/Translate/Cases.idr` (to export `siblings` and `coversAll`, for default expansion, only) | §4.3, §4.4 | F16 |
| G8 Heads and splitting | `Frontend/Growth/Heads.idr` (new) | §4.3–§4.5, §4.7 | F11 |
| G9 Data positions | `Frontend/Growth/Fields.idr` (new) | §4.3, §4.4, §4.8 | F13 |
| G10 Caps | `Frontend/Growth/Caps.idr` (new) | §4.3, §4.9 | F15 |
| G2 The graph | `Frontend/Growth/Graph.idr` (new) | §4.1, §4.3–§4.9 | — |
| G3 The check | `Frontend/Growth/Check.idr` (new) | §4.1, §4.10, §4.12 | F01 |
| G4 The phase and messages | `Frontend/Growth.idr` (new), `Frontend/Program.idr` | §4.5, §4.6, §4.10, §4.13 | F10 |
| G5 Nodes and B1 | `Frontend/Translate/State.idr`, `Frontend/Translate/Instances.idr`, `Frontend/Translate/Recursion.idr` (the rename and its stale sentence, :117-119), `Frontend/Translate/Keys.idr` (its stale comment, :5-7, only) | §4.3, §4.5 | F02 |
| G6 The worklist | `Frontend/Finite.idr` | §4.2, §4.3, §4.5, §4.11 | F04 |
| G7 Data registration | `Frontend/Translate/Types.idr` | §4.2, §4.3, §4.8, §4.11 | F03 |
| T1 Reject fixtures | `tests/reject/polymorphism-*` (the four), new `tests/reject/polymorphism-growth-{mutual,dictionary,recursion}` (a reject's name starts with its rule, `tests/lib/profile.sh:82-86`) | §4.13, D4 | F06 |
| T2 Accept fixtures | new `tests/accept/bounded-{grow-once,grow-shrink,method,field,capped,dictionary-root,method-own,synonym}` | §1, §4.7–§4.9 | F07 |
| T3 The exhaustive box | new `tests/compiler/growth-check` | §4.1, §4.10, §4.12 | F08 |
| coordinator | `compiler/idris-mlir.ipkg`, `tools/policies.txt`, `proposals/**`, `HANDOFF.md`, `bench/**`, `tests/ACCEPTANCE.md` (every new NEEDS-ACCEPTANCE mark), `Frontend/Profile.idr` (to export `answersForBody`, for G11, only), and the `covering` chain above `translateFrom`: `Frontend/Translate/Programs.idr`, `Frontend/Driver.idr` | all | — |

Nineteen lanes on disjoint files. Each consumes only the packet's
contracts, so all start together, and none waits for a sibling's file. The
coordinator's integration is the tail: the ipkg (the new modules in, the
two deleted modules out), the typecheck, and the gates of §7.

## 7. Acceptance (the conjunction)

`checker built ∧ old relation deleted ∧ translateFrom total ∧ every gate below`.

1. `make typecheck` (every part) and `make check` pass. `tools/policies.txt`
   loses Finite's `covering` and the chain it reaches.
2. On Chez, the integrated frontend is run against `1380a9d0`'s over every
   program in `tests/programs`, `tests/accept` and `tests/reject`.
   - Status, stdout, stderr and Core are identical, except the
     `polymorphism-*` refusals' new messages and lines.
   - Every T2 fixture is admitted, and the frontend writes its module.
     Compiling and running it are the owner's build.
   - Every T1 fixture is refused with its stated cycle.
   - `polymorphic-recursion-swapped`, `growing-specialization-function`,
     `higher-order-dictionary` and `type-level-shapes` are still admitted.
   - No program raises the growth check's internal error.
3. The self compile's frontend step runs **unpatched**, on a fresh copy of
   `compiler/src`, against the S1 prefix `/tmp/0014-S2b/s1/pfx` (D2).
   `tools/self.sh` needs `make build`, which is not run here:
   - no `polymorphism` refusal, and no internal error from the growth check;
   - every other refusal recorded for 0003's next stage;
   - the growth phase's time recorded in `bench/profiles/`.

   A polymorphism refusal there goes to the owner with its cycle, under the
   owner's rule: a real growing cycle is refactored later, and a precision
   loss is a defect in this packet.
4. T3's box is green on Chez.
5. The proof:
   - `Proof/` and `Frontend/Growth/{Check,Potential}.idr` typecheck with
     totality enforced;
   - P2's and P4's statements are exactly §4.12's;
   - searching for `assert_total`, `covering`, `believe_me` and `postulate`
     finds no use in `Proof/`, `Frontend/Growth*` or `Frontend/Finite.idr`;
   - Driver's documented chain to `translateFrom` is gone.

## 8. Decisions

- **D1 (owner).** Option C, with B1 as its edge rule; no stated trust point;
  hard cutover.
- **D2 (owner).** The backdoor is banned:
  - the coordinator deletes `/tmp/0014-S2b/emit`, `/tmp/0014-S21C/self` and
    the prototype's `S22_ADMIT` frontends once the prototype's numbers are
    recorded;
  - no gate uses a patched frontend;
  - the S1 prefix (`/tmp/0014-S2b/s1/pfx`) is a package prefix, not a
    backdoor, and stays until `tools/self.sh` replaces it.
- **D3 (coordinator, under D1; the owner accepted it, 2026-10-16).**
  - A stuck call of a non-recursive definition is unfolded (§4.3) and
    labelled through its leaves.
  - A structural Nat recursion is bounded (§4.3). Any other stuck
    type-level recursion on a static argument (ω) is refused wherever it
    lies, as a `StuckArc`.
  - Off a cycle, its target is finite but has no explicit bound, so
    admitting it would need either a trust point (D1 forbids one) or a
    proof that ties each request to the model, about the size of
    `classify`.
  - *Measured* (prototype Follow-up), the self compile has 8 ω arcs:
    - unfolding removes 5 (`isClockMandatory`, `.varNm`, `.range`,
      `ImpParameter'`);
    - P3's cutover deletes 2 (`Requested → Grows`);
    - the last is `allSplits`'s `length` stuck on a runtime list, in a
      dictionary. The key writes a dictionary as written, and so does §4.3:
      it weighs +3, finite.

    *Measured again* (prototype Follow-up 2: every data-constructor
    application, λ binder and `let` type over markers, 96,247 build sites
    on the self compile), with each target read as its key writes it:
    - 9 ω arcs at type targets before unfolding;
    - 0 remain after it, and on the accepted tests 0 as well;
    - `findIndex`'s `length` sits in `Fin`'s index, which the data key
      erases; `Vector1`'s synonym unfolds to +4 and +3.

    *Measured a third time* (prototype Follow-up 3, under the final
    reading: every signature and every type-constructor head as a site,
    and the structural Nat rule):
    - 0 ω arcs on the self compile once indices are read as keys write
      them, and 0 on the accepted tests and the rejects;
    - `type-level-shapes`' `second` weighs 0 from n;
    - the new sites add no positive cycle;
    - all 12,544 data arguments the self compile registers lie within the
      graph's bounds.

    So D3 refuses, in the tree and the tests, only
    `polymorphism-growth-recursion` (`Two (S (S k))`, two levels a step), a
    finite program that HEAD admits. That is the price of no trust point,
    and the owner confirms it.

    The alternative, normalising a stuck recursion from a bounded Nat-like
    source at each `S^k Z`, would bound none of the measured candidates:
    with indices weighed, the 3 that remain recurse on list values, with
    the marker only in the element type.
- **D4.** Refusals land on the definition: TT from a TTC has no call-site
  location (frontend.md §5). Each fixture's header names its definition's
  line, as T1 lays the fixture out.
- **D5.** A program refused for growth is not translated, since without a
  potential there are no bounds to translate within. The other phases'
  refusals in the same run are still reported. Translate's own refusals wait
  for a run without growth.
- **D6.** Nodes are split by the roots of their dictionary arguments (F11).
  *Measured* (prototype and its Follow-up, on the self compile):
  - the split read off concrete instances gives 0 refusals;
  - the static form of §4.7 gives 0 refusals, at 13,218 nodes, 67,146
    edges, 6,734 positions, 13,265 arcs, with the check in 23 ms in Python;
  - a projection's roots taken from the flow set first give 1 false
    refusal, StateT's `pure`.

  The tests' verdicts are the same under every variant: only the three
  growth rejects are refused.

## 9. Deferred and known limits

These programs are finite but still refused, because finiteness is
undecidable in general (`algorithm.md` §5):
- growth bounded only by a match on another position;
- a growing method nothing calls, since writing an implementation reaches
  every method;
- a type-level recursion stuck on a static argument (D3);
- `StateT s (StateT s' m)`, at a second level of context.

The tree holds none of these, except what §11 still counts. Self-hosting's
other work, the `SyntaxInfo` knot, and whatever this checker refuses wait
until it lands (0003).

## 10. Validation

`python3 proposals/0003-self-host/checker/validate.py`. The record is in §11.

## 11. Validation record

- **The prototype's follow-ups** (1 to 3) are recorded in D3 and D6.
  Their one limit: they read requests that instances made, so the method
  functions no instance ran have no outgoing edges in their data (14 to 42
  of them). The case-tree walk, the real C, may see more arcs there, and
  that is gate 3's to measure.
- **Adversarial review:** `review.md`. Every finding is resolved in §4 or
  in a lane body, except the two items it leaves open for the owner.
- **Assembly and validation** (`assemble.py`, then `validate.py`, at
  2026-10-16): 19 dispatches; 1 link, 16 findings, 987 write pairs and 19
  dispatches checked; 0 problems.

## 12. Integration record

Integration found what the lanes, typechecking against stubs, could not:
the composed checker on the corpus and on the self compile. Each change
below replaced the packet's form outright; nothing is kept beside it.

### Contract changes (§4 as built)

- **§4.3, the reading.**
  - `dictionaryRoot` is structural: the request and the sites call the same
    function, and none reads Idris's normaliser. A projection whose record
    is no constructor has no root; the template's field decides.
  - A projection reads as the choice of its written application and its
    field.
  - Eta is read throughout: `contracted` contracts a lambda that only
    passes its variables on, at every depth, so `\x => a x` reads as `a`.
  - `Static` gains `AFamily`, an erased type parameter whose kind is a
    function into a universe, decided by `keyingOf`. `Template.typeRoot` is
    a family's one root function: the type constructor heading its
    eta-contracted normal form.
  - `Root.Implementation` is `Rooted`.
  - `Applied i d args` is a family applied, which every instance
    beta-reduces; `Formal` is an argument of a family's value. A family
    value reads as its meaning: a lambda's variables are formals, and a
    definition given fewer arguments than it takes is unfolded over them.
- **§4.4, sites.** `sitesOf a heads` reads a definition at a node; a
  family argument's root is its type root. `Argument.shown` is a
  `Core String`, rendered only where a refusal prints. Profile has
  `answersForCalls` (a body never translated) beside `answersForBody`.
- **§4.5, nodes.** `Node.heads` holds family heads as well as dictionary
  roots: a family parameter splits a node by the type constructor its value
  has there. A node's positions are decided at its heads by the request's
  own `staticsOver`/`keyingOf`, so a request's keyed positions are its
  node's (C3 by construction).
- **§4.6, the graph.** The field rule carries a field's value by its
  record's own variables, as deep as the field holds them (`fieldsIn` is
  gone). Leading arcs are drawn once per method node. Per-node readings
  are computed from the flow, and the walk checks that every node it meets
  has one. An applied family is read k heads above its arguments only
  where closed templates no higher than k land at the family (the landings
  rule).
- **§4.7, heads.** The flow gains `Passes`; `reaching` gives the flow's
  set at a parameter.
- **§4.8.** `represented` is cached in `TyConFacts`.
- **§4.10, the check.** Its tables are trees over a position's bits,
  `Places n d` with an erased `LTE n (power 2 d)`, read in about log n
  steps; Tarjan's measure is their count of unseen leaves.
- **§4.12, the proofs.** `Proof.Bound` models beta: `Meaning`, `Lands`,
  `Reduces`, with `betaHeight`, `reducesBelow` and `landed`, so Theorem 1
  covers applied families.
- **§4.13.** A new message: "`<f>` passes `<x>` through its type family
  `<m>` to `<g>`, and nothing bounds what it computes".
- **Option (a).** `Translate/Closed.unfolded` projects structurally first:
  a method resolves to the implementation's method function, not to the
  normal form Idris's normaliser inlines. See below.

### Option (a): methods resolve to the implementation's method function

The packet's "each kind is read as its key writes it" met keys that held
Idris's normal form of a dictionary: `Translate/Closed.unfolded` asked the
normaliser for a projection's record, so a key held `MkShow Int (\x0 =>
primNumShow …)`, and the code translated from it held method bodies the
normaliser had inlined. Reading those forms for growth cost what the
normaliser's output costs: on the self compile, `Ord (Node, Nat)` reaches
`Vect 8 (Fin 256)`'s successor chains, 8 to 14 GB in under two minutes,
whole or one normal form per definition. A projection now takes the field
from the constructor its record reduces to, its arguments as written, so an
implementation in it stays the implementation it names, and a method is a
call of the implementation's method function. Inlining is MLIR's.

On the 381 fixtures (*measured*): status, stdout and stderr are identical
to HEAD's; 306 are identical in every respect; 75 differ in Core and module
only. Over those 75, 442 instances call a method function where HEAD
inlined its body, 345 method-function instances are added, and 15 HEAD
instances merge (a second instance of one function at one implementation,
keyed once by its name and once by its normal form). Module bytes 7,907,895
→ 7,885,057 (−0.29%); Core functions 11,676 → 12,006 (+2.8%); show-heavy
programs shrink (prelude-show −20%), IO-heavy ones grow (prelude-lists
+5.7%). Running them is the owner's build.

### Known limits found at integration

Finite but refused, each conservative and none met by the tree, the
fixtures or the self compile:
- a type family whose value computes, wherever it is applied to static
  arguments: a match on the family's argument (even a non-recursive one),
  a Nat recursion on it, or a dependent pair's predicate whose body
  computes;
- a family value that applies one of its family arguments to what holds
  another (`\g, x => g (List x)`): beta sums two arguments' heights, which
  no weight states (`tests/reject/polymorphism-growth-family-sum`);
- a lambda family forwarded through another definition, when what lands
  there is open.

The link between Template's reading of a family value and `Proof.Bound`'s
`Meaning` is by construction, as the rest of `Describes` is (§4.12): the
proof cannot state Idris's TT. A request outside its bound stays the
check's internal error (C3), so a gap there stops the compile; it never
miscompiles. A node at heads the flow did not give is that error too
(none is known).

### Gates (arm64 macOS, the typecheck machine; no LLVM built)

- **Gate 2** (§7.2): the integrated frontend against HEAD's on Chez over
  every program of `tests/programs`, `tests/accept` and `tests/reject`.
  Status, stdout and stderr are identical on all 381 that HEAD has; 306 are
  identical in every respect; 75 differ in Core and module only, by option
  (a). Every T1 fixture is refused once, at the line and with the cycle its
  header states; every T2 fixture, `erased-elem-match` and the five
  `bounded-family-*` are admitted and write their module; the two
  `polymorphism-growth-family-*` are refused as their headers say;
  `polymorphic-recursion-swapped`, `growing-specialization-function`,
  `higher-order-dictionary` and `type-level-shapes` are still admitted. No
  program raises the growth check's internal error.
- **Gate 3** (§7.3): the self compile's frontend step, unpatched, on a
  fresh copy of `compiler/src`, against a prefix whose fork package the
  integrated frontend built (the S1 prefix predates the fork's TTC version):
  exit 0, no refusal, no internal error. Times and sizes:
  `bench/profiles/2026-10-17-self-growth.md`.
- **Gate 4:** T3's box, from the tree: every verdict as `expected-stdout`
  says.
- **Gate 5:** `Proof/`, `Frontend/Growth*` and `Frontend/Finite.idr` hold
  no `assert_total`, `covering`, `believe_me` or `postulate`, and each is
  `%default total`; Driver's `perform`, `frontend` and `main` are total, the
  error printer being one more field of the fork's `Idris.Host.host`.
- `make check`: 35 of 35.

### What integration fixed beyond the contracts

- **The fork** (41612045, 73d6dcf3): Idris bugs 50 to 54, as the fork's own
  code. 51 made the frontend's reach into Idris's error printer visible,
  which `host.emitError` now states.
- **Soundness:** a family value given as a definition under-applied, or a
  lambda stuck on its variable, read below its meaning, so four programs
  raised the internal error; `Proof.Bound`'s beta model found them.
- **Precision:** eta-expanded markers, and the per-definition kinds that
  refused the fork's `Core.Env.getBinderUnder` three times (its scope `ns`
  sits only in `Term`'s erased index), each a packet defect by §7.
- **Time:** the growth phase on the self compile went from 1,093 s to
  about 67 s: `concat` folding `++` from the left (three quadratic joins),
  arcs looked up by index, and Vect tables in the check (now `Places n d`).
  Each static argument of a request is read once into `TS.readings`, and a
  request carries its heights, so the worklist reads instead of
  recomputing.
- **Spec:** `tests/spec/no-erased-inputs` used `\|` in a basic `sed`
  expression, which BSD sed lacks, so on macOS it never saw the frontend's
  own data types; AlmostFull's `Lifted` hid that. It is `sed -E` now.

### The hard cleanup (2026-10-17)

After integration, at the owner's word ("hard cutovers and hard cleanup after
a night of churn"), six agents cleaned the frontend's checker files and the
fork's five fixes, each in its own files, with outputs identical: the Core
and module of every fixture and the self compile's verdict. What went:
duplicate readings (one reading per kind in Template; caps decided once in
Graph; constructors read once in Types), unread payloads, lists matched by
position (the check's cycle walks are one list of proved edges), Bool tests
that returned no evidence (comparisons in Proof.Requests return proofs),
and the erased-Elem fix's predecessor: `Cases.equated`, `bindEquated`,
`forcedEnv` and Forced's `Known`/`View`, which computed a weaker copy of
what the clause's left-hand side already holds (about 650 lines, behind a
guard fixture, `tests/accept/erased-elem-later-match`). `Proof.Requests`'
`lowBits` takes one step per bit (`lowBits 11` over a million values: 9.5 s
to 0.22 s). The four `Proof.Bound` theorems the frontend's family readings
rest on stay, exported, though no code calls them: the proof is the
guarantee.

The cleanup's one regression, found by gate 3 and by no fixture: Forced
read every left-hand-side term that was not a variable, an erased term or
an as-pattern as a test, so a runtime implicit the unifier computed (the
fork's `Partitions`, whose `ps` holds `cs ++ ps'`, which Idris's tree never
matches) left its clause covering nothing, and the erased indices that
clause unified with constructor fields reached run time as `[__]`. Forced
now reads each place of a clause once, as Idris's case builder does: only
a constructor, an arrow, a constant or a suspension tests; a computed
literal (`fromInteger 3`) is a test not taken apart. The deleted `equated`
was a second copy of what the clause holds. Guard:
`tests/accept/erased-index-forced-index`, the clause and its with-block
form.
