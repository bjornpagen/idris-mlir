module Main

-- A method whose leading arguments are runtime implicits, an auto-implicit
-- reference and a natural, before its explicit ones. A call through the
-- interface applies the implementation's field, a lambda over every
-- argument, to the implicits, and the method's own function must get each
-- in its place: the reference where it reads the reference, never the
-- explicit Int or Bool that follows. Each result writes its arguments in
-- digits of their own, three per argument (one for the Bool), so any two
-- arguments exchanged give another number.

import Prelude
import Data.IORef

interface Q t where
  q : {auto c : IORef Int} -> {n : Nat} -> Int -> t -> IO Int
  qGen : {auto c : IORef Int} -> {n : Nat} -> Int -> Int -> t -> IO Int
  q d x = qGen {n} d 0 x

Q Bool where
  qGen d k b = do
    v <- readIORef c
    writeIORef c (v + 1)
    pure ((((v * 1000 + d) * 1000 + k) * 1000 + cast n) * 10 + (if b then 1 else 0))

Q String where
  q d s = pure ((d * 1000 + cast (length s)) * 1000 + cast n)
  qGen d k s = pure (d * 1000 + k)

main : IO ()
main = do
  r <- newIORef 10
  a <- q {n = 3} 5 True
  b <- q {n = 4} 100 False
  s <- q {n = 7} 1 "abc"
  g <- qGen {n = 0} 2 9 True
  t <- qGen {n = 8} 6 4 "xy"
  v <- readIORef r
  printLn [a, b, s, g, t, v]
