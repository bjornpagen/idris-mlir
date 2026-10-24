module Main

-- A tuple whose expected type is not yet known is the pair type where only
-- the pair type elaborates, the pair where only the pair does, and waits
-- where both do. `(r, fst (head r))` below has no reading as a type: as a
-- type its first part makes `r` a type, and then no `head` applies to it.
-- So it is the pair as soon as it is met, and `located`'s `t` is the type
-- of `r`, a list of pairs, before the pattern lets that follow are
-- elaborated. Taken to fit both, the tuple waited, `t` was still unknown
-- at the lets, and the one candidate for `pick round` that needs nothing
-- more of `t` was taken: the record field, a `Maybe Nat`, which no pair
-- pattern matches. `head round` is the same shape, as the frontend's
-- growth check writes it.

import Data.List1

%default total

namespace Folded
  ||| The first pair of a foldable structure of pairs, or (0, 0).
  export
  pick : Foldable f => f (Nat, Nat) -> (Nat, Nat)
  pick xs = foldr (\x, _ => x) (0, 0) xs

record Reading where
  constructor MkReading
  head : Maybe Nat
  pick : Maybe Nat

||| The first candidate, as Growth.idr's `located` gives it.
located : List1 (t, Nat) -> IO (t, Nat)
located cs = pure (head cs)

rounds : List1 (List1 (Nat, Nat))
rounds = ((1, 2) ::: [(3, 4)]) ::: []

main : IO ()
main = do
  (round, place) <- located (map (\r => (r, fst (head r))) rounds)
  let (source, a) = pick round
  let (first, second) = head round
  printLn (source, a, place)
  printLn (first, second)
