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
|||   part of its value (`Member`), or one its definition's leaves give,
|||   which the flow found, applied to values its own positions received
|||   (`MemberOf`), carried as a held dictionary is;
||| - a family applied where only closed values no higher than k land is
|||   read as k heads above its arguments (`raise k`), and writes beta, or a
|||   member, of a value no higher than k (`Landed`, `LandedMember`);
||| - a field of a dictionary writes the field template of the
|||   implementation the dictionary is, over that implementation's
|||   arguments (`AtField`), and a dictionary held in a value is an
|||   implementation the flow found, applied to values its own positions
|||   received (`AtHeld`).
||| A family that computes from what it is given (`Computing`) writes
||| nothing any rule states: its arcs are unmeasured, so in an admitted
||| graph no position of the writer's reads one.
|||
||| V, the least family closed under the sites (`InV`), holds every value
||| the theorem bounds. A capped position's type looks only so deep, so the
||| frontend keys it by the value cut there: it holds every value of the
||| cap's height, and no site into it is listed.
|||
||| The graph covers a site (`CoveredAt`) as `Describes` draws it: an arc from
||| each marker's position weighing at least how much deeper the marker
||| sits in what is written than in its value; for an applied family, an
||| arc as heavy as its arguments are high; for a field, K above the field
||| templates' closed parts, and its record placed as deep as they hold the
||| record's arguments (their `reach`), with K above the record there, or
||| nothing of the record where they hold none; for a held dictionary, an
||| arc from every position of every implementation it can be. K is at
||| least each template's own height. If the potential is also feasible,
||| every value of V at p is within `bound`.
|||
||| The graph builds `Describes` for the model it is drawn from
||| (`Proof.Describes`). What this does not reach is whether a value a
||| request is given is one of V: that is the readers', which read what
||| Idris's evaluator returns (`Idris.Host`), so the worklist checks each
||| request against its bound (`Finite`).
|||
||| Every proof is erased and total, and nothing here runs. The arithmetic is
||| on naturals, a depth below its record being what it adds and what it
||| takes away.
module IdrisMLIR.Proof.Bound

import IdrisMLIR.Proof.Growth
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

||| A template occurs e levels down in another: through a head's or a
||| recursion's children, one level each, and a choice's leaves, none.
public export
data OccursAt : Template -> Nat -> Template -> Type where
  Top : OccursAt t 0 t
  BelowHead : Elem c cs -> OccursAt x e c -> OccursAt x (S e) (Head a cs)
  BelowOpaque : Elem c cs -> OccursAt x e c -> OccursAt x (S e) (Opaque a cs)
  InLeafOf : Elem c cs -> OccursAt x e c -> OccursAt x e (Choice s cs)

||| A template that holds no marker of its writer: no variable, field, held
||| dictionary or applied family. What every instance writes there is no
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

