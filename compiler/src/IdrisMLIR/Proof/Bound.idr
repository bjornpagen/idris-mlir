-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The bound the growth check gives each static position holds for every
||| value the position can receive: Lemma 1 and Theorem 1, over a model of
||| what the frontend's sites write.
|||
||| A value is a tree of heads, with leaves for closed parts of known
||| height. A template is a value with pattern variables, each bound in the
||| value at some position, as deep as the case tree's patterns reach it.
||| The frontend's sites read as the model's:
||| - a template's marker for the writer's parameter i, matched d deep, is a
|||   variable bound at that position, at depth d;
||| - a head and a leaf are themselves;
||| - a stuck definition unfolded to its leaves is one site per leaf;
||| - a projection of a dictionary that is not yet a constructor is, for each
|||   implementation that can have written it, that implementation applied
|||   to variables bound at its own positions.
||| A dispatch carries only the method's own arguments: the dictionary's
||| arguments reached the method function through the site that wrote the
||| implementation. Calls, data fields and dictionaries are all sites, and
||| V, the least family closed under them, holds everything the frontend
||| requests. A capped position's type looks only so deep, so the frontend
||| keys it by the value cut there: it holds every value of the cap's height,
||| and no site writes into it whole.
|||
||| A family the writer was given (`m : Type -> Type`), applied in a static
||| argument, is beta-reduced at every instance: the key holds what the
||| family's value computes from the arguments, which no substitution of the
||| template writes. The frontend reads it one of two ways, each a template
||| of the model:
||| - where only closed values no higher than k land at the family's
|||   position, as k heads above its arguments;
||| - applied to closed arguments, as the family raised by their height.
||| What an instance writes there is beta of the family's meaning
||| (`Meaning`): its body over the arguments' values, reduced in turn where
||| it applies an argument of its own to closed arguments. Beta of a family no higher than
||| k, applied to arguments no higher than h, is no higher than k + h
||| (`betaHeight`), so each reading is at least as high as what the
||| instance writes (`reducesBelow`). This needs the family to be inert:
||| its body no higher than its key, holding each variable no deeper than
||| its key is high. The frontend reads every family's value as its meaning
||| (a lambda's variables, and the parameters a definition given fewer
||| arguments than it takes lacks, as arguments), with the key's form
||| beside it. A type constructor given fewer arguments than it takes is
||| inert (`partialMeaning`), and so is a body that is a part of its key
||| (`lambdaMeaning`). A body that holds a definition stuck on an argument
||| (whose match beta lets compute), or applies an argument to what holds
||| another or to other than as many arguments as it takes, has no meaning:
||| the frontend reads a family applied where such a value can land as
||| nothing bounds it.
|||
||| Suppose the graph covers every site:
||| - an arc runs from each variable's position, weighing at least how much
|||   deeper the variable sits in the template than in its value;
||| - K is at least each template's own height;
||| - each capped position has an arc from the origin, weighing the cap less K.
||| If the potential is also feasible, every value of V at p is within
||| `bound`. The frontend builds no derivation. The worklist checks the
||| conclusion on every request, so a site read otherwise raises an internal
||| error there, never a wrong instance or a hang.
|||
||| Every proof is erased and total, and nothing here runs. The arithmetic is
||| on naturals, a weight being what it adds and what it takes away.
module IdrisMLIR.Proof.Bound

import IdrisMLIR.Proof.Growth

import Control.Relation
import Data.Fin
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.Vect

%default total

||| A template over m pattern variables: a head with its children (a type or
||| data constructor, an implementation, a primitive type former), a
||| variable, or a closed part of that height (a literal, a primitive type).
public export
data Term : Nat -> Type where
  Var : Fin m -> Term m
  Head : List (Term m) -> Term m
  Leaf : Nat -> Term m

||| A value: a template with no variable to hold.
public export
Tree : Type
Tree = Term 0

mutual
  ||| A head stands one above its tallest child, a nullary one at 1, and a
  ||| variable counts 0: a template's height is its own part's, which K bounds.
  public export
  height : Term m -> Nat
  height (Var _) = 0
  height (Head ts) = S (heights ts)
  height (Leaf h) = h

  ||| The tallest of some templates, 0 for none.
  public export
  heights : List (Term m) -> Nat
  heights [] = 0
  heights (t :: ts) = maximum (height t) (heights ts)

