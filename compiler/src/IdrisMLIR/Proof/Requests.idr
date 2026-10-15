-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The relation the frontend's request chains keep, defined once, and the
||| proof that it is almost full, so that every chain it admits is finite.
|||
||| A request is an instance of a definition at static arguments. A chain
||| (the instance requesting it, the one that requested that, back to the
||| root) cannot hold a request that grows against an earlier instance of
||| the same definition: smaller at no argument and larger at one. The
||| frontend checks a request by `admit`, whose answer is either the
||| evidence that the request is new to the chain, which the worklist
||| descends on, or the earlier instance and the way the request grows
||| against it, which the refusal names. The answer costs comparisons of
||| numbers; its proofs are erased.
|||
||| An argument is written in prefix order, a symbol per node of the term:
||| the node's form (finitely many), the context name it names (finitely
||| many), and a number below the argument's size (a variable's index, a
||| count of arguments); a literal's magnitude weighs as much as itself.
||| An argument's size is the weight of its symbols, so finitely many
||| arguments share a size, finitely many requests share a definition and
||| a vector of sizes, and the relation is almost full: pointwise `<=` on
||| the sizes (Dickson's lemma), intersected with equality of definitions
||| and with equality within a finite fibre. Nothing about the requests is
||| assumed; the bound is in their type.
module IdrisMLIR.Proof.Requests

import IdrisMLIR.Proof.AlmostFull

import Control.Relation
import Control.WellFounded
import public Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.So
import public Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Deciding at runtime
------------------------------------------------------------------------------

||| A decision as the frontend makes it at runtime: the evidence that it
||| holds, which the frontend reads, or the erased evidence that it does
||| not. The comparisons it rests on are the machine's (`<`, `==` on
||| naturals, which Idris compiles to integer operations), and the proofs
||| that they mean what the relation says are erased, so a decision costs
||| its comparisons and nothing more.
public export
data Decision : Type -> Type where
  Holds : p -> Decision p
  Fails : (0 _ : Not p) -> Decision p

||| `<` on naturals, as the machine compares them, is `LT`.
export
ltSo : {b, a : Nat} -> So (b < a) -> LT b a
ltSo {b = Z} {a = S _} _ = LTESucc LTEZero
ltSo {b = S b} {a = S a} so = LTESucc (ltSo so)
ltSo {b = Z} {a = Z} so = absurd so
ltSo {b = S _} {a = Z} so = absurd so

lteSo : {b, a : Nat} -> So (b <= a) -> LTE b a
lteSo {b = Z} _ = LTEZero
lteSo {b = S b} {a = S a} so = LTESucc (lteSo so)
lteSo {b = S _} {a = Z} so = absurd so

notLtSo : {b, a : Nat} -> So (not (b < a)) -> Not (LT b a)
notLtSo {b = Z} {a = S _} so _ = absurd so
notLtSo {b = S b} {a = S a} so (LTESucc lt) = notLtSo so lt
notLtSo {a = Z} _ lt = absurd lt

notLteSo : {b, a : Nat} -> So (not (b <= a)) -> Not (LTE b a)
notLteSo {b = Z} {a = Z} so _ = absurd so
notLteSo {b = Z} {a = S _} so _ = absurd so
notLteSo {b = S b} {a = S a} so (LTESucc le) = notLteSo so le
notLteSo {b = S _} {a = Z} _ le = absurd le

||| Equal naturals, as the machine compares them.
export
equalSo : {m, n : Nat} -> So (m == n) -> m = n
equalSo {m = Z} {n = Z} _ = Refl
equalSo {m = S m} {n = S n} so = cong S (equalSo so)
equalSo {m = Z} {n = S _} so = absurd so
equalSo {m = S _} {n = Z} so = absurd so

||| A natural compares equal to itself.
export
equalSelf : (m : Nat) -> So (m == m)
equalSelf Z = Oh
equalSelf (S m) = equalSelf m

------------------------------------------------------------------------------
-- Growth
------------------------------------------------------------------------------

namespace Pointwise
  ||| Two size vectors of one length, the first nowhere larger.
  public export
  data Pointwise : List Nat -> List Nat -> Type where
    Nil : Pointwise [] []
    (::) : (0 _ : LTE b a) -> Pointwise bs as -> Pointwise (b :: bs) (a :: as)

||| `after` grows against `before`: they have one length, `after` is
||| smaller at no position and larger at one.
public export
data Grows : (before, after : List Nat) -> Type where
  ||| Larger here, and smaller nowhere after.
  Here : (0 _ : LT b a) -> (0 _ : Pointwise bs as) -> Grows (b :: bs) (a :: as)
  ||| As large here, and growing after.
  There : (0 _ : LTE b a) -> Grows bs as -> Grows (b :: bs) (a :: as)

||| The position at which a growth is larger.
public export
position : Grows before after -> Nat
position (Here _ _) = 0
position (There _ g) = S (position g)

0 growsPointwise : Grows bs as -> Pointwise bs as
growsPointwise (Here lt pw) = lteSuccLeft lt :: pw
growsPointwise (There le g) = le :: growsPointwise g

pointwise : (bs, as : List Nat) -> Decision (Pointwise bs as)
pointwise [] [] = Holds []
pointwise [] (_ :: _) = Fails (\case _ impossible)
pointwise (_ :: _) [] = Fails (\case _ impossible)
pointwise (b :: bs) (a :: as) = case choose (b <= a) of
  Right nle => Fails (\(le :: _) => notLteSo nle le)
  Left le => case pointwise bs as of
    Fails npw => Fails (\(_ :: pw) => npw pw)
    Holds pw => Holds (lteSo le :: pw)

