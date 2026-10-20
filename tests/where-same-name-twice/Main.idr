-- Two clauses of one definition each define a `where` function of the
-- same name: two blocks, one display name, under one parent. Each is a
-- function of its own in the module, and both run.
module Main
import Prelude

data Shape = Sq Int | Rect Int Int | Tri Int Int

describe : Shape -> String
describe (Sq n) = "square " ++ edges n
  where
    edges : Int -> String
    edges k = show k ++ " by " ++ show k
describe (Rect w h) = "rect " ++ edges w h
  where
    edges : Int -> Int -> String
    edges a b = show a ++ " by " ++ show b
describe (Tri b h) = "tri " ++ edges
  where
    edges : String
    edges = show b ++ " wide, " ++ show h ++ " high"

main : IO ()
main = do
  putStrLn (describe (Sq 2))
  putStrLn (describe (Rect 3 4))
  putStrLn (describe (Tri 5 6))