mutual
  ||| A template with each variable replaced by its value.
  public export
  subst : Vect m Tree -> Term m -> Tree
  subst sigma (Var y) = index y sigma
  subst sigma (Head ts) = Head (substs sigma ts)
  subst _ (Leaf h) = Leaf h

  ||| Each of some templates with each variable replaced by its value.
  public export
  substs : Vect m Tree -> List (Term m) -> List Tree
  substs _ [] = []
  substs sigma (t :: ts) = subst sigma t :: substs sigma ts

||| c heads above a template: an applied family's reading, k heads above its
||| arguments where only closed values no higher than k land at the family,
||| or the family raised by the height of the closed arguments it is applied
||| to.
public export
raise : Nat -> Term m -> Term m
raise Z t = t
raise (S c) t = Head [raise c t]

||| Variable y occurs e levels down in a template.
public export
data Occurs : Fin m -> Nat -> Term m -> Type where
  Root : Occurs y 0 (Var y)
  Under : Elem t ts -> Occurs y e t -> Occurs y (S e) (Head ts)

||| A part of a value d levels down: what a pattern binds at depth d. A leaf
||| is a run of successors as far as a match goes, one level a match.
public export
data Sub : Nat -> Tree -> Tree -> Type where
  Self : Sub 0 v v
  Child : Elem c cs -> Sub d c u -> Sub (S d) (Head cs) u
  Peel : Sub d (Leaf h) u -> Sub (S d) (Leaf (S h)) u

||| Where a pattern variable is bound: the position whose value it is matched
||| in, and how deep.
public export
record Binder (n : Nat) where
  constructor MkBinder
  position : Fin n
  depth : Nat

||| A template written at a position. Its variables may be bound at any
||| positions, not one writer's: a dictionary's field, read through the
||| implementation that wrote it, binds at that implementation's positions,
||| so calls, data fields and dictionaries are all sites.
public export
record Site (n : Nat) where
  constructor MkSite
  target : Fin n
  vars : Nat
  binders : Vect vars (Binder n)
  template : Term vars

||| A template holds no variable.
public export
Closed : {m : Nat} -> Term m -> Type
Closed t = (y : Fin m) -> (e : Nat) -> Not (Occurs y e t)

||| What every instance's beta makes of a family whose key reads as v,
||| applied to n arguments: its body, over one variable for each argument.
||| The family is inert: its body is no higher than its key, and holds each
||| argument no deeper than its key is high.
public export
record Meaning (v : Tree) (n : Nat) where
  constructor MkMeaning
  body : Term n
  low : LTE (height body) (height v)
  shallow : (y : Fin n) -> (e : Nat) -> Occurs y e body -> LTE e (height v)

||| Some arguments' values, one for each variable of a family's body.
||| Data.Vect's `fromList` builds its vector reversed through an
||| accumulator, which no proof here can index.
public export
arguments : (ws : List Tree) -> Vect (length ws) Tree
arguments [] = []
arguments (w :: ws) = w :: arguments ws

||| Only closed values no higher than k land at a position: it is uncapped,
||| and every listed site into it writes a template that holds no variable
||| and is no higher than k.
public export
record Lands (g : Graph) (ss : List (Site g.size)) (p : Fin g.size) (k : Nat) where
  constructor MkLands
  uncapped : index p g.caps = Nothing
  under : (s : Site g.size) -> Elem s ss -> s.target = p -> LTE (height s.template) k
  closed : (s : Site g.size) -> Elem s ss -> s.target = p -> Closed s.template

||| Where a site's variable y lands only closed values no higher than k: at
||| its binder's position.
public export
LandsAt : (g : Graph) -> List (Site g.size) -> Vect m (Binder g.size) -> Fin m -> Nat -> Type
LandsAt g ss bs y k = Lands g ss (index y bs).position k

||| Where a family's body lands nothing: its variables are its arguments,
||| no position's.
public export
Nowhere : Fin m -> Nat -> Type
Nowhere _ _ = Void

namespace Reductions
  ||| What an instance writes for each of some templates.
  public export
  data Reductions : (Fin m -> Nat -> Type) -> Vect m Tree -> List (Term m) -> List Tree -> Type

