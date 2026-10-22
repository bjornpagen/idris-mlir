-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- JSON and arithmetic expressions parsed by hand: recursive descent over
-- each line of stdin as a string and a position, no combinators and no
-- closures, the baseline the combinator parsers (json-comb, json-linear,
-- json-bytes) are measured against on the same lines (json-lines). Each
-- line is a JSON value or, where it is none, an expression; prints how
-- many lines were each, the JSON values' nodes and the sum of their
-- numbers, the expressions' values summed, and how many lines were
-- neither. Written as the workload of the e-graph's measurements has it,
-- partial where base's strIndex is.

import Prelude
import Data.String

%default partial

data JSON = JNull | JBool Bool | JNum Integer | JStr String
          | JArr (List JSON) | JObj (List (String, JSON))

data Res a = Fail | Ok a Int

skip : String -> Int -> Int -> Int
skip t n i = if i < n && isSpace (strIndex t i) then skip t n (i + 1) else i

lit : String -> Int -> Int -> String -> Int -> Bool
lit t n i w k = if k >= strLength w then True
  else i + k < n && strIndex t (i + k) == strIndex w k && lit t n i w (k + 1)

digits : String -> Int -> Int -> Integer -> Res Integer
digits t n i acc =
  if i < n && isDigit (strIndex t i)
    then digits t n (i + 1) (acc * 10 + cast (ord (strIndex t i) - 48))
    else Ok acc i

number : String -> Int -> Int -> Res Integer
number t n i =
  let neg = i < n && strIndex t i == '-'
      j = if neg then i + 1 else i in
  if j < n && isDigit (strIndex t j)
    then case digits t n j 0 of
      Ok v k => Ok (if neg then negate v else v) (skip t n k)
      Fail => Fail
    else Fail

strEnd : String -> Int -> Int -> Int
strEnd t n i = if i < n && strIndex t i /= '"' then strEnd t n (i + 1) else i

str : String -> Int -> Int -> Res String
str t n i =
  if i < n && strIndex t i == '"'
    then let e = strEnd t n (i + 1) in
         if e < n then Ok (substr (cast (i + 1)) (cast (e - i - 1)) t) (skip t n (e + 1)) else Fail
    else Fail

sym : String -> Int -> Int -> Char -> Res ()
sym t n i c = if i < n && strIndex t i == c then Ok () (skip t n (i + 1)) else Fail

mutual
  value : String -> Int -> Int -> Res JSON
  value t n i =
    if i >= n then Fail else case strIndex t i of
      'n' => if lit t n i "null" 0 then Ok JNull (skip t n (i + 4)) else Fail
      't' => if lit t n i "true" 0 then Ok (JBool True) (skip t n (i + 4)) else Fail
      'f' => if lit t n i "false" 0 then Ok (JBool False) (skip t n (i + 5)) else Fail
      '"' => case str t n i of
        Ok s j => Ok (JStr s) j
        Fail => Fail
      '[' => case sym t n i '[' of
        Ok () j => case sym t n j ']' of
          Ok () k => Ok (JArr []) k
          Fail => elements t n j [<]
        Fail => Fail
      '{' => case sym t n i '{' of
        Ok () j => case sym t n j '}' of
          Ok () k => Ok (JObj []) k
          Fail => members t n j [<]
        Fail => Fail
      _ => case number t n i of
        Ok v j => Ok (JNum v) j
        Fail => Fail

  elements : String -> Int -> Int -> SnocList JSON -> Res JSON
  elements t n i acc = case value t n i of
    Ok v j => case sym t n j ',' of
      Ok () k => elements t n k (acc :< v)
      Fail => case sym t n j ']' of
        Ok () k => Ok (JArr (acc <>> [v])) k
        Fail => Fail
    Fail => Fail

  members : String -> Int -> Int -> SnocList (String, JSON) -> Res JSON
  members t n i acc = case str t n i of
    Ok k j => case sym t n j ':' of
      Ok () j' => case value t n j' of
        Ok v j'' => case sym t n j'' ',' of
          Ok () l => members t n l (acc :< (k, v))
          Fail => case sym t n j'' '}' of
            Ok () l => Ok (JObj (acc <>> [(k, v)])) l
            Fail => Fail
        Fail => Fail
      Fail => Fail
    Fail => Fail

mutual
  expr : String -> Int -> Int -> Res Integer
  expr t n i = case term t n i of
    Ok v j => exprRest t n j v
    Fail => Fail

  exprRest : String -> Int -> Int -> Integer -> Res Integer
  exprRest t n i acc = case sym t n i '+' of
    Ok () j => case term t n j of
      Ok v k => exprRest t n k (acc + v)
      Fail => Ok acc i
    Fail => case sym t n i '-' of
      Ok () j => case term t n j of
        Ok v k => exprRest t n k (acc - v)
        Fail => Ok acc i
      Fail => Ok acc i

  term : String -> Int -> Int -> Res Integer
  term t n i = case factor t n i of
    Ok v j => termRest t n j v
    Fail => Fail

  termRest : String -> Int -> Int -> Integer -> Res Integer
  termRest t n i acc = case sym t n i '*' of
    Ok () j => case factor t n j of
      Ok v k => termRest t n k (acc * v)
      Fail => Ok acc i
    Fail => case sym t n i '/' of
      Ok () j => case factor t n j of
        Ok v k => termRest t n k (div acc v)
        Fail => Ok acc i
      Fail => Ok acc i

  factor : String -> Int -> Int -> Res Integer
  factor t n i = case number t n i of
    Ok v j => Ok v j
    Fail => case sym t n i '(' of
      Ok () j => case expr t n j of
        Ok v k => case sym t n k ')' of
          Ok () l => Ok v l
          Fail => Fail
        Fail => Fail
      Fail => Fail

size : JSON -> Integer
size (JArr xs) = 1 + sum (map size xs)
size (JObj ms) = 1 + sum (map (size . snd) ms)
size _ = 1

numbers : JSON -> Integer
numbers (JNum n) = n
numbers (JArr xs) = sum (map numbers xs)
numbers (JObj ms) = sum (map (numbers . snd) ms)
numbers _ = 0

-- What the lines so far were.
record Tally where
  constructor MkTally
  jsonLines, nodes, jsonSum, exprLines, exprSum, errorLines : Integer

-- A line: a JSON value when one spans it, else an expression when one
-- does, else neither.
tally : Tally -> String -> Tally
tally s t =
  let n = strLength t
      i = skip t n 0 in
  case value t n i of
    Ok j k => if k >= n
      then { jsonLines $= (+ 1), nodes $= (+ size j), jsonSum $= (+ numbers j) } s
      else exprLine n i
    Fail => exprLine n i
  where
    exprLine : Int -> Int -> Tally
    exprLine n i = case expr t n i of
      Ok v k => if k >= n then { exprLines $= (+ 1), exprSum $= (+ v) } s else { errorLines $= (+ 1) } s
      Fail => { errorLines $= (+ 1) } s

loop : Tally -> IO Tally
loop s = do
  t <- getLine
  if t == "" then pure s else loop (tally s t)

report : Tally -> IO ()
report s = do
  putStrLn ("json " ++ show s.jsonLines ++ " size " ++ show s.nodes ++ " sum " ++ show s.jsonSum)
  putStrLn ("expr " ++ show s.exprLines ++ " sum " ++ show s.exprSum)
  putStrLn ("error " ++ show s.errorLines)

main : IO ()
main = loop (MkTally 0 0 0 0 0 0) >>= report
