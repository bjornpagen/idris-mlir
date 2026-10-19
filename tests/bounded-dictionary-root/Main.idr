module Main

import Prelude

-- describe is given its Show implementation as the second part of a pair,
-- and through a let and a function that returns the implementation it is
-- given. The keys hold them as written, snd (MkPair () (dictOf Int ...))
-- and dictOf Bool ..., but the implementation at each root is Show Int and
-- Show Bool, and describe's recursion passes the same one on, as deep as
-- the input says.

dictOf : Show a => Show a
dictOf @{d} = d

describe : Show a => Nat -> a -> String
describe Z x = show x
describe (S k) x = "(" ++ describe k x ++ ")"

main : IO ()
main = do
  line <- getLine
  let k = integerToNat (cast line)
  putStrLn (describe @{snd (MkPair () (dictOf {a = Int}))} k 5)
  putStrLn (describe @{let d = dictOf {a = Bool} in d} k True)
