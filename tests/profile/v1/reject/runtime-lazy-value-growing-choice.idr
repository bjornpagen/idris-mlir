-- expect: runtime lazy value, line 16
module Main

import Prelude

-- Which Lazy value is inside is chosen by a recursion on a runtime value,
-- and each level suspends a computation on the one below: it would need the
-- heap. (A choice among a fixed set of Lazy values needs nothing: a tag.)
data Later : Type where
  Soon : Lazy Int -> Later
  Never : Lazy Int -> Later

later : Int -> Later
later 0 = Soon 1
later n =
  case later (prim__sub_Int n 1) of
    Soon x => Never (prim__add_Int x 1)
    Never y => Soon y

main : IO ()
main = do
  c <- getChar
  case later (prim__cast_CharInt c) of
    Soon x => putStrLn (prim__cast_IntString x)
    Never y => putStrLn (prim__cast_IntString y)
