-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A worklist processed a generation at a time ends when each element of a
||| generation is below an element of the one before under a well-founded
||| relation.
|||
||| First in, first out, a worklist takes the elements requested while it
||| took one generation only once that generation is done: they are the
||| next generation, and each of them was requested by an element of the
||| last. If every requested element is below its requester under a
||| relation along which every element is accessible, the generations
||| themselves descend under a well-founded relation: a generation is below
||| another when the other has an element and each of its own is below one
||| of the other's. This is the multiset ordering's argument in the form a
||| first-in, first-out worklist needs it, and what lets that worklist
||| recurse structurally: within a generation on the elements still to
||| take, from one generation to the next on the accessibility proof.
module IdrisMLIR.Proof.Generations

import Control.Relation
import Control.WellFounded
import Data.List
import Data.List.Elem
import Data.List.Quantifiers

%default total

||| The generation `new` follows `old`: `old` has an element, and each
||| element of `new` is below one of `old`.
public export
data Follows : Rel a -> List a -> List a -> Type where
  MkFollows : NonEmpty old -> All (\c => Any (lt c) old) new -> Follows lt new old

elemNonEmpty : Elem x xs -> NonEmpty xs
elemNonEmpty Here = IsNonEmpty
elemNonEmpty (There _) = IsNonEmpty

anyNonEmpty : Any p xs -> NonEmpty xs
anyNonEmpty (Here _) = IsNonEmpty
anyNonEmpty (There _) = IsNonEmpty

elemAny : {0 p : a -> Type} -> Elem x ys -> p x -> Any p ys
elemAny Here px = Here px
elemAny (There e) px = There (elemAny e px)

-- Which elements a generation has, as far as following it goes.
record Within (xs, ys : List a) where
  constructor MkWithin
  member : {0 x : a} -> Elem x xs -> Elem x ys

anyWithin : {0 p : a -> Type} -> Within xs ys -> Any p xs -> Any p ys
anyWithin sub (Here px) = elemAny (sub.member Elem.Here) px
anyWithin sub (There rest) = anyWithin (MkWithin (\e => sub.member (There e))) rest

nonEmptyWithin : Within xs ys -> NonEmpty xs -> NonEmpty ys
nonEmptyWithin sub IsNonEmpty = elemNonEmpty (sub.member Elem.Here)

nothingWithin : Within [] ys
nothingWithin = MkWithin (\e => absurd e)

-- Following a generation depends only on which elements it has.
within : {0 lt : Rel a} -> Accessible (Follows lt) old -> Within old' old -> Accessible (Follows lt) old'
within (Access rec) sub = Access next
  where
    next : (new : List a) -> Follows lt new old' -> Accessible (Follows lt) new
    next new (MkFollows ne below) =
      rec new (MkFollows (nonEmptyWithin sub ne) (mapProperty (anyWithin sub) below))

-- No generation follows the empty one.
none : {0 lt : Rel a} -> Accessible (Follows lt) []
none = Access (\_, (MkFollows ne _) => absurd ne)

-- A generation following a concatenation, split by which part each of
-- its elements is below.
record Split (lt : Rel a) (as, bs, cs : List a) where
  constructor MkSplit
  left : List a
  right : List a
  belowLeft : All (\c => Any (lt c) as) left
  belowRight : All (\c => Any (lt c) bs) right
  covered : Within cs (left ++ right)

anyAppend : (as : List a) -> Any p (as ++ bs) -> Either (Any p as) (Any p bs)
anyAppend [] e = Right e
anyAppend (_ :: _) (Here px) = Left (Here px)
anyAppend (_ :: as) (There e) = case anyAppend as e of
  Left l => Left (There l)
  Right r => Right r

elemAppendLeft : (xs : List a) -> Elem x xs -> Elem x (xs ++ ys)
elemAppendLeft (_ :: _) Here = Here
elemAppendLeft (_ :: xs) (There e) = There (elemAppendLeft xs e)

elemAppendRight : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemAppendRight [] e = e
elemAppendRight (_ :: xs) e = There (elemAppendRight xs e)