Uninhabited (Unmarked (Held c p)) where
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
||| each implementation's field templates, over its own parameters as
||| markers at depth 0 (a constructor's field k is its argument k); the
||| definition and parameter each position is; and the positions of each
||| definition's nodes.
public export
record Model (g : Graph) where
  constructor MkModel
  sites : List (Site g.size)
  fields : Address -> Nat -> Maybe Template
  positionOf : Fin g.size -> (Address, Nat)
  positionsOf : Address -> List (Fin g.size)

||| Where a template's markers take their values: from what the site's
||| writer received, or from the arguments of the implementation a field
||| template is read through.
public export
data Markers : Nat -> Type where
  AtSite : Site n -> Markers n
  OfArguments : List Template -> Markers n

mutual
  ||| V: the values each position can receive, the least family closed
  ||| under the sites.
  public export
  data InV : {g : Graph} -> (m : Model g) -> Fin g.size -> Template -> Type where
    ||| A site writes what an instance makes of its template.
    Reduced : (s : Site g.size) -> Elem s m.sites -> Writes m (AtSite s) s.template w -> InV m s.target w
    ||| A capped position holds every value of the cap's height.
    Capped : index p g.caps = Just c -> LTE (height v) c -> InV m p v

  ||| What an instance writes where a template reads.
  public export
  data Writes : {g : Graph} -> (m : Model g) -> Markers g.size -> Template -> Template -> Type where
    AtVar : Elem (i, p) s.writers -> InV m p v -> Sub d v w -> Writes m (AtSite s) (Var i d) w
    AtArgument : (j : Fin (length as)) -> Sub d (index' as j) w -> Writes m (OfArguments as) (Var (finToNat j) d) w
    AtHead : AllWrite m b ts ws -> Writes m b (Head a ts) (Head a ws)
    AtOpaque : AllWrite m b ts ws -> Writes m b (Opaque a ts) (Opaque a ws)
    AtLeaf : Writes m b (Leaf h) (Leaf h)
    AtToken : Writes m b (Token k) (Token k)
    AtFormal : Writes m b (Formal j k) (Formal j k)
    Chosen : Elem x ls -> Writes m b x w -> Writes m b (Choice c ls) w
    Beta : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f body -> AllWrite m (AtSite s) ts ws ->
           Instantiates ws body w -> Writes m (AtSite s) (Applied i d ts) w
    Member : Elem (i, p) s.writers -> InV m p v -> Sub d v f -> Within f w -> Writes m (AtSite s) (Applied i d ts) w
    MemberOf : Elem j (s.roots (Applied i d ts)) -> Arguments m j 0 as ->
               Writes m (AtSite s) (Applied i d ts) (Head (Just j) as)
    Landed : LTE (height f) k -> Within f body -> AllWrite m (AtSite s) ts ws ->
             Instantiates ws body w -> Writes m (AtSite s) (raise k (Head Nothing ts)) w
    LandedMember : LTE (height f) k -> Within f w -> Writes m (AtSite s) (raise k (Head Nothing ts)) w
    AtField : Writes m (AtSite s) r (Head (Just j) as) -> Elem j (s.roots r) -> m.fields j k = Just ft ->
              Writes m (OfArguments as) ft w -> Writes m (AtSite s) (Field k r) w
    AtHeld : Elem j (s.roots (Held c p)) -> Arguments m j 0 as -> Writes m (AtSite s) (Held c p) (Head (Just j) as)

  public export
  data AllWrite : {g : Graph} -> (m : Model g) -> Markers g.size -> List Template -> List Template -> Type where
    Nil : AllWrite m b [] []
    (::) : Writes m b t w -> AllWrite m b ts ws -> AllWrite m b (t :: ts) (w :: ws)

  ||| An implementation's arguments from parameter q on, each a value a
  ||| position of one of its nodes received at that parameter.
  public export
  data Arguments : {g : Graph} -> (m : Model g) -> Address -> Nat -> List Template -> Type where
    Ended : Arguments m j q []
    Given : (p : Fin g.size) -> Elem p (m.positionsOf j) -> m.positionOf p = (j, q) -> InV m p a ->
            Arguments m j (S q) as -> Arguments m j q (a :: as)

------------------------------------------------------------------------------
-- What the graph says of a site
------------------------------------------------------------------------------

||| An arc from position p carries a part matched d deep to the site's
||| target, where it sits at depth e less l: its weight is at least e - l - d.
public export
data Carries : (g : Graph) -> Fin g.size -> Nat -> (Nat, Nat) -> Fin g.size -> Type where
  MkCarries : Elem (MkArc p q (Measured gain loss)) g.arcs -> LTE (e + loss) (d + l + gain) -> Carries g p d (e, l) q

||| A field template read at depth e less l: K above its closed parts, and
||| no argument of the record held deeper than dg - dl below where it was
||| matched.
public export
record FieldWithin (g : Graph) (dg, dl : Nat) (depth : (Nat, Nat)) (ft : Template) where
  constructor MkFieldWithin
  closed : LTE (height ft + fst depth) (g.constant + snd depth)
  deep : (q, dq, eq : Nat) -> OccursAt (Var q dq) eq ft -> LTE (eq + dl) (dq + dg)

||| A field template that holds no argument of its record where what it
||| writes takes one in: no marker occurs in it. What it writes is no higher
||| than it, whatever the record is, so the record needs no arc.
public export
0 Unread : Template -> Type
Unread ft = (q, dq, eq : Nat) -> Not (OccursAt (Var q dq) eq ft)

mutual
  ||| What the graph says of a part of a site's template at depth e less l.
  public export
  data CoveredAt : {g : Graph} -> (m : Model g) -> Site g.size -> (Nat, Nat) -> Template -> Type where
    CVar : ((p : Fin g.size) -> Elem (i, p) s.writers -> Carries g p d (e, l) s.target) -> CoveredAt m s (e, l) (Var i d)
    CHead : AllCovered m s (S e, l) ts -> CoveredAt m s (e, l) (Head a ts)
    COpaque : AllCovered m s (S e, l) ts -> CoveredAt m s (e, l) (Opaque a ts)
    CLeaf : CoveredAt m s el (Leaf h)
    CToken : CoveredAt m s el (Token k)
    CFormal : CoveredAt m s el (Formal j k)
    CChoice : AllCovered m s el ls -> CoveredAt m s el (Choice c ls)
    CApplied : ((p : Fin g.size) -> Elem (i, p) s.writers -> (Carries g p d (e + tallest ts, l) s.target, AllUnmarked ts)) ->
               ((j : Address) -> Elem j (s.roots (Applied i d ts)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                Carries g p' 0 (S e, l) s.target) ->
               CoveredAt m s (e, l) (Applied i d ts)
    ||| A family that computes from what it is given writes nothing any
    ||| rule states, so the graph says of it only that no position of the
    ||| writer's reads it.
    CComputing : ((p : Fin g.size) -> Elem (i, p) s.writers -> Void) -> CoveredAt m s el (Computing i d ts)
    CField : (dg, dl : Nat) ->
             ((j : Address) -> Elem j (s.roots r) -> (ft : Template) -> m.fields j k = Just ft ->
              FieldWithin g dg dl (e, l) ft) ->
             CoveredAt m s (e + S dg, l + (dl + 2)) r ->
             LTE (height r + (e + S dg)) (g.constant + (l + (dl + 2))) ->
             CoveredAt m s (e, l) (Field k r)
    CClosedField : ((j : Address) -> Elem j (s.roots r) -> (ft : Template) -> m.fields j k = Just ft ->
                    (Unread ft, LTE (height ft + e) (g.constant + l))) ->
                   CoveredAt m s (e, l) (Field k r)
    CHeld : ((j : Address) -> Elem j (s.roots (Held c p)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
             Carries g p' 0 (S e, l) s.target) ->
            LTE (S e) (g.constant + l) ->
            CoveredAt m s (e, l) (Held c p)

  public export
  data AllCovered : {g : Graph} -> (m : Model g) -> Site g.size -> (Nat, Nat) -> List Template -> Type where
    Nil : AllCovered m s el []
    (::) : CoveredAt m s el t -> AllCovered m s el ts -> AllCovered m s el (t :: ts)

||| What the graph says of a site: its target is uncapped, K is at least its
||| template's own height, and it covers the template.
public export
record Covers (g : Graph) (m : Model g) (s : Site g.size) where
  constructor MkCovers
  uncapped : index s.target g.caps = Nothing
  constant : LTE (height s.template) g.constant
  covered : CoveredAt m s (0, 0) s.template

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

0 swapLast : (p, q, r : Nat) -> (p + q) + r = (p + r) + q
swapLast p q r =
  rewrite sym (plusAssociative p q r) in
  rewrite plusCommutative q r in
  plusAssociative p r q

-- Two differences in a row, each written as a sum on both sides: a - b
-- within c - d, and c - d within x - y, give a - b within x - y.
0 crossTrans : {a, b, c, d, x, y : Nat} -> LTE (a + d) (c + b) -> LTE (c + y) (x + d) -> LTE (a + y) (x + b)
crossTrans h1 h2 =
  lteCancelRight d $
    lteL (swapLast a d y) $
    lteR (swapLast x d b) $
    transitive (plusLteMonotoneRight y (a + d) (c + b) h1)
               (lteL (swapLast c y b) (plusLteMonotoneRight b (c + y) (x + d) h2))

0 swap4 : (a, b, c, d : Nat) -> (a + b) + (c + d) = (a + c) + (b + d)
swap4 a b c d =
  rewrite sym (plusAssociative a b (c + d)) in
  rewrite plusAssociative b c d in
  rewrite plusCommutative b c in
  rewrite sym (plusAssociative c b d) in
  plusAssociative a c (b + d)

-- The induction's step, every difference written as a sum on both sides:
-- a part of height h, d deep in a value within k + q, sits at depth e less
-- l in what is written; the arc weighs gain less loss, at least e less l
-- less d; and the potential satisfies the arc, q + gain within p + loss.
-- Then h + e is within k + p + l.
0 carry : {h, d, k, q, e, l, loss, gain, p : Nat} ->
          LTE (h + d) (k + q) -> LTE (e + loss) (d + l + gain) -> LTE (q + gain) (p + loss) ->
          LTE (h + e) (k + p + l)
carry hd el qg =
  lteCancelRight loss $
    lteL (plusAssociative h e loss) $
    lteR (trans (sym (swap4 k p l loss)) (plusAssociative (k + p) l loss)) $
    transitive (plusLteMonotoneLeft h (e + loss) ((d + l) + gain) el) $
    lteL (trans (sym (plusAssociative h d (l + gain))) (cong (h +) (plusAssociative d l gain))) $
    transitive (plusLteMonotoneRight (l + gain) (h + d) (k + q) hd) $
    lteL (sym (swap4 k q l gain)) $
    plusLteMonotoneLeft (k + l) (q + gain) (p + loss) qg

-- A part of a record's argument, dq deep, written eq deep in a field
-- placed e deep, from a record placed e + 1 + dg less l + dl + 2 deep: the
-- field template holds the argument no deeper than dg less dl below where
-- it was matched.
0 fieldArith : {hu, dq, t, e, dg, dl, eq, b, l : Nat} ->
               LTE (hu + dq) t -> LTE (eq + dl) (dq + dg) ->
               LTE (S t + (e + S dg)) (b + (l + (dl + 2))) ->
               LTE (hu + (eq + e)) (b + l)
fieldArith h1 h2 h3 =
  lteCancelRight dl $
    lteL e3 $
    transitive (plusLteMonotoneLeft (hu + e) (eq + dl) (dq + dg) h2) $
    lteL (sym (swap4 hu e dq dg)) $
    transitive (plusLteMonotoneRight (e + dg) (hu + dq) t h1) recordAt
  where
    0 e1 : S t + (e + S dg) = (t + (e + dg)) + 2
    e1 = trans (cong (\z => S (t + z)) (sym (plusSuccRightSucc e dg)))
               (trans (cong S (sym (plusSuccRightSucc t (e + dg)))) (plusCommutative 2 (t + (e + dg))))

    0 e2 : b + (l + (dl + 2)) = ((b + l) + dl) + 2
    e2 = trans (plusAssociative b l (dl + 2)) (plusAssociative (b + l) dl 2)

    0 e3 : (hu + e) + (eq + dl) = (hu + (eq + e)) + dl
    e3 = trans (sym (plusAssociative hu e (eq + dl)))
               (trans (cong (hu +) (plusAssociative e eq dl))
                      (trans (cong (\z => hu + (z + dl)) (plusCommutative e eq))
                             (plusAssociative hu (eq + e) dl)))

    -- The record, placed e + 1 + dg less l + dl + 2 deep, is no higher
    -- than its bound there: two cancel.
    0 recordAt : LTE (t + (e + dg)) ((b + l) + dl)
    recordAt = lteCancelRight 2 (lteL e1 (lteR e2 h3))

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
  0 unmarkedWrites : Unmarked t -> Writes m b t w -> LTE (height w) (height t)
  unmarkedWrites u (AtVar _ _ _) = absurd u
  unmarkedWrites u (AtArgument _ _) = absurd u
  unmarkedWrites u (AtHead xs) = LTESucc (unmarkedAll (unmarkedHead u) xs)
  unmarkedWrites u (AtOpaque xs) = LTESucc (unmarkedAll (unmarkedOpaque u) xs)
  unmarkedWrites u AtLeaf = reflexive
  unmarkedWrites u AtToken = reflexive
  unmarkedWrites u AtFormal = reflexive
  unmarkedWrites u (Chosen el x) =
    transitive (unmarkedWrites (unmarkedAt el (unmarkedChoice u)) x) (tallestAbove el)
  unmarkedWrites u (Beta _ _ _ _ _ _) = absurd u
  unmarkedWrites u (Member _ _ _ _) = absurd u
  unmarkedWrites u (MemberOf _ _) = absurd u
  unmarkedWrites u (Landed {k} {ts} {ws} hf wb xs inst) =
    lteR (sym (raisedHeight k (Head Nothing ts))) $
      transitive (instHeight inst)
        (transitive (plusLteMonotone (transitive (withinHeight wb) hf)
                                     (unmarkedAll (unmarkedHead (unmarkedRaise k u)) xs))
                    (plusLteMonotoneLeft k (tallest ts) (S (tallest ts)) (lteSuccRight reflexive)))
  unmarkedWrites u (LandedMember {k} {ts} hf wm) =
    lteR (sym (raisedHeight k (Head Nothing ts))) (transitive (transitive (withinHeight wm) hf) (lteAddRight k))
  unmarkedWrites u (AtField _ _ _ _) = absurd u
  unmarkedWrites u (AtHeld _ _) = absurd u

  0 unmarkedAll : AllUnmarked ts -> AllWrite m b ts ws -> LTE (tallest ws) (tallest ts)
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

-- K is no higher than K above a potential, l to spare.
0 belowBound : {k, q, l : Nat} -> LTE x (k + l) -> LTE x (k + q + l)
belowBound le = transitive le (plusLteMonotoneRight l k (k + q) (lteAddRight k))

-- A value of V at p, with a part d deep of it: the part stands within the
-- bound at p, uncapped, less d.
0 partBelow : {g : Graph} -> {pot : Vect g.size Nat} -> {p : Fin g.size} ->
              LTE (height v) (bound g pot p) -> Sub d v u -> LTE (height u + d) (g.constant + index p pot)
partBelow {g} {pot} {p} bv sub = transitive (subHeight sub) (transitive bv (boundBelow g pot p))

------------------------------------------------------------------------------
-- What the graph says, read back
------------------------------------------------------------------------------

0 coveredVar : CoveredAt m s (e, l) (Var i d) -> (p : Fin g.size) -> Elem (i, p) s.writers -> Carries g p d (e, l) s.target
coveredVar (CVar c) = c

0 coveredHead : CoveredAt m s (e, l) (Head a ts) -> AllCovered m s (S e, l) ts
coveredHead (CHead cs) = cs

0 coveredOpaque : CoveredAt m s (e, l) (Opaque a ts) -> AllCovered m s (S e, l) ts
coveredOpaque (COpaque cs) = cs

0 coveredChoice : CoveredAt m s el (Choice c ls) -> AllCovered m s el ls
coveredChoice (CChoice cs) = cs

0 coveredApplied : CoveredAt m s (e, l) (Applied i d ts) ->
                   ( (p : Fin g.size) -> Elem (i, p) s.writers -> (Carries g p d (e + tallest ts, l) s.target, AllUnmarked ts)
                   , (j : Address) -> Elem j (s.roots (Applied i d ts)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                     Carries g p' 0 (S e, l) s.target )
coveredApplied (CApplied c arcs) = (c, arcs)

0 coveredField : CoveredAt m s (e, l) (Field k r) ->
                 Either ((j : Address) -> Elem j (s.roots r) -> (ft : Template) -> m.fields j k = Just ft ->
                         (Unread ft, LTE (height ft + e) (g.constant + l)))
                        (dg : Nat ** dl : Nat **
                         ( (j : Address) -> Elem j (s.roots r) -> (ft : Template) -> m.fields j k = Just ft -> FieldWithin g dg dl (e, l) ft
                         , CoveredAt m s (e + S dg, l + (dl + 2)) r
                         , LTE (height r + (e + S dg)) (g.constant + (l + (dl + 2))) ))
coveredField (CClosedField fts) = Left fts
coveredField (CField dg dl roots c h) = Right (dg ** dl ** (roots, c, h))

0 coveredHeld : CoveredAt m s (e, l) (Held c p) ->
                ( (j : Address) -> Elem j (s.roots (Held c p)) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                  Carries g p' 0 (S e, l) s.target
                , LTE (S e) (g.constant + l) )
coveredHeld (CHeld arcs one) = (arcs, one)

0 coveredRaise : {e : Nat} -> (k : Nat) -> CoveredAt m s (e, l) (raise k t) -> CoveredAt m s (k + e, l) t
coveredRaise Z c = c
coveredRaise {e} (S k) c = case coveredHead c of
  (c' :: []) => rewrite plusSuccRightSucc k e in coveredRaise k c'

0 coveredIn : Elem x ls -> AllCovered m s el ls -> CoveredAt m s el x
coveredIn Here (c :: _) = c
coveredIn (There i) (_ :: cs) = coveredIn i cs

------------------------------------------------------------------------------
-- A field template, read over its record's arguments
------------------------------------------------------------------------------

mutual
  -- Lemma 1 for a field template: what it writes, e deep, is within c when
  -- its closed parts are and every part of an argument it holds is, at
  -- the depth it holds it.
  0 argumentsWritten : {as : List Template} -> {c, e : Nat} -> Writes m (OfArguments as) t w -> LTE (height t + e) c ->
                       ((q : Fin (length as)) -> (dq, eq : Nat) -> (u : Template) ->
                        OccursAt (Var (finToNat q) dq) eq t -> Sub dq (index' as q) u -> LTE (height u + (eq + e)) c) ->
                       LTE (height w + e) c
  argumentsWritten (AtArgument q sub) hp occ = occ q _ 0 _ Top sub
  argumentsWritten {e} (AtHead {ts} {ws} xs) hp occ =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      argumentsAll xs (lteL (plusSuccRightSucc (tallest ts) e) hp)
        (\x, el, q, dq, eq, u, o, sub =>
           lteL (cong (height u +) (plusSuccRightSucc eq e)) (occ q dq (S eq) u (BelowHead el o) sub))
  argumentsWritten {e} (AtOpaque {ts} {ws} xs) hp occ =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      argumentsAll xs (lteL (plusSuccRightSucc (tallest ts) e) hp)
        (\x, el, q, dq, eq, u, o, sub =>
           lteL (cong (height u +) (plusSuccRightSucc eq e)) (occ q dq (S eq) u (BelowOpaque el o) sub))
  argumentsWritten AtLeaf hp occ = hp
  argumentsWritten AtToken hp occ = hp
  argumentsWritten AtFormal hp occ = hp
  argumentsWritten (Chosen el x) hp occ =
    argumentsWritten x (transitive (plusLteMonotoneRight _ _ _ (tallestAbove el)) hp)
      (\q, dq, eq, u, o, sub => occ q dq eq u (InLeafOf el o) sub)
  argumentsWritten (AtVar _ _ _) _ _ impossible
  argumentsWritten (Beta _ _ _ _ _ _) _ _ impossible
  argumentsWritten (Member _ _ _ _) _ _ impossible
  argumentsWritten (MemberOf _ _) _ _ impossible
  argumentsWritten (Landed _ _ _ _) _ _ impossible
  argumentsWritten (LandedMember _ _) _ _ impossible
  argumentsWritten (AtField _ _ _ _) _ _ impossible
  argumentsWritten (AtHeld _ _) _ _ impossible

  0 argumentsAll : {as : List Template} -> {c, e : Nat} -> AllWrite m (OfArguments as) ts ws -> LTE (tallest ts + S e) c ->
                   ((x : Template) -> Elem x ts -> (q : Fin (length as)) -> (dq, eq : Nat) -> (u : Template) ->
                    OccursAt (Var (finToNat q) dq) eq x -> Sub dq (index' as q) u -> LTE (height u + (eq + S e)) c) ->
                   LTE (tallest ws + S e) c
  argumentsAll [] hp occ = hp
  argumentsAll {e} {ts = t :: ts} (x :: xs) hp occ =
    maxPlus (argumentsWritten x (transitive (plusLteMonotoneRight (S e) _ _ (maximumLeftUpperBound _ _)) hp) (occ t Here))
            (argumentsAll xs (transitive (plusLteMonotoneRight (S e) _ _ (maximumRightUpperBound _ _)) hp)
                          (\x', el => occ x' (There el)))

------------------------------------------------------------------------------
-- Where the graph places a field's record
------------------------------------------------------------------------------

||| A reach at least g - l: what a marker eq deep and matched dq deep asks
||| of the reach of the templates it occurs in, g = eq and l = dq.
public export
data Reaches : (g, l : Nat) -> Reach -> Type where
  ReachedBy : LTE (g + l') (g' + l) -> Reaches g l (Deepest g' l')

Uninhabited (Reaches g l Nowhere) where
  uninhabited (ReachedBy _) impossible

0 deeperLeft : {g, l : Nat} -> {a, b : Reach} -> Reaches g l a -> Reaches g l (deeper a b)
deeperLeft {a = Deepest g1 l1} {b = Nowhere} (ReachedBy le) = ReachedBy le
deeperLeft {g} {l} {a = Deepest g1 l1} {b = Deepest g2 l2} (ReachedBy le) with (g1 + l2 <= g2 + l1) proof eq
  _ | True = ReachedBy (crossTrans {a = g} {b = l} {c = g1} {d = l1} {x = g2} {y = l2} le
                          (lteSo (the (So (g1 + l2 <= g2 + l1)) (rewrite eq in Oh))))
  _ | False = ReachedBy le
deeperLeft {a = Nowhere} r = absurd r

0 deeperRight : {g, l : Nat} -> {a, b : Reach} -> Reaches g l b -> Reaches g l (deeper a b)
deeperRight {a = Nowhere} r = r
deeperRight {g} {l} {a = Deepest g1 l1} {b = Deepest g2 l2} (ReachedBy le) with (g1 + l2 <= g2 + l1) proof eq
  _ | True = ReachedBy le
  _ | False =
    ReachedBy (crossTrans {a = g} {b = l} {c = g2} {d = l2} {x = g1} {y = l1} le
                 (lteSuccLeft (notLTEImpliesGT (notLteSo (the (So (not (g1 + l2 <= g2 + l1))) (rewrite eq in Oh))))))
deeperRight {a = Deepest _ _} {b = Nowhere} r = absurd r

-- A template among others read at one level reaches no deeper than they.
0 reachedIn : {g, l, e : Nat} -> {t : Template} -> {ts : List Template} ->
              Elem t ts -> Reaches g l (reachAt e t) -> Reaches g l (reachAll e ts)
reachedIn {e} {t} {ts = _ :: rest} Here r = deeperLeft {a = reachAt e t} {b = reachAll e rest} r
reachedIn {e} {ts = x :: rest} (There el) r = deeperRight {a = reachAt e x} {b = reachAll e rest} (reachedIn el r)

||| Every marker a template holds where what it writes takes it in is
||| within the template's reach.
export
0 occursReached : {e, eq : Nat} -> {t : Template} -> OccursAt (Var q dq) eq t -> Reaches (eq + e) dq (reachAt e t)
occursReached Top = ReachedBy reflexive
occursReached {e} (BelowHead {e = eq'} el o) =
  rewrite plusSuccRightSucc eq' e in reachedIn el (occursReached {e = S e} o)
occursReached {e} (BelowOpaque {e = eq'} el o) =
  rewrite plusSuccRightSucc eq' e in reachedIn el (occursReached {e = S e} o)
occursReached {e} (InLeafOf el o) = reachedIn el (occursReached {e} o)

||| The graph places a field's record by the reach of the field templates of
||| its roots (`Describes.fieldPlaced`): a marker one of them holds eq deep,
||| matched dq deep, is no deeper than the reach less dq, as `FieldWithin`
||| asks.
export
0 reachHolds : {fts : List Template} -> Elem ft fts -> OccursAt (Var q dq) eq ft ->
               reachAll 0 fts = Deepest dg dl -> LTE (eq + dl) (dq + dg)
reachHolds {eq} {dq} {dg} {dl} el occ same = case replace {p = Reaches (eq + 0) dq} same (reachedIn el (occursReached occ)) of
  ReachedBy le => lteR (plusCommutative dg dq) (lteL (cong (+ dl) (plusZeroRightNeutral eq)) le)

||| Where the field templates of a record's roots reach nowhere, none of
||| them holds an argument of the record, as `CClosedField` asks.
export
0 reachNowhere : {fts : List Template} -> Elem ft fts -> reachAll 0 fts = Nowhere -> Unread ft
reachNowhere el same = \q, dq, eq, occ => absurd (replace {p = Reaches (eq + 0) dq} same (reachedIn el (occursReached occ)))

------------------------------------------------------------------------------
-- Theorem 1
------------------------------------------------------------------------------

mutual
  ||| Theorem 1: under a feasible potential, every value a position can
  ||| receive is within its bound.
  export
  0 bounded : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {p : Fin g.size} -> {v : Template} ->
              Describes m -> Feasible g pot -> InV m p v -> LTE (height v) (bound g pot p)
  bounded ds fe (Capped cap le) = boundCapped cap le (transitive le (capHolds fe _ cap))
  bounded ds fe (Reduced s el wr) =
    let cov = indexAll el ds in
    rewrite boundUncapped {g} {pot} {p = s.target} cov.uncapped in
      lteL (plusZeroRightNeutral _) $ lteR (plusZeroRightNeutral _) $
        writtenAt ds fe wr cov.covered
          (lteL (sym (plusZeroRightNeutral _)) $ lteR (sym (plusZeroRightNeutral _)) $
             transitive cov.constant (lteAddRight _))

  -- Lemma 1, by induction on what an instance writes: a part of a site's
  -- template at depth e less l, within K above the target's potential l
  -- to spare, writes what stays there.
  0 writtenAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} ->
                {t, w : Template} -> {e, l : Nat} ->
                Describes m -> Feasible g pot -> Writes m (AtSite s) t w -> CoveredAt m s (e, l) t ->
                LTE (height t + e) (g.constant + index s.target pot + l) ->
                LTE (height w + e) (g.constant + index s.target pot + l)
  writtenAt ds fe (AtVar {p} wa iv sub) cov hp = case coveredVar cov p wa of
    MkCarries arc wt => carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc)
  writtenAt ds fe (AtArgument _ _) _ _ impossible
  writtenAt {e} ds fe (AtHead {ts} {ws} xs) cov hp =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      allWrittenAt ds fe xs (coveredHead cov) (lteL (plusSuccRightSucc (tallest ts) e) hp)
  writtenAt {e} ds fe (AtOpaque {ts} {ws} xs) cov hp =
    lteL (sym (plusSuccRightSucc (tallest ws) e)) $
      allWrittenAt ds fe xs (coveredOpaque cov) (lteL (plusSuccRightSucc (tallest ts) e) hp)
  writtenAt ds fe AtLeaf cov hp = hp
  writtenAt ds fe AtToken cov hp = hp
  writtenAt ds fe AtFormal cov hp = hp
  writtenAt ds fe (Chosen el x) cov hp =
    writtenAt ds fe x (coveredIn el (coveredChoice cov)) (transitive (plusLteMonotoneRight _ _ _ (tallestAbove el)) hp)
  writtenAt {e} ds fe (Beta {p} {f} {ts} {ws} wa iv sub wb xs inst) cov hp = case coveredApplied cov of
    (writes, _) => case writes p wa of
      (MkCarries arc wt, us) =>
        appliedWithin (carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc))
          (transitive (instHeight inst) (plusLteMonotone (withinHeight wb) (unmarkedAll us xs)))
  writtenAt {e} ds fe (Member {p} {f} {ts} wa iv sub wm) cov hp = case coveredApplied cov of
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
  -- A field template that holds no argument writes no higher than itself,
  -- whatever the record is; one that holds some writes them as deep as the
  -- record is placed.
  writtenAt {e} {l} ds fe (AtField {as} {j} {ft} wr el found wf) cov hp = case coveredField cov of
    Left fts => case fts j el ft found of
      (unread, closed) =>
        argumentsWritten wf (belowBound closed) (\q, dq, eq, u, occ, sub => void (unread (finToNat q) dq eq occ))
    Right (dg ** dl ** (templates, covR, hR)) =>
      let fw = templates j el ft found
          0 atRecord = writtenAt ds fe wr covR (belowBound hR) in
      argumentsWritten wf (belowBound fw.closed)
        (\q, dq, eq, u, occ, sub =>
           fieldArith (transitive (subHeight sub) (tallestIndex as q)) (fw.deep (finToNat q) dq eq occ) atRecord)
  writtenAt {e} ds fe (AtHeld {as} el args) cov hp = case coveredHeld cov of
    (arcs, one) =>
      lteL (sym (plusSuccRightSucc (tallest as) e)) $
        heldWithin ds fe args (arcs _ el) (belowBound one)

  -- A head's children, one deeper.
  0 allWrittenAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e, l : Nat} ->
                   Describes m -> Feasible g pot -> AllWrite m (AtSite s) ts ws -> AllCovered m s (S e, l) ts ->
                   LTE (tallest ts + S e) (g.constant + index s.target pot + l) ->
                   LTE (tallest ws + S e) (g.constant + index s.target pot + l)
  allWrittenAt ds fe [] [] hp = hp
  allWrittenAt {e} ds fe (x :: xs) (c :: cs) hp =
    maxPlus (writtenAt ds fe x c (transitive (plusLteMonotoneRight (S e) _ _ (maximumLeftUpperBound _ _)) hp))
            (allWrittenAt ds fe xs cs (transitive (plusLteMonotoneRight (S e) _ _ (maximumRightUpperBound _ _)) hp))

  -- A held dictionary's arguments, one deeper than it, each carried from
  -- the position of the implementation that received it.
  0 heldWithin : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e, l : Nat} ->
                 Describes m -> Feasible g pot -> Arguments m j q as ->
                 ((p' : Fin g.size) -> Elem p' (m.positionsOf j) -> Carries g p' 0 (S e, l) s.target) ->
                 LTE (S e) (g.constant + index s.target pot + l) ->
                 LTE (tallest as + S e) (g.constant + index s.target pot + l)
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
landed l (Capped cap _) = absurd (trans (sym cap) l.uncapped)
landed l (Reduced s el wr) = case l.under s el Refl of
  (u, le) => transitive (unmarkedWrites u wr) le
