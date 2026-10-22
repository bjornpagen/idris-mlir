-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A request's identity, the listing of every request, and the universe
||| of requests within bounds, which the worklist recurses on.
|||
||| A request is an instance of a definition at static arguments: its link,
||| the definition's address in the context and one written argument per
||| parameter. An argument is written in prefix order, a symbol per node of
||| the term: the node's form (finitely many), the context name it names
||| (finitely many), and a number below the argument's size (a variable's
||| index, a count of arguments); a literal's magnitude weighs as much as
||| itself. An argument's size is the weight of its symbols, so finitely
||| many arguments share a size. The requests of a definition at sizes
||| pointwise at most a bound are finitely many, listed (`Universe`); the
||| growth check gives the bounds (`Bounds`); a request within them is a
||| member of the universe, which `within` decides by comparisons of
||| numbers, so a worklist that keeps each link once has room for fewer at
||| each step. Nothing about the requests is assumed; the bound is in their
||| type.
module IdrisMLIR.Proof.Requests

import IdrisMLIR.Proof.Growth

import public Data.Fin
import Data.Fin.Properties
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.So
import public Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Sizes compared
------------------------------------------------------------------------------

namespace Pointwise
  ||| Two size vectors of one length, the first nowhere larger.
  public export
  data Pointwise : List Nat -> List Nat -> Type where
    Nil : Pointwise [] []
    (::) : (0 _ : LTE b a) -> Pointwise bs as -> Pointwise (b :: bs) (a :: as)

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
listedVia to from back l =
  MkListed (map from l.values)
    (\y => replace {p = \z => Elem z (map from l.values)} (back y) (elemMap from (l.complete (to y))))

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

-- A bit, as the number it adds.
bitOf : Bool -> Nat
bitOf False = 0
bitOf True = 1

0 bitAtMostOne : (b : Bool) -> LTE (bitOf b) 1
bitAtMostOne False = LTEZero
bitAtMostOne True = reflexive

-- A bit and twice a number below `n` are together below twice `n`.
0 twiceBelow : (b : Bool) -> LT x n -> LT (bitOf b + (x + x)) (n + (n + 0))
twiceBelow b lt =
  rewrite plusZeroRightNeutral n in
  transitive (LTESucc (plusLteMonotoneRight (x + x) (bitOf b) 1 (bitAtMostOne b)))
             (replace {p = \z => LTE (S z) (n + n)} (sym (plusSuccRightSucc x x)) (plusLteMonotone lt lt))

-- Twice a number below `n`, and one more for a set bit: a number below
-- twice `n`, computed on the number itself (`finToNat` and `natToFinLT`
-- are the identity at run time), so that a bit costs one step whatever
-- the number.
doubled : (bit : Bool) -> Fin n -> Fin (n + (n + 0))
doubled bit f = natToFinLT (bitOf bit + (finToNat f + finToNat f)) {prf = twiceBelow bit (elemSmallerThanBound f)}

||| The low `d` bits of a non-negative number, a number below `2^d`, read
||| bit by bit: an address's bytes, a character's halves.
export
lowBits : (d : Nat) -> Integer -> Fin (power 2 d)
lowBits Z _ = FZ
lowBits (S d) v = doubled (v `mod` 2 == 1) (lowBits d (v `div` 2))

-- Every vector of a length over a listed type, listed. Stated over any
-- length and type, so that no listing is ever spelt out.
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

-- Every comparison decides, keeping its evidence: the machine compares the
-- numbers (`samePosition`, `==` on naturals), and every proof that the
-- comparison means equality is erased, so a decision costs its comparisons.

export
sameNat : (k, k' : Nat) -> Decision (k = k')
sameNat k k' = case choose (k == k') of
  Left same => Holds (irrelevantEq (equalSo same))
  Right other => Fails (\Refl => soNotToNotSo other (equalSelf k))

-- A form compares as its writer decides.
sameForm : DecEq form => (f, g : form) -> Decision (f = g)
sameForm f g = case decEq f g of
  Yes eq => Holds eq
  No ne => Fails ne

||| Two addresses are one exactly when their bytes are.
export
decideAddress : (a, b : Vect k (Fin 256)) -> Decision (a = b)
decideAddress [] [] = Holds Refl
decideAddress (x :: xs) (y :: ys) = case samePosition x y of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => case decideAddress xs ys of
    Fails ne => Fails (\Refl => ne Refl)
    Holds Refl => Holds Refl

||| Two addresses are one: their bytes compare equal.
export
sameAddress : Vect k (Fin 256) -> Vect k (Fin 256) -> Bool
sameAddress a b = case decideAddress a b of
  Holds _ => True
  Fails _ => False

