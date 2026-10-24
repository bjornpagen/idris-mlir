-- expect: elaboration, line 18
-- message: is not a prefix operator
module Main
import Prelude

-- A backticked name with no fixity of its own is an infix operator,
-- non-associative at precedence 1. Written before its operand, as
-- `f` 5, it is no prefix operator: the operator was given an infix
-- precedence where a prefix one goes, and resolving the operators found
-- it with one operand where an infix operator takes two, an internal
-- error. The prefix side of a backticked name without a fixity is now
-- refused where it is written, as a symbol with no prefix fixity is.

f : Integer -> Integer
f x = x + 1

y : Integer
y = `f` 5

main : IO ()
main = printLn y
