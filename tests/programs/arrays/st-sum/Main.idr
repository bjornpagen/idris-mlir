module Main

-- A sum in a state thread: Control.Monad.ST's references are IORefs, and
-- runST runs the thread for its value through base's unsafePerformIO. The
-- loop is an explicit recursion in ST, which modifies the reference once
-- per number from 100000 down to 1.

import Prelude
import Control.Monad.ST

sumDown : STRef s Int -> Int -> ST s ()
sumDown r n =
  if n <= 0 then pure ()
  else do modifySTRef r (+ n)
          sumDown r (n - 1)

sumTo : Int -> Int
sumTo n = runST (do r <- newSTRef 0
                    sumDown r n
                    readSTRef r)

main : IO ()
main = printLn (sumTo 100000)