||| Two optional parts are one when both are absent, or both present and one.
export
sameMaybe : ((x, y : a) -> Decision (x = y)) -> (m, m' : Maybe a) -> Decision (m = m')
sameMaybe same Nothing Nothing = Holds Refl
sameMaybe same (Just x) (Just y) = case same x y of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => Holds Refl
sameMaybe same Nothing (Just _) = Fails (\case Refl impossible)
sameMaybe same (Just _) Nothing = Fails (\case Refl impossible)

||| Two lists are one when they are as long and one at every place.
export
sameList : ((x, y : a) -> Decision (x = y)) -> (xs, ys : List a) -> Decision (xs = ys)
sameList same [] [] = Holds Refl
sameList same (x :: xs) (y :: ys) = case same x y of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => case sameList same xs ys of
    Fails ne => Fails (\Refl => ne Refl)
    Holds Refl => Holds Refl
sameList same [] (_ :: _) = Fails (\case Refl impossible)
sameList same (_ :: _) [] = Fails (\case Refl impossible)

sameToken : DecEq form => (t, u : Token form) -> Decision (t = u)
sameToken (Node f m k) (Node g m' k') = case sameForm f g of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => case sameMaybe decideAddress m m' of
    Fails ne => Fails (\Refl => ne Refl)
    Holds Refl => case sameNat k k' of
      Fails ne => Fails (\Refl => ne Refl)
      Holds Refl => Holds Refl