||| Whether `after` grows against `before`, at the first position at which
||| it is larger.
export
grows : (before, after : List Nat) -> Decision (Grows before after)
grows [] [] = Fails (\case _ impossible)
grows [] (_ :: _) = Fails (\case _ impossible)
grows (_ :: _) [] = Fails (\case _ impossible)
grows (b :: bs) (a :: as) = case choose (b < a) of
  Left lt => case pointwise bs as of
    Holds pw => Holds (Here (ltSo lt) pw)
    Fails npw => Fails (\case Here _ pw => npw pw
                              There _ g => npw (growsPointwise g))
  Right nlt => case choose (b <= a) of
    Right nle => Fails (\case Here lt _ => notLteSo nle (lteSuccLeft lt)
                              There le _ => notLteSo nle le)
    Left le => case grows bs as of
      Holds g => Holds (There (lteSo le) g)
      Fails ng => Fails (\case Here lt _ => notLtSo nlt lt
                               There _ g => ng g)

------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------

||| A finitely listed type: every value is in the list.
public export
record Listed (a : Type) where
  constructor MkListed
  values : List a
  complete : (x : a) -> Elem x values

-- The numbers below `n`, as base lists them.
fins : (n : Nat) -> List (Fin n)
fins = Data.Fin.List.allFins

finsComplete : (i : Fin n) -> Elem i (fins n)
finsComplete FZ = Here
finsComplete (FS i) = There (elemMap FS (finsComplete i))

elemAppendLeft : Elem x xs -> Elem x (xs ++ ys)
elemAppendLeft Here = Here
elemAppendLeft (There e) = There (elemAppendLeft e)

elemAppendRight : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemAppendRight [] e = e
elemAppendRight (_ :: xs) e = There (elemAppendRight xs e)

||| The numbers below `n`, listed.
export
listedFin : (n : Nat) -> Listed (Fin n)
listedFin n = MkListed (fins n) finsComplete

||| Two listed types, side by side.
export
listedEither : Listed a -> Listed b -> Listed (Either a b)
listedEither la lb = MkListed (map Left la.values ++ map Right lb.values) complete
  where
    complete : (x : Either a b) -> Elem x (map Left la.values ++ map Right lb.values)
    complete (Left x) = elemAppendLeft (elemMap Left (la.complete x))
    complete (Right y) = elemAppendRight (map Left la.values) (elemMap Right (lb.complete y))

||| A type that another listed one maps onto, with an inverse: listed.
export
listedVia : (to : b -> a) -> (from : a -> b) -> ((y : b) -> from (to y) = y) -> Listed a -> Listed b
listedVia to from back l = MkListed (map from l.values) complete
  where
    complete : (y : b) -> Elem y (map from l.values)
    complete y = replace {p = \z => Elem z (map from l.values)} (back y) (elemMap from (l.complete (to y)))

||| A type that a finite numbering codes and decodes: listed, and with
||| equality decided by the codes. This is how a closed enumeration of the
||| frontend's is finite without listing its cases twice.
public export
record Numbered (a : Type) where
  constructor MkNumbered
  range : Nat
  code : a -> Fin range
  decode : Fin range -> a
  decodeCode : (x : a) -> decode (code x) = x

||| A numbered type, listed.
export
listedNumbered : Numbered a -> Listed a
listedNumbered n = MkListed (map n.decode (fins n.range)) complete
  where
    complete : (x : a) -> Elem x (map n.decode (fins n.range))
    complete x = replace {p = \y => Elem y (map n.decode (fins n.range))} (n.decodeCode x)
                   (elemMap n.decode (finsComplete (n.code x)))

||| Equality on a numbered type, decided by the codes.
export
decideNumbered : Numbered a -> (x, y : a) -> Dec (x = y)
decideNumbered n x y = case decEq (n.code x) (n.code y) of
  Yes eq => Yes (trans (sym (n.decodeCode x)) (trans (cong n.decode eq) (n.decodeCode y)))
  No ne => No (\eq => ne (cong n.code eq))

-- Every vector of a length over a list.
vectConses : List a -> List (Vect k a) -> List (Vect (S k) a)
vectConses [] _ = []
vectConses (x :: xs) rest = map (x ::) rest ++ vectConses xs rest

vectConsesComplete : (xs : List a) -> (rest : List (Vect k a)) -> Elem x xs -> Elem v rest ->
                     Elem (x :: v) (vectConses xs rest)
vectConsesComplete (y :: _) rest Here ev = elemAppendLeft (elemMap (y ::) ev)
vectConsesComplete (y :: ys) rest (There ex) ev = elemAppendRight (map (y ::) rest) (vectConsesComplete ys rest ex ev)

vectors : (k : Nat) -> List a -> List (Vect k a)
vectors Z _ = [[]]
vectors (S k) xs = vectConses xs (vectors k xs)

vectorsComplete : (xs : List a) -> ((x : a) -> Elem x xs) -> {k : Nat} -> (v : Vect k a) -> Elem v (vectors k xs)
vectorsComplete xs all [] = Here
vectorsComplete {k = S k} xs all (x :: v) = vectConsesComplete xs (vectors k xs) (all x) (vectorsComplete xs all v)

||| A name of the context by its index, as the index's eight bytes, the low
||| byte first: finitely many, whatever the index.
public export
Address : Type
Address = Vect 8 (Fin 256)

||| Every vector of a length over a listed type, listed. Stated over any
||| length and type, so that no listing is ever spelt out.
export
listedVect : (k : Nat) -> Listed a -> Listed (Vect k a)
listedVect k l = MkListed (vectors k l.values) (vectorsComplete l.values l.complete)

||| Every address, listed.
export
addresses : Listed Address
addresses = listedVect 8 (listedFin 256)

