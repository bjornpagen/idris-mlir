-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Almost-full relations: the constructive form of a well-quasi-order, in
||| which "every infinite sequence has an earlier element related to a later
||| one" is an inductive fact a recursion can descend on.
|||
||| A relation is almost full when it is full (every pair related), or when,
||| whatever element comes first, the relation lifted by it is almost full.
||| Lifting by `x` relates `y` to `z` when the relation does, or when `x` is
||| related to `y`: the sequence that starts with `x` is good as soon as a
||| later element is above `x`. The witness is kept apart from the relation
||| (a tree, and a proof that the tree secures the relation), so that every
||| construction is a structural recursion on trees and weakening a relation
||| keeps its tree.
|||
||| What is proved here: `<=` on naturals is almost full; almost-full
||| relations are closed under weakening, union, inverse image and
||| intersection (the intuitionistic Ramsey theorem), hence under products,
||| and so pointwise `<=` on vectors of naturals is almost full (Dickson's
||| lemma); equality on a type is almost full where every fibre of a map
||| from it is finitely listed; and an almost-full relation makes the
||| extension of a bad sequence by an element new to it well founded, so a
||| recursion that keeps its sequence bad ends.
module IdrisMLIR.Proof.AlmostFull

import Control.Relation
import Control.WellFounded
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Relations, trees and security
------------------------------------------------------------------------------

||| The relation once `x` has been seen: `y` and `z` are related when the
||| relation relates them, or relates `x` to `y`.
public export
Lift : Rel a -> a -> Rel a
Lift r x = \y, z => Either (r y z) (r x y)

||| A well-founded tree branching over `a`: the shape of an almost-full
||| witness, apart from the relation it secures.
public export
data WFT : Type -> Type where
  ZT : WFT a
  SUP : (a -> WFT a) -> WFT a

||| A tree secures a relation when the relation is full at each leaf, the
||| relation lifted by every element seen on the way there.
public export
SecureBy : {a : Type} -> Rel a -> WFT a -> Type
SecureBy r ZT = (x, y : a) -> r x y
SecureBy r (SUP f) = (x : a) -> SecureBy (Lift r x) (f x)

||| An almost-full relation: a tree, and the proof that it secures it.
public export
record AF {a : Type} (r : Rel a) where
  constructor MkAF
  tree : WFT a
  secure : SecureBy r tree

||| An inclusion of relations.
public export
Sub : {a : Type} -> Rel a -> Rel a -> Type
Sub r s = (x, y : a) -> r x y -> s x y

||| An inclusion holds of the relations lifted by the same element.
liftSub : {0 r, s : Rel a} -> Sub r s -> (x : a) -> Sub (Lift r x) (Lift s x)
liftSub h x y z (Left p) = Left (h y z p)
liftSub h x y z (Right p) = Right (h x y p)

||| A tree that secures a relation secures every weaker one.
export
secStrengthen : {0 r, s : Rel a} -> (p : WFT a) -> SecureBy r p -> Sub r s -> SecureBy s p
secStrengthen ZT sec h = \x, y => h x y (sec x y)
secStrengthen (SUP f) sec h = \x => secStrengthen (f x) (sec x) (liftSub h x)

||| A relation that includes an almost-full one is almost full.
export
strengthen : {0 r, s : Rel a} -> Sub r s -> AF r -> AF s
strengthen h (MkAF p sec) = MkAF p (secStrengthen p sec h)

||| A full relation is almost full.
export
full : {0 r : Rel a} -> ((x, y : a) -> r x y) -> AF r
full h = MkAF ZT h

||| A relation is almost full when, whatever comes first, the relation
||| lifted by it is.
export
sup : {0 r : Rel a} -> ((x : a) -> AF (Lift r x)) -> AF r
sup f = MkAF (SUP (\x => (f x).tree)) (\x => (f x).secure)

||| The union with an almost-full relation is almost full.
export
union : {0 r, s : Rel a} -> AF r -> AF (\x, y => Either (r x y) (s x y))
union = strengthen (\_, _ => Left)

------------------------------------------------------------------------------
-- Naturals
------------------------------------------------------------------------------

||| `<=` once an element at least `n` would end the sequence: a later
||| element is above an earlier one, or the earlier one is at least `n`.
Capped : Nat -> Rel Nat
Capped n = \y, z => Either (LTE y z) (LTE n y)

