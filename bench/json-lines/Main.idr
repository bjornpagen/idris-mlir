-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- The input of the parser benchmarks: n lines from one pseudo-random
-- sequence, the even ones JSON objects nested three deep (null, booleans,
-- signed numbers, strings, arrays and objects), the odd ones arithmetic
-- expressions over + - * and one level of parentheses, and every
-- sixteenth an array left unclosed, which every parser must reject. Built
-- a line at a time, its pieces collected and written once. As a benchmark
-- it measures building strings and writing them.

import Prelude

-- The generator's state: the seed, and the line built so far, its pieces
-- last first.
record Gen where
  constructor MkGen
  seed : Int
  pieces : SnocList String

-- The next number below k, the seed stepped first; its high bits are the
-- number, its low bits too regular.
roll : Int -> Gen -> (Int, Gen)
roll k (MkGen s ps) =
  let s' = (s * 1103515245 + 12345) `mod` 2147483648
  in ((s' `div` 65536) `mod` k, MkGen s' ps)

emit : String -> Gen -> Gen
emit p (MkGen s ps) = MkGen s (ps :< p)

jsonNumber : Gen -> Gen
jsonNumber g =
  let (v, g1) = roll 1000 g
      (neg, g2) = roll 4 g1
  in emit ((if neg == 0 && v > 0 then "-" else "") ++ show v) g2

-- A JSON value at depth d: below depth 3 it may be an array or an object
-- of up to three entries, each a value one deeper.
mutual
  value : Int -> Gen -> Gen
  value d g =
    let (r, g1) = roll (if d < 3 then 8 else 6) g in
    case r of
      0 => emit "null" g1
      1 => emit "true" g1
      2 => emit "false" g1
      5 => let (k, g2) = roll 100 g1 in emit ("\"k" ++ show k ++ "\"") g2
      6 => let (c, g2) = roll 4 g1 in elements (d + 1) c 0 (emit "[" g2)
      7 => let (c, g2) = roll 4 g1 in members (d + 1) c 0 (emit "{" g2)
      _ => jsonNumber g1

  elements : Int -> Int -> Int -> Gen -> Gen
  elements d c i g =
    if i >= c then emit "]" g
    else elements d c (i + 1) (value d (if i > 0 then emit ", " g else g))

  members : Int -> Int -> Int -> Gen -> Gen
  members d c i g =
    if i >= c then emit "}" g
    else members d c (i + 1) (value d (emit ("\"m" ++ show i ++ "\": ") (if i > 0 then emit ", " g else g)))

exprNumber : Gen -> Gen
exprNumber g = let (v, g1) = roll 100 g in emit (show v) g1

-- An expression at depth d of t terms, each of one or two factors; a
-- factor at depth 0 is a parenthesized expression one time in four, so
-- every value fits in a 64-bit word.
mutual
  factor : Int -> Gen -> Gen
  factor d g =
    if d < 1
      then let (p, g1) = roll 4 g in
           if p == 0
             then let (t, g2) = roll 3 g1 in emit ")" (terms (d + 1) (1 + t) 0 (emit "(" g2))
             else exprNumber g1
      else exprNumber g

  factors : Int -> Int -> Int -> Gen -> Gen
  factors d f i g =
    if i >= f then g
    else factors d f (i + 1) (factor d (if i > 0 then emit " * " g else g))

  term : Int -> Gen -> Gen
  term d g = let (f, g1) = roll 2 g in factors d (1 + f) 0 g1

  terms : Int -> Int -> Int -> Gen -> Gen
  terms d t i g =
    if i >= t then g
    else if i == 0 then terms d t 1 (term d g)
    else let (op, g1) = roll 2 g in
         terms d t (i + 1) (term d (emit (if op == 0 then " + " else " - ") g1))

line : Int -> Gen -> Gen
line k g =
  if k `mod` 16 == 15
    then let (a, g1) = roll 100 g
             (b, g2) = roll 100 g1
         in emit ("[" ++ show a ++ ", " ++ show b) g2
    else if k `mod` 2 == 0
      then let (c, g1) = roll 4 g in members 1 (3 + c) 0 (emit "{" g1)
      else let (t, g1) = roll 3 g in terms 0 (2 + t) 0 g1

writeLines : Int -> Int -> Int -> IO ()
writeLines n k s =
  if k >= n then pure ()
  else do
    let MkGen s' ps = line k (MkGen s [<])
    putStrLn (fastConcat (ps <>> []))
    writeLines n (k + 1) s'

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
  writeLines n 0 42
