module Main

-- k-nucleotide (the Benchmarks Game): the frequencies of nucleotides and
-- pairs in the third sequence of a FASTA input, then the counts of five
-- longer fragments, each counted in a sorted map keyed by the fragment.

import Prelude
import Data.List
import Data.Maybe
import Data.SortedMap

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

splitLines : List Char -> List (List Char)
splitLines [] = []
splitLines cs = let (l, rest) = break (== '\n') cs in l :: splitLines (drop 1 rest)

-- The sequence after the header starting ">THREE", in upper case.
three : List (List Char) -> List Char
three [] = []
three (l :: ls) = if isPrefixOf (unpack ">THREE") l then collect ls else three ls
  where
    collect : List (List Char) -> List Char
    collect [] = []
    collect (l :: ls) = if isPrefixOf ['>'] l then [] else map toUpper l ++ collect ls

-- Every fragment of k characters, counted; remaining is the sequence's length.
count : Nat -> Int -> List Char -> SortedMap String Int -> SortedMap String Int
count k remaining cs m =
  if remaining < cast k then m
  else let key = pack (take k cs)
           m' = case lookup key m of
                  Nothing => insert key 1 m
                  Just c => insert key (c + 1) m
       in count k (remaining - 1) (drop 1 cs) m'

fixed : Nat -> Double -> String
fixed d x =
  let scale = cast {to = Int} (pow 10.0 (cast d))
      s = cast {to = Int} (x * cast scale + 0.5)
      frac = show (s `mod` scale)
  in show (s `div` scale) ++ "." ++ pack (replicate (minus d (length frac)) '0') ++ frac

byFrequency : (String, Int) -> (String, Int) -> Ordering
byFrequency (k1, c1) (k2, c2) = case compare c2 c1 of
  EQ => compare k1 k2
  o => o

frequencies : Nat -> Int -> List Char -> IO ()
frequencies k len seq = do
  let denom = cast (len - cast k + 1)
  let counts = sortBy byFrequency (toList (count k len seq empty))
  traverse_ (\(key, c) => putStrLn (key ++ " " ++ fixed 3 (100.0 * cast c / denom))) counts
  putStrLn ""

fragment : Int -> List Char -> String -> IO ()
fragment len seq frag = do
  let n = fromMaybe 0 (lookup frag (count (length frag) len seq empty))
  putStrLn (show n ++ "\t" ++ frag)

main : IO ()
main = do
  input <- readAll []
  let seq = three (splitLines input)
  let len = cast (length seq)
  frequencies 1 len seq
  frequencies 2 len seq
  traverse_ (fragment len seq) ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"]