||| `Capped n` is almost full, for every `n` up to a bound the recursion
||| descends on: once `x` is seen, either `x >= n` ends it, or what remains
||| is `Capped x` with `x < n`.
capped : (bound, n : Nat) -> LTE n bound -> AF (Capped n)
capped bound Z _ = full (\_, _ => Right LTEZero)
capped Z (S n) le = absurd le
capped (S bound) (S n) (LTESucc le) = sup next
  where
    next : (x : Nat) -> AF (Lift (Capped (S n)) x)
    next x = case isLTE (S n) x of
      Yes big => full (\_, _ => Right (Right big))
      No small =>
        strengthen (\y, z, c => case c of
                                  Left yz => Left (Left yz)
                                  Right xy => Right (Left xy))
                   (capped bound x (transitive (fromLteSucc (notLTEImpliesGT small)) le))

||| `<=` on naturals is almost full.
export
afLTE : AF {a = Nat} LTE
afLTE = sup (\x => capped x x reflexive)

------------------------------------------------------------------------------
-- Intersection: the intuitionistic Ramsey theorem
------------------------------------------------------------------------------

-- The tree of an intersection is built from the two trees in three
-- stages, each a structural recursion on its trees: the nullary sum
-- secures a relation joined with the conjunction of two propositions that
-- do not depend on the elements, the unary sum one joined with the
-- conjunction of two predicates on the earlier element, and the binary sum
-- the intersection itself.

oplusNullary : WFT a -> WFT a -> WFT a
oplusNullary ZT q = q
oplusNullary (SUP f) q = SUP (\x => oplusNullary (f x) q)

oplusUnary : WFT a -> WFT a -> WFT a
oplusUnary ZT q = q
oplusUnary (SUP f) ZT = SUP f
oplusUnary (SUP f) (SUP g) =
  SUP (\x => oplusNullary (oplusUnary (f x) (SUP g)) (oplusUnary (SUP f) (g x)))

oplusBinary : WFT a -> WFT a -> WFT a
oplusBinary ZT q = q
oplusBinary (SUP f) ZT = SUP f
oplusBinary (SUP f) (SUP g) =
  SUP (\x => oplusUnary (oplusBinary (f x) (SUP g)) (oplusBinary (SUP f) (g x)))

-- Each inclusion the constructions need is stated on its own, so that the
-- relations are explicit where the proofs regroup them.

nullaryLeaf : {0 c : Rel a} -> {0 pa, pb : Type} -> ((y, z : a) -> Either (c y z) pa) ->
              Sub (\y, z => Either (c y z) pb) (\y, z => Either (c y z) (pa, pb))
nullaryLeaf sp y z (Left yz) = Left yz
nullaryLeaf sp y z (Right b) = case sp y z of
  Left yz => Left yz
  Right a => Right (a, b)

nullaryIn : {0 c : Rel a} -> {0 pa : Type} -> (x : a) ->
            Sub (Lift (\y, z => Either (c y z) pa) x) (\y, z => Either (Either (c y z) (c x y)) pa)
nullaryIn x y z (Left (Left yz)) = Left (Left yz)
nullaryIn x y z (Left (Right a)) = Right a
nullaryIn x y z (Right (Left xy)) = Left (Right xy)
nullaryIn x y z (Right (Right a)) = Right a

nullaryWeak : {0 c : Rel a} -> {0 pb : Type} -> (x : a) ->
              Sub (\y, z => Either (c y z) pb) (\y, z => Either (Either (c y z) (c x y)) pb)
nullaryWeak x y z (Left yz) = Left (Left yz)
nullaryWeak x y z (Right b) = Right b

nullaryOut : {0 c : Rel a} -> {0 p : Type} -> (x : a) ->
             Sub (\y, z => Either (Either (c y z) (c x y)) p) (Lift (\y, z => Either (c y z) p) x)
nullaryOut x y z (Left (Left yz)) = Left (Left yz)
nullaryOut x y z (Left (Right xy)) = Right (Left xy)
nullaryOut x y z (Right ab) = Left (Right ab)

nullarySecure : {0 c : Rel a} -> {0 pa, pb : Type} -> (p, q : WFT a) ->
                SecureBy (\y, z => Either (c y z) pa) p ->
                SecureBy (\y, z => Either (c y z) pb) q ->
                SecureBy (\y, z => Either (c y z) (pa, pb)) (oplusNullary p q)
