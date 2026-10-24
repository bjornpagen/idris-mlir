module Main

-- A tail call whose result has two dynamic axes: the first is the
-- natural the call is given, which the tie around the call states before
-- the call; the second is that natural's successor, which no argument of
-- the call states. The tie names the first axis alone and leaves the
-- second untied, read off nothing, so nothing but the tie stands between
-- the call and the return, and grid's call of wide is a tail call.
-- Each function recurses, so each stays a function wherever another is
-- inlined into it: wide counts down before it makes its array, and grid
-- before it calls wide.

import Prelude
import Array
import Linear.Notation

-- n rows of n + 1 columns, each element k, once d steps are counted down.
wide : (n : Nat) -> (d : Nat) -> Int -> Array [<n, S n] Int
wide n Z k = let MkBang x = withArray [<n, S n] k (\a => LArray.freeze a) in x
wide n (S d) k = wide n d k

-- The same array, by a call of wide in tail position, once d steps are
-- counted down.
grid : (n : Nat) -> (d : Nat) -> Int -> Array [<n, S n] Int
grid n Z k = wide n 1000 k
grid n (S d) k = grid n d k

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  printLn (toList (grid (cast k) 1000 k))
