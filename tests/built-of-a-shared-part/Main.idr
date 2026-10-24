module Main

-- A value built of a part used many times claims nothing the part's other
-- uses reach: a pair of one list in both fields, a pair of one record, and
-- a record kept in a Maybe and read again after it is built are each a
-- fresh cell over a value something else reaches as well. The frontend
-- writes each constructor's claim by the specification's rule, and the
-- dialect's verifier holds every value typed `unique deep` to the same
-- rule from the module's read on, so the program compiles only where none
-- of them claims more than its parts give. Each value is built from what
-- is read at run time, so none is static data.

import Prelude

record Point where
  constructor MkPoint
  across : Int
  down : Int

main : IO ()
main = do
  c <- getChar
  let n = ord c
      xs = [n, 2]
      p = MkPoint n 3
      twice = (p, p)
      kept = Just p
  printLn (xs, xs)
  printLn (across (fst twice) + down (snd twice))
  printLn (map across kept, down p)
