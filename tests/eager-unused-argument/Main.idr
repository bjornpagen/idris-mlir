module Main

-- A polymorphic function given where one is asked for, applied by its
-- receiver to closed arguments. Arguments are evaluated before the
-- function itself, so a closed call the given function never uses is
-- computed all the same, and its crash happens where evaluation reaches
-- it: after "before" is written, and before "after" is.
--
-- The character on stdin chooses one call:
--   c  `applied (\x, y => x)`: its unused argument, `boom 3`, divides by
--      a written 0, so the program writes "before" and crashes there by
--      division by zero.
--   r  `returning (\x, y => x)`: the same form, its unused argument a
--      call that returns, gives its first argument, 1.
--   any other  `returning (\x, y => y)`: the form that uses the argument
--      gives it, 6 divided by 2, 3.
-- boom and halve differ only in the divisor, so the crash is the unused
-- argument's alone: the form that gives its first argument gives 1 once
-- that argument returns, and the receiver passes its second argument as
-- it computes it.

import Prelude

partial
boom : Int -> Int
boom x = prim__div_Int x 0

partial
halve : Int -> Int
halve x = prim__div_Int x 2

partial
applied : ({0 a : Type} -> a -> a -> a) -> Int
applied f = f 1 (boom 3)

partial
returning : ({0 a : Type} -> a -> a -> a) -> Int
returning f = f 1 (halve 6)

partial
main : IO ()
main = do
  c <- getChar
  putStrLn "before"
  case c of
    'c' => printLn (applied (\x, y => x))
    'r' => printLn (returning (\x, y => x))
    _ => printLn (returning (\x, y => y))
  putStrLn "after"
