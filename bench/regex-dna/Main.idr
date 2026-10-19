-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- regex-dna (the Benchmarks Game, retired for regex-redux): the DNA of a
-- FASTA input with its headers and newlines removed, the matches of nine
-- patterns counted, and each of the eleven IUB codes replaced in turn by
-- the alternation of the nucleotides it stands for. Idris has no regex
-- library, so the program carries its own: a recursive-descent parser for
-- the subset the patterns use (literals, classes, `.`, `*`, alternation)
-- and a backtracking matcher in continuation style, with Perl's
-- leftmost-first meaning. A replacement writes its output front to back,
-- each cell in tail position modulo the constructor, so the output takes
-- no stack and is never reversed.

import Prelude
import Data.List

data Re = Lit Char | AnyC | Cls Bool (List Char) | Star Re | Seq (List Re) | Alt (List Re)

-- A pattern read left to right: its alternatives, each a sequence of
-- atoms, an atom followed by `*` starred.
mutual
  parseAlts : List Char -> List (List Re)
  parseAlts cs = case parseSeq cs of
    (atoms, '|' :: rest) => atoms :: parseAlts rest
    (atoms, _) => [atoms]

  parseSeq : List Char -> (List Re, List Char)
  parseSeq [] = ([], [])
  parseSeq ('|' :: cs) = ([], '|' :: cs)
  parseSeq cs =
    let (atom, rest) = parseAtom cs
        (atom', rest') = starred atom rest
        (atoms, after) = parseSeq rest'
    in (atom' :: atoms, after)

  starred : Re -> List Char -> (Re, List Char)
  starred atom ('*' :: cs) = (Star atom, cs)
  starred atom cs = (atom, cs)

  parseAtom : List Char -> (Re, List Char)
  parseAtom ('\\' :: c :: cs) = (Lit c, cs)
  parseAtom ('.' :: cs) = (AnyC, cs)
  parseAtom ('[' :: '^' :: cs) = let (set, rest) = parseSet cs [] in (Cls True set, rest)
  parseAtom ('[' :: cs) = let (set, rest) = parseSet cs [] in (Cls False set, rest)
  parseAtom (c :: cs) = (Lit c, cs)
  parseAtom [] = (Seq [], [])

  parseSet : List Char -> List Char -> (List Char, List Char)
  parseSet (']' :: cs) acc = (acc, cs)
  parseSet (c :: cs) acc = parseSet cs (c :: acc)
  parseSet [] acc = (acc, [])

parse : String -> Re
parse s = Alt (map Seq (parseAlts (unpack s)))

-- What follows a match of the pattern at the front of the input, if any;
-- the continuation decides what the rest must satisfy.
match : Re -> List Char -> (List Char -> Maybe (List Char)) -> Maybe (List Char)
match (Lit c) (x :: xs) k = if x == c then k xs else Nothing
match (Lit _) [] _ = Nothing
match AnyC (x :: xs) k = if x == '\n' then Nothing else k xs
match AnyC [] _ = Nothing
match (Cls neg set) (x :: xs) k = if elem x set /= neg then k xs else Nothing
match (Cls _ _) [] _ = Nothing
match (Seq []) xs k = k xs
match (Seq (r :: rs)) xs k = match r xs (\rest => match (Seq rs) rest k)
match (Alt []) _ _ = Nothing
match (Alt (r :: rs)) xs k = case match r xs k of
  Nothing => match (Alt rs) xs k
  found => found
match (Star r) xs k = case match r xs (\rest => match (Star r) rest k) of
  Nothing => k xs
  found => found

countMatches : Re -> List Char -> Int -> Int
countMatches re [] acc = acc
countMatches re xs@(_ :: rest) acc = case match re xs Just of
  Just remaining => countMatches re remaining (acc + 1)
  Nothing => countMatches re rest acc

-- Every match replaced, the output built front to back: the first argument
-- is what is still to be written of the last replacement.
subst : Re -> List Char -> List Char -> List Char -> List Char
subst re rep (r :: pending) xs = r :: subst re rep pending xs
subst re rep [] [] = []
subst re rep [] xs@(x :: rest) = case match re xs Just of
  Just remaining => subst re rep rep remaining
  Nothing => x :: subst re rep [] rest

variants : List String
variants =
  [ "agggtaaa|tttaccct"
  , "[cgt]gggtaaa|tttaccc[acg]"
  , "a[act]ggtaaa|tttacc[agt]t"
  , "ag[act]gtaaa|tttac[agt]ct"
  , "agg[act]taaa|ttta[agt]cct"
  , "aggg[acg]aaa|ttt[cgt]ccct"
  , "agggt[cgt]aa|tt[acg]accct"
  , "agggta[cgt]a|t[acg]taccct"
  , "agggtaa[cgt]|[acg]ttaccct" ]

-- The IUB codes, each a pattern, and the alternation it is replaced by.
iub : List (String, String)
iub =
  [ ("B", "(c|g|t)")
  , ("D", "(a|g|t)")
  , ("H", "(a|c|t)")
  , ("K", "(g|t)")
  , ("M", "(a|c)")
  , ("N", "(a|c|g|t)")
  , ("R", "(a|g)")
  , ("S", "(c|g)")
  , ("V", "(a|c|g)")
  , ("W", "(a|t)")
  , ("Y", "(c|t)") ]

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

-- The Prelude's length keeps a frame per element. The input is longer than
-- the program's stack, so the count is an accumulator.
nelen : List a -> Int
nelen = go 0
  where
    go : Int -> List a -> Int
    go n [] = n
    go n (_ :: xs) = go (n + 1) xs

main : IO ()
main = do
  input <- readAll []
  let seq = subst (parse ">.*\n|\n") [] [] input
  traverse_ (\v => putStrLn (v ++ " " ++ show (countMatches (parse v) seq 0))) variants
  let final = foldl (\s, (p, r) => subst (parse p) (unpack r) [] s) seq iub
  putStrLn ""
  printLn (nelen input)
  printLn (nelen seq)
  printLn (nelen final)