||| One symbol of an argument written in prefix order, a node of the
||| term: its form (the writer's, finitely many), the context name it
||| names if it names one, and a number (a variable's index, a count of
||| arguments, 0 where it has none); or a literal's form and magnitude.
public export
data Token : Type -> Type where
  Node : form -> Maybe Address -> Nat -> Token form
  Number : form -> Nat -> Token form

||| What a symbol adds to the size of its argument: one, and a magnitude
||| as much again as itself, so that a literal is measured by its value
||| without being spelt out.
public export
weight : Token form -> Nat
weight (Node _ _ _) = 1
weight (Number _ m) = S m

||| The size of a written argument: the weight of its symbols.
public export
weighs : List (Token form) -> Nat
weighs [] = 0
weighs (t :: ts) = weight t + weighs ts

||| Every number of a symbol is below a bound.
public export
Fits : Nat -> Token form -> Type
Fits s (Node _ _ k) = LT k s
Fits s (Number _ m) = LT m s

||| A static argument written out: its size, its symbols, the proof that
||| they weigh the size, and the proof that every number in them is below
||| it, which is why finitely many arguments share a size.
public export
record Written (form : Type) where
  constructor MkWritten
  size : Nat
  symbols : List (Token form)
  0 weighed : weighs symbols = size
  0 fitting : All (Fits size) symbols

||| A request as its chain compares it: the definition, by its address in
||| the context, and the static arguments, one per parameter, `Nothing`
||| where a parameter keys nothing.
public export
record Link (form : Type) where
  constructor MkLink
  definition : Address
  arguments : List (Maybe (Written form))

||| The size of a static argument: 0 where a parameter keys nothing.
public export
argumentSize : Maybe (Written form) -> Nat
argumentSize Nothing = 0
argumentSize (Just w) = w.size

||| The size of each static argument.
public export
sizes : Link form -> List Nat
sizes l = map argumentSize l.arguments

||| An earlier request `x` and a later one `y` of the same definition that
||| a chain cannot hold both of.
public export
data Requested : Link form -> Link form -> Type where
  ||| `y` grows against `x`.
  Grown : (0 _ : x.definition = y.definition) -> Grows (sizes x) (sizes y) -> Requested x y
  ||| `y` has another number of arguments than `x`.
  Arity : (0 _ : x.definition = y.definition) -> (0 _ : Not (length x.arguments = length y.arguments)) ->
          Requested x y
  ||| `y` is `x`.
  Again : (0 _ : x = y) -> Requested x y

DecEq form => DecEq (Token form) where
  decEq (Node f n i) (Node g m j) = case decEq (f, n, i) (g, m, j) of
    Yes Refl => Yes Refl
    No ne => No (\case Refl => ne Refl)
  decEq (Number f i) (Number g j) = case decEq (f, i) (g, j) of
    Yes Refl => Yes Refl
    No ne => No (\case Refl => ne Refl)
  decEq (Node _ _ _) (Number _ _) = No (\case _ impossible)
  decEq (Number _ _) (Node _ _ _) = No (\case _ impossible)

-- Two writings of an argument with the same symbols are one: the proofs
-- that they weigh and fit its size are erased, and unique.
uip : (0 p, q : x = y) -> p = q
uip Refl Refl = Refl

0 lteUnique : (p, q : LTE m n) -> p = q
lteUnique LTEZero LTEZero = Refl
lteUnique (LTESucc p) (LTESucc q) = cong LTESucc (lteUnique p q)

0 fitsUnique : (t : Token form) -> (p, q : Fits s t) -> p = q
fitsUnique (Node _ _ _) p q = lteUnique p q
fitsUnique (Number _ _) p q = lteUnique p q

0 fittingUnique : (ts : List (Token form)) -> (p, q : All (Fits s) ts) -> p = q
fittingUnique [] [] [] = Refl
fittingUnique (t :: ts) (p :: ps) (q :: qs) with (fitsUnique t p q, fittingUnique ts ps qs)
  fittingUnique (t :: ts) (p :: ps) (p :: ps) | (Refl, Refl) = Refl

written : (0 p, q : weighs ts = s) -> (0 b, c : All (Fits s) ts) -> MkWritten s ts p b = MkWritten s ts q c
written p q b c =
  replace {p = \z => MkWritten s ts p b = MkWritten s ts z c} (uip p q)
    (replace {p = \z => MkWritten s ts p b = MkWritten s ts p z} (fittingUnique ts b c) Refl)

writtenEq : s = t -> ts = us -> {0 p : weighs ts = s} -> {0 q : weighs us = t} ->
            {0 b : All (Fits s) ts} -> {0 c : All (Fits t) us} -> MkWritten s ts p b = MkWritten t us q c
writtenEq Refl Refl = written _ _ _ _

DecEq form => DecEq (Written form) where
  decEq (MkWritten s ts p b) (MkWritten t us q c) = case decEq s t of
    No ne => No (\eq => ne (cong (.size) eq))
    Yes same => case decEq ts us of
      No ne => No (\eq => ne (cong (.symbols) eq))
      Yes alike => Yes (writtenEq same alike)

DecEq form => DecEq (Link form) where
  decEq (MkLink d as) (MkLink e bs) = case decEq d e of
    No ne => No (\case Refl => ne Refl)
    Yes Refl => case decEq as bs of
      No ne => No (\case Refl => ne Refl)
      Yes Refl => Yes Refl

||| Requests are kept apart in a map by their links: two links compare
||| equal exactly when every part of them does.
export
Eq form => Eq (Token form) where
  Node f m k == Node g m' k' = f == g && m == m' && k == k'
  Number f k == Number g k' = f == g && k == k'
  _ == _ = False

export
Ord form => Ord (Token form) where
  compare (Node f m k) (Node g m' k') = compare (f, m, k) (g, m', k')
  compare (Number f k) (Number g k') = compare (f, k) (g, k')
  compare (Node _ _ _) (Number _ _) = LT
  compare (Number _ _) (Node _ _ _) = GT

export
Eq form => Eq (Written form) where
  w == v = w.size == v.size && w.symbols == v.symbols

export
Ord form => Ord (Written form) where
  compare w v = compare (w.size, w.symbols) (v.size, v.symbols)

export
Eq form => Eq (Link form) where
  x == y = x.definition == y.definition && x.arguments == y.arguments

export
Ord form => Ord (Link form) where
  compare x y = compare (x.definition, x.arguments) (y.definition, y.arguments)

------------------------------------------------------------------------------
-- Writing within bounds
------------------------------------------------------------------------------

||| What symbols weigh together.
export
0 weighsAppend : (xs, ys : List (Token form)) -> weighs (xs ++ ys) = weighs xs + weighs ys
weighsAppend [] ys = Refl
weighsAppend (x :: xs) ys = rewrite weighsAppend xs ys in plusAssociative (weight x) (weighs xs) (weighs ys)

||| Symbols that fit a bound fit any larger one.
export
0 fittingMore : LTE s s' -> All (Fits s) ts -> All (Fits s') ts
fittingMore le [] = []
fittingMore le ((::) {x = Node _ _ _} f fs) = transitive f le :: fittingMore le fs
fittingMore le ((::) {x = Number _ _} f fs) = transitive f le :: fittingMore le fs

