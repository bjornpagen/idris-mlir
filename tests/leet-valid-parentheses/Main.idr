-- Valid parentheses (LeetCode 20): a linear stack of the open brackets
-- seen, read off a linear list of characters; a close bracket pops its
-- match. Neither list's cells are shared, so pushing and popping move them.
module Main

import Prelude
import Linear.Notation
import Linear.List

closes : Char -> Char -> Bool
closes '(' ')' = True
closes '[' ']' = True
closes '{' '}' = True
closes _ _ = False

drain : LList (!* Char) -@ ()
drain [] = ()
drain (MkBang _ :: xs) = drain xs

-- Whether the stack is empty; a stack that is not is drained.
consume : LList (!* Char) -@ Bool
consume [] = True
consume (MkBang _ :: xs) = let 1 () = drain xs in False

-- The input is a linear list too, so every cell check takes apart, of the
-- input or of the stack, is its own.
check : LList (!* Char) -@ LList (!* Char) -@ Bool
check [] stack = consume stack
check (MkBang c :: cs) stack =
  if c == '(' || c == '[' || c == '{' then check cs (MkBang c :: stack)
  else case stack of
    [] => let 1 () = drain cs in False
    (MkBang o :: rest) =>
      if closes o c then check cs rest
      else let 1 () = drain cs in let 1 () = drain rest in False

linear : List Char -> LList (!* Char)
linear [] = []
linear (c :: cs) = MkBang c :: linear cs

-- 2n well-nested brackets of three kinds, or the same with one swapped.
nested : Int -> LList (!* Char) -@ LList (!* Char)
nested n acc =
  if n <= 0 then acc
  else nested (n - 1) (MkBang '(' :: MkBang '[' :: MkBang '{' :: MkBang '}' :: MkBang ']' :: MkBang ')' :: acc)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (check (linear (unpack "()[]{}")) [])
  printLn (check (linear (unpack "([)]")) [])
  printLn (check (linear (unpack "{[]}")) [])
  printLn (check (linear (unpack "((")) [])
  printLn (check (nested n []) [])
  printLn (check (nested n (MkBang ']' :: [])) [])
