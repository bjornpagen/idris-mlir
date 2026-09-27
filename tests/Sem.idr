||| TEST-SEM-1: table-driven integer semantics over every integer type.
|||
||| Each generated program is an ordinary v0 end-to-end fixture: `Prog.main`
||| is 0 when every case agrees with the table, and otherwise the number of
||| the first case that disagrees. `Oracle.idr` proves `Prog.main = 0` with
||| `Refl`, so the stock evaluator agrees with the same table (SEM-REF-1). The
||| table itself is computed here from the rules in
||| docs/architecture/03-semantics.md.
|||
||| The tests are `tests/e2e/v0/SEM-INT-<type>-<table>-<part>/`. Their `run`
||| asks the test runner for the program:
|||
|||     runtests --sem-program <type> <table> <part>
|||
||| and `runtests --sem-list` names every test the tables make.
|||
||| rule: TEST-SEM-1, SEM-INT-1, SEM-INT-2, SEM-INT-3, SEM-INT-5, SEM-INT-6, SEM-INT-7, PROF-PRIM-1
||| rule: LOW-DIV-1, IDR-DIV-1, IDR-DIV-2, IDR-IN-3, SEM-EVAL-1, SEM-EVAL-2
module Sem

import Data.Bits
import Data.List
import Data.String

%default covering

public export
record IntType where
  constructor MkIntType
  name : String
  width : Nat
  signed : Bool

||| Every integer type, in the order the tables are made.
export
types : List IntType
types =
  [ MkIntType "Int" 64 True, MkIntType "Int8" 8 True, MkIntType "Int16" 16 True
  , MkIntType "Int32" 32 True, MkIntType "Int64" 64 True
  , MkIntType "Bits8" 8 False, MkIntType "Bits16" 16 False
  , MkIntType "Bits32" 32 False, MkIntType "Bits64" 64 False
  ]

||| The most cases one program checks.
maxCases : Nat
maxCases = 120

int : IntType
int = MkIntType "Int" 64 True

pow2 : Nat -> Integer
pow2 k = shiftL 1 k