||| What an instance writes where a template reads as t, its variables
||| bound to sigma: t substituted, except where t reads a family applied,
||| where the instance writes beta of the family's meaning at the
||| arguments' values: its body over them, reduced in turn. A family
||| applied reads one of two ways:
||| - where only closed values no higher than k land at the family's
|||   position (`lands`), as k heads above its arguments;
||| - applied to closed arguments, as the family raised by their height.
||| A site's template reads the first where its writer's position lands so
||| (`LandsAt`); a family's body, whose variables are its arguments, only
||| the second (`Nowhere`): its own argument applied to closed arguments.
public export
data Reduces : (lands : Fin m -> Nat -> Type) -> Vect m Tree -> Term m -> Tree -> Type where
  AtVar : Reduces lands sigma (Var y) (index y sigma)
  AtLeaf : Reduces lands sigma (Leaf h) (Leaf h)
  AtHead : Reductions lands sigma ts ws -> Reduces lands sigma (Head ts) (Head ws)
  Landed : (y : Fin m) -> lands y k -> Reductions lands sigma ts ws -> (f : Meaning (index y sigma) (length ws)) ->
           Reduces Nowhere (arguments ws) f.body w -> Reduces lands sigma (raise k (Head ts)) w
  Raised : (y : Fin m) -> Closed (Head ts) -> Reductions lands sigma ts ws -> (f : Meaning (index y sigma) (length ws)) ->
           Reduces Nowhere (arguments ws) f.body w -> Reduces lands sigma (raise (heights ts) (Var y)) w

namespace Reductions
  public export
  data Reductions where
    Nil : Reductions lands sigma [] []
    (::) : Reduces lands sigma t w -> Reductions lands sigma ts ws -> Reductions lands sigma (t :: ts) (w :: ws)

||| V: the values each position can receive, the least family closed under
||| the sites. A capped position is keyed by its value cut at the cap, so it
||| holds every value of the cap's height, and no site into it is listed.
public export
data InV : (g : Graph) -> List (Site g.size) -> Fin g.size -> Tree -> Type

||| Each variable bound to a part, as deep as its pattern, of a value of V at
||| its position, each variable on its own.
public export
data Matches : (g : Graph) -> List (Site g.size) -> Vect m (Binder g.size) -> Vect m Tree -> Type where
  Nil : Matches g ss [] []
  Bind : InV g ss b.position v -> Sub b.depth v u -> Matches g ss bs us ->
         Matches g ss (b :: bs) (u :: us)

data InV where
  ||| A site writes what an instance makes of its template, its variables
  ||| bound by a match: every family applied in it beta-reduced where the
  ||| template reads it, the rest substituted.
  Reduced : (s : Site g.size) -> {0 sigma : Vect s.vars Tree} -> Elem s ss ->
            Matches g ss s.binders sigma -> Reduces (LandsAt g ss s.binders) sigma s.template w -> InV g ss s.target w
  ||| The origin writes every value of the cap's height at a capped position.
  Capped : index p g.caps = Just c -> LTE (height v) c -> InV g ss p v