elemSplit : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
elemSplit [] e = Right e
elemSplit (_ :: _) Here = Left Here
elemSplit (_ :: xs) (There e) = case elemSplit xs e of
  Left l => Left (There l)
  Right r => Right r

split : {0 lt : Rel a} -> (as, bs, cs : List a) -> All (\c => Any (lt c) (as ++ bs)) cs -> Split lt as bs cs
split as bs [] [] = MkSplit [] [] [] [] nothingWithin
split as bs (c :: cs) (b :: bs') =
  let MkSplit l r bl br cov = split as bs cs bs' in
  case anyAppend as b of
    Left inA => MkSplit (c :: l) r (inA :: bl) br (MkWithin (left cov))
    Right inB => MkSplit l (c :: r) bl (inB :: br) (MkWithin (right l cov))
  where
    left : Within cs (l ++ r) -> Elem x (c :: cs) -> Elem x ((c :: l) ++ r)
    left cov Here = Here
    left cov (There e) = There (cov.member e)

    right : (l : List a) -> Within cs (l ++ r) -> Elem x (c :: cs) -> Elem x (l ++ (c :: r))
    right l cov Here = elemAppendRight l Here
    right l cov (There e) = case elemSplit l (cov.member e) of
      Left inL => elemAppendLeft l inL
      Right inR => elemAppendRight l (There inR)

-- Two accessible generations together are accessible: what follows them
-- splits into what follows each, and both proofs descend.
union : {0 lt : Rel a} -> (as, bs : List a) -> Accessible (Follows lt) as -> Accessible (Follows lt) bs ->
        Accessible (Follows lt) (as ++ bs)
union as bs (Access ra) (Access rb) = Access next
  where
    joined : (l, r : List a) -> All (\c => Any (lt c) as) l -> All (\c => Any (lt c) bs) r ->
             Accessible (Follows lt) (l ++ r)
    joined [] [] _ _ = none
    joined [] (c :: r) _ br = rb (c :: r) (MkFollows (anyNonEmpty (head br)) br)
    joined (c :: l) [] bl _ =
      within (ra (c :: l) (MkFollows (anyNonEmpty (head bl)) bl))
             (MkWithin (\e => case elemSplit (c :: l) e of
                                 Left inL => inL
                                 Right inR => absurd inR))
    joined (c :: l) (c' :: r) bl br =
      union (c :: l) (c' :: r) (ra (c :: l) (MkFollows (anyNonEmpty (head bl)) bl))
                               (rb (c' :: r) (MkFollows (anyNonEmpty (head br)) br))

    next : (cs : List a) -> Follows lt cs (as ++ bs) -> Accessible (Follows lt) cs
    next cs (MkFollows _ below) =
      let MkSplit l r bl br cov = split as bs cs below in within (joined l r bl br) cov

-- The generation of one accessible element is accessible.
single : {0 lt : Rel a} -> (x : a) -> Accessible lt x -> Accessible (Follows lt) [x]
single x (Access rx) = Access next
  where
    only : Any p [y] -> p y
    only (Here py) = py
    only (There e) = absurd e

    below : (cs : List a) -> All (\c => Any (lt c) [x]) cs -> Accessible (Follows lt) cs
    below [] [] = none
    below (c :: cs) (b :: bs) = union [c] cs (single c (rx c (only b))) (below cs bs)

    next : (cs : List a) -> Follows lt cs [x] -> Accessible (Follows lt) cs
    next cs (MkFollows _ bs) = below cs bs

||| A generation of accessible elements is accessible: every sequence of
||| generations from it, each following the last, ends.
export
generations : {0 lt : Rel a} -> (old : List a) -> All (Accessible lt) old -> Accessible (Follows lt) old
generations [] [] = none
generations (x :: xs) (ax :: axs) = union [x] xs (single x ax) (generations xs axs)

||| Each element of an accessible generation is accessible: below one, a
||| generation of one element follows the generation, and descends.
export
elemAccessible : {0 lt : Rel a} -> Accessible (Follows lt) gen -> Elem x gen -> Accessible lt x
elemAccessible (Access rec) e =
  Access (\y, below => elemAccessible (rec [y] (MkFollows (elemNonEmpty e) [elemAny e below])) Here)