||| Symbols written at a depth fit their weight and the depth together: two
||| runs of them, each fitting its own, fit the two together.
export
0 fittingAppend : (xs, ys : List (Token form)) -> All (Fits (weighs xs + d)) xs -> All (Fits (weighs ys + d)) ys ->
                  All (Fits (weighs (xs ++ ys) + d)) (xs ++ ys)
fittingAppend xs ys fx fy =
  rewrite weighsAppend xs ys in
  fittingMore (plusLteMonotoneRight d (weighs xs) (weighs xs + weighs ys) (lteAddRight (weighs xs))) fx ++
  fittingMore (plusLteMonotoneRight d (weighs ys) (weighs xs + weighs ys)
                 (rewrite plusCommutative (weighs xs) (weighs ys) in lteAddRight (weighs ys))) fy

||| A run written one binder deeper fits after a run that weighs at least
||| one, at the outer depth.
export
0 fittingUnder : (xs, ys : List (Token form)) -> LTE 1 (weighs xs) -> All (Fits (weighs xs + d)) xs ->
                 All (Fits (weighs ys + S d)) ys -> All (Fits (weighs (xs ++ ys) + d)) (xs ++ ys)
fittingUnder xs ys one fx fy =
  rewrite weighsAppend xs ys in
  fittingMore (plusLteMonotoneRight d (weighs xs) (weighs xs + weighs ys) (lteAddRight (weighs xs))) fx ++
  fittingMore {s = weighs ys + S d}
    (replace {p = \b => LTE b ((weighs xs + weighs ys) + d)} (plusSuccRightSucc (weighs ys) d)
       (plusLteMonotoneRight d (S (weighs ys)) (weighs xs + weighs ys)
          (plusLteMonotoneRight (weighs ys) 1 (weighs xs) one)))
    fy

------------------------------------------------------------------------------
-- Comparing requests at runtime
------------------------------------------------------------------------------

-- A `Fin` is the number it is, at runtime as in proofs, so two compare as
-- their numbers.
sameFin : Fin n -> Fin n -> Bool
sameFin i j = finToNat i == finToNat j

0 finInjective : (i, j : Fin n) -> finToNat i = finToNat j -> i = j
finInjective FZ FZ _ = Refl
finInjective (FS i) (FS j) eq = cong FS (finInjective i j (cong pred eq))
finInjective FZ (FS _) eq = absurd eq
finInjective (FS _) FZ eq = absurd eq

0 sameFinSound : (i, j : Fin n) -> So (sameFin i j) -> i = j
sameFinSound i j so = finInjective i j (equalSo so)

0 sameFinSelf : (i : Fin n) -> So (sameFin i i)
sameFinSelf i = equalSelf (finToNat i)

||| Two addresses are one: their bytes compare equal.
export
sameAddress : Vect k (Fin 256) -> Vect k (Fin 256) -> Bool
sameAddress [] [] = True
sameAddress (b :: bs) (c :: cs) = sameFin b c && sameAddress bs cs

export
0 sameAddressSound : (a, b : Vect k (Fin 256)) -> So (sameAddress a b) -> a = b
sameAddressSound [] [] _ = Refl
sameAddressSound (b :: bs) (c :: cs) so =
  let (sb, sbs) = soAnd so in rewrite sameFinSound b c sb in rewrite sameAddressSound bs cs sbs in Refl

export
0 sameAddressSelf : (a : Vect k (Fin 256)) -> So (sameAddress a a)
sameAddressSelf [] = Oh
sameAddressSelf (b :: bs) = andSo (sameFinSelf b, sameAddressSelf bs)

sameName : Maybe Address -> Maybe Address -> Bool
sameName Nothing Nothing = True
sameName (Just a) (Just b) = sameAddress a b
sameName Nothing (Just _) = False
sameName (Just _) Nothing = False

0 sameNameSound : (m, m' : Maybe Address) -> So (sameName m m') -> m = m'
sameNameSound Nothing Nothing _ = Refl
sameNameSound (Just a) (Just b) so = cong Just (sameAddressSound a b so)
sameNameSound Nothing (Just _) so = absurd so
sameNameSound (Just _) Nothing so = absurd so

0 sameNameSelf : (m : Maybe Address) -> So (sameName m m)
sameNameSelf Nothing = Oh
sameNameSelf (Just a) = sameAddressSelf a

