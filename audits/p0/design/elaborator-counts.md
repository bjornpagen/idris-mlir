<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the elaborator's two search counts

Written 2026-10-21 at e96bb991 for D45 (DP-20;
`proposals/0000-mlir-native.md:756-772`): "The fork's elaborator refuses
no program because a count ran out." It reads the fork (`compiler/idris`)
and the pinned Idris (`third_party/Idris2` at 1c630e67), and measures the
stock pinned Idris (`.toolchain/idris2/bin/idris2`, "Idris 2, version
0.8.0-1c630e67c") with `idris2 --check` on small files in a scratch
directory, arm64 macOS, one run each, wall time from `/usr/bin/time -p`.
Nothing of the project was built and no code was changed.

Grounds: *read* (a path:line I read; fork paths are under
`compiler/idris/` unless said), *measured* (a command I ran, with its
input), *recalled* (from memory, not re-read), *conjecture*.

## 0. In plain words

- **Overloaded names (`%ambiguity_depth`, 3).** The count never made
  anything end. Resolving a name with several candidates elaborates each
  candidate's arguments, and those are smaller pieces of the source, so
  the work always ends (read, §1.2). The count only refuses: the stock
  Idris refuses `printLn (1, 2, 3, 4, 5, 6)`, because tuple syntax is
  ambiguous between the pair type and the pair value and the tuple nests
  five deep (measured, §1.4). The replacement is to delete the count and
  put nothing in its place. "A search bounded by what it has already
  tried", as D45 proposed, is not the mechanism: it is not needed for the
  work to end, and it would not make it cheaper, because the number of
  attempts is already polynomial (measured) while the time per attempt
  grows. The price is time on nested overloads whose types are unknown:
  a 22-element tuple under `printLn` takes 433 s (measured, §1.5).
- **Automatic search (`%auto_implicit_depth`, 50).** Here the count is
  the only thing that ends a search that grows, but it bounds each path,
  not the work: two growing hints keep the stock Idris busy past 60 s
  (measured), while a 60-element `Elem` proof is refused (measured).
  **D45's size rule cannot be adopted as recorded.** Upstream's own
  prelude and base contain implementations that any Paterson-style size
  rule refuses (`Prelude/Types.idr:301`, about forty in base, read and
  measured, §2.5), and every program imports the prelude. Data
  constructors and interface parents are hints in the same search too,
  so a rule on implementations alone does not end it: two growing
  constructors keep the stock search running past 60 s with no
  implementation at all (measured).
- **What ends by construction instead:** a rule on the search path. A
  goal that contains an earlier goal on its own path (homeomorphic
  embedding) means the search grows. Kruskal's tree theorem says every
  infinite path has such a pair, so stopping there ends every search with
  no count. Stopping refuses the program (it does not quietly drop a
  branch), and when unknowns are involved the search is retried later,
  as upstream does with an ambiguous search. A program the fork accepts
  then elaborates exactly as the stock Idris does with the depth raised
  far enough (§2.6).
- **The owner decides, one at a time (§7):** (1) the path rule in place
  of D45's size rule, which reverses a recorded design; (2) what a growth
  involving unknowns does; (3) accepting the time cost of nested
  overloads.

## 1. Overloaded names: `%ambiguity_depth`

### 1.1 What the count bounds (read)

`checkAmbigDepth` (`src/TTImp/Elab/Ambiguity.idr:326-334`) throws
`AmbiguityTooDeep` when `length (ambigTries info) > getAmbigLimit`.
`ambigTries` is a field of `ElabInfo` (`src/TTImp/Elab/Check.idr:484`,
`[]` at `initElabInfo`, :488). It grows only in `addAmbig`
(`Ambiguity.idr:343-348`), which pushes the candidate's name when more
than one candidate survived pruning, at each candidate's elaboration
(`Ambiguity.idr:386, 390, 395, 429`). It is checked at the start of both
clauses of `checkAlternative` (`Ambiguity.idr:455, 468`), before
`delayOnFailure` (`:464, :482`). So it bounds the nesting of resolutions:
how many candidates of enclosing overloaded names are being tried around
the one about to be resolved. The default 3 lets four nest and refuses
the fifth (`Core/Options.idr` `defaultElab`, read via the
`fork-totality-depth` diff's hunk: `MkElabDirectives True True
CoveringOnly 3 50 25 True`).

Every application of an overloaded name becomes an `IAlternative`
(`Ambiguity.idr:67-72`), as do tuple syntax (`(a, b)` is `UniqueDefault
(MkPair a b)` over `[Pair a b, MkPair a b]`, `src/Idris/Desugar.idr:529-534`),
dependent pairs (`:535-547`), `()` (`:557-560`), `===`
(`FirstSuccess` over `===` and `~=~`, `:404-408`) and macro argument splits
(`Ambiguity.idr:140-156`). `pruneByType` keeps only candidates whose
return type can match the expected type (`Ambiguity.idr:305-324`); with
an unknown expected type every candidate stays (`:279`).

### 1.2 Why the resolution ends without the count (read)

A candidate is the whole application with its head replaced by one
resolved name (`mkAlt`, `Ambiguity.idr:158-160`, `buildAlt`, `:109-117`).
Checking it resolves the head to exactly one definition
(`lookupCtxtName` of a `Resolved` name, `:59-66`) and then elaborates its
arguments, which are strict subterms of the source term. So the chain of
nested resolutions follows a strictly descending chain of subterms of a
finite term. The two other ways back into resolution do not deepen it:

- A delayed resolution (`delayOnFailure`, `src/TTImp/Elab/Delayed.idr:80-117`)
  is retried with the `ElabInfo` it captured, on the same term.
  `retryDelayed` (`Delayed.idr:262-328`) loops only while a round resolves
  a delayed hole, each resolution is permanent (`updateDef ... PMDef`,
  :289-291), and the delays a retry creates are for its own subterms
  (:286-287). So the rounds are bounded by the sites of the term.
- A macro (`IRunElab`, `Ambiguity.idr:142-145`) runs a user's elaborator
  script, whose termination is that script's, as is the evaluation of a
  partial function in a type: neither count touches them.

So the count bounds nothing that would otherwise not end. Measured: with
`%ambiguity_depth 1000`, every program in §1.4 and §1.5 finished.

### 1.3 What the count changes (read)

A candidate that throws `AmbiguityTooDeep` is an ordinary failed
candidate: `successful` catches every error but `abandon`'s
(`Check.idr:541-612`; `abandon` lists `UndefinedName` and its wrappers,
`:605-612`). `exactlyOne'` then takes the one candidate left
(`Check.idr:615-668`), and prefers the depth error only when every
candidate failed (`depthError`, `:650-668`). `ambiguous` counts
`AmbiguityTooDeep` as a reason to delay (`Delayed.idr:161`), so a depth
error usually delays the enclosing site rather than failing it (measured
below: `Over.idr`). Three consequences:

1. **Refusal.** A program whose undetermined overloads nest past four is
   refused with "Maximum ambiguity depth exceeded" (measured, §1.4).
2. **Disambiguation.** At the site just above the limit, a candidate
   whose arguments nest further fails, and a candidate whose expected
   argument type prunes the inner site to one candidate (so it adds
   nothing to `ambigTries`) can win alone. Without the count both may
   succeed, the site is ambiguous and delayed, and either a later retry
   resolves it or the program is refused.
3. **Meaning.** A delayed site retried later, with more known, could in
   principle resolve to a different candidate than the one the count let
   win early. I constructed no such program; whether one exists is
   conjecture. What is exact (read): the count is read only in
   `checkAmbigDepth`, so the fork with the check deleted elaborates every
   program as the stock Idris does with `%ambiguity_depth` at least the
   program's deepest nesting. That is the totality precedent's statement
   ("accepted after `%totality_depth 7`", `PINS.md:1067-1089`).

User programs cannot write the pragma today: the frontend's profile
rejects every pragma in a user module but `default`, `hide`, `unhide` and
`logging` (`compiler/src/IdrisMLIR/Frontend/Profile.idr:136-176`, read),
so for them the default decides (`audits/p0/17-fork-boundary.md` FB-40).

### 1.4 Programs the count refuses (measured)

Stock Idris, default depth unless stated:

| program | result | wall |
|---|---|---|
| `printLn (1, 2, 3, 4)` | accepted | 0.51 s |
| `printLn (1, 2, 3, 4, 5)` | accepted | 0.75 s |
| `printLn (1, 2, 3, 4, 5, 6)` | refused: "Maximum ambiguity depth exceeded ... MkPair --> MkPair --> MkPair --> MkPair" | 0.41 s |
| `printLn` of an 8-tuple | refused, same | 0.47 s |
| `let t = (1, ..., 8) in printLn t` | refused, same | 0.49 s |
| `t : (Nat, ..., Nat)` (8), `t = (1, ..., 8)` | accepted (the expected type prunes) | 0.34 s |
| `%ambiguity_depth 100`, `printLn` of an 8-tuple | accepted | 0.74 s |
| `x (x (x (x (x val))))`, `A.x : Bool -> Bool`, `B.x : Nat -> Bool` | refused at 5 and 8 nested; accepted at 3, 4 | 0.33 s |
| the same, `%ambiguity_depth 20`, 8 and 12 nested | accepted | 0.34-0.35 s |
| the same, `%ambiguity_depth 1000`, 16, 24, 32, 48 nested | accepted | 0.33-0.37 s |
| `printLn (f (g (g (g (g (g 0))))))`, `A.f : a -> a`, `B.f : Nat -> Nat`, `X.g : Nat -> Nat`, `Y.g : String -> String` (`Over.idr`) | refused as ambiguous, at the default and at 10: `A.f ?delayed` beside `B.f (X.g ...)` | — |

The tuple is the ordinary case: a tuple of six or more components whose
type is not known from outside (an argument of `printLn`, `show`, or a
`let`) is refused by the stock Idris. Upstream's own test of the pragma
(`third_party/Idris2/tests/idris2/error/error021/DeepAmbig.idr`, read)
sets `%ambiguity_depth 1000` and expects an undefined-name error found
through `abandon`; it nests `x $ x $ ...`, where each `x` is an argument of
`$`, so `ambigTries` never grows there (read: `x`'s candidates are leaves).

### 1.5 The cost without the count (measured)

`printLn` of an n-tuple of literals, `%ambiguity_depth 1000`:

| n | 10 | 12 | 14 | 16 | 18 | 20 | 22 |
|---|---|---|---|---|---|---|---|
| wall | 1.23 s | 2.12 s | 4.17 s | 9.79 s | 23.66 s | 97.35 s | 433.49 s |

Counting attempts from the elaborator's own logs (`--log
elab.ambiguous:5 --log elab.delay:5 --log auto:3`, build directory
cleared):

| n | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 14 | 16 |
|---|---|---|---|---|---|---|---|---|---|
| resolutions ("Ambiguous elaboration") | 9 | 21 | 41 | 71 | 169 | 331 | — | 911 | 1361 |
| delayed ("Postponing elaborator") | 4 | 9 | 16 | 25 | 49 | 81 | — | 169 | 225 |
| searches ("Initial target") | — | 315 | — | 1033 | 2615 | 5589 | 10611 | 18465 | 30063 |

Resolutions grow cubically (third differences constant), delays are
exactly (n-1)², searches grow about as n^3.2 to n^3.7. The wall grows
faster than any of them, by a factor that itself grows (about ×1.7 per two
components at 10→12, ×4.5 at 20→22). So the time is in the work of each
attempt, not in the number of attempts; where inside an attempt is not
measured (conjecture: normalising and unifying the growing tuple type with
its unknowns, which each retry and each of the two `solveConstraints` per
candidate, `Ambiguity.idr:435-436`, repeats).

### 1.6 Is "bounded by what it has already tried" the mechanism? No

The totality fix names each comparison by a pair of paths and memoises it,
because a comparison is a pure function of the two subterms
(`upstream/fork-totality-depth/README.md`, read). A resolution is not: a
candidate's elaboration reads and writes five pieces of state, which
`successful` saves and restores around each candidate (`UST`, `DLY`,
`EST`, `MD`, `Ctxt`; `Check.idr:552-590`, read), and its outcome depends
on the expected type and on every metavariable solved so far. A memo
keyed by (site, candidate, expected type) is sound only where the expected
type and the environment hold no unknowns and the elaboration creates no
delays, and that is exactly where `pruneByType` already narrows the
candidates. And in the measured case the attempts are polynomial already
(§1.5). So no memo of tried candidates bounds the cost polynomially, and
none is needed for the resolution to end (§1.2).

Overload resolution combined with type inference is hard in general
(recalled, not re-read: ML typability with overloading is known to be
NP-hard or worse; Swift's type checker bounds its solver and reports
"expression too complex"). So no rule on the program short of the count
itself bounds the cost polynomially: the smallest such rule I can state,
"an overloaded name whose candidates the expected type does not narrow to
one may not occur inside the arguments of another such name", refuses
`printLn (1, 2, 3)`, far more than the count.

### 1.7 The replacement

Delete the count. Nothing replaces it. Concretely (read): the
`AmbiguityTooDeep` error and its cases (`Core/Core.idr:128, 320, 477,
570`; `Core/Context.idr:769, 868`; `Idris/Error.idr:78, 456-461`),
`checkAmbigDepth` and its two calls, `ambigTries` and `addAmbig`,
`depthError` and `getDepthError` in `exactlyOne'` (`altError ls []`
becomes `AllFailed ls`), the `ambiguous` case (`Delayed.idr:161`),
`ambigLimit` (`Core/Options.idr:105` and `defaultElab`), `setAmbigLimit`
and `getAmbigLimit` (`Core/Context.idr:2246-2248, 2292-2296`), the
`AmbigDepth` directive (`Idris/Syntax.idr:434`), `AmbigDepthPragma`
(`TTImp/TTImp.idr:517`), their desugaring (`Idris/Desugar.idr:1386,
1464`), the parser's alternative (`Idris/Parser.idr:1495-1498`) and
`KwAmbiguityDepth` (`Idris/Syntax/Pragmas.idr:17, 84, 110, 136`).

What changes, against the stock Idris at the default:

- **Accepted now, refused before:** `printLn (1, 2, 3, 4, 5, 6)`,
  `x (x (x (x (x val))))` above, every nesting the count alone refused,
  with the elaboration the stock Idris gives at a large enough depth.
- **Refused now, accepted before:** a site the count disambiguated
  (§1.3, 2) whose later retry stays ambiguous. I have no example; the
  shape is a candidate whose arguments nest undetermined overloads beside
  a candidate whose expected type prunes them, both type-correct.
- **Slower:** nested undetermined overloads, as measured (§1.5).
  Who pays: a program with a long tuple under a polymorphic consumer
  compiles, slowly, where it was refused at once.

Representation note, for a later change and not part of D45: the tuple's
ambiguity is an artefact of one syntax for two things (the pair type and
the pair value). A resolution that settles `(a, b)` by the sort of its
expected type when known, and by its components when not, would compute
upstream's answer without trying both at every level (conjecture; not
designed here).

## 2. Automatic search: `%auto_implicit_depth` and the other depths

### 2.1 What the count bounds (read)

`makeAutoImplicit` passes `getAutoImplicitLimit` to `searchVar`
(`src/TTImp/Elab/App.idr:272-274`), which stores it in a `BySearch rig
depth def` hole (`Core/UnifyState.idr:497-502`; `Check.idr:419-431`).
`retryGuess` runs `search` with it (`Core/Unify.idr:1439-1442`), and the
depth reaches `searchIfHole`, which decrements it once for each argument
of a candidate it searches and, at zero, fails the goal: `throw
(CantSolveGoal ...) -- possibly should say depth limit hit?`
(`Core/AutoSearch.idr:103-105`). So it bounds the length of every path of
the search tree: goal, hint, premise goal, hint, and so on. It does not
bound the tree: each node tries every local (`searchLocalVars`,
`AutoSearch.idr:360-364`) and every hint of every group (`tryGroups`,
`:553-566`).

The same search is entered with four other depths, all counts (read):
`%search` written in a term, 50 (`Idris/Parser.idr:146-147`); the auto
implicit of a `with` clause, 500 (`TTImp/WithClause.idr:156`); an
implementation's parent constraints, 500
(`Idris/Elab/Implementation.idr:260`); the raw TTImp parser's `%search`,
1000 (`TTImp/Parser.idr:61`). The depth is part of `ISearch`
(`TTImp/TTImp.idr:97`), `PSearch` (`Idris/Syntax.idr:114`), `BySearch`
(serialised, `Core/TTC.idr:1192, 1226`) and the reconstruction in
`TTImp/Unelab.idr:230`. Base's reflection API carries it too
(`ISearch : FC -> (depth : Nat) -> TTImp`,
`third_party/Idris2/libs/base/Language/Reflection/TTImp.idr:66`).

The hints a goal `T ū` tries (`getSearchData`, `Core/Context.idr:1725-1752`,
read), in order, each group tried only if the one before failed:
`%globalhint`s marked open, `%globalhint`s, the direct hints of `T`, and
the indirect ("chaser") hints of `T`. Direct hints of `T` are:

- every implementation of interface `T` that is not named
  (`Hint True`, `Implementation.idr:176-178`);
- every `%hint` function returning `T` (`TTImp/ProcessFnOpt.idr:50-56`);
- **every constructor of data type `T`**, unless `T` is declared `noHints`
  (`TTImp/ProcessData.idr:561-562`); an interface's record type is
  `noHints` (`Idris/Elab/Interface.idr:113`).

Indirect hints are the parent projections: for `interface P a => C a`,
the function `C a -> P a` (`Hint False`, `Interface.idr:222-253`). A group
of `T`'s direct hints keeps the first success (`anyOne`) unless `T` is
`UniqueSearch` (interfaces are, `Interface.idr:113`), in which case it
requires exactly one (`Context.idr:1750`); chasers keep the first success
(`:1751`).

Determining arguments: a data type's are all its arguments
(`Core/Context/Data.idr:93, 103-106`), narrowed by `| x` on an interface
or `search x` on a data type (`Context.idr:1788-1797`). They must be
free of unknowns only at the top goal (`checkConcreteDets`, called with
`checkdets = True` only from `search`, `AutoSearch.idr:539-541, 576-581`;
premises are searched with `False`, `:118`). Measured: `show (Just [])`
searches `Show (Maybe (List ?a))` seven times, and each attempt stops at
the determining check ("Determining arguments for Prelude.Show.Show [0]")
and is postponed (`Meta.idr`, `--log auto:10`).

The only cycle check compares a goal, by conversion, with the goals on
its path (`abandonIfCycle`, `AutoSearch.idr:508-517`); the path (`trying`)
is reset under a Π goal (`:520-527`), and a local used as a function is
cleared from the environment of its own premises (`:304-306`).

### 2.2 Why the search may not end without it (read, measured)

A hint whose premise is larger than its conclusion makes goals grow
without repeating, and the conversion check never fires:

- `%hint viaList : Foo (List a) -> Foo a` and the goal `Foo Nat`: `Foo
  (List Nat)`, `Foo (List (List Nat))`, ... Measured (`Loop1.idr`): the
  stock Idris refuses ("Can't find an implementation for Foo Nat") in
  0.38 s, after 50 levels.
- Adding `%hint viaMaybe : Foo (Maybe a) -> Foo a` doubles the tree at
  every level, 2^50 paths: measured (`Loop.idr`), still running at the
  60 s timeout. The count bounds each path, not the work.
- With no implementation and no `%hint`, `data G : Nat -> Type where
  Up1 : G (S n) -> G n; Up2 : G (S (S n)) -> G n` and `x : G 0; x =
  %search`: measured (`Cons2.idr`), still running at the 60 s timeout;
  with `Up1` alone (`Cons1.idr`) refused in 0.38 s.
- Unknowns make goals repeat without converting: `Elem 3 ?xs` tries
  `There : Elem x xs -> Elem x (y :: xs)` and asks `Elem 3 ?xs2`, a fresh
  unknown each time (conjecture from the code; `Elem` has no determining
  restriction, so the top check passes only once `?xs` is known, but a
  premise's unknowns are never checked, `:118`).

### 2.3 What the count changes (read, measured)

Running out of depth is `CantSolveGoal`, an ordinary failure
(`AutoSearch.idr:103-104`), caught by every combinator: `successful`
(`:130-153`), `anyOne` (`tryUnify`, `:155-168`), `tryGroups`
(`tryUnifyUnambig'`, which re-throws only `AmbiguousSearch`, `:20-28,
553-566`). So a branch that would succeed deeper fails, and the search
picks a sibling: in an `anyOne` group, the next hint; in an `exactlyOne`
group, the remaining success instead of an ambiguity. `retryGuess` treats
the failure as recoverable and postpones the search
(`Unify.idr:1456-1466`).

Measured: `Elem 60 xs` for `xs = [0, ..., 60]` is refused by `%search`
(1.74 s) and by an auto implicit (2.10 s), and accepted with
`%auto_implicit_depth 100` (0.78 s). `%search` cannot be raised at all:
its 50 is fixed by the parser. User modules cannot write `%search` or
`%hint` in any case (the profile, `Profile.idr:141, 176`).

### 2.4 D45's size rule, stated exactly

D45: "an implementation whose requirements are not smaller than what it
implements is refused (a size rule in the manner of Haskell's Paterson
conditions)". Over Idris's terms (GHC's conditions recalled: no variable
has more occurrences in a constraint than in the head; a constraint has
fewer constructors and variables than the head; no type family in a
constraint):

A hint `h` has, normalised at its declaration, the type
`Π (x₁ : A₁) … (xₙ : Aₙ). T u₁ … u_k` with `T` a type constructor whose
determining positions are `D`. Its **head** `H` is `(u_j)_{j ∈ D}`; its
**head variables** `V` are the `xᵢ` occurring in `H`. Its **premises** are
the `Aᵢ` whose `xᵢ` occurs in no `u_j`: those are the arguments
`searchIfHole` searches rather than unification solving. For a premise
`P = T' w₁ … w_m` with determining positions `D'`, write `P_D` for
`(w_j)_{j ∈ D'}`. `‖t‖` counts the nodes of `t`: each name (type or data
constructor, function, local), variable occurrence, primitive constant,
`Type`, binder. The rule, for every premise `P`:

- **S1 (variables).** Every variable in `P_D` is in `V`, and occurs in
  `P_D` no more often than in `H`. A variable of `P` outside `V` occurs
  only once, only at a non-determining position of `T'`.
- **S2 (size).** `‖P_D‖ < ‖H‖`.
- **S3 (no reduction).** `P_D` names no definition that reduces, and
  applies no head variable (`f a` with `f ∈ V`).
- **S4 (coverage).** Every variable at a non-determining position of the
  head is in `V`.
- **S5 (first order).** `P` is a type-constructor application or a
  variable, not a Π.

Why the search would then end: the top goal's determining arguments are
free of unknowns (§2.1). Unifying such a goal with `H` binds every
`v ∈ V` to a subterm free of unknowns, and by S4 nothing else of the head
is left unknown, so every premise's `P_D θ` is free of unknowns too
(induction down the path). By S1 and S3, substitution adds
`occ(v)·(‖θv‖ − 1)` per variable on each side, so
`‖P_D θ‖ ≤ ‖Hθ‖ − (‖H‖ − ‖P_D‖) < ‖Hθ‖`: the determining size falls
strictly at every hint. A local used as a function is cleared for its
own premises (`:304-306`), and S5 keeps Π goals (which add locals) to the
top goal, so the pair (usable locals, determining size) falls
lexicographically at every step. Each node has finitely many children, so
by König's lemma the tree is finite. No memo is needed and no cycle check
for termination.

### 2.5 Why it cannot be adopted as recorded

**(a) Implementations are not the only hints.** A rule on implementations
leaves data constructors, `%hint`s and parent projections free, and
`Cons2.idr` runs past 60 s with nothing but constructors (§2.2). Applied
to every hint, the rule refuses declarations of the prelude itself:

- `No : (contra : Not prop) -> Dec prop`
  (`third_party/Idris2/libs/prelude/Prelude/Types.idr:274`): the premise
  is a Π (S5) and larger (S2);
- `S : Nat -> Nat` and `(::) : a -> List a -> List a`: equal size (S2);
- every record or constructor with a field larger than its type
  (`MkConfig : List String -> Config`), and every recursion through a
  container (`MkRose : a -> List (Rose a) -> Rose a`);
- parent projections such as `MonadState s m -> Monad m` (equal size)
  and, for `interface (Monoid w, Monad m) => MonadWriter w m | m`
  (`third_party/Idris2/libs/base/Control/Monad/Writer/Interface.idr:24`),
  `MonadWriter w m -> Monoid w`, whose premise's determining argument `m`
  is not in the head (S1). That projection is how `Monoid w` is found
  from a `MonadWriter w m` in scope.

**(b) Upstream's prelude and base break it.** A crude scan of one-line,
unnamed implementation heads (measured: token counts, so a lower bound;
script in the scratch directory, not kept):

| tree | smaller | equal | larger | named (not hints) |
|---|---|---|---|---|
| `libs/prelude` (stock) | 17 | 2 | 1 | 15 |
| `libs/base` (stock) | 156 | 37 | 8 | 13 |
| `compiler/idris/src` (the fork) | 91 | 0 | 0 | 1 |
| `compiler/src` (the frontend) | 7 | 0 | 0 | 0 |
| `libs/` (ours) | 0 | 0 | 0 | 0 |
| `tests/` | 8 | 0 | 0 | 2 |

Read, among them:

- `Either (Uninhabited a) (Uninhabited b) => Uninhabited (a, b)`
  (`Prelude/Types.idr:301`): larger. In the prelude, which every program
  imports, so the non-strict rule refuses every program.
- `HasLinearIO io => HasIO io` (`Prelude/IO.idr:48`) and `(Integral a,
  Ord a, Neg a) => Range a` (`Prelude/Types.idr:1122`): equal, so the
  strict rule (S2, D45's "not smaller") refuses them too.
- `All (Show . p) xs => Show (All p xs)` and its siblings for `Eq`, `Ord`,
  `Semigroup`, `Monoid`, `DecEq`, `Uninhabited`, over `List`, `Vect`,
  `List1`, `SnocList` (`base/Data/List/Quantifiers.idr:40-200` and the
  three like it): equal by tokens; normalised, `Show . p` is a lambda
  applying `p` (conjecture on the exact normal form), against S3.
- `All Show (map p xs) => Show (All p xs)`
  (`base/Data/SnocList/Quantifiers.idr:169`): a function in the premise.
- `HasErr AppHasIO e => PrimIO e` (`base/Control/App.idr:362`), `Has
  [PrimIO, Exception IOError] e => FileIO e`
  (`base/Control/App/FileIO.idr:55`): larger.
- `Reflexive ty rel => Serial ty rel` and `(Transitive ty rel, Symmetric
  ty rel, Serial ty rel) => Reflexive ty rel`
  (`base/Control/Relation.idr:80, 85`): equal, and a cycle the
  conversion check cuts.
- `Eq (m (Maybe a)) => Eq (MaybeT m a)` and the like
  (`base/Control/Monad/Maybe.idr:108-116`,
  `base/Control/Monad/Error/Either.idr:95-103`): equal, and a head
  variable applied (S3).

D45 expected "a few programs upstream accepts are refused". The rule
refuses the prelude. Our own code passes even the strict rule (the fork,
the frontend, our libs and tests: no equal or larger head in the scan),
but every program is elaborated against the stock prelude and base.

**(c) Strict versus non-strict does not rescue it.** The non-strict form
(`≤` in S2, with a cycle check comparing goals with their unknowns
collapsed) admits the equal cases but still refuses
`Prelude/Types.idr:301` and the base cases above, and still needs a rule
for constructors.

### 2.6 The rule that ends by construction: the path rule

Before `searchType` searches a goal `G` that is a type-constructor
application (`AutoSearch.idr:528-547`, after `nf`), compare it with every
goal `G'` on its path: the goals whose premise searches led to `G`,
across Π goals and local steps (the path upstream's `trying` resets under
Π is kept whole for this). Let `⌊t⌋` be `t` with every unsolved
metavariable replaced by one symbol `?`, every local bound by a step of
the search (under a Π goal) by one symbol `x`, and every primitive
constant by its type. Let `⊴` be homeomorphic embedding on these trees
(`s ⊴ t` if `s` embeds in a child of `t`, or the roots are equal and the
children of `s` embed, in order, into a subsequence of the children of
`t`). If `⌊G'⌋ ⊴ ⌊G⌋` for some `G'`:

1. if `G` is convertible with `G'`: the step fails, as upstream's cycle
   check does today (`AutoSearch.idr:508-517`);
2. otherwise, if `G` or `G'` holds an unsolved metavariable: the whole
   search is postponed, as a determining-argument failure is
   (`Unify.idr:1450-1455`), and at the last chance the program is refused;
3. otherwise the program is refused, naming `G'`, `G` and the hints
   between them.

**Why it ends (by construction, no count).** The labels of `⌊·⌋` form a
finite set: the names of the context, the locals of the search's root
environment, `?`, `x`, one symbol per primitive type, the binder kinds.
Kruskal's tree theorem (recalled: every infinite sequence of finite trees
labelled from a well-quasi-order, children compared by Higman's
embedding, has `i < j` with `tᵢ ⊴ tⱼ`) says every infinite path has an
embedded pair; the first one stops the path at case 1, 2 or 3. Every
node has finitely many children (locals, hints, premises), so by König's
lemma each search is finite. A postponed search is retried only after a
round makes progress, and progress solves a hole for good
(`Unify.idr:1428-1447`), so postponement ends too. The check costs, per
goal, one embedding test per ancestor, each polynomial in the two goals'
sizes (the standard dynamic programme); conjecture on the constant.

**Refuse, never fail.** Cases 2 and 3 must not be catchable as a failed
branch, or the search would pick a sibling and the answer would differ
from upstream's. In the search, a growth is a value of the result type
(a `Grown` case beside the found term), not an `Error`, so no `catch`,
`tryUnify` or `handleUnify` (`AutoSearch.idr:20-34, 155-194`) can turn it
into a failure: each combinator's type makes it pass the growth up. At
the boundary to the elaborator (`retryGuess`, `Unify.idr:1439-1466`) it
becomes either the postponement of case 2 or a refusal error that
`abandon` (`Check.idr:605-612`) and `recoverable` (`Unify.idr:1426`,
`Delayed.idr` `recoverable`) classify as final. The `depth` parameter and
the `Z` clause of `searchIfHole` go, with every depth listed in §2.1.

**What it refuses, against the stock Idris:**

- `Loop1.idr`, `Loop.idr`, `Cons1.idr`, `Cons2.idr`: refused at the
  second goal (`Foo Nat ⊴ Foo (List Nat)`), where the stock Idris refuses
  after 50 levels or runs past 60 s.
- A search the stock Idris answers after a growing detour: a growing hint
  tried before a hint that succeeds (in an `anyOne` group, or as the
  failing half of an `exactlyOne` group). Refused, where the stock Idris
  accepts with the answer its depth left it.
- A search through a container that wraps its own goal:
  `{auto t : Rose Nat}` reaches `List (Rose Nat)`, in which `Rose Nat`
  embeds; the stock Idris answers `MkRose Z []` (conjecture from the
  code, not run). Rare: searching for a value of a recursive data type.
- A search that recurs through unknowns that never become known (`Elem 3
  ?xs` when nothing fixes `?xs`): refused at the last chance, where the
  stock Idris commits to an answer its depth chose (`There` 49 times, then
  `Here`, conjecture from the order of `addHintFor`, `Context.idr:1857-1865`)
  and then usually fails on the unknowns left.

**What it accepts that the stock Idris refuses:** a search longer than
the depth on goals that shrink: `Elem 60 xs` (measured to be refused at
50 and accepted at 100, §2.3).

**Meaning.** On a program the fork accepts, cases 2 and 3 never fired
and case 1 is upstream's own, so the explored tree is upstream's with no
depth, and every path in it is finite. The stock Idris with
`%auto_implicit_depth` at least the longest path explores the same tree
and gives the same answer (read). The one exception is case 2: a search
postponed because of unknowns may later be answered from what other
constraints fixed, where the stock Idris answered at once with what its
depth decided along a descent through unknowns that would not otherwise
have ended. So the fork differs from upstream only where upstream's
answer is the count's, never where it is the language's. Prelude and
base: no search in them is known to trigger cases 2 or 3 (conjecture; the
check is §8's first experiment).

### 2.7 A static rule as well?

A static rule at declarations (S1 to S5 or a weaker form) would report
some growths where the implementation is written rather than where it is
used. It cannot replace the path rule (§2.5), and beside it, it only
refuses more: `Grow.idr` (`Show (a, a) => Show (Twice a)`, larger,
measured accepted by the stock Idris in 0.47 s) and `Equal.idr` (`Show
(List a) => Show (Wrap a)`, equal, accepted in 0.44 s) both search
finitely and the path rule accepts them. If wanted, it could apply to
user modules only, since the prelude and base break it. Not recommended.

## 3. Who relies on the pragmas or on a deep search

- **The pragmas** (grep over `compiler/`, `libs/`, `tests/`, `tools/`,
  read): neither `%ambiguity_depth` nor `%auto_implicit_depth` is written
  anywhere; the only mention is the error text
  `compiler/idris/src/Idris/Error.idr:460`. The frontend's profile
  refuses both in user modules today (`Profile.idr:141, 176`).
- **`%search` in the fork's own source** (read): `Core/Core.idr:1155`
  (`Functor (Tap m)` from a function), `Core/Normalise/Quote.idr:233, 261`
  and `Libraries/Data/SparseMatrix.idr:162` (`@{%search}`): one or two
  levels each.
- **Implementations the size rule would refuse:** none in the fork, the
  frontend, our libs or tests (§2.5 table). The prelude and base: §2.5.
- **`%hint`s:** none in the frontend or our libs; ten in the fork (read,
  e.g. `Core/TT/Var.idr:432-465`, `WeakenVar : Weaken (Var ...)`: no
  premises) and ten in base (`base/Control/App.idr:237`, `mapState :
  State tag t e -> State tag t (eff :: e)`: premise smaller).
- **Nesting of overloads in our code:** it compiles under the stock Idris
  today, so no nesting there exceeds the count in a way that refuses.
  Whether a depth failure disambiguates a site in our code (§1.3, 2) is
  unknown; building the Idris side with the change answers it (§8).
- **Two hosts.** The Idris side keeps compiling under the stock Idris,
  counts and all; under idris-mlir it is elaborated by the fork. Both
  accept it with the same meaning provided no site in it depends on a
  count (by §1.3 and §2.6), which is the measurement above.

## 4. What the pragmas become

As `%totality_depth` did (`upstream/fork-totality-depth/pull-request.diff`,
read): the parser no longer knows `%ambiguity_depth` or
`%auto_implicit_depth`, so a module that writes either is refused where
it writes it, before anything is checked, with the frontend's
`unsupported (elaboration)` (the shape of
`tests/elaboration-totality-depth-pragma/expected`, read). `%search` stays
(it means "find this by search") and loses its hidden 50.

Two neighbours, outside D45's two counts, for the coordinator:

- **`%search_timeout`** is parsed and stored (`Idris/Parser.idr:1510`,
  `Core/Context.idr:2261-2263`) and read by nothing: `startTimer` has no
  caller in the fork (read, grep), its one upstream caller being the
  REPL's expression search (`third_party/Idris2/src/TTImp/Interactive/ExprSearch.idr:61,
  878`), which the fork deleted. It is FB-39's dead timer; a pragma that
  means nothing should be refused by the parser in the same way when the
  timer goes.
- **The reflected depth.** Base's `ISearch : FC -> (depth : Nat) ->
  TTImp` is upstream's API and stays. `TTImp/Reflect.idr` reifies it and
  must then drop the number; reflecting the fork's depth-less `ISearch`
  out needs some number, and any number is invented. Whether the frontend
  admits elaborator reflection at all I did not establish (no refusal of
  `%runElab` or `ElabReflection` in `compiler/src`, grep; conjecture that
  something else refuses it). The coordinator settles this beside the
  change.

Other counts in the fork, none of which refuses (read), so D45 does not
reach them: `%nf_metavar_threshold` (`Core/Unify.idr:870-873`, falls back
to a full quote, FB-42), the quote limit 10 in `makeAutoImplicit`
(`App.idr:268-269`, falls back), `normaliseSizeLimit 10` for a case
function's type (`TTImp/Elab/Case.idr:208`, falls back to the unnormalised
type, `Core/Normalise.idr:88-95`) and for hole types
(`TTImp/Elab.idr:78-79`, falls back). The case-function one feeds
`findErased` (`Case.idr:209`), so a count may decide which arguments of a
case function are found erased (conjecture; worth its own check).

## 5. The PINS.md entries (described, not written)

Two entries, in the shape of `totality-depth` (`PINS.md:1067-1089`):

**`ambiguity-depth`**
- symptom: at the pinned Idris, whether a program elaborates depends on
  `%ambiguity_depth` (default 3): a fifth nested resolution of an
  overloaded name whose candidates the expected type does not narrow is
  refused, so `printLn (1, 2, 3, 4, 5, 6)` is refused while the 5-tuple
  is accepted, and a candidate whose arguments nest past the count fails
  while another wins; the resolution ends without the count. The fork
  inherited it; the frontend reaches it through every elaboration.
- sites: §1.7's list.
- workaround: none; the fork carries the change of
  `upstream/fork-ambiguity-depth/pull-request.diff`: the count, its error,
  its option and its pragma are gone, and the parser refuses the pragma.
  Everything the pin accepts at a large enough depth is accepted with the
  same elaboration.
- retire: when a re-sync brings upstream's own removal of the count.
- upstream: upstream/fork-ambiguity-depth; nothing is sent (**Idris**).

**`search-depth`**
- symptom: at the pinned Idris, automatic search is bounded by a depth
  (`%auto_implicit_depth`, 50; `%search`, 50 fixed; a `with` clause's and
  an implementation's parents', 500), and running out is an ordinary
  failure: `Elem 60 xs` is refused, a growing search with two hints runs
  for longer than any count suggests (2^50 paths), and a branch cut by the
  depth lets a sibling win. The fork inherited it.
- sites: `Core/AutoSearch.idr` (the depth parameters, `searchIfHole`'s
  `Z`, the path rule, `Grown`), `Core/Unify.idr` (`search`, `retryGuess`),
  `Core/UnifyState.idr` (`newSearch`), `Core/Context/Context.idr` and
  `Core/TTC.idr` (`BySearch` without a depth; a TTC format change),
  `TTImp/Elab/{App,Check,Term}.idr`, `TTImp/{TTImp,Unelab,WithClause,Parser,Reflect}.idr`,
  `TTImp/TTImp/{Functor,Traversals,TTC}.idr`, `TTImp/Utils.idr`,
  `Idris/{Syntax,Parser,Desugar,Resugar,Pretty}.idr`,
  `Idris/Elab/Implementation.idr`, `Idris/Syntax/Pragmas.idr`,
  `Core/{Options,Context,Core}.idr`, `Idris/Error.idr` (the refusal's
  text).
- workaround: none; the fork carries the change of
  `upstream/fork-search-depth/pull-request.diff`: no depth anywhere; a
  goal that embeds an earlier goal on its path refuses the program (or
  postpones the search, when unknowns are involved); the parser refuses
  `%auto_implicit_depth`.
- retire: when a re-sync brings upstream's own bound that is not a count.
- upstream: upstream/fork-search-depth; nothing is sent (**Idris**).

The fork's README (`compiler/idris/README.md:615-630`) gains both names
in its list beside `fork-totality-depth`, and `upstream/README.md`'s table
(`:116`) a row each.

## 6. The upstream directories (described, not written)

**`upstream/fork-ambiguity-depth/`**: `README.md` in the shape of
`upstream/fork-totality-depth/README.md` (title "[Idris2] Whether a
program elaborates depends on a count of nested overloaded names";
Reproduce, Expected, Cause, The fix, Why there is no patch, Testing at
the pin, Upstreaming plan with nothing sent); reproducers `Tuple.idr`
(`printLn (1, 2, 3, 4, 5, 6)`) and `Nested.idr` (`x` five deep, §1.4);
`pull-request.diff` against the pin, laid out as a stock checkout: §1.7's
deletions, the `%ambiguity_depth` section of
`docs/source/reference/pragmas.rst` and the threshold paragraph of
`docs/source/updates/updates.rst:259-270` rewritten, and upstream's test
`tests/idris2/error/error021/DeepAmbig.idr` without its
`%ambiguity_depth 1000` line (expected output unchanged: the undefined
name is still found through `abandon`).

**`upstream/fork-search-depth/`**: `README.md` likewise; reproducers
`Deep.idr` (`Elem 60` by an auto implicit), `Grows.idr` (`Cons2.idr`'s two
constructors) and `Loop.idr` (two `%hint`s); `pull-request.diff` with
§5's sites, the `%auto_implicit_depth` section of `pragmas.rst` removed,
and a new upstream test beside `total025`'s style that checks `Elem 60` is
found and `Grows.idr` is refused. Whether upstream's own suite relies on a
search running out of depth is unknown until it runs with the change.

Tests in our tree, in the shape of `tests/elaboration-totality-depth-pragma/`
and `tests/totality-past-depth/` (read): one refusing each pragma where it
is written (with a `near/` program without it); one accepting an 8-tuple
under `printLn` and printing it; one accepting an `Elem 60` auto implicit;
one refusing `Cons2.idr`'s search with `unsupported (elaboration)` (with a
`near/` whose constructor shrinks the index).

## 7. Decisions for the owner, in order, one at a time

Each waits for the one before.

1. **The search's bound: the path rule (§2.6) in place of D45's size
   rule.** This reverses a recorded design, so it is the owner's.
   - *Path rule* (recommended): ends every search with no count; refuses
     only searches that actually grow, at the use; accepted programs
     elaborate as upstream with the depth raised. Cost: one embedding test
     per ancestor per goal; an error at the use, not at the declaration;
     refuses a search through a self-wrapping container (rare). Who pays:
     the fork's search code (a new result case, the check), and a program
     whose search grows, refused where upstream answered after a detour.
   - *D45's size rule as recorded*: refuses the prelude (§2.5); not
     viable without exempting the prelude and base, which would leave
     their hints, and every constructor, unbounded.
   - *Keep the count*: reverses D45's "A"; acceptance keeps depending on
     50.
2. **A growth through unknowns (§2.6, case 2):** postpone until the last
   chance (recommended: upstream also postpones an ambiguous search, and
   refusing at once would refuse a program only because its search was
   tried early), or refuse at once (never differs from upstream's answer,
   but refuses programs upstream accepts once their unknowns are known).
3. **Overloaded names (§1):** delete the count with nothing in its place
   (recommended), accepting the measured cost of nested undetermined
   overloads (433 s for a 22-tuple under `printLn`). No rule on programs
   smaller than the count bounds the cost (§1.6). D45's "bounded by what
   it has already tried" is withdrawn as the mechanism, since reading the
   code shows it is not needed and the measurements show it would not
   help.

For the coordinator, not the owner: culling `%search_timeout` with
FB-39's timer; the reflected `ISearch` depth (§4); whether `findErased`
depends on the case-function size limit (§4).

## 8. Unknowns, and the cheapest experiment for each

- **Do the prelude, base, the fork, the frontend and our libs trigger the
  path rule?** Implement it first as a log line (no refusal), build the
  Idris side and `make test` with the fork, count firings. Zero is the
  expectation (conjecture).
- **Does any site in our code or base depend on the ambiguity count to
  disambiguate?** Same build with `checkAmbigDepth` deleted; any new
  ambiguity error is such a site.
- **Upstream's suite with each change**, for the `pull-request.diff`
  records (as `fork-totality-depth` did not run it either).
- **Where the tuple's time goes** (§1.5): a profile of the 16-tuple with
  the count lifted; if it is the tuple type's normalisation per retry, the
  representation note of §1.7 is the fix.
- **The embedding test's cost** on the deepest search the tree has (the
  `Elem 60` reproducer): measured once implemented.

## 9. Sources

Read: `proposals/0000-mlir-native.md:209-224` (D12), `:756-772` (D45),
`:913-914` (DP-20); `PINS.md:1067-1089`;
`upstream/fork-totality-depth/{README.md,Depth.idr,pull-request.diff}`;
`audits/p0/17-fork-boundary.md:570-575, 741-747` (FB-39 to FB-42, C7);
the fork's files cited above; `third_party/Idris2/docs/source/reference/pragmas.rst:60-76`,
`docs/source/updates/updates.rst:248-290`,
`docs/source/tutorial/interfaces.rst:756-775`,
`docs/source/implementation/overview.rst:370-390`;
`third_party/Idris2/tests/idris2/error/error021/`;
`compiler/src/IdrisMLIR/Frontend/Profile.idr:136-176`;
`tests/elaboration-totality-depth-pragma/`, `tests/totality-past-depth/`.

Measured: the files `Tup*.idr`, `TupP*.idr`, `TupT.idr`, `TupL.idr`,
`Nest*.idr`, `Over*.idr`, `L*.idr`, `G18.idr`, `G22.idr`, `H14.idr`,
`H16.idr`, `Deep.idr`, `DeepAuto*.idr`, `Grow.idr`, `Equal.idr`,
`Loop.idr`, `Loop1.idr`, `Cons1.idr`, `Cons2.idr`, `Meta.idr` under
`/tmp/elabcounts/` (scratch, not kept), each checked once by the stock
pinned Idris as described at the top.

Recalled: GHC's instance termination conditions (Paterson conditions,
coverage condition for functional dependencies); Kruskal's tree theorem
and Higman's lemma; homeomorphic embedding as a termination test in
supercompilation and partial deduction; the hardness of overload
resolution with inference; Swift's "expression too complex".
