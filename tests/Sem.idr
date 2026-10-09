||| Table-driven integer semantics over every integer type.
|||
||| Each generated program is the `Prog` module of an ordinary end-to-end
||| fixture, whose Main.idr prints `Prog.result`: 0 when every case agrees
||| with the table, and otherwise the number of the first case that
||| disagrees. The table is computed here, from what each primitive means,
||| not from the compiler; this compiler computes every case, with
||| compile-time evaluation and without it.
|||
||| The tests are `tests/programs/semantics/prim-<type>-<table>-<part>/`, the type in
||| lower case. Their `run` asks the test runner for the program:
|||
|||     runtests --sem-program prim-<type>-<table>-<part>
|||
||| `runtests --sem-expected <name>` prints the stdout a test's program must
||| print, the value `result` ends with when every case agrees, so that the
||| value is stated once, here; and `runtests --sem-list` names every test the
||| tables make.
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

||| `n` divided by `m > 0`, rounded down.
floorDiv : Integer -> Integer -> Integer
floorDiv n m = if n >= 0 then n `div` m else negate ((negate n + m - 1) `div` m)

||| A shift: `a`, as an integer of unbounded width, moved `s` places, left or
||| right, the other way when `s` is negative, then wrapped to the type.
shifted : IntType -> (left : Bool) -> Integer -> Integer -> Integer
shifted t left a s =
  let places = if left then s else negate s
  in if places >= 0 then wrap t (a * pow2 (cast places))
                    else wrap t (floorDiv a (pow2 (cast (negate places))))

||| The shift amounts of a type: within its width, at it and past it, and a
||| signed type's negative ones, which shift the other way.
shiftAmounts : IntType -> List Integer
shiftAmounts t =
  let w = cast {to = Integer} t.width
      within = [0, 1, 3, w - 1, w, w + 1]
  in if t.signed then within ++ [-1, -3] else within

||| An Idris expression of type t with value v: an Int literal, cast to t.
||| A primitive applied to literals reaches this compiler as written
||| (upstream/18-elaboration-primitive-folding), so every case is this
||| compiler's arithmetic.
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
      shifts = [(binary t op a s, t, shifted t left a s)
               | (op, left) <- [("shl", True), ("shr", False)], a <- vs, s <- shiftAmounts t]
      cmp = [(binary t op a b, int, if f a b then 1 else 0) | (op, f) <- comparisons, (a, b) <- pairs vs]
      casts = [("(prim__cast_" ++ t.name ++ u.name ++ " " ++ lit t a ++ ")", u, wrap u a)
              | u <- types, u.name /= t.name, a <- vs]
  in [("arith", arith), ("div", divs), ("mod", mods), ("bitwise", bits), ("shift", shifts),
      ("compare", cmp), ("cast", casts)]

chunks : Nat -> List a -> List (List a)
chunks n [] = []
chunks n xs = take n xs :: chunks n (drop n xs)

||| What `result` is when every case agrees: no case is numbered 0, so it
||| cannot be mistaken for the number of one that disagrees.
agreed : Nat
agreed = 0

||| The Prog module that checks the given cases.
program : List Case -> String
program cases =
  let numbered = zip [1 .. length cases] cases
      body = foldr (\(i, (expr, ty, expected)), rest =>
                      "chk (prim__eq_" ++ ty.name ++ " " ++ expr ++ " " ++ lit ty expected ++ ") "
                        ++ show i ++ "\n  (" ++ rest ++ ")")
                   (show agreed) numbered
  in unlines
       [ "module Prog", ""
       , "-- Generated by tests/Sem.idr.", ""
       , "public export"
       , "chk : Int -> Int -> Int -> Int"
       , "chk 1 _ rest = rest"
       , "chk _ i _ = i", ""
       , "public export partial"
       , "result : Int"
       , "result ="
       , "  " ++ body
       ]

||| Every test: its name, and the cases its program checks.
tests : List (String, List Case)
tests = do
  t <- types
  (title, table) <- tables t
  (part, chunk) <- zip [0 .. length table] (chunks maxCases table)
  pure ("prim-" ++ toLower t.name ++ "-" ++ title ++ "-" ++ show part, chunk)

||| The name of every test, `prim-<type>-<table>-<part>`.
export
names : List String
names = map fst tests

||| The program of a test, by its name.
export
programOf : (name : String) -> Maybe String
programOf name = program <$> lookup name tests

||| The stdout of a test's program, by its name: Main.idr prints `result`
||| with printLn, and every case agrees.
export
expectedOf : (name : String) -> Maybe String
expectedOf name = (\_ => show agreed ++ "\n") <$> lookup name tests