nullarySecure ZT q sp sq = secStrengthen q sq (nullaryLeaf sp)
nullarySecure {c} {pa} {pb} (SUP f) q sp sq = \x =>
  secStrengthen (oplusNullary (f x) q)
    (nullarySecure {c = \y, z => Either (c y z) (c x y)} {pa} {pb} (f x) q
       (secStrengthen (f x) (sp x) (nullaryIn x))
       (secStrengthen q sq (nullaryWeak x)))
    (nullaryOut x)

unaryLeft : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> ((y, z : a) -> Either (c y z) (pa y)) ->
            Sub (\y, z => Either (c y z) (pb y)) (\y, z => Either (c y z) (pa y, pb y))
unaryLeft sp y z (Left yz) = Left yz
unaryLeft sp y z (Right b) = case sp y z of
  Left yz => Left yz
  Right a => Right (a, b)

unaryRight : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> ((y, z : a) -> Either (c y z) (pb y)) ->
             Sub (\y, z => Either (c y z) (pa y)) (\y, z => Either (c y z) (pa y, pb y))
unaryRight sq y z (Left yz) = Left yz
unaryRight sq y z (Right a) = case sq y z of
  Left yz => Left yz
  Right b => Right (a, b)

-- After `x`, the predicate on the later element absorbs what relates `x`
-- to it and what holds of `x` itself.
Absorbed : Rel a -> (a -> Type) -> a -> a -> Type
Absorbed c p x y = Either (c x y) (Either (p y) (p x))

-- What the two halves of the unary step meet in: the pair related, `x`
-- related to the later element, or both predicates of the later element.
Met : Rel a -> (pa, pb : a -> Type) -> a -> Rel a
Met c pa pb x y z = Either (c y z) (Either (c x y) (pa y, pb y))

unaryIn : {0 c : Rel a} -> {0 p : a -> Type} -> (x : a) ->
          Sub (Lift (\y, z => Either (c y z) (p y)) x) (\y, z => Either (c y z) (Absorbed c p x y))
unaryIn x y z (Left (Left yz)) = Left yz
unaryIn x y z (Left (Right py)) = Right (Right (Left py))
unaryIn x y z (Right (Left xy)) = Right (Left xy)
unaryIn x y z (Right (Right px)) = Right (Right (Right px))

unaryOutA : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> (x : a) ->
            Sub (\y, z => Either (c y z) (Absorbed c pa x y, pb y)) (\y, z => Either (Met c pa pb x y z) (pa x))
unaryOutA x y z (Left yz) = Left (Left yz)
unaryOutA x y z (Right (Left xy, _)) = Left (Right (Left xy))
unaryOutA x y z (Right (Right (Left ay), by)) = Left (Right (Right (ay, by)))
unaryOutA x y z (Right (Right (Right ax), _)) = Right ax

unaryOutB : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> (x : a) ->
            Sub (\y, z => Either (c y z) (pa y, Absorbed c pb x y)) (\y, z => Either (Met c pa pb x y z) (pb x))
unaryOutB x y z (Left yz) = Left (Left yz)
unaryOutB x y z (Right (_, Left xy)) = Left (Right (Left xy))
unaryOutB x y z (Right (ay, Right (Left by))) = Left (Right (Right (ay, by)))
unaryOutB x y z (Right (_, Right (Right bx))) = Right bx

unaryOut : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> (x : a) ->
           Sub (\y, z => Either (Met c pa pb x y z) (pa x, pb x)) (Lift (\y, z => Either (c y z) (pa y, pb y)) x)
unaryOut x y z (Left (Left yz)) = Left (Left yz)
unaryOut x y z (Left (Right (Left xy))) = Right (Left xy)
unaryOut x y z (Left (Right (Right ab))) = Left (Right ab)
unaryOut x y z (Right ab) = Right (Right ab)

unarySecure : {0 c : Rel a} -> {0 pa, pb : a -> Type} -> (p, q : WFT a) ->
              SecureBy (\y, z => Either (c y z) (pa y)) p ->
              SecureBy (\y, z => Either (c y z) (pb y)) q ->
              SecureBy (\y, z => Either (c y z) (pa y, pb y)) (oplusUnary p q)
