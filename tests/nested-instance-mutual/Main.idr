module Main

-- `Ord (List a)` and `Ord (a, b)` nested in each other: the list's
-- constraint is `Ord (Int, List Int)`, whose pair holds `Ord (List Int)`,
-- and each one's parent is built from the parents its constraints hold.
-- Each instance reads a parent of a strictly smaller dictionary, which
-- the type's levels bound, so the program compiles and runs.
main : IO ()
main = do
  printLn (compare (the (List (Int, List Int)) [(1, [2])]) [(1, [3])])
  printLn (the (List (Int, List Int)) [(1, [2])] == [(1, [2])])
