module Main

-- rule: PROF-IO-4, ELIM-G-20
-- A program that uses only the Prelude: its own putStrLn, printLn and
-- putChar, with values known only at runtime (from a recursive function).

import Prelude

countdown : Int -> Int
countdown 0 = 0
countdown n = 1 + countdown (n - 1)

main : IO ()
main = do
  let n = countdown 7
  printLn n
  printLn (n * n)
  putStrLn (if n > 5 then "big" else "small")
  printLn (the Double (cast n) / 2.0)
  putChar 'x'
  putChar '\n'
  print (n == 7)
  putStrLn ""