unarySecure ZT q sp sq = secStrengthen q sq (unaryLeft sp)
unarySecure (SUP f) ZT sp sq = secStrengthen (SUP f) sp (unaryRight sq)
unarySecure {c} {pa} {pb} (SUP f) (SUP g) sp sq = \x =>
  secStrengthen (oplusNullary (oplusUnary (f x) (SUP g)) (oplusUnary (SUP f) (g x)))
    (nullarySecure {c = Met c pa pb x} {pa = pa x} {pb = pb x}
       (oplusUnary (f x) (SUP g)) (oplusUnary (SUP f) (g x))
       (secStrengthen (oplusUnary (f x) (SUP g))
          (unarySecure {c} {pa = Absorbed c pa x} {pb} (f x) (SUP g)
             (secStrengthen (f x) (sp x) (unaryIn x)) sq)
          (unaryOutA x))
       (secStrengthen (oplusUnary (SUP f) (g x))
          (unarySecure {c} {pa} {pb = Absorbed c pb x} (SUP f) (g x)
             sp (secStrengthen (g x) (sq x) (unaryIn x)))
          (unaryOutB x)))
    (unaryOut x)

binaryLeaf : {0 r, s : Rel a} -> ((y, z : a) -> r y z) -> Sub s (\y, z => (r y z, s y z))
binaryLeaf sp y z b = (sp y z, b)

binaryLeaf' : {0 r, s : Rel a} -> ((y, z : a) -> s y z) -> Sub r (\y, z => (r y z, s y z))
binaryLeaf' sq y z a = (a, sq y z)

binaryInP : {0 r, s : Rel a} -> (x : a) ->
            Sub (\y, z => (Lift r x y z, s y z)) (\y, z => Either (r y z, s y z) (r x y))
binaryInP x y z (Left yz, syz) = Left (yz, syz)
binaryInP x y z (Right xy, _) = Right xy

binaryInQ : {0 r, s : Rel a} -> (x : a) ->
            Sub (\y, z => (r y z, Lift s x y z)) (\y, z => Either (r y z, s y z) (s x y))
binaryInQ x y z (ryz, Left yz) = Left (ryz, yz)
binaryInQ x y z (_, Right xy) = Right xy

binaryOut : {0 r, s : Rel a} -> (x : a) ->
            Sub (\y, z => Either (r y z, s y z) (r x y, s x y)) (Lift (\y, z => (r y z, s y z)) x)
binaryOut x y z e = e

binarySecure : {0 r, s : Rel a} -> (p, q : WFT a) -> SecureBy r p -> SecureBy s q ->
               SecureBy (\y, z => (r y z, s y z)) (oplusBinary p q)
