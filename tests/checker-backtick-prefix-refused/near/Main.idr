module Main
import Prelude

-- The refused program with the backticked name applied as a function.

f : Integer -> Integer
f x = x + 1

y : Integer
y = f 5

main : IO ()
main = printLn y
