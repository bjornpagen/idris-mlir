-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The bound the growth check gives each static position holds for every
||| value the position can receive: Lemma 1 and Theorem 1, over the
||| templates the frontend's readers produce (`Proof.Template`).
|||
||| A site is one argument the graph reads: the position it lands at, the
||| template its writer wrote there, the positions its writer's node reads
||| the template's parameters at, and the implementations the flow found
||| each dictionary of it can be. What an instance writes where a template
||| reads (`Writes`) is said once per constructor of the template:
||| - a marker `Var i d` is a part, d deep, of a value a position of the
|||   writer's parameter i received;
||| - a head and a recursion stuck on closed arguments write themselves,
|||   their children written in turn; a leaf, a token and an argument of a
|||   family's value write themselves;
||| - a choice writes one of its leaves;
||| - a family the writer was given, applied to closed arguments
|||   (`Applied`), writes beta of the family's value at them: its meaning,
|||   a part of the value, with each of its arguments given (`Beta`); a
|||   function the writer was given that computes an implementation, applied
|||   (a rank-2 dictionary), writes one of the implementations it gives: a
|||   part of its value (`GivenPart`), or one its definition's leaves give,
|||   which the flow found, applied to values its own positions received
|||   (`MemberOf`), each argument carried from where it was received;
||| - a family applied where only closed values no higher than k land is
|||   read as k heads above its arguments (`raise k`), and writes beta, or a
|||   member, of a value no higher than k (`Landed`, `LandedMember`);
||| - a field of a dictionary writes a value the position of that field of
|||   an implementation the dictionary can be received (`AtField`): each
|||   implementation's field is a position, which the field's template,
|||   over the implementation's own parameters, writes as any site does;
|||   and a member of a choice the running program makes writes a value a
|||   position its members are read from received (`AtMember`): every
|||   place that makes a member of it writes the member's form at its
|||   head's, as any site does, its holes renumbered as the place that
|||   reads it renumbers them (`Renumbered`); where a request holds a hole
|||   in a member's place, a site reading the member writes the hole, as
|||   high as a member made there (`AtHeldHole`);
||| - a leaf two high written where a builtin is applied to the writer's
|||   markers writes the constant it computes at an instance whose values
|||   are constants (`AtComputed`).
||| A family that computes from what it is given (`Computing`) writes
||| nothing any rule states: its arcs are unmeasured, so in an admitted
||| graph no position of the writer's reads one.
|||
||| V, the least family closed under the sites (`InV`), holds every value
||| the theorem bounds. A capped position's type looks only so deep, so the
||| frontend keys it by the value cut there: it holds every value of the
||| cap's height a chain's shape can be, a node with one child at most and
||| no token, and no site into it is listed.
|||
||| The graph covers a site (`CoveredAt`) as `Describes` draws it: an arc from
||| each marker's position weighing at least how much deeper the marker
||| sits in what is written than in its value; for an applied family, an
||| arc as heavy as its arguments are high; for a field, an arc from that
||| field's position of every implementation its record can be, as heavy
||| as the field sits deep; for a member of a choice, an arc from each
||| position its members are read from, as heavy as the member sits deep.
||| K is at least each template's own height. If the potential is also
||| feasible, every value of V at p is within `bound`.
|||
||| The graph builds `Describes` for the model it is drawn from
||| (`Proof.Describes`). What this does not reach is whether a value a
||| request is given is one of V: that is the readers', which read what
||| Idris's evaluator returns (`Idris.Host`), so the worklist checks each
||| request against its bound (`Finite`).
|||
||| Every proof is erased and total, and nothing here runs. The arithmetic is
||| on naturals, a weight being what it adds and what it takes away.
module IdrisMLIR.Proof.Bound

import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Control.Relation
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Parts of a value
------------------------------------------------------------------------------

||| A part of a value d levels down: what a pattern binds at depth d. A
||| head's child is one level down, and so is a run's predecessor: a leaf
||| of height h + 1 is a run of successors whose predecessor is a leaf of
||| height h.
public export
data Sub : Nat -> Template -> Template -> Type where
  Self : Sub 0 v v
  Child : Elem c cs -> Sub d c u -> Sub (S d) (Head a cs) u
  Peel : Sub d (Leaf h) u -> Sub (S d) (Leaf (S h)) u

||| A part of a value at any depth, through heads and a choice's leaves:
||| what a family's value computes with (its meaning, the body under its
||| lambdas) and what a function's value can give (a member of the closed
||| sum its leaves make). Neither is higher than the value.
public export
data Within : Template -> Template -> Type where
  Itself : Within v v
  InChild : Elem c cs -> Within c u -> Within (Head a cs) u
  InChoice : Elem c cs -> Within c u -> Within (Choice s cs) u

||| A template that holds no marker of its writer: no variable, field,
||| member of a choice or applied family. What every instance writes there is no
||| higher than it (`unmarkedWrites`).
mutual
  public export
  data Unmarked : Template -> Type where
    UnmarkedHead : AllUnmarked ts -> Unmarked (Head a ts)
    UnmarkedOpaque : AllUnmarked ts -> Unmarked (Opaque a ts)
    UnmarkedLeaf : Unmarked (Leaf h)
    UnmarkedToken : Unmarked (Token k)
    UnmarkedFormal : Unmarked (Formal j k)
    UnmarkedChoice : AllUnmarked ls -> Unmarked (Choice c ls)

  public export
  data AllUnmarked : List Template -> Type where
    Nil : AllUnmarked []
    (::) : Unmarked t -> AllUnmarked ts -> AllUnmarked (t :: ts)