yes : Dec p -> Bool
yes (Yes _) = True
yes (No _) = False

sameForm : DecEq form => form -> form -> Bool
sameForm f g = yes (decEq f g)

0 sameFormSound : DecEq form => (f, g : form) -> So (sameForm f g) -> f = g
sameFormSound f g so with (decEq f g)
  sameFormSound f g so | Yes eq = eq
  sameFormSound f g so | No _ = absurd so

0 sameFormSelf : DecEq form => (f : form) -> So (sameForm f f)
sameFormSelf f with (decEq f f)
  sameFormSelf f | Yes _ = Oh
  sameFormSelf f | No ne = absurd (ne Refl)

sameToken : DecEq form => Token form -> Token form -> Bool
sameToken (Node f m k) (Node g m' k') = sameForm f g && (sameName m m' && k == k')
sameToken (Number f k) (Number g k') = sameForm f g && k == k'
sameToken (Node _ _ _) (Number _ _) = False
sameToken (Number _ _) (Node _ _ _) = False

0 sameTokenSound : DecEq form => (t, u : Token form) -> So (sameToken t u) -> t = u
sameTokenSound (Node f m k) (Node g m' k') so =
  let (sf, rest) = soAnd so
      (sm, sk) = soAnd rest in
  rewrite sameFormSound f g sf in rewrite sameNameSound m m' sm in rewrite equalSo {m = k} {n = k'} sk in Refl