binarySecure ZT q sp sq = secStrengthen q sq (binaryLeaf sp)
binarySecure (SUP f) ZT sp sq = secStrengthen (SUP f) sp (binaryLeaf' sq)
binarySecure {r} {s} (SUP f) (SUP g) sp sq = \x =>
  secStrengthen (oplusUnary (oplusBinary (f x) (SUP g)) (oplusBinary (SUP f) (g x)))
    (unarySecure {c = \y, z => (r y z, s y z)} {pa = r x} {pb = s x}
       (oplusBinary (f x) (SUP g)) (oplusBinary (SUP f) (g x))
       (secStrengthen (oplusBinary (f x) (SUP g))
          (binarySecure {r = Lift r x} {s} (f x) (SUP g) (sp x) sq) (binaryInP x))
       (secStrengthen (oplusBinary (SUP f) (g x))
          (binarySecure {r} {s = Lift s x} (SUP f) (g x) sp (sq x)) (binaryInQ x)))
    (binaryOut x)

||| The intersection of two almost-full relations is almost full.
export
intersection : {0 r, s : Rel a} -> AF r -> AF s -> AF (\x, y => (r x y, s x y))
intersection (MkAF p sp) (MkAF q sq) = MkAF (oplusBinary p q) (binarySecure p q sp sq)

------------------------------------------------------------------------------
-- Inverse images and products
------------------------------------------------------------------------------

cofmap : (b -> a) -> WFT a -> WFT b
cofmap g ZT = ZT
cofmap g (SUP w) = SUP (\y => cofmap g (w (g y)))

cofmapSecure : {0 r : Rel a} -> (g : b -> a) -> (p : WFT a) -> SecureBy r p ->
               SecureBy (\x, y => r (g x) (g y)) (cofmap g p)
cofmapSecure g ZT sec = \x, y => sec (g x) (g y)
cofmapSecure g (SUP w) sec = \y => cofmapSecure g (w (g y)) (sec (g y))

||| A relation compared through a map is almost full when the relation is.
export
inverse : {0 r : Rel a} -> (g : b -> a) -> AF r -> AF (\x, y => r (g x) (g y))
inverse g (MkAF p sec) = MkAF (cofmap g p) (cofmapSecure g p sec)

||| Two almost-full relations, one on each component, are almost full on
||| pairs.
export
product : {0 r : Rel a} -> {0 s : Rel b} -> AF r -> AF s ->
          AF (\x, y : (a, b) => (r (fst x) (fst y), s (snd x) (snd y)))
product ar as = intersection (inverse fst ar) (inverse snd as)

namespace Below
  ||| Pointwise `<=` on vectors of naturals.
  public export
  data Below : Vect k Nat -> Vect k Nat -> Type where
    Nil : Below [] []
    (::) : LTE x y -> Below xs ys -> Below (x :: xs) (y :: ys)

||| Dickson's lemma: pointwise `<=` on vectors of naturals of one length is
||| almost full.
export
dickson : (k : Nat) -> AF {a = Vect k Nat} Below
dickson Z = full (\[], [] => [])
dickson (S k) =
  strengthen (\(x :: xs), (y :: ys), (le, below) => le :: below)
             (intersection (inverse head afLTE) (inverse tail (dickson k)))

------------------------------------------------------------------------------
-- Finitely listed fibres
------------------------------------------------------------------------------

-- Once `seen` holds elements of the fibre of `s`, a later element can only
-- be new while it lies in the fibre and is not yet seen.
Unseen : {a : Type} -> (f : a -> v) -> v -> List a -> Rel a
Unseen f s seen y z = Either (Not (f y = s)) (Either (Elem y seen) (f y = f z -> y = z))

-- Every element of the fibre of `s` is seen or still to come.
Covers : {a : Type} -> (f : a -> v) -> v -> List a -> List a -> Type
Covers f s seen rest = (k : a) -> f k = s -> Either (Elem k seen) (Elem k rest)

elemDropped : Elem k xs -> (p : Elem b xs) -> Not (k = b) -> Elem k (dropElem xs p)
elemDropped Here Here ne = absurd (ne Refl)
elemDropped (There e) Here ne = e
elemDropped Here (There p) ne = Here
elemDropped (There e) (There p) ne = There (elemDropped e p ne)

dropShorter : (xs : List a) -> (p : Elem b xs) -> LT (length (dropElem xs p)) (length xs)
dropShorter (_ :: ys) Here = reflexive
dropShorter (_ :: ys) (There p) = LTESucc (dropShorter ys p)

grow : {0 f : a -> v} -> {0 s : v} -> (b : a) -> Sub (Unseen f s (b :: seen)) (Lift (Unseen f s seen) b)
grow b y z (Left out) = Left (Left out)
grow b b z (Right (Left Here)) = Right (Right (Right (\_ => Refl)))
grow b y z (Right (Left (There e))) = Left (Right (Left e))
grow b y z (Right (Right h)) = Left (Right (Right h))

-- The elements of a fibre still to come are fewer once one of them is
-- seen, and none is left to come once all are.
unseen : DecEq a => DecEq v => (f : a -> v) -> (s : v) -> (seen, rest : List a) ->
         Covers f s seen rest -> (0 _ : SizeAccessible rest) -> AF (Unseen f s seen)
unseen f s seen rest cov (Access rec) = sup next
  where
    next : (b : a) -> AF (Lift (Unseen f s seen) b)
    next b with (decEq (f b) s)
      next b | No out = full (\_, _ => Right (Left out))
      next b | Yes inside with (isElem b seen)
        next b | Yes inside | Yes old = full (\_, _ => Right (Right (Left old)))
        next b | Yes inside | No new with (cov b inside)
          next b | Yes inside | No new | Left old = absurd (new old)
          next b | Yes inside | No new | Right here =
            strengthen (grow b)
              (unseen f s (b :: seen) (dropElem rest here) covered
                 (rec (dropElem rest here) (dropShorter rest here)))
            where
              covered : Covers f s (b :: seen) (dropElem rest here)
              covered k eq with (cov k eq)
                covered k eq | Left old = Left (There old)
                covered k eq | Right later with (decEq k b)
                  covered k eq | Right later | Yes same = rewrite same in Left Here
                  covered k eq | Right later | No other = Right (elemDropped later here other)

||| Where every fibre of a map is finitely listed, the elements it maps
||| alike are almost always equal: a sequence on which no earlier element
||| equals a later one it maps alike is finite.
export
finiteFibres : DecEq a => DecEq v => (f : a -> v) -> (fibre : v -> List a) ->
               ((x : a) -> Elem x (fibre (f x))) -> AF (\x, y => f x = f y -> x = y)
finiteFibres f fibre listed = sup first
  where
    start : (x : a) -> Sub (Unseen f (f x) [x]) (Lift (\x, y => f x = f y -> x = y) x)
    start x y z (Left out) = Right (\eq => absurd (out (sym eq)))
    start x x z (Right (Left Here)) = Right (\_ => Refl)
    start x y z (Right (Left (There e))) = absurd e
    start x y z (Right (Right h)) = Left h

    first : (x : a) -> AF (Lift (\x, y => f x = f y -> x = y) x)
    first x = strengthen (start x)
                (unseen f (f x) [x] (fibre (f x))
                   (\k, eq => Prelude.Right (rewrite sym eq in listed k))
                   (sizeAccessible (fibre (f x))))

||| Equality on a finitely listed type is almost full.
export
finiteEquality : DecEq a => (all : List a) -> ((x : a) -> Elem x all) -> AF {a} (\x, y => x = y)
finiteEquality all listed =
  strengthen (\_, _, h => h Refl) (finiteFibres (const ()) (const all) listed)

------------------------------------------------------------------------------
-- Bad sequences end
------------------------------------------------------------------------------

||| `x` is new to a sequence when no element of it is related to `x`.
public export
New : Rel a -> List a -> a -> Type
New r xs x = All (\y => Not (r y x)) xs

namespace Bad
  ||| A sequence, latest first, in which no element is related to a later
  ||| one.
  public export
  data Bad : Rel a -> List a -> Type where
    Nil : Bad r []
    (::) : New r xs x -> Bad r xs -> Bad r (x :: xs)

||| A bad sequence extended by an element new to it.
public export
data Extends : Rel a -> List a -> List a -> Type where
  Extend : New r xs x -> Extends r (x :: xs) xs

-- The relation lifted by every element of a sequence, the earliest first.
Lifted : Rel a -> List a -> Rel a
Lifted r [] = r
Lifted r (x :: xs) = Lift (Lifted r xs) x

-- After a bad sequence, an element new to it is related to a later one
-- by the lifted relation only as the relation relates them.
liftedBad : {0 r : Rel a} -> Bad r xs -> New r xs y -> Lifted r xs y z -> r y z
liftedBad [] [] l = l
liftedBad (nx :: bxs) (ny :: nys) (Left l) = liftedBad bxs nys l
liftedBad (nx :: bxs) (ny :: nys) (Right l) = absurd (ny (liftedBad bxs nx l))

securedAccessible : {0 r : Rel a} -> (p : WFT a) -> SecureBy (Lifted r xs) p -> Bad r xs ->
                    Accessible (Extends r) xs
securedAccessible ZT sec bad = Access first
  where
    -- Once the lifted relation is full, a second element new to the
    -- sequence would be related to the first.
    second : (y : a) -> New r xs y -> (zs : List a) -> Extends r zs (y :: xs) -> Accessible (Extends r) zs
    second y ny (z :: _) (Extend (nyz :: _)) = absurd (nyz (liftedBad bad ny (sec y z)))

    first : (ys : List a) -> Extends r ys xs -> Accessible (Extends r) ys
    first (y :: _) (Extend ny) = Access (second y ny)
securedAccessible (SUP f) sec bad = Access next
  where
    next : (ys : List a) -> Extends r ys xs -> Accessible (Extends r) ys
    next (y :: _) (Extend ny) = securedAccessible (f y) (sec y) (ny :: bad)

||| Under an almost-full relation, extending a bad sequence by an element
||| new to it is well founded: a recursion that extends one so ends.
export
extendsAccessible : {0 r : Rel a} -> AF r -> (xs : List a) -> Bad r xs -> Accessible (Extends r) xs
extendsAccessible af [] [] = securedAccessible af.tree af.secure []
extendsAccessible af (x :: xs) (nx :: bxs) =
  let Access rec = extendsAccessible af xs bxs in rec (x :: xs) (Extend nx)
