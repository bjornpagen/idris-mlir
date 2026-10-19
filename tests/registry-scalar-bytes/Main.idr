module Main

-- The linear string iterator's step, the registry's scalarBytes, over every
-- Unicode scalar value: one string of each, NUL included, packed from the
-- list of them, then read back by the iterator's foldl, which counts them,
-- and its unpack, whose characters are the list's. A wrong length for any
-- one moves every later step off the start of its character, so the count
-- and the characters differ from then on.

import Prelude
import Linear.String.Iterator

scalars : List Char
scalars = map chr ([0 .. 0xD7FF] ++ [0xE000 .. 0x10FFFF])

main : IO ()
main = do
  let s = pack scalars
  putStrLn ("characters: " ++ show (Iterator.foldl (\n, _ => n + 1) (the Int 0) s) ++ " of " ++ show (length s))
  putStrLn (if toList (Iterator.unpack s) == scalars then "unpack: the same" else "unpack: differs")