||| `n mod m` for `m > 0`, never negative (Python's `%`).
modulo : Integer -> Integer -> Integer
modulo n m =
  if n >= 0 then n `mod` m
     else let r = negate n `mod` m in if r == 0 then 0 else m - r

wrap : IntType -> Integer -> Integer
wrap t n =
  let m = modulo n (pow2 t.width)
  in if t.signed && m >= pow2 (pred t.width) then m - pow2 t.width else m

bounds : IntType -> (Integer, Integer)
bounds t =
  if t.signed
     then (negate (pow2 (pred t.width)), pow2 (pred t.width) - 1)
     else (0, pow2 t.width - 1)

values : IntType -> List Integer
values t =
  let (lo, hi) = bounds t
  in if t.signed then [lo, lo + 1, -1, 0, 1, hi]
                 else [0, 1, 2, pow2 (pred t.width), hi - 1, hi]

divValues : IntType -> List Integer
divValues t =
  let (lo, hi) = bounds t
  in if t.signed then [lo, -7, -2, -1, 0, 1, 2, 7, hi]
                 else [0, 1, 2, 7, hi - 1, hi]

||| Euclidean division: the remainder is never negative.
euclid : Integer -> Integer -> (Integer, Integer)
euclid a b =
  let q0 = abs a `div` abs b
      q = if (a < 0) == (b < 0) then q0 else negate q0
      r = a - b * q
  in if r < 0 then (if b > 0 then (q - 1, r + b) else (q + 1, r - b))
              else (q, r)

quotient : IntType -> Integer -> Integer -> Integer
quotient t a b = if t.signed then wrap t (fst (euclid a b)) else a `div` b

remainder : IntType -> Integer -> Integer -> Integer
remainder t a b = if t.signed then wrap t (snd (euclid a b)) else a `mod` b

bitwise : IntType -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bitwise t op a b = wrap t (op (modulo a (pow2 t.width)) (modulo b (pow2 t.width)))

||| An Idris expression of type t with value v, built from an Int literal.
lit : IntType -> Integer -> String
lit t v =
  let asInt = wrap int v
      text = if asInt >= 0 then show asInt else "(" ++ show asInt ++ ")"
  in if t.name == "Int" then text else "(prim__cast_Int" ++ t.name ++ " " ++ text ++ ")"

||| An expression, the type of its result and the value it must have.
Case : Type
Case = (String, IntType, Integer)

binary : IntType -> String -> Integer -> Integer -> String
binary t op a b = "(prim__" ++ op ++ "_" ++ t.name ++ " " ++ lit t a ++ " " ++ lit t b ++ ")"

pairs : List Integer -> List (Integer, Integer)
pairs vs = [(a, b) | a <- vs, b <- vs]

arithmetic : List (String, Integer -> Integer -> Integer)
arithmetic = [("add", (+)), ("sub", (-)), ("mul", (*))]

logical : List (String, Integer -> Integer -> Integer)
logical = [("and", (.&.)), ("or", (.|.)), ("xor", xor)]

comparisons : List (String, Integer -> Integer -> Bool)
comparisons = [("lt", (<)), ("lte", (<=)), ("eq", (==)), ("gte", (>=)), ("gt", (>))]

||| The tables of one type, each a title and its cases.
tables : IntType -> List (String, List Case)
tables t =
  let vs = values t
      ds = filter (\(_, b) => b /= 0) (pairs (divValues t))
      arith = [(binary t op a b, t, wrap t (f a b)) | (op, f) <- arithmetic, (a, b) <- pairs vs]
      divs = [(binary t "div" a b, t, quotient t a b) | (a, b) <- ds]
      mods = [(binary t "mod" a b, t, remainder t a b) | (a, b) <- ds]
      bits = [(binary t op a b, t, bitwise t f a b) | (op, f) <- logical, (a, b) <- pairs vs]
      cmp = [(binary t op a b, int, if f a b then 1 else 0) | (op, f) <- comparisons, (a, b) <- pairs vs]
      casts = [("(prim__cast_" ++ t.name ++ u.name ++ " " ++ lit t a ++ ")", u, wrap u a)
              | u <- types, u.name /= t.name, a <- vs]
  in [("arith", arith), ("div", divs), ("mod", mods), ("bitwise", bits), ("compare", cmp), ("cast", casts)]

chunks : Nat -> List a -> List (List a)
chunks n [] = []
chunks n xs = take n xs :: chunks n (drop n xs)

||| The v0 program that checks the given cases.
program : List Case -> String
program cases =
  let numbered = zip [1 .. length cases] cases
      body = foldr (\(i, (expr, ty, expected)), rest =>
                      "chk (prim__eq_" ++ ty.name ++ " " ++ expr ++ " " ++ lit ty expected ++ ") "
                        ++ show i ++ "\n  (" ++ rest ++ ")")
                   "0" numbered
  in unlines
       [ "module Prog", ""
       , "-- Generated by tests/Sem.idr (TEST-SEM-1).", ""
       , "public export"
       , "chk : Int -> Int -> Int -> Int"
       , "chk 1 _ rest = rest"
       , "chk _ i _ = i", ""
       , "public export partial"
       , "main : Int"
       , "main ="
       , "  " ++ body
       ]

||| Every test: its name, and the cases its program checks.
tests : List (String, List Case)
tests = do
  t <- types
  (title, table) <- tables t
  (part, chunk) <- zip [0 .. length table] (chunks maxCases table)
  pure ("SEM-INT-" ++ t.name ++ "-" ++ title ++ "-" ++ show part, chunk)

||| The name of every test, `SEM-INT-<type>-<table>-<part>`.
export
names : List String
names = map fst tests

||| The program of a test, by its name.
export
programOf : (name : String) -> Maybe String
programOf name = program <$> lookup name tests
