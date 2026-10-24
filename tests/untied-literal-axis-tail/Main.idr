module Main

-- A tail call whose result has two dynamic axes in its callee's type,
-- given a literal size at the call: the first is the natural the call is
-- given, 3, which the tie around the call states before the call; the
-- second is its successor, which the call's index terms fix at 4 and its
-- caller's type states, but which no argument of the call states. The tie
-- names the first axis alone and leaves the second untied, read off
-- nothing, so small's call of wide is a tail call.
-- Each function recurses, so each stays a function wherever another is
-- inlined into it: wide counts down before it makes its array, and small
-- before it calls wide.

import Prelude
import Array
import Linear.Notation

-- n rows of n + 1 columns, each element k, once d steps are counted down.
wide : (n : Nat) -> (d : Nat) -> Int -> Array [<n, S n] Int
wide n Z k = let MkBang x = withArray [<n, S n] k (\a => LArray.freeze a) in x
wide n (S d) k = wide n d k

-- Three rows of four, by a call of wide in tail position, once d steps
-- are counted down.
small : (d : Nat) -> Int -> Array [<3, 4] Int
small Z k = wide 3 1000 k
small (S d) k = small d k

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  printLn (toList (small 1000 k))
