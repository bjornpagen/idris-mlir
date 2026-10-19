-- expect: escape hatch, line 9
module Main
import Prelude

-- A hole where a value is needed at runtime, in a lambda: the program
-- type-checks, and Idris leaves the hole unsolved.

main : IO ()
main = printLn (the (Either Int (List Int)) (for [1, 2] (\x => if x > 0 then Right (x * 2) else Left ?which)))
