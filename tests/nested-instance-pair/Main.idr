module Main

-- `Ord (a, b)` at a pair of pairs: the implementation's constraint pair
-- holds `Ord (Int, Int)`, the same implementation one level down, and its
-- parent `Eq (a, b)` is built from its pair's halves' parents. Each
-- instance reads that parent of a strictly smaller dictionary, which the
-- type's two levels bound, so the program compiles and runs.
main : IO ()
main = do
  printLn (compare (the ((Int, Int), String) ((1, 2), "a")) ((1, 3), "a"))
  printLn (the ((Int, Int), String) ((1, 2), "a") == ((1, 2), "a"))