sameTokenSound (Number f k) (Number g k') so =
  let (sf, sk) = soAnd so in
  rewrite sameFormSound f g sf in rewrite equalSo {m = k} {n = k'} sk in Refl
sameTokenSound (Node _ _ _) (Number _ _) so = absurd so
sameTokenSound (Number _ _) (Node _ _ _) so = absurd so

0 sameTokenSelf : DecEq form => (t : Token form) -> So (sameToken t t)
sameTokenSelf (Node f m k) = andSo (sameFormSelf f, andSo (sameNameSelf m, equalSelf k))
sameTokenSelf (Number f k) = andSo (sameFormSelf f, equalSelf k)

sameTokens : DecEq form => List (Token form) -> List (Token form) -> Bool
sameTokens [] [] = True
sameTokens (t :: ts) (u :: us) = sameToken t u && sameTokens ts us
sameTokens [] (_ :: _) = False
sameTokens (_ :: _) [] = False

0 sameTokensSound : DecEq form => (ts, us : List (Token form)) -> So (sameTokens ts us) -> ts = us
sameTokensSound [] [] _ = Refl
sameTokensSound (t :: ts) (u :: us) so =
  let (st, sts) = soAnd so in
  rewrite sameTokenSound t u st in rewrite sameTokensSound ts us sts in Refl
sameTokensSound [] (_ :: _) so = absurd so
sameTokensSound (_ :: _) [] so = absurd so

0 sameTokensSelf : DecEq form => (ts : List (Token form)) -> So (sameTokens ts ts)
sameTokensSelf [] = Oh
sameTokensSelf (t :: ts) = andSo (sameTokenSelf t, sameTokensSelf ts)

sameWritten : DecEq form => Written form -> Written form -> Bool
sameWritten w v = w.size == v.size && sameTokens w.symbols v.symbols

0 sameWrittenSound : DecEq form => (w, v : Written form) -> So (sameWritten w v) -> w = v
sameWrittenSound (MkWritten s ts p b) (MkWritten t us q c) so =
  let (ss, sts) = soAnd so in writtenEq (equalSo ss) (sameTokensSound ts us sts)

0 sameWrittenSelf : DecEq form => (w : Written form) -> So (sameWritten w w)
sameWrittenSelf (MkWritten s ts _ _) = andSo (equalSelf s, sameTokensSelf ts)

sameArgument : DecEq form => Maybe (Written form) -> Maybe (Written form) -> Bool
sameArgument Nothing Nothing = True
sameArgument (Just w) (Just v) = sameWritten w v
sameArgument Nothing (Just _) = False
sameArgument (Just _) Nothing = False

0 sameArgumentSound : DecEq form => (a, b : Maybe (Written form)) -> So (sameArgument a b) -> a = b
sameArgumentSound Nothing Nothing _ = Refl
sameArgumentSound (Just w) (Just v) so = cong Just (sameWrittenSound w v so)
sameArgumentSound Nothing (Just _) so = absurd so
sameArgumentSound (Just _) Nothing so = absurd so

0 sameArgumentSelf : DecEq form => (a : Maybe (Written form)) -> So (sameArgument a a)
sameArgumentSelf Nothing = Oh
sameArgumentSelf (Just w) = sameWrittenSelf w

sameArguments : DecEq form => List (Maybe (Written form)) -> List (Maybe (Written form)) -> Bool
sameArguments [] [] = True
sameArguments (a :: as) (b :: bs) = sameArgument a b && sameArguments as bs
sameArguments [] (_ :: _) = False
sameArguments (_ :: _) [] = False

0 sameArgumentsSound : DecEq form => (as, bs : List (Maybe (Written form))) -> So (sameArguments as bs) -> as = bs
sameArgumentsSound [] [] _ = Refl
sameArgumentsSound (a :: as) (b :: bs) so =
  let (sa, sas) = soAnd so in
  rewrite sameArgumentSound a b sa in rewrite sameArgumentsSound as bs sas in Refl
sameArgumentsSound [] (_ :: _) so = absurd so
sameArgumentsSound (_ :: _) [] so = absurd so

0 sameArgumentsSelf : DecEq form => (as : List (Maybe (Written form))) -> So (sameArguments as as)
sameArgumentsSelf [] = Oh
sameArgumentsSelf (a :: as) = andSo (sameArgumentSelf a, sameArgumentsSelf as)

||| Two requests are one: their definitions and arguments compare equal.
sameLink : DecEq form => Link form -> Link form -> Bool
sameLink x y = sameAddress x.definition y.definition && sameArguments x.arguments y.arguments

0 sameLinkSound : DecEq form => (x, y : Link form) -> So (sameLink x y) -> x = y
sameLinkSound (MkLink d as) (MkLink e bs) so =
  let (sd, sas) = soAnd so in
  rewrite sameAddressSound d e sd in rewrite sameArgumentsSound as bs sas in Refl

0 sameLinkSelf : DecEq form => (x : Link form) -> So (sameLink x x)
sameLinkSelf (MkLink d as) = andSo (sameAddressSelf d, sameArgumentsSelf as)

||| Whether a chain cannot hold an earlier `x` and a later `y`, deciding by
||| comparisons of numbers: the definitions' addresses, the numbers of
||| arguments, the sizes, and, between requests of one definition at sizes
||| neither grows against, their symbols.
export
requested : DecEq form => (x, y : Link form) -> Decision (Requested x y)
requested x y = case choose (sameAddress x.definition y.definition) of
  Right nd => Fails (\case Grown d _ => notSame nd d
                           Arity d _ => notSame nd d
                           Again eq => notSame nd (cong (.definition) eq))
  Left sd => case choose (length x.arguments == length y.arguments) of
    Right nl => Holds (Arity (sameAddressSound _ _ sd)
                         (\l => soNotToNotSo nl
                                  (replace {p = \z => So (length x.arguments == z)} l (equalSelf (length x.arguments)))))
    Left sl => case grows (sizes x) (sizes y) of
      Holds g => Holds (Grown (sameAddressSound _ _ sd) g)
      Fails ng => case choose (sameLink x y) of
        Left same => Holds (Again (sameLinkSound x y same))
        Right other => Fails (\case Grown _ g => ng g
                                    Arity _ nl => nl (equalSo sl)
                                    Again eq => soNotToNotSo other
                                                  (replace {p = \z => So (sameLink x z)} eq (sameLinkSelf x)))
  where
    0 notSame : {a, b : Address} -> So (not (sameAddress a b)) -> Not (a = b)
    notSame nd eq = soNotToNotSo nd (replace {p = \z => So (sameAddress a z)} eq (sameAddressSelf a))

------------------------------------------------------------------------------
-- Chains
------------------------------------------------------------------------------

||| The chain's relation on whatever a chain holds, compared by its link.
public export
Via : (e -> Link form) -> Rel e
Via link x y = Requested (link x) (link y)

||| What a chain says of a request: new to every instance on it, or not
||| new to one, which it names with the reason.
public export
data Admission : (e -> Link form) -> List e -> e -> Type where
  Admitted : (0 _ : New (Via link) chain y) -> Admission link chain y
  Refused : (x : e) -> (0 _ : Elem x chain) -> Requested (link x) (link y) -> Admission link chain y

||| A chain's answer to a request, the nearest instance first.
export
admit : DecEq form => (link : e -> Link form) -> (chain : List e) -> (y : e) -> Admission link chain y
admit link [] y = Admitted []
admit link (x :: xs) y = case requested (link x) (link y) of
  Holds r => Refused x Here r
  Fails nr => case admit link xs y of
    Admitted new => Admitted (nr :: new)
    Refused x' e r => Refused x' (There e) r

------------------------------------------------------------------------------
-- The relation is almost full
------------------------------------------------------------------------------

-- Every list of an element of the first followed by one of the second.
conses : List a -> List (List a) -> List (List a)
conses [] _ = []
conses (x :: xs) rest = map (x ::) rest ++ conses xs rest

consesComplete : (xs : List a) -> (rest : List (List a)) -> Elem x xs -> Elem r rest -> Elem (x :: r) (conses xs rest)
consesComplete (y :: _) rest Here er = elemAppendLeft (elemMap (y ::) er)
consesComplete (y :: ys) rest (There ex) er = elemAppendRight (map (y ::) rest) (consesComplete ys rest ex er)

-- Every list of at most `k` elements of a list.
upTo : (k : Nat) -> List a -> List (List a)
upTo Z _ = [[]]
upTo (S k) xs = [] :: conses xs (upTo k xs)

upToComplete : (xs : List a) -> (k : Nat) -> (ys : List a) -> All (\y => Elem y xs) ys ->
               LTE (length ys) k -> Elem ys (upTo k xs)
upToComplete xs Z [] _ _ = Here
upToComplete xs (S k) [] _ _ = Here
upToComplete xs Z (_ :: _) _ le = absurd le
upToComplete xs (S k) (y :: ys) (e :: es) (LTESucc le) =
  There (consesComplete xs (upTo k xs) e (upToComplete xs k ys es le))

lteWeaken : (c : Nat) -> LTE a b -> LTE a (c + b)
lteWeaken Z le = le
lteWeaken (S c) le = lteSuccRight (lteWeaken c le)

-- Every symbol weighs at least one, so an argument has no more symbols
-- than its size.
lengthWeighs : (ts : List (Token form)) -> LTE (length ts) (weighs ts)
lengthWeighs [] = LTEZero
lengthWeighs (Node _ _ _ :: ts) = LTESucc (lengthWeighs ts)
lengthWeighs (Number _ m :: ts) = LTESucc (lteWeaken m (lengthWeighs ts))

joinMap : (a -> List b) -> List a -> List b
joinMap g [] = []
joinMap g (x :: xs) = g x ++ joinMap g xs

joinMapComplete : (g : a -> List b) -> (xs : List a) -> Elem x xs -> Elem y (g x) -> Elem y (joinMap g xs)
joinMapComplete g (_ :: _) Here ey = elemAppendLeft ey
joinMapComplete g (z :: zs) (There ex) ey = elemAppendRight (g z) (joinMapComplete g zs ex ey)

pairs : List a -> List b -> List (a, b)
pairs xs ys = joinMap (\x => map (x,) ys) xs

pairsComplete : (xs : List a) -> (ys : List b) -> Elem x xs -> Elem y ys -> Elem (x, y) (pairs xs ys)
pairsComplete xs ys ex ey = joinMapComplete (\x => map (x,) ys) xs ex (elemMap (_,) ey)

||| Two listed types, in pairs.
export
listedPair : Listed a -> Listed b -> Listed (a, b)
listedPair la lb =
  MkListed (pairs la.values lb.values) (\(x, y) => pairsComplete la.values lb.values (la.complete x) (lb.complete y))

-- The numbers below a bound.
below : Nat -> List Nat
below Z = []
below (S s) = s :: below s

lteNotEqual : {x, y : Nat} -> LTE x y -> Not (x = y) -> LT x y
lteNotEqual {x = Z} {y = Z} _ ne = absurd (ne Refl)
lteNotEqual {x = Z} {y = S _} _ _ = LTESucc LTEZero
lteNotEqual {x = S _} {y = S _} (LTESucc le) ne = LTESucc (lteNotEqual le (\eq => ne (cong S eq)))

belowComplete : (s, k : Nat) -> LT k s -> Elem k (below s)
belowComplete (S s) k (LTESucc le) = case decEq k s of
  Yes Refl => Here
  No ne => There (belowComplete s k (lteNotEqual le ne))

maybes : Listed a -> Listed (Maybe a)
maybes l = MkListed (Nothing :: map Just l.values) complete
  where
    complete : (x : Maybe a) -> Elem x (Nothing :: map Just l.values)
    complete Nothing = Here
    complete (Just x) = There (elemMap Just (l.complete x))

node : (form, (Maybe Address, Nat)) -> Token form
node (f, (n, k)) = Node f n k

number : (form, Nat) -> Token form
number (f, m) = Number f m

-- Every symbol whose numbers fit a size.
tokens : Listed form -> Listed Address -> Nat -> List (Token form)
tokens forms names s =
  map node (pairs forms.values (pairs (maybes names).values (below s))) ++
  map number (pairs forms.values (below s))

tokensComplete : (forms : Listed form) -> (names : Listed Address) -> (s : Nat) -> (t : Token form) -> Fits s t ->
                 Elem t (tokens forms names s)
tokensComplete forms names s (Node f n k) fits =
  elemAppendLeft (elemMap node (pairsComplete forms.values (pairs (maybes names).values (below s)) (forms.complete f)
                                  (pairsComplete (maybes names).values (below s) ((maybes names).complete n)
                                     (belowComplete s k fits))))
tokensComplete forms names s (Number f m) fits =
  elemAppendRight (map node (pairs forms.values (pairs (maybes names).values (below s))))
    (elemMap number (pairsComplete forms.values (below s) (forms.complete f) (belowComplete s m fits)))

decFits : (s : Nat) -> (t : Token form) -> Dec (Fits s t)
decFits s (Node _ _ k) = isLT k s
decFits s (Number _ m) = isLT m s

-- The writing of symbols at a size, if they weigh and fit it.
weighing : (size : Nat) -> List (Token form) -> List (Written form)
weighing size ts with (decEq (weighs ts) size, all (decFits size) ts)
  weighing size ts | (Yes p, Yes b) = [MkWritten size ts p b]
  weighing size ts | _ = []

weighingComplete : (size : Nat) -> (ts : List (Token form)) -> (0 p : weighs ts = size) ->
                   (0 b : All (Fits size) ts) -> Elem (MkWritten size ts p b) (weighing size ts)
weighingComplete size ts p b with (decEq (weighs ts) size, all (decFits size) ts)
  weighingComplete size ts p b | (Yes q, Yes c) =
    replace {p = \w => Elem w [MkWritten size ts q c]} (written q p c b) Here
  weighingComplete size ts p b | (No np, _) = void (np p)
  weighingComplete size ts p b | (Yes _, No nb) = void (nb b)

-- Every argument at a size: none, or one written to weigh and fit it.
writtenAt : Listed form -> Listed Address -> Nat -> List (Maybe (Written form))
writtenAt forms names size =
  Nothing :: map Just (joinMap (weighing size) (upTo size (tokens forms names size)))

inTokens : (forms : Listed form) -> (names : Listed Address) -> (s : Nat) -> (ts : List (Token form)) ->
           All (Fits s) ts -> All (\t => Elem t (tokens forms names s)) ts
inTokens forms names s [] [] = []
inTokens forms names s (t :: ts) (f :: fs) = tokensComplete forms names s t f :: inTokens forms names s ts fs

-- An argument has no more symbols than the size they weigh.
lengthWeighed : (ts : List (Token form)) -> (s : Nat) -> (0 _ : weighs ts = s) -> LTE (length ts) s
lengthWeighed ts s eq = case isLTE (length ts) s of
  Yes le => le
  No nle => void (nle (replace {p = \n => LTE (length ts) n} eq (lengthWeighs ts)))

writtenComplete : (forms : Listed form) -> (names : Listed Address) -> (w : Written form) ->
                  Elem (Just w) (writtenAt forms names w.size)
writtenComplete forms names (MkWritten size ts p b) with (all (decFits size) ts)
  writtenComplete forms names (MkWritten size ts p b) | No nb = void (nb b)
  writtenComplete forms names (MkWritten size ts p b) | Yes fits =
    There (elemMap Just
             (joinMapComplete (weighing size) (upTo size (tokens forms names size))
                (upToComplete (tokens forms names size) size ts (inTokens forms names size ts fits)
                   (lengthWeighed ts size p))
                (weighingComplete size ts p b)))

-- Every list of arguments at a vector of sizes.
argumentsAt : Listed form -> Listed Address -> List Nat -> List (List (Maybe (Written form)))
argumentsAt forms names [] = [[]]
argumentsAt forms names (s :: ss) = conses (writtenAt forms names s) (argumentsAt forms names ss)

argumentsComplete : (forms : Listed form) -> (names : Listed Address) -> (as : List (Maybe (Written form))) ->
                    Elem as (argumentsAt forms names (map Requests.argumentSize as))
argumentsComplete forms names [] = Here
argumentsComplete forms names (Nothing :: as) =
  consesComplete (writtenAt forms names 0) (argumentsAt forms names (map argumentSize as))
                 Here (argumentsComplete forms names as)
argumentsComplete forms names (Just w :: as) =
  consesComplete (writtenAt forms names w.size) (argumentsAt forms names (map argumentSize as))
                 (writtenComplete forms names w) (argumentsComplete forms names as)

-- The requests of a definition at a vector of sizes, all of them.
fibre : Listed form -> Listed Address -> (Address, List Nat) -> List (Link form)
fibre forms names (d, ss) = map (MkLink d) (argumentsAt forms names ss)

fibreComplete : (forms : Listed form) -> (names : Listed Address) -> (l : Link form) ->
                Elem l (fibre forms names (l.definition, sizes l))
fibreComplete forms names (MkLink d as) = elemMap (MkLink d) (argumentsComplete forms names as)

||| Size vectors of one length compared pointwise; of two lengths, always
||| related.
Lengthwise : Rel (List Nat)
Lengthwise xs ys = Either (Not (length xs = length ys)) (Pointwise xs ys)

pad : (k : Nat) -> List Nat -> Vect k Nat
pad Z _ = []
pad (S k) [] = 0 :: pad k []
pad (S k) (x :: xs) = x :: pad k xs

padBelow : (k : Nat) -> (xs, ys : List Nat) -> length xs = k -> length ys = k ->
           Below (pad k xs) (pad k ys) -> Pointwise xs ys
padBelow Z [] [] _ _ _ = []
padBelow Z (_ :: _) _ px _ _ = absurd px
padBelow Z [] (_ :: _) _ py _ = absurd py
padBelow (S _) [] _ px _ _ = absurd px
padBelow (S _) (_ :: _) [] _ py _ = absurd py
padBelow (S k) (x :: xs) (y :: ys) px py (le :: b) = le :: padBelow k xs ys (cong pred px) (cong pred py) b

lengthwiseAt : (a : List Nat) -> Sub (\y, z => Below (pad (length a) y) (pad (length a) z)) (Lift Lengthwise a)
lengthwiseAt a y z b = case decEq (length y) (length a) of
  No ny => Right (Left (\ay => ny (sym ay)))
  Yes ya => case decEq (length z) (length a) of
    No nz => Left (Left (\yz => nz (trans (sym yz) ya)))
    Yes za => Left (Right (padBelow (length a) y z ya za b))

||| Size vectors are almost always pointwise ordered or of two lengths.
afLengthwise : AF Lengthwise
afLengthwise = sup (\a => strengthen (lengthwiseAt a) (inverse (pad (length a)) (dickson (length a))))

-- Related by all three, two requests are related by the chain's relation.
lengthMap : (f : a -> b) -> (xs : List a) -> length (map f xs) = length xs
lengthMap f [] = Refl
lengthMap f (_ :: xs) = cong S (lengthMap f xs)

-- Nowhere larger and not equal is growth.
pointwiseGrows : {bs, as : List Nat} -> Pointwise bs as -> Not (bs = as) -> Grows bs as
pointwiseGrows [] ne = absurd (ne Refl)
pointwiseGrows {bs = b :: bs} {as = a :: as} (le :: pw) ne = case decEq b a of
  Yes Refl => There le (pointwiseGrows pw (\eq => ne (cong (b ::) eq)))
  No nba => Here (lteNotEqual le nba) pw

lower : DecEq form => (x, y : Link form) ->
        (x.definition = y.definition,
         (Lengthwise (sizes x) (sizes y),
          (x.definition, sizes x) = (y.definition, sizes y) -> x = y)) ->
        Requested x y
lower x y (d, (Left nl, _)) =
  Arity d (\l => nl (trans (lengthMap _ x.arguments) (trans l (sym (lengthMap _ y.arguments)))))
lower x y (d, (Right pw, same)) = case decEq (sizes x) (sizes y) of
  Yes s => Again (same (rewrite d in rewrite s in Refl))
  No ns => Grown d (pointwiseGrows pw ns)

||| The chain's relation is almost full over requests whose forms are
||| finitely listed: every chain it admits is finite.
export
afRequested : DecEq form => (forms : Listed form) -> AF {a = Link form} Requested
afRequested forms = afOver forms addresses
  where
    -- Over any listing of the addresses, so that none is spelt out.
    afOver : Listed form -> Listed Address -> AF {a = Link form} Requested
    afOver forms names =
      strengthen lower
        (intersection (inverse (.definition) (finiteEquality names.values names.complete))
           (intersection (inverse sizes afLengthwise)
              (finiteFibres (\l => (l.definition, sizes l)) (fibre forms names) (fibreComplete forms names))))

||| Every chain the relation admits is accessible under extension by a
||| request new to it: a recursion that extends one so ends.
export
chainAccessible : DecEq form => (forms : Listed form) -> (link : e -> Link form) ->
                  (chain : List e) -> Bad (Via link) chain -> Accessible (Extends (Via link)) chain
chainAccessible forms link chain bad = extendsAccessible (inverse link (afRequested forms)) chain bad
