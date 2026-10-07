module Main

-- regex-redux (the Benchmarks Game): the DNA of a FASTA input with its
-- headers and newlines removed, the matches of nine patterns counted, and
-- five replacements applied in turn. Idris has no regex library, so the
-- program carries its own: a parser for the subset the patterns use
-- (literals, classes, `.`, `*`, alternation) and a backtracking matcher in
-- continuation style, with Perl's leftmost-first meaning.

import Prelude
import Data.List

data Re = Lit Char | AnyC | Cls Bool (List Char) | Star Re | Seq (List Re) | Alt (List Re)

mutual
  parseAlts : List Char -> List Re -> List (List Re) -> Re
  parseAlts [] cur alts = Alt (reverse (map (Seq . reverse) (cur :: alts)))
  parseAlts ('|' :: cs) cur alts = parseAlts cs [] (cur :: alts)
  parseAlts ('*' :: cs) (r :: cur) alts = parseAlts cs (Star r :: cur) alts
  parseAlts cs cur alts = let (atom, rest) = parseAtom cs in parseAlts rest (atom :: cur) alts

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
parse s = parseAlts (unpack s) [] []

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

-- Every match replaced; the output is built backwards and reversed once.
subst : Re -> List Char -> List Char -> List Char
subst re rep = go []
  where
    go : List Char -> List Char -> List Char
    go acc [] = reverse acc
    go acc xs@(x :: rest) = case match re xs Just of
      Just remaining => go (reverseOnto acc rep) remaining
      Nothing => go (x :: acc) rest

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

replacements : List (String, String)
replacements =
  [ ("tHa[Nt]", "<4>")
  , ("aND|caN|Ha[DS]|WaS", "<3>")
  , ("a[NSt]|BY", "<2>")
  , ("<[^>]*>", "|")
  , ("\\|[^|][^|]*\\|", "-") ]

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
  let seq = subst (parse ">.*\n|\n") [] input
  traverse_ (\v => putStrLn (v ++ " " ++ show (countMatches (parse v) seq 0))) variants
  let final = foldl (\s, (p, r) => subst (parse p) (unpack r) s) seq replacements
  putStrLn ""
  printLn (nelen input)
  printLn (nelen seq)
  printLn (nelen final)
