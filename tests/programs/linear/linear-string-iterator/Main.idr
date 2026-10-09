-- The linear string iterator of libs/mlir-linear, with contrib's API: for
-- each string, constant or read from stdin, its characters counted by
-- foldl, the sum of their code points by a loop over uncons, what is left
-- after two characters (withIteratorString), and whether unpack gives the
-- string back. ASCII, two-, three- and four-byte characters, interior NULs
-- and a U+FFFD from ill-formed input.
module Main

import Data.List.Lazy
import Linear.String.Iterator

codeSum : (str : String) -> Int -> (1 it : StringIterator str) -> Int
codeSum str acc it = case uncons str it of
  EOF => acc
  Character c it' => codeSum str (acc + ord c) it'

afterTwo : (str : String) -> (1 it : StringIterator str) -> String
afterTwo str it = case uncons str it of
  EOF => ""
  Character _ it1 => case uncons str it1 of
    EOF => ""
    Character _ it2 => withIteratorString str it2 id

report : String -> IO ()
report s =
  putStrLn $ show (Iterator.foldl (\n, _ => n + 1) (the Int 0) s)
    ++ " " ++ show (withString s (codeSum s 0))
    ++ " " ++ show (withString s (afterTwo s))
    ++ " " ++ show (pack (toList (Iterator.unpack s)) == s)

readLines : IO ()
readLines = do
  l <- getLine
  if l == "" then pure () else do
    report l
    readLines

main : IO ()
main = do
  traverse_ report ["", "hello", "héllo", "naïve café", "日本語", "a😀b", "\NULx\NUL"]
  readLines
