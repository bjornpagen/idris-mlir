module Main

-- The refused program with its index an append, `rev as ++ bs`, whose
-- match against `xs ++ ys` solves `xs`.

import Prelude

%default total

data P : List Nat -> Nat -> Type where
  MkP : P xs n

firstOf : P (xs ++ ys) n -> P xs n
firstOf _ = MkP

rev : List Nat -> List Nat
rev [] = []
rev (x :: xs) = rev xs ++ [x]

0 reversed : (as, bs : List Nat) -> (w : P (rev as ++ bs) n) -> firstOf w = firstOf w
reversed as bs w = Refl

main : IO ()
main = putStrLn "checked"
