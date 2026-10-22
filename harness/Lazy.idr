-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The lazy fuzzer: programs of lazy structures, each read as a case says,
||| whose every run must end with exit 0, nothing on stderr (the checked
||| runtime ends a run that leaves a cell live as an internal error) and
||| each case's lines as the case's model computes them (`fuzzLazy`,
||| FuzzRun.idr).
|||
|||     runtests --lazy-program <seed> <cases> main|stdin
|||     runtests --lazy-program checks
|||
||| A case is a structure and a reader. The structure is a sequence from an
||| affine step, x -> (a * x + b) mod m, written one of four ways:
|||
||| - a top-level Stream, a CAF, whose cells every reader forces and finds
|||   forced (`Caf`);
||| - a top-level LazyList of a length the case gives, a CAF the optimizer
|||   may fold into static data, whose tails are memo cells forced into it
|||   (`CafList`);
||| - a Stream made at run time from a start read from stdin (`Made`);
||| - a LazyList of a length the case gives, from a start read from stdin
|||   (`Listed`);
||| - a pair of memo cells, each a Lazy Int of the sum so far, read from
|||   stdin (`Cells`).
|||
||| The reader takes the first elements of the structure and sums them:
||| once (`Once`), twice from the one structure, so the second walk finds
||| every cell forced (`Twice`), in each round of a loop over the one
||| structure (`Rounds`), or in two calls of one function given the same
||| structure (`Across`). What a case prints is its sums, each a line
||| `l<case> <value>`, which the model computes from the step alone: no
||| oracle outside the program. Every value stays far below 2^63.
|||
||| A case is drawn on its own seed (output n of splitmix64 from the
||| program's seed), as Fuzz's are, so a seed replays it.
module Lazy

import Prelude
import Data.Fin
import Data.List
import Data.String
import Gen

%default total

------------------------------------------------------------------------------
-- What a case holds
------------------------------------------------------------------------------

||| The affine step of a case's sequence, with its modulus: at least 2, so
||| every element is below it.
record Step where
  constructor MkStep
  mul : Nat
  add : Nat
  modulus : Nat

||| Where a case's sequence lives, and how it is made.
data Structure = Caf | CafList | Made | Listed | Cells

||| How a case reads its structure: once, twice, in each of some rounds of
||| a loop, or in two calls.
data Reader = Once | Twice | Rounds Nat | Across

record Case where
  constructor MkCase
  structure : Structure
  reader : Reader
  step : Step
  start : Nat
  ||| How many elements a read takes: at least one.
  taken : Nat

------------------------------------------------------------------------------
-- The model
------------------------------------------------------------------------------

next : Step -> Integer -> Integer
next s x = mod (natToInteger s.mul * x + natToInteger s.add) (natToInteger s.modulus)

||| The sum of the first `k` elements from `x`.
sumFrom : Step -> Nat -> Integer -> Integer
sumFrom _ Z _ = 0
sumFrom s (S k) x = x + sumFrom s k (next s x)

||| What a case prints, one value a line, in order.
model : Case -> List Integer
model c =
  let summed = sumFrom c.step c.taken (natToInteger c.start) in
  case c.reader of
    Once => [summed]
    Twice => [summed, summed]
    Rounds k => [natToInteger k * summed]
    Across => [summed, summed]

------------------------------------------------------------------------------
-- Drawing a case
------------------------------------------------------------------------------

structureOf : Fin 5 -> Structure
structureOf FZ = Caf
structureOf (FS FZ) = CafList
structureOf (FS (FS FZ)) = Made
structureOf (FS (FS (FS FZ))) = Listed
structureOf (FS (FS (FS (FS _)))) = Cells

genReader : Gen Reader
genReader = do
  i <- draw (S 3)
  case i of
    FZ => pure Once
    FS FZ => pure Twice
    FS (FS FZ) => (\k => Rounds (2 + finToNat k)) <$> draw (S 3)
    FS (FS (FS _)) => pure Across

||| A step whose modulus is 2 to 1000, and whose multiplier and increment
||| are below it.
genStep : Gen Step
genStep = do
  m <- (\i => 2 + finToNat i) <$> draw (S 998)
  a <- draw (S 999)
  b <- draw (S 999)
  pure (MkStep (mod (finToNat a) m) (mod (finToNat b) m) m)

genCase : Gen Case
genCase = do
  structure <- structureOf <$> draw (S 4)
  reader <- genReader
  step <- genStep
  start <- finToNat <$> draw (S 999)
  taken <- (\i => 1 + finToNat i) <$> draw (S 199)
  pure (MkCase structure reader step start taken)

||| The draws a case makes, with room to spare.
caseCapacity : Nat
caseCapacity = 16

cases : Bits64 -> Nat -> List Case
cases seed n = map fst (seededEach caseCapacity (map (caseSeed seed) [1 .. n]) genCase)

------------------------------------------------------------------------------
-- The program
------------------------------------------------------------------------------

lbl : Nat -> String
lbl n = "l" ++ show n

||| The definitions and the runner of case `n`.
written : Nat -> Case -> List String
written n c =
  let k = show n
      s = c.step
      step = "step" ++ k
      sum = "sum" ++ k
      say = \e => "  putStrLn (\"" ++ lbl n ++ " \" ++ show (" ++ e ++ "))"
      readStart = [ "  line" ++ k ++ " <- getLine"
                  , "  let start" ++ k ++ " : Int = cast line" ++ k ]
      stepDef = [ step ++ " : Int -> Int"
                , step ++ " x = mod (" ++ show s.mul ++ " * x + " ++ show s.add ++ ") " ++ show s.modulus
                , "" ]
      streamDefs = [ "from" ++ k ++ " : Int -> Stream Int"
                   , "from" ++ k ++ " x = x :: from" ++ k ++ " (" ++ step ++ " x)"
                   , ""
                   , sum ++ " : Nat -> Stream Int -> Int"
                   , sum ++ " Z _ = 0"
                   , sum ++ " (S j) (x :: xs) = x + " ++ sum ++ " j xs"
                   , "" ]
      listDefs = [ "from" ++ k ++ " : Nat -> Int -> LazyList Int"
                 , "from" ++ k ++ " Z _ = []"
                 , "from" ++ k ++ " (S j) x = x :: from" ++ k ++ " j (" ++ step ++ " x)"
                 , ""
                 , sum ++ " : LazyList Int -> Int"
                 , sum ++ " [] = 0"
                 , sum ++ " (x :: xs) = x + " ++ sum ++ " xs"
                 , "" ]
      -- A memo cell of the sum of the first j elements, built of the cell
      -- before it, each forced by the one after: the reader forces the
      -- last, which forces them all, and a second read finds it forced.
      cellDefs = [ "cells" ++ k ++ " : Nat -> Int -> Lazy Int -> Lazy Int"
                 , "cells" ++ k ++ " Z _ acc = acc"
                 , "cells" ++ k ++ " (S j) x acc = cells" ++ k ++ " j (" ++ step ++ " x) (Delay (force acc + x))"
                 , "" ]
      taken = show c.taken
      -- The structure as an expression a reader takes, and what reads it.
      (defs, made, readOf) = the (List String, String, String -> String) $ case c.structure of
        Caf => ( streamDefs ++ [ "caf" ++ k ++ " : Stream Int"
                               , "caf" ++ k ++ " = from" ++ k ++ " " ++ show c.start, "" ]
               , "caf" ++ k, \v => sum ++ " " ++ taken ++ " (" ++ v ++ ")" )
        CafList => ( listDefs ++ [ "caf" ++ k ++ " : LazyList Int"
                                 , "caf" ++ k ++ " = from" ++ k ++ " " ++ taken ++ " " ++ show c.start, "" ]
                   , "caf" ++ k, \v => sum ++ " (" ++ v ++ ")" )
        Made => (streamDefs, "from" ++ k ++ " start" ++ k, \v => sum ++ " " ++ taken ++ " (" ++ v ++ ")")
        Listed => (listDefs, "from" ++ k ++ " " ++ taken ++ " start" ++ k, \v => sum ++ " (" ++ v ++ ")")
        Cells => (cellDefs, "cells" ++ k ++ " " ++ taken ++ " start" ++ k ++ " (Delay 0)", \v => "force (" ++ v ++ ")")
      ty = the String $ case c.structure of
        Listed => "LazyList Int"
        CafList => "LazyList Int"
        Cells => "Lazy Int"
        _ => "Stream Int"
      reads = case c.reader of
        Once => [say (readOf made)]
        Twice => [ "  let v" ++ k ++ " = " ++ made, say (readOf ("v" ++ k)), say (readOf ("v" ++ k)) ]
        Rounds r => [ say ("rounds" ++ k ++ " " ++ show r ++ " (" ++ made ++ ") 0") ]
        Across => [ "  let v" ++ k ++ " = " ++ made
                  , "  let (p" ++ k ++ ", q" ++ k ++ ") = both" ++ k ++ " v" ++ k
                  , say ("p" ++ k), say ("q" ++ k) ]
      readerDefs = case c.reader of
        Rounds _ => [ "rounds" ++ k ++ " : Nat -> " ++ ty ++ " -> Int -> Int"
                    , "rounds" ++ k ++ " Z _ acc = acc"
                    , "rounds" ++ k ++ " (S j) v acc = rounds" ++ k ++ " j v (acc + " ++ readOf "v" ++ ")"
                    , "" ]
        Across => [ "both" ++ k ++ " : " ++ ty ++ " -> (Int, Int)"
                  , "both" ++ k ++ " v = (" ++ readOf "v" ++ ", " ++ readOf "v" ++ ")"
                  , "" ]
        _ => []
      startRead = case c.structure of
        Caf => []
        CafList => []
        _ => readStart
  in stepDef ++ defs ++ readerDefs ++
     [ "run" ++ k ++ " : IO ()", "run" ++ k ++ " = do" ] ++ startRead ++ reads ++ [""]

||| The input a case reads: its start, a line, unless its structure is a CAF.
input : Case -> List String
input c = case c.structure of
  Caf => []
  CafList => []
  _ => [show c.start]

data File = MainFile | StdinFile

parseFile : String -> Maybe File
parseFile "main" = Just MainFile
parseFile "stdin" = Just StdinFile
parseFile _ = Nothing

programText : String -> File -> List Case -> String
programText request file cs =
  let numbered = zip [the Nat 1 .. length cs] cs in
  case file of
    StdinFile => unlines (cs >>= input)
    MainFile => unlines $
      [ "module Main", ""
      , "-- Generated by harness/Lazy.idr: runtests --lazy-program " ++ request, ""
      , "import Prelude"
      , "import Data.List.Lazy", ""
      , "%default partial", "" ]
      ++ (numbered >>= \(n, c) => written n c)
      ++ [ "main : IO ()", "main = do" ]
      ++ map (\(n, _) => "  run" ++ show n) numbered

------------------------------------------------------------------------------
-- The check
------------------------------------------------------------------------------

||| The lines a program of these cases must print, in order.
expected : List Case -> List String
expected cs = zip [the Nat 1 .. length cs] cs >>= \(n, c) => map (\v => lbl n ++ " " ++ show v) (model c)

||| Each case whose lines are not its model's, a line each, naming the case
||| and its first line that differs: a line missing, extra, or of another
||| value. An output that agrees names none.
checked : String -> List Case -> String -> List String
checked name cs output =
  let wanted = expected cs
      got = lines output
      numbered = zip [the Nat 1 .. length cs] cs
  in mapMaybe (differs got) numbered ++ extra wanted got
  where
    ofCase : Nat -> List String -> List String
    ofCase n = filter (\l => isPrefixOf (lbl n ++ " ") l)
    differs : List String -> (Nat, Case) -> Maybe String
    differs got (n, c) =
      let want = map (\v => lbl n ++ " " ++ show v) (model c)
          have = ofCase n got in
      if want == have then Nothing
      else Just (name ++ ": case " ++ show n ++ ": model " ++ unwords (map show (model c))
                 ++ ", but " ++ (if null have then "no line" else joinBy "; " have))
    extra : List String -> List String -> List String
    extra wanted got = case filter (\l => not (elem l wanted)) got of
      [] => []
      (l :: _) => [name ++ ": a line no case prints: " ++ l]

parseSeed : String -> Maybe Bits64
parseSeed s = cast {to = Bits64} <$> parseInteger {a = Integer} s

parseCases : String -> Maybe Nat
parseCases s = case parsePositive {a = Nat} s of
  Just (S k) => Just (S k)
  _ => Nothing

||| The checker's own checks, on seed 1's program of four cases: its model's
||| output names no case; with a case's line changed, that case; with a
||| case's line left out, that case; an empty output, every case.
export
checkerChecks : List (String, Bool)
checkerChecks =
  let cs = cases 1 4
      good = expected cs
      changed = map (\l => if isPrefixOf (lbl 2 ++ " ") l then lbl 2 ++ " -1" else l) good
      short = filter (not . isPrefixOf (lbl 3 ++ " ")) good in
  [ ("the model's output names no case", null (checked "1" cs (unlines good)))
  , ("an output with a case's line changed names that case",
     map (isPrefixOf "1: case 2: ") (checked "1" cs (unlines changed)) == [True, False])
  , ("an output without a case's lines names that case",
     map (isPrefixOf "1: case 3: ") (checked "1" cs (unlines short)) == [True])
  , ("an empty output names every case", length (checked "1" cs "") == 4) ]

||| `runtests --lazy-program <seed> <cases> main|stdin`, or `checks`, the
||| checker's own checks on the host that runs it, a line each.
export covering
programOf : List String -> Maybe String
programOf request@[seed, n, file] = do
  s <- parseSeed seed
  k <- parseCases n
  f <- parseFile file
  pure (programText (unwords request) f (cases s k))
programOf ["checks"] =
  Just (unlines (map (\(name, holds) => "lazy-check: " ++ name ++ ": " ++ (if holds then "ok" else "failed")) checkerChecks))
programOf _ = Nothing

||| The check of a program of `<seed> <cases>`, of the text of its stdout:
||| the cases that print other than their model, a line each.
export covering
checkOf : List String -> (output : String) -> Maybe String
checkOf [seed, n] output = do
  s <- parseSeed seed
  k <- parseCases n
  pure (unlines (checked seed (cases s k) output))
checkOf _ _ = Nothing

