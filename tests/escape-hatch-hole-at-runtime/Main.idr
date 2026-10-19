-- expect: escape hatch, line 14
-- message: ?which
module Main
import Prelude

-- A hole where a value is needed at runtime, in a lambda: the program
-- type-checks, and Idris leaves the hole unsolved. near/ has a value
-- there: the numbers doubled while each is positive, or the first that is
-- not.

main : IO ()
main = do
  line <- getLine
  printLn (the (Either Int (List Int)) (for [cast line, 2] (\x => if x > 0 then Right (x * 2) else Left ?which)))
