module Main

-- Types that are an `if` on a Bool, as base's Data.Bool.Decidable states
-- `invert` and `remember`, and a function whose result type is one. An
-- `if` is a case block, named by the full name of the declaration it is
-- in; a declaration's type is checked while its name has a position in the
-- context and nothing is defined there, and the type checker, finding no
-- definition to read the name from, named the block by the bare position,
-- which a TTC cannot hold: "INTERNAL ERROR: Can't write resolved name". The
-- context now keeps the name it gave a position until something is
-- defined there, so each block here is named by its declaration. Checking
-- the types, and writing the module, is the test; the program only runs.

import Prelude

%default total

data Reflects : Type -> Bool -> Type where
  RTrue : p -> Reflects p True
  RFalse : Not p -> Reflects p False

0 pick : (b : Bool) -> if b then Nat else Bool
pick True = Z
pick False = False

0 picked : (pick True = Z, pick False = False)
picked = (Refl, Refl)

0 invert : {0 b : Bool} -> {0 p : Type} -> Reflects p b -> if b then p else Not p
invert {b = True} (RTrue x) = x
invert {b = False} (RFalse nx) = nx

0 remember : {b : Bool} -> {0 p : Type} -> (if b then p else Not p) -> Reflects p b
remember {b = True} = RTrue
remember {b = False} = RFalse

0 recalled : (x : p) -> invert (remember {b = True} x) = x
recalled x = Refl

main : IO ()
main = putStrLn "checked"
