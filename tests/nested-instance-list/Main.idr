module Main

-- `Ord (List a)` at a list of lists: its constraint is `Ord (List Int)`,
-- the same implementation one level down, whose parent `Eq (List Int)`
-- the outer parent is built from. The type's two levels bound the
-- nesting, so the program compiles and runs.
main : IO ()
main = printLn (compare (the (List (List Int)) [[1]]) [[2]])
