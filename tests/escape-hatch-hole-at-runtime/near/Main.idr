module Main
import Prelude

main : IO ()
main = do
  line <- getLine
  printLn (the (Either Int (List Int)) (for [cast line, 2] (\x => if x > 0 then Right (x * 2) else Left x)))
