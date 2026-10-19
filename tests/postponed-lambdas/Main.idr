module Main

-- Lambdas whose type Idris knows only once the call around them is
-- elaborated: it postpones each, and the checked term keeps a metavariable
-- that it solved afterwards, applied to the variables in scope, which may
-- be a `let`, an implementation or a case block's fields. Each is compiled
-- as its solution. `for` and `traverse` over Either and Maybe, at closed
-- and at runtime values, and over IO.

import Prelude

doubledAll : (Num a, Ord a) => List a -> Either a (List a)
doubledAll xs = for xs (\x => if x > 0 then Right (x * 2) else Left x)

shifted : Int -> List Int -> Maybe (List Int)
shifted n xs =
  let k = n + 1 in
  traverse (\x => if x > k then Just (x - k) else Nothing) xs

picked : Maybe Int -> List Int -> Either Int (List Int)
picked m xs = case m of
  Just d => for xs (\x => if x /= d then Right (x + d) else Left x)
  Nothing => traverse (\x => if x > 0 then Right x else Left 0) xs

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (for (the (List Int) [1, 2]) (\x => if x > 0 then Right (x * 2) else Left x))
  printLn (traverse (\x => if x > 0 then Just (x * n) else Nothing) [n, n + 1])
  printLn (for [n, -n, n] (\x => if x > 0 then Right (x * 2) else Left x))
  printLn (doubledAll [n, n + 1])
  printLn (doubledAll [1.5, the Double (cast n)])
  printLn (shifted n [10, 20])
  printLn (shifted n [1, 20])
  printLn (picked (Just n) [1, 2, 3])
  printLn (picked (Just n) [n, 2])
  printLn (picked Nothing [n, 0])
  ys <- for [n, n - 3] (\x => if x > 3 then pure (x * 10) else do putStrLn "small"; pure x)
  printLn ys