Uninhabited (Unmarked (Var i d)) where
  uninhabited (UnmarkedHead _) impossible
  uninhabited (UnmarkedOpaque _) impossible
  uninhabited UnmarkedLeaf impossible
  uninhabited UnmarkedToken impossible
  uninhabited UnmarkedFormal impossible
  uninhabited (UnmarkedChoice _) impossible

Uninhabited (Unmarked (Applied i d ts)) where
  uninhabited (UnmarkedHead _) impossible
  uninhabited (UnmarkedOpaque _) impossible
  uninhabited UnmarkedLeaf impossible
  uninhabited UnmarkedToken impossible
  uninhabited UnmarkedFormal impossible
  uninhabited (UnmarkedChoice _) impossible

Uninhabited (Unmarked (Field k r)) where
  uninhabited (UnmarkedHead _) impossible
  uninhabited (UnmarkedOpaque _) impossible
  uninhabited UnmarkedLeaf impossible
  uninhabited UnmarkedToken impossible
  uninhabited UnmarkedFormal impossible
  uninhabited (UnmarkedChoice _) impossible

Uninhabited (Unmarked (Member k)) where
  uninhabited (UnmarkedHead _) impossible
  uninhabited (UnmarkedOpaque _) impossible
  uninhabited UnmarkedLeaf impossible
  uninhabited UnmarkedToken impossible
  uninhabited UnmarkedFormal impossible
  uninhabited (UnmarkedChoice _) impossible

------------------------------------------------------------------------------
-- Beta of a family's value
------------------------------------------------------------------------------

