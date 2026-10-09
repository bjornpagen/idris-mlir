module Main

-- A program that imports the linear string iterator loads its module, so
-- the entries of its primitives are validated when it compiles.

import Prelude
import Linear.String.Iterator

main : IO ()
main = putStrLn (show (Iterator.foldl (\n, _ => n + 1) (the Int 0) "héllo"))