sameToken (Number f k) (Number g k') = case sameForm f g of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => case sameNat k k' of
    Fails ne => Fails (\Refl => ne Refl)
    Holds Refl => Holds Refl
sameToken (Node _ _ _) (Number _ _) = Fails (\case Refl impossible)
sameToken (Number _ _) (Node _ _ _) = Fails (\case Refl impossible)

-- Two writings are one when their sizes and symbols are: the proofs that
-- the symbols weigh and fit the size are erased, and unique (`writtenEq`).
sameWritten : DecEq form => (w, v : Written form) -> Decision (w = v)
sameWritten (MkWritten s ts p b) (MkWritten t us q c) = case sameNat s t of
  Fails ne => Fails (\eq => ne (cong (.size) eq))
  Holds same => case sameList sameToken ts us of
    Fails ne => Fails (\eq => ne (cong (.symbols) eq))
    Holds alike => Holds (irrelevantEq (writtenEq same alike))

-- Two links are one exactly when their definitions and arguments are.
sameLink : DecEq form => (x, y : Link form) -> Decision (x = y)
sameLink (MkLink d as) (MkLink e bs) = case decideAddress d e of
  Fails ne => Fails (\Refl => ne Refl)
  Holds Refl => case sameList (sameMaybe sameWritten) as bs of
    Fails ne => Fails (\Refl => ne Refl)
    Holds Refl => Holds Refl

||| Links are equal as `sameLink` decides, by the machine's comparisons:
||| what a short list of links, such as the fields the passes learn, is
||| searched by.
export
DecEq form => DecEq (Link form) where
  decEq x y = case sameLink x y of
    Holds eq => Yes eq
    Fails ne => No (\eq => void (ne eq))

------------------------------------------------------------------------------
-- Every request, listed
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

------------------------------------------------------------------------------
-- The requests within bounds
------------------------------------------------------------------------------

||| How large a request may be: for each definition, by its address, the
||| height each static argument of its requests stays within, one per
||| parameter, a parameter past the list's end or at 0 keying nothing; the
||| most children of any template's node (`arity`); the heaviest literal or
||| hole token any template holds (`heaviest`); and the breadth, above
||| every link's length, constructor index and argument index of the
||| reachable program, without which a padded bound would admit a link of
||| any length.
public export
record Bounds where
  constructor MkBounds
  heightAt : Address -> List Nat
  arity : Nat
  heaviest : Nat
  breadth : Nat

||| The bound of each of `n` parameters: the list's, and 0 past its end.
public export
padded : Nat -> List Nat -> List Nat
padded Z _ = []
padded (S n) [] = 0 :: padded n []
padded (S n) (s :: ss) = s :: padded n ss

||| The most nodes a tree of a height has when none has more than `arity`
||| children: arity^0 + arity^1 + ... + arity^(height - 1).
public export
nodesWithin : (arity, height : Nat) -> Nat
nodesWithin arity Z = 0
nodesWithin arity (S h) = 1 + arity * nodesWithin arity h

||| The most a static argument weighs written when it is no higher than
||| `height`, no node of it has more than `arity` children and no literal
||| or hole token weighs more than `heaviest`, its tree read as its key
||| writes it (`Template.closedHeight`):
||| (2 * height + heaviest) * sum [max 1 arity ^ k | k < height].
||| Level k of such a tree has at most (max 1 arity)^k nodes, so it has at
||| most `nodesWithin (max 1 arity) height` of them, a lone leaf counted
||| when the arity is 0. A node's symbols weigh at most twice its height
||| plus the heaviest token: a head of k children writes k applications and
||| its own symbol, which its children's nodes outnumber; a run of n
||| successors with its zero (`Keys.succeeding`), the heaviest symbols a
||| height bounds, weighs 2n + 1 at height n + 1; and any other literal or
||| hole weighs at most `heaviest`. Erased: the number is never computed
||| (`fitsWithin` compares against it).
public export
0 sizeWithin : (arity, height, heaviest : Nat) -> Nat
sizeWithin arity height heaviest = (2 * height + heaviest) * nodesWithin (S (pred arity)) height

-- The counts grow with the height, for at least one child a node.
0 nodesGrow : (m, k, r : Nat) -> LTE (nodesWithin (S m) k) (nodesWithin (S m) (r + k))
nodesGrow m k Z = reflexive
nodesGrow m k (S r) = transitive (nodesGrow m k r) (lteSuccRight (lteAddRight (nodesWithin (S m) (r + k))))

0 timesLte : (c : Nat) -> LTE x y -> LTE (c * x) (c * y)
timesLte Z _ = LTEZero
timesLte (S c) le = plusLteMonotone le (timesLte c le)

-- Below a bound that is itself below another: the second proof is erased,
-- so this costs the first's size, however large the bounds.
lteThrough : LTE a b -> (0 _ : LTE b c) -> LTE a c
lteThrough LTEZero _ = LTEZero
lteThrough (LTESucc p) q = rewrite above q in LTESucc (lteThrough p (fromLteSucc (rewrite sym (above q) in q)))
  where
    0 above : LTE (S n) m -> m = S (pred m)
    above (LTESucc _) = Refl

-- From the count n at level k, r levels below the height: whether `size`
-- fits c times the count at the height. It stops at the first level whose
-- product reaches `size`, since the counts only grow, so it never builds
-- the product at the height.
climb : (size, c, m : Nat) -> (r, k, n : Nat) -> (0 _ : n = nodesWithin (S m) k) ->
        Decision (LTE size (c * nodesWithin (S m) (r + k)))
climb size c m r k n eq = case choose (size <= c * n) of
  Left fits =>
    Holds (lteThrough (lteSo fits)
             (replace {p = \z => LTE (c * z) (c * nodesWithin (S m) (r + k))} (sym eq) (timesLte c (nodesGrow m k r))))
  Right over => case r of
    Z => Fails (\le => notLteSo over (replace {p = \z => LTE size (c * z)} (sym eq) le))
    S r' => replace {p = \t => Decision (LTE size (c * nodesWithin (S m) t))} (sym (plusSuccRightSucc r' k))
              (climb size c m r' (S k) (1 + S m * n) (cong (\z => 1 + S m * z) eq))

-- Whether a static argument of a size fits `sizeWithin`, by comparisons of
-- numbers no larger than the size times the first factor: the terms are
-- summed only until they pass the size, at most `height` of them.
fitsWithin : (size, arity, height, heaviest : Nat) -> Decision (LTE size (sizeWithin arity height heaviest))
fitsWithin size arity height heaviest =
  replace {p = \t => Decision (LTE size ((2 * height + heaviest) * nodesWithin (S (pred arity)) t))}
          (plusZeroRightNeutral height)
          (climb size (2 * height + heaviest) (pred arity) height 0 0 Refl)

||| The sizes each of a definition's `n` parameters stays within.
public export
0 sizesAt : Bounds -> Nat -> Address -> List Nat
sizesAt b n d = map (\h => sizeWithin b.arity h b.heaviest) (padded n (b.heightAt d))

-- Every size vector pointwise at most a bound.
vectorsBelow : List Nat -> List (List Nat)
vectorsBelow [] = [[]]
vectorsBelow (b :: bs) = conses (below (S b)) (vectorsBelow bs)

0 vectorsBelowComplete : (ss, bs : List Nat) -> Pointwise ss bs -> Elem ss (vectorsBelow bs)
vectorsBelowComplete [] [] [] = Here
vectorsBelowComplete (s :: ss) (b :: bs) (le :: pw) =
  consesComplete (below (S b)) (vectorsBelow bs) (belowComplete (S b) s (LTESucc le))
                 (vectorsBelowComplete ss bs pw)

||| Every link within the bounds: of every definition, with at most the
||| breadth of arguments, at every list of them each of whose sizes is at
||| most `sizeWithin` of its parameter's height. Stated over any listing of
||| the addresses (callers pass `addresses`), so that none is spelt out
||| where two are compared. It is finite, and never computed: it is the
||| room a worklist that keeps each link once recurses on.
public export
0 Universe : Listed form -> Listed Address -> Bounds -> List (Link form)
Universe forms names b =
  joinMap (\d => joinMap (\n => joinMap (\ss => fibre forms names (d, ss)) (vectorsBelow (sizesAt b n d)))
                         (below (S b.breadth)))
          names.values

0 inUniverse : (forms : Listed form) -> (names : Listed Address) -> (b : Bounds) -> (l : Link form) ->
               LTE (length l.arguments) b.breadth ->
               Pointwise (sizes l) (sizesAt b (length l.arguments) l.definition) ->
               Elem l (Universe forms names b)
inUniverse forms names b l short sized =
  joinMapComplete (\d => joinMap (\n => joinMap (\ss => fibre forms names (d, ss)) (vectorsBelow (sizesAt b n d)))
                                 (below (S b.breadth)))
                  names.values (names.complete l.definition)
    (joinMapComplete (\n => joinMap (\ss => fibre forms names (l.definition, ss)) (vectorsBelow (sizesAt b n l.definition)))
                     (below (S b.breadth)) (belowComplete (S b.breadth) (length l.arguments) (LTESucc short))
       (joinMapComplete (\ss => fibre forms names (l.definition, ss))
                        (vectorsBelow (sizesAt b (length l.arguments) l.definition))
                        (vectorsBelowComplete (sizes l) (sizesAt b (length l.arguments) l.definition) sized)
          (fibreComplete forms names l)))

||| A link within the bounds: the comparisons `within` made, and the
||| membership in the universe they give, all erased. The membership's
||| index is a place in a list never computed, so it is no value at
||| runtime.
public export
record InUniverse (0 forms : Listed form) (0 names : Listed Address) (b : Bounds) (l : Link form) where
  constructor MkIn
  0 short : LTE (length l.arguments) b.breadth
  0 sized : Pointwise (sizes l) (sizesAt b (length l.arguments) l.definition)
  0 member : Elem l (Universe forms names b)

||| Whether a link is within the bounds, by the machine's comparisons: its
||| number of arguments against the breadth, and each argument's size
||| against `sizeWithin` of its parameter's height (`fitsWithin`), the
||| heights padded with 0.
export
within : (0 forms : Listed form) -> (0 names : Listed Address) -> (b : Bounds) -> (l : Link form) ->
         Decision (InUniverse forms names b l)
within forms names b l = case choose (length l.arguments <= b.breadth) of
  Right long => Fails (\inside => notLteSo long inside.short)
  Left fits => case allFit l.arguments (b.heightAt l.definition) of
    Fails large => Fails (\inside => large inside.sized)
    Holds sized => Holds (MkIn (lteSo fits) sized (inUniverse forms names b l (lteSo fits) sized))
  where
    -- One argument against its parameter's height, then the rest.
    next : (a : Maybe (Written form)) -> (h : Nat) -> Lazy (Decision (Pointwise ss hs)) ->
           Decision (Pointwise (argumentSize a :: ss) (sizeWithin b.arity h b.heaviest :: hs))
    next a h rest = case fitsWithin (argumentSize a) b.arity h b.heaviest of
      Fails over => Fails (\(le :: _) => over le)
      Holds le => case rest of
        Fails more => Fails (\(_ :: pw) => more pw)
        Holds pw => Holds (le :: pw)

    -- Down the arguments, the heights padded with 0 as they run out, as
    -- `padded` pads them: one height for each argument.
    allFit : (as : List (Maybe (Written form))) -> (hs : List Nat) ->
             Decision (Pointwise (map Requests.argumentSize as) (map (\h => sizeWithin b.arity h b.heaviest) (padded (length as) hs)))
    allFit [] _ = Holds []
    allFit (a :: as) [] = next a 0 (allFit as [])
    allFit (a :: as) (h :: hs) = next a h (allFit as hs)

||| Whether a link is one of a list's, by the machine's comparisons
||| (`sameLink`). A chain of requests decides it of each request that
||| extends it: the erased evidence that the link is not one of the chain's
||| keeps the chain free of duplicates.
export
elemLink : DecEq form => (l : Link form) -> (ls : List (Link form)) -> Decision (Elem l ls)
elemLink l [] = Fails absurd
elemLink l (k :: ks) = case sameLink l k of
  Holds Refl => Holds Here
  Fails other => case elemLink l ks of
    Holds e => Holds (There e)
    Fails ne => Fails (neitherHereNorThere other ne)