||| What beta makes of a family's meaning at its arguments' values: each
||| argument of the value (`Formal j`) the j-th of them, and an argument
||| applied to closed arguments as many as it takes, beta of that
||| argument's own meaning at them. An argument applied to what holds
||| another computes from it, and the reading says so (`Computing`), so no
||| rule states it.
mutual
  public export
  data Instantiates : List Template -> Template -> Template -> Type where
    IFormal : (j : Fin (length ws)) -> Instantiates ws (Formal (finToNat j) k) (index' ws j)
    IApplied : (j : Fin (length ws)) -> Within (index' ws j) body -> Instantiates as body w ->
               Instantiates ws (Head Nothing (Formal (finToNat j) k :: as)) w
    IHead : AllInstantiate ws ts us -> Instantiates ws (Head a ts) (Head a us)
    IOpaque : AllInstantiate ws ts us -> Instantiates ws (Opaque a ts) (Opaque a us)
    ILeaf : Instantiates ws (Leaf h) (Leaf h)
    IToken : Instantiates ws (Token n) (Token n)
    IChosen : Elem x ls -> Instantiates ws x w -> Instantiates ws (Choice c ls) w

  public export
  data AllInstantiate : List Template -> List Template -> List Template -> Type where
    Nil : AllInstantiate ws [] []
    (::) : Instantiates ws t u -> AllInstantiate ws ts us -> AllInstantiate ws (t :: ts) (u :: us)

------------------------------------------------------------------------------
-- Holes renumbered, constants computed
------------------------------------------------------------------------------

mutual
  ||| A template with its hole tokens renumbered: every node the same, each
  ||| token's weight any. A held dispatch's arm renumbers the holes of the
  ||| member it holds after the ones it holds already.
  public export
  data Renumbered : Template -> Template -> Type where
    TokenRenumbered : Renumbered (Token k) (Token k')
    HeadRenumbered : AllRenumbered ts us -> Renumbered (Head a ts) (Head a us)
    OpaqueRenumbered : AllRenumbered ts us -> Renumbered (Opaque a ts) (Opaque a us)
    AppliedRenumbered : AllRenumbered ts us -> Renumbered (Applied i d ts) (Applied i d us)
    ComputingRenumbered : AllRenumbered ts us -> Renumbered (Computing i d ts) (Computing i d us)
    ChoiceRenumbered : Renumbered c c' -> AllRenumbered ts us -> Renumbered (Choice c ts) (Choice c' us)
    FieldRenumbered : Renumbered r r' -> Renumbered (Field k r) (Field k r')
    AsItWas : Renumbered t t

  public export
  data AllRenumbered : List Template -> List Template -> Type where
    NoneRenumbered : AllRenumbered [] []
    EachRenumbered : Renumbered t u -> AllRenumbered ts us -> AllRenumbered (t :: ts) (u :: us)

mutual
  ||| Renumbering holes keeps every height.
  export
  0 renumberedHeight : Renumbered v w -> height w = height v
  renumberedHeight TokenRenumbered = Refl
  renumberedHeight (HeadRenumbered xs) = cong S (allRenumberedHeight xs)
  renumberedHeight (OpaqueRenumbered xs) = cong S (allRenumberedHeight xs)
  renumberedHeight (AppliedRenumbered xs) = cong S (allRenumberedHeight xs)
  renumberedHeight (ComputingRenumbered xs) = cong S (allRenumberedHeight xs)
  renumberedHeight (ChoiceRenumbered _ xs) = allRenumberedHeight xs
  renumberedHeight (FieldRenumbered _) = Refl
  renumberedHeight AsItWas = Refl

  0 allRenumberedHeight : AllRenumbered ts us -> tallest us = tallest ts
  allRenumberedHeight NoneRenumbered = Refl
  allRenumberedHeight (EachRenumbered x xs) = cong2 maximum (renumberedHeight x) (allRenumberedHeight xs)

||| What a constant's template is (`Template.constant`): one token, one
||| leaf, or a node with a leaf per character.
public export
data ConstantForm : Template -> Type where
  CountedForm : ConstantForm (Token k)
  LeafForm : ConstantForm (Leaf 1)
  SpeltForm : All (\c => c = Leaf 1) cs -> ConstantForm (Head Nothing cs)

0 speltBelow : All (\c => c = Leaf 1) cs -> LTE (tallest cs) 1
speltBelow [] = LTEZero
speltBelow (Refl :: rest) = leafAbove (speltBelow rest)
  where
    leafAbove : LTE t 1 -> LTE (maximum 1 t) 1
    leafAbove {t = Z} _ = lteRefl
    leafAbove {t = S Z} _ = lteRefl
    leafAbove {t = S (S _)} (LTESucc le) = absurd le

||| A constant is no higher than two.
export
0 constantHeight : ConstantForm w -> LTE (height w) 2
constantHeight CountedForm = lteSuccRight lteRefl
constantHeight LeafForm = lteSuccRight lteRefl
constantHeight (SpeltForm leaves) = LTESucc (speltBelow leaves)

------------------------------------------------------------------------------
-- The sites and what an instance writes
------------------------------------------------------------------------------

||| One argument the graph reads: the position it lands at, the template
||| written there, the position the writer's node reads each parameter the
||| template holds at, and the implementations the flow found each
||| dictionary the template holds can be, at the writer's node.
public export
record Site (n : Nat) where
  constructor MkSite
  target : Fin n
  template : Template
  writers : List (Nat, Fin n)
  roots : Template -> List Address

||| What the theorem reads of the program besides its graph: the sites;
||| the position of each implementation's field k (none, or one), which a
||| site writes the field's template at, over the implementation's own
||| parameters (a constructor's field k is its argument k); the positions
||| a member of each choice is read from: its head's (none, or one), which
||| every place that makes a member of it writes the member at, and the
||| unshown head's, or, for the unshown head, every choice's; what each
||| other position is a parameter of (a definition, or the application at
||| a use) and which, nothing for a field's or a choice's; and the
||| positions of each definition's nodes.
public export
record Model (g : Graph) where
  constructor MkModel
  sites : List (Site g.size)
  fieldPositions : Address -> Nat -> List (Fin g.size)
  choicePositions : ChoiceHead -> List (Fin g.size)
  positionOf : Fin g.size -> Maybe (Head, Nat)
  positionsOf : Address -> List (Fin g.size)

mutual
  ||| V: the values each position can receive, the least family closed
  ||| under the sites.
  public export
  data InV : {g : Graph} -> (m : Model g) -> Fin g.size -> Template -> Type where
    ||| A site writes what an instance makes of its template.
    Reduced : (s : Site g.size) -> Elem s m.sites -> Writes m s s.template w -> InV m s.target w
    ||| A capped position holds every value of the cap's height a chain's
    ||| shape can be: no node with more than one child, no token.
    Capped : index p g.caps = Just c -> LTE (height v) c -> LTE (arity v) 1 -> LTE (heaviest v) 0 -> InV m p v

  ||| What an instance writes where a site's template reads.
  public export
  data Writes : {g : Graph} -> (m : Model g) -> Site g.size -> Template -> Template -> Type where
    AtVar : Elem (i, p) s.writers -> InV m p v -> Sub d v w -> Writes m s (Var i d) w
    AtHead : AllWrite m s ts ws -> Writes m s (Head a ts) (Head a ws)
    AtOpaque : AllWrite m s ts ws -> Writes m s (Opaque a ts) (Opaque a ws)
    AtLeaf : Writes m s (Leaf h) (Leaf h)
    ||| A leaf two high, where a builtin is applied to the writer's markers:
    ||| the constant it computes at an instance whose values are constants.
    AtComputed : ConstantForm w -> Writes m s (Leaf 2) w
    AtToken : Writes m s (Token k) (Token k)
    AtFormal : Writes m s (Formal j k) (Formal j k)
    Chosen : Elem x ls -> Writes m s x w -> Writes m s (Choice c ls) w
    Beta : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f body -> AllWrite m s ts ws ->
           Instantiates ws body w -> Writes m s (Applied i d ts) w
    GivenPart : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f w -> Writes m s (Applied i d ts) w
    MemberOf : Elem j (s.roots (Applied i d ts)) -> Arguments m j 0 as ->
               Writes m s (Applied i d ts) (Head (Just j) as)
    Landed : LTE (height f) k -> Within f body -> AllWrite m s ts ws ->
             Instantiates ws body w -> Writes m s (raise k (Head Nothing ts)) w
    LandedMember : LTE (height f) k -> Within f w -> Writes m s (raise k (Head Nothing ts)) w
    AtField : Elem j (s.roots r) -> Elem p (m.fieldPositions j k) -> InV m p w -> Writes m s (Field k r) w
    ||| A member of the choice, as a place that makes one made it, its holes
    ||| renumbered as the reader holds it.
    AtMember : Elem p (m.choicePositions k) -> InV m p v -> Renumbered v w -> Writes m s (Member k) w
    ||| A hole where a site reads a member of the choice: one node, no
    ||| higher than a member made there.
    AtHeldHole : Elem p (m.choicePositions k) -> InV m p v -> LTE 1 (height v) -> Writes m s (Member k) (Token n)

  public export
  data AllWrite : {g : Graph} -> (m : Model g) -> Site g.size -> List Template -> List Template -> Type where
    Nil : AllWrite m s [] []
    (::) : Writes m s t w -> AllWrite m s ts ws -> AllWrite m s (t :: ts) (w :: ws)

  ||| An implementation's arguments from parameter q on, each a value a
  ||| position of one of its nodes received at that parameter.
  public export
  data Arguments : {g : Graph} -> (m : Model g) -> Address -> Nat -> List Template -> Type where
    Ended : Arguments m j q []
    Given : (p : Fin g.size) -> Elem p (m.positionsOf j) -> m.positionOf p = Just (ADefinition j, q) -> InV m p a ->
            Arguments m j (S q) as -> Arguments m j q (a :: as)

------------------------------------------------------------------------------
-- What the graph says of a site
------------------------------------------------------------------------------

||| An arc from position p carries a part matched d deep to the site's
||| target, where it sits e deep: its weight is at least e - d.
public export
data Carries : (g : Graph) -> Fin g.size -> (d, e : Nat) -> Fin g.size -> Type where
  MkCarries : Elem (MkArc p q (Measured gain loss)) g.arcs -> LTE (e + loss) (d + gain) -> Carries g p d e q

mutual
  ||| What the graph says of a part of a site's template e deep.
  public export
  data CoveredAt : {g : Graph} -> (m : Model g) -> Site g.size -> Nat -> Template -> Type where
    CVar : ((p : Fin g.size) -> Elem (i, p) s.writers -> Carries g p d e s.target) -> CoveredAt m s e (Var i d)
    CHead : AllCovered m s (S e) ts -> CoveredAt m s e (Head a ts)
    COpaque : AllCovered m s (S e) ts -> CoveredAt m s e (Opaque a ts)
    CLeaf : CoveredAt m s e (Leaf h)
    CToken : CoveredAt m s e (Token k)
    CFormal : CoveredAt m s e (Formal j k)
    CChoice : AllCovered m s e ls -> CoveredAt m s e (Choice c ls)
    CApplied : ((p : Fin g.size) -> Elem (i, p) s.writers -> (Carries g p d (e + tallest ts) s.target, AllUnmarked ts)) ->
               ((j : Address) -> Elem j (s.roots (Applied i d ts)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                Carries g p' 0 (S e) s.target) ->
               CoveredAt m s e (Applied i d ts)
    ||| A family that computes from what it is given writes nothing any
    ||| rule states, so the graph says of it only that no position of the
    ||| writer's reads it.
    CComputing : ((p : Fin g.size) -> Elem (i, p) s.writers -> Void) -> CoveredAt m s e (Computing i d ts)
    CField : ((j : Address) -> Elem j (s.roots r) -> (p : Fin g.size) -> Elem p (m.fieldPositions j k) ->
              Carries g p 0 e s.target) ->
             CoveredAt m s e (Field k r)
    CMember : ((p : Fin g.size) -> Elem p (m.choicePositions k) -> Carries g p 0 e s.target) ->
              CoveredAt m s e (Member k)

  public export
  data AllCovered : {g : Graph} -> (m : Model g) -> Site g.size -> Nat -> List Template -> Type where
    Nil : AllCovered m s e []
    (::) : CoveredAt m s e t -> AllCovered m s e ts -> AllCovered m s e (t :: ts)

||| What the graph says of a site: its target is uncapped, K is at least its
||| template's own height, and it covers the template.
public export
record Covers (g : Graph) (m : Model g) (s : Site g.size) where
  constructor MkCovers
  uncapped : index s.target g.caps = Nothing
  constant : LTE (height s.template) g.constant
  covered : CoveredAt m s 0 s.template

||| The graph says what the sites write: it covers every site. A capped
||| position's cap is the graph's own (`caps`), which a feasible potential
||| meets.
public export
Describes : {g : Graph} -> Model g -> Type
Describes {g} m = All (Covers g m) m.sites

||| Only closed values no higher than k land at a position: it is uncapped,
||| and every site into it writes an unmarked template no higher than k.
||| Where this holds of a family's position, its applied readings are
||| `Landed` (`landed`).
public export
record Lands (g : Graph) (m : Model g) (p : Fin g.size) (k : Nat) where
  constructor MkLands
  uncapped : index p g.caps = Nothing
  under : (s : Site g.size) -> Elem s m.sites -> s.target = p -> (Unmarked s.template, LTE (height s.template) k)

------------------------------------------------------------------------------
-- The arithmetic
------------------------------------------------------------------------------

0 lteL : x = x' -> LTE x y -> LTE x' y
lteL Refl le = le

0 lteR : y = y' -> LTE x y -> LTE x y'
lteR Refl le = le

-- Base states only that `maximum` is above both arguments; the induction
-- needs that it is the least such.
0 maxLub : {a, c : Nat} -> LTE a b -> LTE c b -> LTE (maximum a c) b
maxLub {a = Z} _ lc = lc
maxLub {a = S _} {c = Z} la _ = la
maxLub {a = S a} {c = S c} (LTESucc la) (LTESucc lc) = LTESucc (maxLub la lc)

0 maxMono : {a, a', c, c' : Nat} -> LTE a a' -> LTE c c' -> LTE (maximum a c) (maximum a' c')
maxMono la lc = maxLub (transitive la (maximumLeftUpperBound _ _)) (transitive lc (maximumRightUpperBound _ _))

-- Two bounds below one, each with the same depth added.
0 maxPlus : {a, a', c, b : Nat} -> LTE (a + c) b -> LTE (a' + c) b -> LTE (maximum a a' + c) b
maxPlus {a = Z} _ r = r
maxPlus {a = S x} {a' = Z} l _ = l
maxPlus {a = S x} {a' = S y} {c} l r =
  rewrite plusSuccRightSucc (maximum x y) c in
    maxPlus {a = x} {a' = y} {c = S c} (rewrite sym (plusSuccRightSucc x c) in l)
                                       (rewrite sym (plusSuccRightSucc y c) in r)

-- Two bounds each with the same amount added.
0 maxPlusMono : {a, b, x, y, c : Nat} -> LTE a (x + c) -> LTE b (y + c) -> LTE (maximum a b) (maximum x y + c)
maxPlusMono la lb =
  maxLub (transitive la (plusLteMonotoneRight c x (maximum x y) (maximumLeftUpperBound x y)))
         (transitive lb (plusLteMonotoneRight c y (maximum x y) (maximumRightUpperBound x y)))

-- Base cancels a sum only in an equation, not in an inequality.
0 lteCancelLeft : (c : Nat) -> LTE (c + a) (c + b) -> LTE a b
lteCancelLeft Z le = le
lteCancelLeft (S c) (LTESucc le) = lteCancelLeft c le

0 lteCancelRight : {a, b : Nat} -> (c : Nat) -> LTE (a + c) (b + c) -> LTE a b
lteCancelRight c le = lteCancelLeft c (rewrite plusCommutative c a in rewrite plusCommutative c b in le)

-- The induction's step, every difference written as a sum on both sides:
-- a part of height h, d deep in a value within k + q, sits e deep in what
-- is written; the arc weighs gain less loss, at least e less d; and the
-- potential satisfies the arc, q + gain within p + loss. Then h + e is
-- within k + p.
0 carry : {h, d, k, q, e, loss, gain, p : Nat} ->
          LTE (h + d) (k + q) -> LTE (e + loss) (d + gain) -> LTE (q + gain) (p + loss) ->
          LTE (h + e) (k + p)
carry hd el qg =
  lteCancelRight loss $
    lteL (plusAssociative h e loss) $
    lteR (plusAssociative k p loss) $
    transitive (plusLteMonotoneLeft h (e + loss) (d + gain) el) $
    lteL (sym (plusAssociative h d gain)) $
    transitive (plusLteMonotoneRight gain (h + d) (k + q) hd) $
    lteL (plusAssociative k q gain) $
    plusLteMonotoneLeft k (q + gain) (p + loss) qg

-- c heads above a template stand c above it.
0 raisedHeight : (c : Nat) -> (t : Template) -> height (raise c t) = c + height t
raisedHeight Z t = Refl
raisedHeight (S c) t = cong S (trans (maximumZeroNLeft _) (raisedHeight c t))

-- An applied family's reading k heads above its arguments, e deep: its
-- arguments k + 1 deeper.
0 raisedAt : (k : Nat) -> (ts : List Template) -> (e : Nat) ->
             height (raise k (Head Nothing ts)) + e = tallest ts + S (k + e)
raisedAt k ts e =
  trans (cong (+ e) (raisedHeight k (Head Nothing ts)))
        (trans (cong (+ e) (sym (plusSuccRightSucc k (tallest ts))))
               (trans (cong S (trans (cong (+ e) (plusCommutative k (tallest ts)))
                                     (sym (plusAssociative (tallest ts) k e))))
                      (plusSuccRightSucc (tallest ts) (k + e))))

-- Beta of a value no higher than k at arguments, e deep: below the
-- arguments, k + 1 deeper.
0 landedArith : {x, k, t, e : Nat} -> LTE x (k + t) -> LTE (x + e) (t + S (k + e))
landedArith le =
  lteR (plusSuccRightSucc t (k + e)) $
    lteSuccRight (lteR (trans (cong (+ e) (plusCommutative k t)) (sym (plusAssociative t k e)))
                       (plusLteMonotoneRight e x (k + t) le))

-- An applied family's value e deep: no higher than beta's bound, its
-- value carried by the arc as heavy as its arguments are high.
0 appliedWithin : {x, hf, t, e, b : Nat} -> LTE (hf + (e + t)) b -> LTE x (hf + t) -> LTE (x + e) b
appliedWithin reach high =
  transitive (plusLteMonotoneRight e x (hf + t) high)
             (lteL (trans (cong (hf +) (plusCommutative e t)) (plusAssociative hf t e)) reach)

------------------------------------------------------------------------------
-- Heights
------------------------------------------------------------------------------

0 tallestAbove : Elem t ts -> LTE (height t) (tallest ts)
tallestAbove Here = maximumLeftUpperBound _ _
tallestAbove (There el) = transitive (tallestAbove el) (maximumRightUpperBound _ _)

0 tallestIndex : (ws : List Template) -> (j : Fin (length ws)) -> LTE (height (index' ws j)) (tallest ws)
tallestIndex [] j = absurd j
tallestIndex (w :: ws) FZ = maximumLeftUpperBound _ _
tallestIndex (w :: ws) (FS j) = transitive (tallestIndex ws j) (maximumRightUpperBound _ _)

||| Lemma 1, the pattern's half: a part d levels down is at least d lower.
export
0 subHeight : Sub d v u -> LTE (height u + d) (height v)
subHeight {u} Self = rewrite plusZeroRightNeutral (height u) in reflexive
subHeight {u} {d = S d} (Child el s) =
  rewrite sym (plusSuccRightSucc (height u) d) in LTESucc (transitive (subHeight s) (tallestAbove el))
subHeight {u} {d = S d} (Peel s) =
  rewrite sym (plusSuccRightSucc (height u) d) in LTESucc (subHeight s)

||| A part of a value is no higher than it.
export
0 withinHeight : Within v u -> LTE (height u) (height v)
withinHeight Itself = reflexive
withinHeight (InChild el w) = transitive (withinHeight w) (lteSuccRight (tallestAbove el))
withinHeight (InChoice el w) = transitive (withinHeight w) (tallestAbove el)

mutual
  ||| Beta's bound: what beta makes of a meaning is no higher than the
  ||| meaning above its tallest argument.
  export
  0 instHeight : Instantiates ws t w -> LTE (height w) (height t + tallest ws)
  instHeight {ws} (IFormal j) = lteSuccRight (tallestIndex ws j)
  instHeight {ws} (IApplied {as} j wb inner) =
    lteR (plusCommutative (tallest ws) (S (maximum 1 (tallest as)))) $
      transitive (transitive (instHeight inner)
                             (plusLteMonotoneRight (tallest as) _ (tallest ws)
                                (transitive (withinHeight wb) (tallestIndex ws j))))
                 (plusLteMonotoneLeft (tallest ws) (tallest as) (S (maximum 1 (tallest as)))
                    (lteSuccRight (maximumRightUpperBound 1 (tallest as))))
  instHeight (IHead xs) = LTESucc (allInstHeight xs)
  instHeight (IOpaque xs) = LTESucc (allInstHeight xs)
  instHeight ILeaf = lteAddRight _
  instHeight IToken = lteAddRight _
  instHeight (IChosen el x) = transitive (instHeight x) (plusLteMonotoneRight _ _ _ (tallestAbove el))

  0 allInstHeight : AllInstantiate ws ts us -> LTE (tallest us) (tallest ts + tallest ws)
  allInstHeight [] = LTEZero
  allInstHeight (x :: xs) = maxPlusMono (instHeight x) (allInstHeight xs)

0 unmarkedHead : Unmarked (Head a ts) -> AllUnmarked ts
unmarkedHead (UnmarkedHead us) = us

0 unmarkedOpaque : Unmarked (Opaque a ts) -> AllUnmarked ts
unmarkedOpaque (UnmarkedOpaque us) = us

0 unmarkedChoice : Unmarked (Choice c ls) -> AllUnmarked ls
unmarkedChoice (UnmarkedChoice us) = us

0 unmarkedRaise : (k : Nat) -> Unmarked (raise k t) -> Unmarked t
unmarkedRaise Z u = u
unmarkedRaise (S k) u = case unmarkedHead u of
  (x :: _) => unmarkedRaise k x

0 unmarkedAt : Elem t ts -> AllUnmarked ts -> Unmarked t
unmarkedAt Here (u :: _) = u
unmarkedAt (There el) (_ :: us) = unmarkedAt el us

mutual
  ||| What an instance writes at an unmarked template is no higher than it:
  ||| an applied family's reading there stands above what beta makes.
  export
  0 unmarkedWrites : Unmarked t -> Writes m s t w -> LTE (height w) (height t)
  unmarkedWrites u (AtVar _ _ _) = absurd u
  unmarkedWrites u (AtHead xs) = LTESucc (unmarkedAll (unmarkedHead u) xs)
  unmarkedWrites u (AtOpaque xs) = LTESucc (unmarkedAll (unmarkedOpaque u) xs)
  unmarkedWrites u AtLeaf = reflexive
  unmarkedWrites u (AtComputed form) = constantHeight form
  unmarkedWrites u AtToken = reflexive
  unmarkedWrites u AtFormal = reflexive
  unmarkedWrites u (Chosen el x) =
    transitive (unmarkedWrites (unmarkedAt el (unmarkedChoice u)) x) (tallestAbove el)
  unmarkedWrites u (Beta _ _ _ _ _ _) = absurd u
  unmarkedWrites u (GivenPart _ _ _ _) = absurd u
  unmarkedWrites u (MemberOf _ _) = absurd u
  unmarkedWrites u (Landed {k} {ts} {ws} hf wb xs inst) =
    lteR (sym (raisedHeight k (Head Nothing ts))) $
      transitive (instHeight inst)
        (transitive (plusLteMonotone (transitive (withinHeight wb) hf)
                                     (unmarkedAll (unmarkedHead (unmarkedRaise k u)) xs))
                    (plusLteMonotoneLeft k (tallest ts) (S (tallest ts)) (lteSuccRight reflexive)))
  unmarkedWrites u (LandedMember {k} {ts} hf wm) =
    lteR (sym (raisedHeight k (Head Nothing ts))) (transitive (transitive (withinHeight wm) hf) (lteAddRight k))
  unmarkedWrites u (AtField _ _ _) = absurd u
  unmarkedWrites u (AtMember _ _ _) = absurd u
  unmarkedWrites u (AtHeldHole _ _ _) = absurd u

  0 unmarkedAll : AllUnmarked ts -> AllWrite m s ts ws -> LTE (tallest ws) (tallest ts)
  unmarkedAll [] [] = LTEZero
  unmarkedAll (u :: us) (x :: xs) = maxMono (unmarkedWrites u x) (unmarkedAll us xs)


------------------------------------------------------------------------------
-- The bound
------------------------------------------------------------------------------

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

0 arcHolds : Feasible g pot -> Elem (MkArc q p (Measured gain loss)) g.arcs ->
             LTE (index q pot + gain) (index p pot + loss)
arcHolds (MkFeasible sat _) el = case indexAll el sat of MkSatisfies le => le

0 capHolds : Feasible g pot -> (p : Fin g.size) -> index p g.caps = Just c -> LTE c (g.constant + index p pot)
capHolds (MkFeasible _ caps) p cap = capAt caps p cap

-- A value of V at p, with a part d deep of it: the part stands within the
-- bound at p, uncapped, less d.
0 partBelow : {g : Graph} -> {pot : Vect g.size Nat} -> {p : Fin g.size} ->
              LTE (height v) (bound g pot p) -> Sub d v u -> LTE (height u + d) (g.constant + index p pot)
partBelow {g} {pot} {p} bv sub = transitive (subHeight sub) (transitive bv (boundBelow g pot p))

------------------------------------------------------------------------------
-- What the graph says, read back
------------------------------------------------------------------------------

0 coveredVar : CoveredAt m s e (Var i d) -> (p : Fin g.size) -> Elem (i, p) s.writers -> Carries g p d e s.target
coveredVar (CVar c) = c

0 coveredHead : CoveredAt m s e (Head a ts) -> AllCovered m s (S e) ts
coveredHead (CHead cs) = cs

0 coveredOpaque : CoveredAt m s e (Opaque a ts) -> AllCovered m s (S e) ts
coveredOpaque (COpaque cs) = cs

0 coveredChoice : CoveredAt m s e (Choice c ls) -> AllCovered m s e ls
coveredChoice (CChoice cs) = cs

0 coveredApplied : CoveredAt m s e (Applied i d ts) ->
                   ( (p : Fin g.size) -> Elem (i, p) s.writers -> (Carries g p d (e + tallest ts) s.target, AllUnmarked ts)
                   , (j : Address) -> Elem j (s.roots (Applied i d ts)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                     Carries g p' 0 (S e) s.target )
coveredApplied (CApplied c arcs) = (c, arcs)

0 coveredField : CoveredAt m s e (Field k r) ->
                 (j : Address) -> Elem j (s.roots r) -> (p : Fin g.size) -> Elem p (m.fieldPositions j k) ->
                 Carries g p 0 e s.target
coveredField (CField arcs) = arcs

0 coveredMember : CoveredAt m s e (Member k) ->
                  (p : Fin g.size) -> Elem p (m.choicePositions k) -> Carries g p 0 e s.target
coveredMember (CMember arcs) = arcs

0 coveredRaise : {e : Nat} -> (k : Nat) -> CoveredAt m s e (raise k t) -> CoveredAt m s (k + e) t
coveredRaise Z c = c
coveredRaise {e} (S k) c = case coveredHead c of
  (c' :: []) => rewrite plusSuccRightSucc k e in coveredRaise k c'

0 coveredIn : Elem x ls -> AllCovered m s e ls -> CoveredAt m s e x
coveredIn Here (c :: _) = c
coveredIn (There i) (_ :: cs) = coveredIn i cs

------------------------------------------------------------------------------
-- Theorem 1
------------------------------------------------------------------------------

mutual
  ||| Theorem 1: under a feasible potential, every value a position can
  ||| receive is within its bound.
  export
  0 bounded : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {p : Fin g.size} -> {v : Template} ->
              Describes m -> Feasible g pot -> InV m p v -> LTE (height v) (bound g pot p)
  bounded ds fe (Capped cap le _ _) = boundCapped cap le (transitive le (capHolds fe _ cap))
  bounded ds fe (Reduced s el wr) =
    let cov = indexAll el ds in
    rewrite boundUncapped {g} {pot} {p = s.target} cov.uncapped in
      lteL (plusZeroRightNeutral _) $
        writtenAt ds fe wr cov.covered
          (lteL (sym (plusZeroRightNeutral _)) (transitive cov.constant (lteAddRight _)))

  -- Lemma 1, by induction on what an instance writes: a part of a site's
  -- template e deep, within K above the target's potential, writes what
  -- stays there.
  0 writtenAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} ->
                {t, w : Template} -> {e : Nat} ->
                Describes m -> Feasible g pot -> Writes m s t w -> CoveredAt m s e t ->
                LTE (height t + e) (g.constant + index s.target pot) ->
                LTE (height w + e) (g.constant + index s.target pot)
  writtenAt ds fe (AtVar {p} wa iv sub) cov hp = case coveredVar cov p wa of
    MkCarries arc wt => carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc)
  writtenAt {e} ds fe (AtHead {ts} {ws} xs) cov hp =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      allWrittenAt ds fe xs (coveredHead cov) (lteL (plusSuccRightSucc (tallest ts) e) hp)
  writtenAt {e} ds fe (AtOpaque {ts} {ws} xs) cov hp =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      allWrittenAt ds fe xs (coveredOpaque cov) (lteL (plusSuccRightSucc (tallest ts) e) hp)
  writtenAt ds fe AtLeaf cov hp = hp
  writtenAt {e} ds fe (AtComputed form) cov hp = transitive (plusLteMonotoneRight e _ 2 (constantHeight form)) hp
  writtenAt ds fe AtToken cov hp = hp
  writtenAt ds fe AtFormal cov hp = hp
  writtenAt ds fe (Chosen el x) cov hp =
    writtenAt ds fe x (coveredIn el (coveredChoice cov)) (transitive (plusLteMonotoneRight _ _ _ (tallestAbove el)) hp)
  writtenAt {e} ds fe (Beta {p} {f} {ts} {ws} wa iv sub wb xs inst) cov hp = case coveredApplied cov of
    (writes, _) => case writes p wa of
      (MkCarries arc wt, us) =>
        appliedWithin (carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc))
          (transitive (instHeight inst) (plusLteMonotone (withinHeight wb) (unmarkedAll us xs)))
  writtenAt {e} ds fe (GivenPart {p} {f} {ts} wa iv sub wm) cov hp = case coveredApplied cov of
    (writes, _) => case writes p wa of
      (MkCarries arc wt, _) =>
        appliedWithin (carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc))
          (transitive (withinHeight wm) (lteAddRight (height f)))
  writtenAt {e} ds fe (MemberOf {ts} {as} el args) cov hp = case coveredApplied cov of
    (_, arcs) =>
      lteL (sym (plusSuccRightSucc (tallest as) e)) $
        heldWithin ds fe args (arcs _ el)
          (transitive (LTESucc (plusLteMonotoneRight e 0 (tallest ts) LTEZero)) hp)
  writtenAt {e} ds fe (Landed {k} {ts} {ws} hf wb xs inst) cov hp =
    transitive (landedArith (transitive (instHeight inst)
                                        (plusLteMonotoneRight (tallest ws) _ k (transitive (withinHeight wb) hf))))
               (allWrittenAt ds fe xs (coveredHead (coveredRaise k cov)) (lteL (raisedAt k ts e) hp))
  writtenAt {e} ds fe (LandedMember {k} {ts} hf wm) cov hp =
    transitive (landedArith (transitive (transitive (withinHeight wm) hf) (lteAddRight k)))
               (lteL (raisedAt k ts e) hp)
  -- A field writes what its position received, carried from there as a
  -- part of it no deeper than itself.
  writtenAt ds fe (AtField {p} el inField iv) cov hp = case coveredField cov _ el p inField of
    MkCarries arc wt => carry (partBelow (bounded ds fe iv) Self) wt (arcHolds fe arc)
  -- A member of a choice writes what a position its members are read
  -- from received, carried from there as a field's value is; renumbering
  -- its holes keeps its height.
  writtenAt {e} ds fe (AtMember {p} inChoice iv again) cov hp = case coveredMember cov p inChoice of
    MkCarries arc wt =>
      lteL (cong (+ e) (sym (renumberedHeight again))) (carry (partBelow (bounded ds fe iv) Self) wt (arcHolds fe arc))
  -- A hole in a member's place is one node, carried as the member is.
  writtenAt {e} ds fe (AtHeldHole {p} {v} inChoice iv one) cov hp = case coveredMember cov p inChoice of
    MkCarries arc wt =>
      transitive (plusLteMonotoneRight e 1 (height v) one) (carry (partBelow (bounded ds fe iv) Self) wt (arcHolds fe arc))

  -- A head's children, one deeper.
  0 allWrittenAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e : Nat} ->
                   Describes m -> Feasible g pot -> AllWrite m s ts ws -> AllCovered m s (S e) ts ->
                   LTE (tallest ts + S e) (g.constant + index s.target pot) ->
                   LTE (tallest ws + S e) (g.constant + index s.target pot)
  allWrittenAt ds fe [] [] hp = hp
  allWrittenAt {e} ds fe (x :: xs) (c :: cs) hp =
    maxPlus (writtenAt ds fe x c (transitive (plusLteMonotoneRight (S e) _ _ (maximumLeftUpperBound _ _)) hp))
            (allWrittenAt ds fe xs cs (transitive (plusLteMonotoneRight (S e) _ _ (maximumRightUpperBound _ _)) hp))

  -- The arguments of an implementation an applied function gives, one
  -- deeper than it, each carried from the position of the implementation
  -- that received it.
  0 heldWithin : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e : Nat} ->
                 Describes m -> Feasible g pot -> Arguments m j q as ->
                 ((p' : Fin g.size) -> Elem p' (m.positionsOf j) -> Carries g p' 0 (S e) s.target) ->
                 LTE (S e) (g.constant + index s.target pot) ->
                 LTE (tallest as + S e) (g.constant + index s.target pot)
  heldWithin ds fe Ended arcs one = one
  heldWithin {g} {pot} ds fe (Given p' inJ at iv rest) arcs one =
    maxPlus (case arcs p' inJ of
               MkCarries arc wt =>
                 carry (lteL (sym (plusZeroRightNeutral _)) (transitive (bounded ds fe iv) (boundBelow g pot p')))
                       wt (arcHolds fe arc))
            (heldWithin ds fe rest arcs one)

||| What lands at a position where only closed values no higher than k
||| land is no higher than k: where a family's value is read from such a
||| position, its applied readings are `Landed`.
export
0 landed : {g : Graph} -> {m : Model g} -> {p : Fin g.size} -> {v : Template} ->
           Lands g m p k -> InV m p v -> LTE (height v) k
landed l (Capped cap _ _ _) = absurd (trans (sym cap) l.uncapped)
landed l (Reduced s el wr) = case l.under s el Refl of
  (u, le) => transitive (unmarkedWrites u wr) le
