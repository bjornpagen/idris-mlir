module Main

-- An implementation whose constraints are one pair, which Idris passes as
-- `(O a, O b)` and takes apart with `fst` and `snd`: its parent
-- implementation E (Two a b) is given the pair of the halves' parents. Each
-- half is a part of the pair the implementation was given, so no instance
-- grows, and the program compiles and runs.
interface E a where
  eq : a -> a -> Bool

interface E a => O a where
  cmp : a -> a -> Ordering

E Int where
  eq x y = x == y

O Int where
  cmp x y = compare x y

data Two a b = L a | R b

(E a, E b) => E (Two a b) where
  eq (L x) (L y) = eq x y
  eq (R x) (R y) = eq x y
  eq _ _ = False

(O a, O b) => O (Two a b) where
  cmp (L x) (L y) = cmp x y
  cmp (L _) (R _) = LT
  cmp (R _) (L _) = GT
  cmp (R x) (R y) = cmp x y

-- Equality through the parent of an O implementation.
same : O a => a -> a -> Bool
same x y = eq x y

main : IO ()
main = do
  printLn (cmp (the (Two Int Int) (L 1)) (R 2))
  printLn (same (the (Two Int Int) (R 3)) (R 3))
