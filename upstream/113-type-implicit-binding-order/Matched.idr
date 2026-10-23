module Matched

-- A function on an append's left part, applied in a type to a value whose
-- index is an append of two locals of the type: the implicit `xs` of
-- `firstOf` is solved by matching `as ++ bs` against `xs ++ ys`, as it is
-- on a right-hand side.

data P : List Nat -> Nat -> Type where
  MkP : P xs n

firstOf : P (xs ++ ys) n -> P xs n
firstOf _ = MkP

0 sameFirst : (as, bs : List Nat) -> (w : P (as ++ bs) n) -> firstOf w = firstOf w
sameFirst as bs w = Refl

-- The second part stated: the constraint alone determines `xs`.
0 statedRest : (as, bs : List Nat) -> (w : P (as ++ bs) n) ->
               firstOf {ys = bs} w = firstOf {ys = bs} w
statedRest as bs w = Refl

-- The index an application that reduces to an append, as in the
-- frontend's Proof.Describes.firstPart: `g (x :: xs)` is `h x ++ g xs`.
h : Nat -> List Nat
h Z = []
h (S k) = [k]

g : List Nat -> List Nat
g [] = []
g (x :: xs) = h x ++ g xs

data Q : P xs n -> Type where
  MkQ : Q p

0 placed : (x : Nat) -> (xs : List Nat) -> (w : P (g (x :: xs)) n) -> Q (firstOf w) -> ()
placed x xs w q = ()