||| An arc carries an occurrence: it runs from the variable's position to the
||| site's, and weighs at least how much deeper the variable sits in the
||| template (e) than in its value (the binder's depth).
public export
data Carries : (g : Graph) -> Binder g.size -> Nat -> Fin g.size -> Type where
  MkCarries : Elem (MkArc (Just b.position) p (Finite gain loss) pr) g.arcs ->
              LTE (e + loss) (b.depth + gain) -> Carries g b e p

||| What the graph says of a site: its target is uncapped, K is at least its
||| template's own height, and an arc carries every occurrence of a variable.
public export
record Covers (g : Graph) (s : Site g.size) where
  constructor MkCovers
  uncapped : index s.target g.caps = Nothing
  constant : LTE (height s.template) g.constant
  carried : (y : Fin s.vars) -> (e : Nat) -> Occurs y e s.template ->
            Carries g (index y s.binders) e s.target

||| A capped position's arc from the origin, weighing at least the cap less K.
public export
data Origin : (g : Graph) -> Fin g.size -> Nat -> Type where
  MkOrigin : Elem (MkArc Nothing p (Finite gain loss) pr) g.arcs ->
             LTE (c + loss) (g.constant + gain) -> Origin g p c

||| The graph says what the sites write: it covers every site, and every
||| capped position has its origin arc.
public export
record Describes (g : Graph) (ss : List (Site g.size)) where
  constructor MkDescribes
  sites : All (Covers g) ss
  caps : (p : Fin g.size) -> (c : Nat) -> index p g.caps = Just c -> Origin g p c

||| Lemma 1, the substitution's half: a substitution is no taller than any b
||| above the template's own height and above every variable's value raised
||| by the depth the variable occurs at.
export
0 substHeight : (t : Term m) -> (sigma : Vect m Tree) -> LTE (height t) b ->
                ((y : Fin m) -> (e : Nat) -> Occurs y e t -> LTE (height (index y sigma) + e) b) ->
                LTE (height (subst sigma t)) b

||| Lemma 1, the pattern's half: a part d levels down is at least d lower.
export
0 subHeight : Sub d v u -> LTE (height u + d) (height v)

||| Theorem 1: under a feasible potential, every value a position can
||| receive is within its bound.
export
0 bounded : {g : Graph} -> {ss : List (Site g.size)} -> {pot : Vect g.size Nat} ->
            {p : Fin g.size} -> {v : Tree} ->
            Describes g ss -> Feasible g pot -> InV g ss p v -> LTE (height v) (bound g pot p)

-- An applied family's bound: beta of a family no higher than k, applied to
-- arguments each no higher than h, is no higher than k + h.
0 betaHeight : {k, h : Nat} -> (f : Meaning v n) -> {cs : Vect n Tree} -> Reduces Nowhere cs f.body w -> LTE (height v) k ->
               ((j : Fin n) -> LTE (height (index j cs)) h) -> LTE (height w) (k + h)

-- What an instance writes is no higher than the substitution of its
-- template's reading, given that each family read as closed is no higher
-- than its landings: an applied family's readings are as high as beta.
0 reducesBelow : {lands : Fin m -> Nat -> Type} -> {sigma : Vect m Tree} ->
                 ((y : Fin m) -> (k : Nat) -> lands y k -> LTE (height (index y sigma)) k) ->
                 Reduces lands sigma t w -> LTE (height w) (height (subst sigma t))

-- At a position where only closed values no higher than k land, every
-- value is no higher than k.
0 landed : {g : Graph} -> {ss : List (Site g.size)} -> {p : Fin g.size} -> {v : Tree} ->
           Lands g ss p k -> InV g ss p v -> LTE (height v) k

||| What the graph's arcs carry of an applied family's reading: an
||| occurrence c heads deeper than in what is raised. So an arc of weight at
||| least c + 1 + e - d from an argument's variable, matched d deep and e
||| deep in the argument, carries it in k heads above the arguments; and one
||| of weight at least h + e - d from the family's own, e deep where it is
||| applied, carries it in the family raised by h.
export
0 occursRaised : (c : Nat) -> Occurs y e (raise c t) -> (e' ** (Occurs y e' t, e = c + e'))

||| A reading's height: c above what is raised. So K covers k heads above
||| some arguments when it is at least k + 1 above their own height.
export
0 raisedHeight : (c : Nat) -> (t : Term m) -> height (raise c t) = c + height t

||| A template with no family applied in it writes its substitution.
export
0 substituted : (t : Term m) -> Reduces lands sigma t (subst sigma t)

||| A type constructor given some arguments, fewer than it takes, is inert:
||| beta puts the rest under its head, beside those.
export
0 partialMeaning : (ts : List Tree) -> (ys : List (Fin n)) -> Meaning (Head ts) n

||| A body that is a part of its key, its variables read as anything (the
||| frontend reads an argument of a family's value as a leaf of height 1),
||| is inert: a lambda whose body places its variables, its key holding the
||| body under the binders' heads.
export
0 lambdaMeaning : (b : Term n) -> (sigma : Vect n Tree) -> Sub d v (subst sigma b) -> Meaning v n

------------------------------------------------------------------------------
-- The arithmetic
------------------------------------------------------------------------------

-- Base states only that `maximum` is above both arguments; the induction
-- needs that it is the least such.
0 maxLub : {a, c : Nat} -> LTE a b -> LTE c b -> LTE (maximum a c) b
maxLub {a = Z} _ lc = lc
maxLub {a = S _} {c = Z} la _ = la
maxLub {a = S a} {c = S c} (LTESucc la) (LTESucc lc) = LTESucc (maxLub la lc)

0 maxMono : {a, a', c, c' : Nat} -> LTE a a' -> LTE c c' -> LTE (maximum a c) (maximum a' c')
maxMono la lc = maxLub (transitive la (maximumLeftUpperBound _ _)) (transitive lc (maximumRightUpperBound _ _))

0 dropSucc : {a, e : Nat} -> LTE (a + S e) (S b) -> LTE (a + e) b
dropSucc le = fromLteSucc (rewrite plusSuccRightSucc a e in le)

-- Base cancels a sum only in an equation, not in an inequality.
0 lteCancelLeft : (c : Nat) -> LTE (c + a) (c + b) -> LTE a b
lteCancelLeft Z le = le
lteCancelLeft (S c) (LTESucc le) = lteCancelLeft c le

0 lteCancelRight : {a, b : Nat} -> (c : Nat) -> LTE (a + c) (b + c) -> LTE a b
lteCancelRight c le = lteCancelLeft c (rewrite plusCommutative c a in rewrite plusCommutative c b in le)

-- The induction's step, every difference written as a sum on both sides: a
-- binding of height h, d deep in a value within k + q, sits e deep in the
-- template; the arc weighs g less l, at least e less d; and the potential
-- satisfies the arc, q + (g less l) within p. Then h + e is within k + p.
0 carry : {h, d, k, q, e, l, g, p : Nat} ->
          LTE (h + d) (k + q) -> LTE (e + l) (d + g) -> LTE (q + g) (p + l) -> LTE (h + e) (k + p)
carry hd el qg = lteCancelRight l (rewrite sym (plusAssociative h e l) in rewrite sym (plusAssociative k p l) in
  transitive (plusLteMonotoneLeft h (e + l) (d + g) el)
    (transitive (rewrite plusAssociative h d g in plusLteMonotoneRight g (h + d) (k + q) hd)
      (rewrite sym (plusAssociative k q g) in plusLteMonotoneLeft k (q + g) (p + l) qg)))

-- A cap's place: the origin arc weighs g less l, at least c less k, and the
-- potential satisfies it from the origin's 0, so g less l is within p.
-- Then c is within k + p.
0 capWithin : {c, l, k, g, p : Nat} -> LTE (c + l) (k + g) -> LTE g (p + l) -> LTE c (k + p)
capWithin cl gp = lteCancelRight l (rewrite sym (plusAssociative k p l) in
  transitive cl (plusLteMonotoneLeft k g (p + l) gp))

-- Nat's `<` is `compareNat`'s `LT`, which reduces through `S` on both sides.
0 notBelow : (a, c : Nat) -> (a < c) = False -> LTE c a
notBelow Z Z _ = LTEZero
notBelow Z (S _) eq = absurd eq
notBelow (S _) Z _ = LTEZero
notBelow (S a) (S c) eq = LTESucc (notBelow a c eq)

0 minBelow : {a, c : Nat} -> LTE (min a c) a
minBelow with (a < c) proof eq
  _ | True = reflexive
  _ | False = notBelow a c eq

0 minAbove : {a, c : Nat} -> LTE h a -> LTE h c -> LTE h (min a c)
minAbove la lc with (a < c)
  _ | True = la
  _ | False = lc

------------------------------------------------------------------------------
-- The bound
------------------------------------------------------------------------------

0 boundUncapped : {g : Graph} -> {pot : Vect g.size Nat} -> {p : Fin g.size} ->
                  index p g.caps = Nothing -> bound g pot p = g.constant + index p pot
boundUncapped eq = rewrite eq in Refl

0 boundCapped : {g : Graph} -> {pot : Vect g.size Nat} -> {p : Fin g.size} ->
                index p g.caps = Just c -> LTE h c -> LTE h (g.constant + index p pot) -> LTE h (bound g pot p)
boundCapped eq lc lk = rewrite eq in minAbove lk lc

0 boundBelow : (g : Graph) -> (pot : Vect g.size Nat) -> (p : Fin g.size) ->
               LTE (bound g pot p) (g.constant + index p pot)
boundBelow g pot p with (index p g.caps)
  _ | Nothing = reflexive
  _ | Just c = minBelow

0 arcHolds : Feasible g pot -> Elem (MkArc q p (Finite gain loss) pr) g.arcs ->
             LTE (potentialAt pot q + gain) (index p pot + loss)
arcHolds (MkFeasible sat) el = case indexAll el sat of MkSatisfies le => le

------------------------------------------------------------------------------
-- Lemma 1
------------------------------------------------------------------------------

-- The statements are declared with the model, above; their proofs come
-- after the lemmas they use.

0 heightsAbove : Elem t ts -> LTE (height t) (heights ts)
heightsAbove Here = maximumLeftUpperBound _ _
heightsAbove (There el) = transitive (heightsAbove el) (maximumRightUpperBound _ _)

subHeight {u} Self = rewrite plusZeroRightNeutral (height u) in reflexive
subHeight {u} {d = S d} (Child i s) =
  rewrite sym (plusSuccRightSucc (height u) d) in LTESucc (transitive (subHeight s) (heightsAbove i))
subHeight {u} {d = S d} (Peel s) =
  rewrite sym (plusSuccRightSucc (height u) d) in LTESucc (subHeight s)

-- substHeight's children: every child is within b, by its own part's bound
-- and its occurrences, each reached through the child it lies in.
0 substsHeight : (ts : List (Term m)) -> (sigma : Vect m Tree) -> LTE (heights ts) b ->
                 ((t : Term m) -> Elem t ts -> (y : Fin m) -> (e : Nat) -> Occurs y e t ->
                  LTE (height (index y sigma) + e) b) ->
                 LTE (heights (substs sigma ts)) b

substHeight (Var y) sigma _ occ = rewrite sym (plusZeroRightNeutral (height (index y sigma))) in occ y 0 Root
substHeight (Head ts) sigma (LTESucc c) occ =
  LTESucc (substsHeight ts sigma c (\t, i, y, e, o => dropSucc (occ y (S e) (Under i o))))
substHeight (Leaf h) _ c _ = c

substsHeight [] _ _ _ = LTEZero
substsHeight (t :: ts) sigma c occ =
  maxLub (substHeight t sigma (transitive (maximumLeftUpperBound _ _) c) (occ t Here))
         (substsHeight ts sigma (transitive (maximumRightUpperBound _ _) c) (\t', i => occ t' (There i)))

------------------------------------------------------------------------------
-- An applied family
------------------------------------------------------------------------------

-- A part d levels down is no higher.
0 subBelow : Sub d v u -> LTE (height u) (height v)
subBelow {u} s = transitive (lteAddRight (height u)) (subHeight s)

-- A substitution is no lower than its template, whose variables count 0.
mutual
  0 substAbove : (t : Term m) -> (sigma : Vect m Tree) -> LTE (height t) (height (subst sigma t))
  substAbove (Var _) _ = LTEZero
  substAbove (Head ts) sigma = LTESucc (substsAbove ts sigma)
  substAbove (Leaf _) _ = reflexive

  0 substsAbove : (ts : List (Term m)) -> (sigma : Vect m Tree) -> LTE (heights ts) (heights (substs sigma ts))
  substsAbove [] _ = LTEZero
  substsAbove (t :: ts) sigma = maxMono (substAbove t sigma) (substsAbove ts sigma)

0 substElem : Elem t ts -> Elem (subst sigma t) (substs sigma ts)
substElem Here = Here
substElem (There el) = There (substElem el)

-- A variable e deep stands its value's height above e in the substitution.
0 occursHeight : Occurs y e t -> LTE (e + height (index y sigma)) (height (subst sigma t))
occursHeight Root = reflexive
occursHeight (Under el o) = LTESucc (transitive (occursHeight o) (heightsAbove (substElem el)))

-- A template that holds no variable is as high as any substitution of it.
0 closedWithin : (t : Term m) -> (sigma : Vect m Tree) -> Closed t -> LTE (height (subst sigma t)) (height t)
closedWithin t sigma cl = substHeight t sigma reflexive (\y, e, o => void (cl y e o))

0 heightsBelow : (ts : List (Term m)) -> ((t : Term m) -> Elem t ts -> LTE (height t) b) -> LTE (heights ts) b
heightsBelow [] _ = LTEZero
heightsBelow (t :: ts) f = maxLub (f t Here) (heightsBelow ts (\t', el => f t' (There el)))

0 argumentBelow : (ws : List Tree) -> (j : Fin (length ws)) -> LTE (height (index j (arguments ws))) (heights ws)
argumentBelow [] j = absurd j
argumentBelow (w :: ws) FZ = maximumLeftUpperBound _ _
argumentBelow (w :: ws) (FS j) = transitive (argumentBelow ws j) (maximumRightUpperBound _ _)

raisedHeight Z t = Refl
raisedHeight (S c) t = cong S (trans (maximumZeroNLeft _) (raisedHeight c t))

0 substRaise : (c : Nat) -> (t : Term m) -> subst sigma (raise c t) = raise c (subst sigma t)
substRaise Z t = Refl
substRaise (S c) t = cong (\u => Head [u]) (substRaise c t)

0 substRaisedHeight : (c : Nat) -> (t : Term m) -> height (subst sigma (raise c t)) = c + height (subst sigma t)
substRaisedHeight c t = rewrite substRaise {sigma} c t in raisedHeight c (subst sigma t)

mutual
  substituted (Var _) = AtVar
  substituted (Head ts) = AtHead (substitutedAll ts)
  substituted (Leaf _) = AtLeaf

  0 substitutedAll : (ts : List (Term m)) -> Reductions lands sigma ts (substs sigma ts)
  substitutedAll [] = []
  substitutedAll (t :: ts) = substituted t :: substitutedAll ts

occursRaised Z o = (_ ** (o, Refl))
occursRaised (S c) (Under Here o) = let (e' ** (o', eq)) = occursRaised c o in (e' ** (o', cong S eq))
occursRaised (S c) (Under (There el) _) = absurd el

-- A type constructor's given arguments, as a template's parts.
mutual
  closedTerm : Tree -> Term n
  closedTerm (Var y) = absurd y
  closedTerm (Head ts) = Head (closedAll ts)
  closedTerm (Leaf h) = Leaf h

  closedAll : List Tree -> List (Term n)
  closedAll [] = []
  closedAll (t :: ts) = closedTerm t :: closedAll ts

mutual
  0 heightClosed : (t : Tree) -> height (closedTerm {n} t) = height t
  heightClosed (Var y) = absurd y
  heightClosed {n} (Head ts) = cong S (heightsClosed {n} ts)
  heightClosed (Leaf _) = Refl

  0 heightsClosed : (ts : List Tree) -> heights (closedAll {n} ts) = heights ts
  heightsClosed [] = Refl
  heightsClosed {n} (t :: ts) = cong2 maximum (heightClosed {n} t) (heightsClosed {n} ts)

mutual
  0 closedNothing : (t : Tree) -> Not (Occurs y e (closedTerm {n} t))
  closedNothing (Var v) _ = absurd v
  closedNothing {n} (Head ts) (Under el o) = closedNone {n} ts el o
  closedNothing (Head _) Root impossible
  closedNothing (Leaf _) Root impossible
  closedNothing (Leaf _) (Under _ _) impossible

  0 closedNone : (ts : List Tree) -> Elem u (closedAll {n} ts) -> Not (Occurs y e u)
  closedNone {n} (t :: _) Here o = closedNothing {n} t o
  closedNone {n} (_ :: ts) (There el) o = closedNone {n} ts el o

0 elemEither : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
elemEither [] el = Right el
elemEither (_ :: _) Here = Left Here
elemEither (_ :: xs) (There el) = mapFst There (elemEither xs el)

0 elemVar : (ys : List (Fin n)) -> Elem t (map Var ys) -> (y ** t = Var y)
elemVar (y :: _) Here = (y ** Refl)
elemVar (_ :: ys) (There el) = elemVar ys el

partialMeaning {n} ts ys = MkMeaning (Head (closedAll ts ++ map Var ys)) low shallow
  where
    low : LTE (height (Head (closedAll {n} ts ++ map Var ys))) (height (Head ts))
    low = LTESucc (heightsBelow _ (\t, el => case elemEither (closedAll ts) el of
            Left l => rewrite sym (heightsClosed {n} ts) in heightsAbove l
            Right r => let (y ** eq) = elemVar ys r in rewrite eq in LTEZero))

    shallow : (y : Fin n) -> (e : Nat) -> Occurs y e (Head (closedAll ts ++ map Var ys)) -> LTE e (height (Head ts))
    shallow y (S e) (Under el o) = case elemEither (closedAll ts) el of
      Left l => void (closedNone ts l o)
      Right r => let (y' ** eq) = elemVar ys r in
                 case replace {p = Occurs y e} eq o of
                   Root => LTESucc LTEZero

lambdaMeaning b sigma sub =
  MkMeaning b (transitive (substAbove b sigma) (subBelow sub))
    (\y, e, o => transitive (lteAddRight e) (transitive (occursHeight {sigma} o) (subBelow sub)))

-- The family's value is bound by a match at a position where only closed
-- values no higher than k land.
0 landedAt : {g : Graph} -> {ss : List (Site g.size)} -> {bs : Vect m (Binder g.size)} -> {us : Vect m Tree} ->
             (y : Fin m) -> Lands g ss (index y bs).position k -> Matches g ss bs us -> LTE (height (index y us)) k

0 reductionsBelow : {lands : Fin m -> Nat -> Type} -> {sigma : Vect m Tree} ->
                    ((y : Fin m) -> (k : Nat) -> lands y k -> LTE (height (index y sigma)) k) ->
                    Reductions lands sigma ts ws -> LTE (heights ws) (heights (substs sigma ts))

-- Induction on what an instance writes: each applied family's reading is
-- as high as its beta (`betaHeight`), which descends into what the
-- family's body reduces to.
reducesBelow bnd AtVar = reflexive
reducesBelow bnd AtLeaf = reflexive
reducesBelow bnd (AtHead rs) = LTESucc (reductionsBelow bnd rs)
reducesBelow bnd (Landed {k} {ts} {ws} y l rs f inst) =
  rewrite substRaisedHeight {sigma} k (Head ts) in
    transitive (betaHeight f inst (bnd y k l) (argumentBelow ws))
      (plusLteMonotoneLeft k _ _ (lteSuccRight (reductionsBelow bnd rs)))
reducesBelow bnd (Raised {ts} {ws} y cl rs f inst) =
  rewrite substRaisedHeight {sigma} (heights ts) (Var y) in
  rewrite plusCommutative (heights ts) (height (index y sigma)) in
    betaHeight f inst reflexive
      (\j => transitive (argumentBelow ws j)
               (transitive (reductionsBelow bnd rs) (fromLteSucc (closedWithin (Head ts) sigma cl))))

reductionsBelow bnd [] = LTEZero
reductionsBelow bnd (r :: rs) = maxMono (reducesBelow bnd r) (reductionsBelow bnd rs)

-- Beta's bound: the body is no higher than k, and holds each argument no
-- deeper than k (`low` and `shallow`, Lemma 1); what the body reduces to
-- is no higher than its substitution.
betaHeight {k} {h} {cs} f red low args =
  transitive (reducesBelow (\_, _, v => absurd v) red)
    (substHeight f.body cs (transitive f.low (transitive low (lteAddRight k)))
      (\y, e, o => rewrite plusCommutative (height (index y cs)) e in
                     plusLteMonotone (transitive (f.shallow y e o) low) (args y)))

-- A family's value at a position where only closed values land: on V's
-- derivation, `landedAt` descending into the Matches and `landed` into
-- the InV inside Bind.
landedAt FZ l (Bind iv sub _) = transitive (subBelow sub) (landed l iv)
landedAt (FS y) l (Bind _ _ ms) = landedAt y l ms

landed l (Capped cap _) = absurd (trans (sym cap) l.uncapped)
landed l (Reduced s el ms r) =
  transitive (reducesBelow (\y, k, lk => landedAt y lk ms) r)
    (transitive (closedWithin s.template _ (l.closed s el Refl)) (l.under s el Refl))

------------------------------------------------------------------------------
-- Theorem 1
------------------------------------------------------------------------------

-- What a match binds is within its position's bound, less the pattern's
-- depth; the bound read uncapped, which a capped one is below.
0 within : {g : Graph} -> {ss : List (Site g.size)} -> {pot : Vect g.size Nat} ->
           {bs : Vect m (Binder g.size)} -> {us : Vect m Tree} ->
           Describes g ss -> Feasible g pot -> Matches g ss bs us -> (y : Fin m) ->
           LTE (height (index y us) + (index y bs).depth) (g.constant + index (index y bs).position pot)

-- A listed site's substitution is within K above its target's potential:
-- Lemma 1, each occurrence carried by its arc.
0 written : {g : Graph} -> {ss : List (Site g.size)} -> {pot : Vect g.size Nat} ->
            Describes g ss -> Feasible g pot -> (s : Site g.size) -> {0 sigma : Vect s.vars Tree} -> Elem s ss ->
            Matches g ss s.binders sigma -> LTE (height (subst sigma s.template)) (g.constant + index s.target pot)

-- Induction on V's derivation: `within` descends into the Matches inside
-- Reduced, and `bounded` into the InV inside Bind. What a site reduces to
-- is no higher than its substitution (`reducesBelow`), each family read as
-- closed no higher than what lands at it (`landedAt`).
bounded ds fe (Capped {c} cap le) = case ds.caps _ c cap of
  MkOrigin arc w => boundCapped cap le (transitive le (capWithin w (arcHolds fe arc)))
bounded ds fe (Reduced s el ms r) =
  rewrite boundUncapped {g} {pot} {p = s.target} (indexAll el ds.sites).uncapped in
    transitive (reducesBelow (\y, k, lk => landedAt y lk ms) r) (written ds fe s el ms)

written ds fe s el ms =
  let cov = indexAll el ds.sites in
  substHeight s.template _ (transitive cov.constant (lteAddRight _))
    (\y, e, o => case cov.carried y e o of
                   MkCarries arc w => carry (within ds fe ms y) w (arcHolds fe arc))

within ds fe (Bind iv sub _) FZ = transitive (subHeight sub) (transitive (bounded ds fe iv) (boundBelow _ _ _))
within ds fe (Bind _ _ ms) (FS y) = within ds fe ms y
