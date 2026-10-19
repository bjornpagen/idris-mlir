module Main

-- A pad and a growth of arrays whose elements are references (strings
-- made at run time): every slot of the result holds its own reference,
-- the pad's copies and the array's elements alike, and each is released
-- once at the end. The pad of an array of rows pads with a whole row.

import Prelude
import Linear.Notation
import Array

-- The word, then the word twice: two strings made at run time.
words : String -> Vector 2 String
words w = tabulate [<2] (\[<i] => if finToNat i == 0 then w else w ++ w)

-- Two rows of two strings, each the word and its coordinates.
rows : String -> Array [<2] (Vector 2 String)
rows w = tabulate [<2] (\[<i] => tabulate [<2] (\[<j] => w ++ show (finToNat i) ++ show (finToNat j)))

main : IO ()
main = do
  w <- getLine
  let fill = w ++ "!"
  printLn (toList (pad 1 2 fill (words w)))
  printLn (map toList (toList (pad 1 0 (tabulate [<2] (\_ => fill)) (rows w))))
  let MkBang g = LArray.thaw (words w) (\a => LArray.freeze (LArray.grow 2 fill a))
  printLn (toList g)
