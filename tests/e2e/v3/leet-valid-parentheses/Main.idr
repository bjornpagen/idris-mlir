-- Valid parentheses (LeetCode 20): a linear stack of the open brackets
-- seen; a close bracket pops its match. The stack's cells are never
-- shared, so pushing and popping move them.
module Main

import Prelude
import Data.Linear.Notation
import Data.Linear.LList

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

check : List Char -> LList (!* Char) -@ Bool
check [] stack = consume stack
check (c :: cs) stack =
  if c == '(' || c == '[' || c == '{' then check cs (MkBang c :: stack)
  else case stack of
    [] => False
    (MkBang o :: rest) => if closes o c then check cs rest else let 1 () = drain rest in False

-- 2n well-nested brackets of three kinds, or the same with one swapped.
nested : Int -> List Char -> List Char
nested n acc = if n <= 0 then acc else nested (n - 1) ('(' :: '[' :: '{' :: '}' :: ']' :: ')' :: acc)

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
  printLn (check (unpack "()[]{}") [])
  printLn (check (unpack "([)]") [])
  printLn (check (unpack "{[]}") [])
  printLn (check (unpack "((") [])
  printLn (check (nested n []) [])
  printLn (check (nested n [']']) [])
