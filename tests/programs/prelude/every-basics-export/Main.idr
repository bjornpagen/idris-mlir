module Main

-- Every run-time export of Prelude.Basics, each used (covers): its
-- combinators, Bool's operators, and the constructors of List and
-- SnocList, each line printed so that what it computes is checked.

import Prelude

inc : Int -> Int
inc x = x + 1

addPair : (Int, Int) -> Int
addPair (a, b) = a + b

snocLength : SnocList Int -> Int
snocLength Lin = 0
snocLength (sx :< _) = 1 + snocLength sx

listLength : List Int -> Int
listLength Nil = 0
listLength (_ :: xs) = 1 + listLength xs

-- `f $ x` is application by the time Idris has elaborated it, so ($) is
-- also passed as a value, which keeps the definition.
twice : ((Int -> Int) -> Int -> Int) -> Int
twice app = app inc (app inc 1)

main : IO ()
main = do
  printLn (inc $ 41)
  printLn (twice ($))
  printLn ((inc . inc) 40)
  printLn ((negate .: (+)) 1 2)
  printLn (inc <| 1)
  printLn (1 |> inc)
  printLn (apply inc 2)
  printLn (const (the Int 5) 'x')
  printLn (curry addPair 3 4)
  printLn (uncurry (+) (the Int 5, the Int 6))
  printLn (dup (the Int 7))
  printLn (flip (-) (the Int 1) 10)
  printLn (id (the Int 8))
  printLn (ifThenElse True (the Int 1) 2)
  printLn (intToBool 0, intToBool 3)
  printLn (not False)
  printLn (True && False, False || True)
  printLn (on (+) inc 1 2)
  printLn (listLength (1 :: 2 :: Nil))
  printLn (snocLength (Lin :< 1 :< 2 :< 3))
