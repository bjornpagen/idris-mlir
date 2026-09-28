||| The fuzzer (TEST-FUZZ-1): programs of closed pure expressions
||| over every primitive, each printed from `main`, which the harness
||| compiles three ways, with evaluation, with `--no-eval` and with the stock
||| Chez backend, and whose outputs must agree (tests/fuzz,
||| `fuzz` in tests/testutils.sh).
|||
|||     runtests --fuzz-program <seed> <cases> runtime|static
|||
||| prints the program. Every case is one expression, written three ways:
|||
||| - `d<n>`, directly: its leaves are literals behind `lit<T>`, an identity
|||   the compiler inlines, so the folders compute it. (A primitive applied
|||   to literals themselves would be folded by Idris's elaborator before the
|||   compiler sees it.)
||| - `j<n>`, in a function of its leaves, total and self recursive over a
|||   list of units, called with the literals: a closed call of a total
|||   function, which idr-eval runs at compile time, and which --no-eval
|||   leaves to runtime.
||| - `r<n>`, with its leaves behind `hide<T> 1`, a partial identity (it
|||   recurses on an Int, so Idris does not prove it terminating): partial
|||   code is never evaluated (SEM-EVAL-6), so the expression is computed at
|||   runtime in every build.
|||
||| The three lines of a case must print the same value, in every build, and
||| each line the same as Chez prints. A case whose value goes through the
||| libm functions that the two C libraries may round differently (exp, log,
||| pow and the trigonometric functions: SEM-DBL-3, SEM-DEV-2) has lines
||| labelled `L...`; those are compared among this compiler's builds only.
|||
||| The `runtime` part holds what may exist at runtime: the integer types,
||| Double, Char, a small sum type, and strings that are only written or
||| taken apart without allocating (PROF-PRIM-4). The `static` part
||| holds Integer and every string builder, which exist at compile time only
||| (PROF-TYPE-4, PROF-HEAP-3): it has `d` and `j` lines, and is compiled with
||| evaluation and by Chez.
|||
||| Division has a divisor that is a nonzero leaf; casts from Double to an
||| integer, from Int to Char and from String take leaves in their domain;
||| strings are taken apart within their bounds. Everything else is any value
||| of its type, NaN, the infinities, -0.0 and subnormals included.
|||
||| rule: SEM-REF-1, SEM-EVAL-6, SEM-EVAL-7, ELIM-G-6, ELIM-EVAL-1, SEM-STR-2, SEM-DBL-5
module Fuzz

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.String

%default covering

------------------------------------------------------------------------------
-- Types and expressions
------------------------------------------------------------------------------

public export
data Ty = TInt | TI8 | TI16 | TI32 | TI64 | TB8 | TB16 | TB32 | TB64
        | TDbl | TChr | TStr | TBig

tyName : Ty -> String
tyName TInt = "Int"
tyName TI8 = "Int8"
tyName TI16 = "Int16"
tyName TI32 = "Int32"
tyName TI64 = "Int64"
tyName TB8 = "Bits8"
tyName TB16 = "Bits16"
tyName TB32 = "Bits32"
tyName TB64 = "Bits64"
tyName TDbl = "Double"
tyName TChr = "Char"
tyName TStr = "String"
tyName TBig = "Integer"

Eq Ty where
  a == b = tyName a == tyName b

intTys : List Ty
intTys = [TInt, TI8, TI16, TI32, TI64, TB8, TB16, TB32, TB64]

||| The bounds of an integer type.
bounds : Ty -> (Integer, Integer)
bounds TI8 = (-128, 127)
bounds TI16 = (-32768, 32767)
bounds TI32 = (-2147483648, 2147483647)
bounds TB8 = (0, 255)
bounds TB16 = (0, 65535)
bounds TB32 = (0, 4294967295)
bounds TB64 = (0, 18446744073709551615)
bounds _ = (-9223372036854775808, 9223372036854775807)

||| An expression: a leaf of a type, as the literal's source text, or a
||| function applied to expressions.
data Expr = Leaf Ty String | App String (List Expr)

||| The leaves of an expression, in order.
leaves : Expr -> List (Ty, String)
leaves (Leaf t s) = [(t, s)]
leaves (App _ as) = concatMap leaves as

||| How a leaf is written: `D`, behind lit<T>; `R`, behind hide<T> 1; `J`,
||| as the next parameter.
data Mode = D | R | J

render : Mode -> Expr -> State Nat String
render D (Leaf t s) = pure ("(lit" ++ tyName t ++ " " ++ s ++ ")")
render R (Leaf t s) = pure ("(hide" ++ tyName t ++ " 1 " ++ s ++ ")")
render J (Leaf _ _) = do
  n <- get
  put (S n)
  pure ("x" ++ show n)
render m (App f as) = do
  rs <- traverse (render m) as
  pure ("(" ++ f ++ concatMap (" " ++) rs ++ ")")

------------------------------------------------------------------------------
-- Randomness: a 64-bit linear congruential generator (Knuth's MMIX)
------------------------------------------------------------------------------

Rnd : Type -> Type
Rnd = State Integer

||| A number in [0, n), n > 0, from the generator's high bits.
below : Nat -> Rnd Nat
below Z = pure 0
below n = do
  s <- get
  let s' = (s * 6364136223846793005 + 1442695040888963407) `mod` 18446744073709551616
  put s'
  pure (integerToNat ((s' `div` 4294967296) `mod` natToInteger n))

pick : List a -> Rnd (Maybe a)
pick [] = pure Nothing
pick xs = do
  i <- below (length xs)
  pure (head' (drop i xs))

||| One of a non-empty list, given as its head and tail.
oneOf : a -> List a -> Rnd a
oneOf x xs = fromMaybe x <$> pick (x :: xs)

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

integerText : Integer -> String
integerText n = if n < 0 then "(" ++ show n ++ ")" else show n

intLit : Ty -> Rnd String
intLit t = do
  let (lo, hi) = bounds t
  k <- below 9
  v <- case k of
         0 => pure lo
         1 => pure hi
         2 => pure 0
         3 => pure 1
         4 => pure (if lo < 0 then -1 else 2)
         5 => pure 7
         6 => pure (if lo < 0 then -100 else 100)
         _ => do a <- below 65536
                 b <- below 65536
                 c <- below 65536
                 e <- below 65536
                 let r = ((natToInteger a * 65536 + natToInteger b) * 65536 + natToInteger c) * 65536 + natToInteger e
                 pure (lo + r `mod` (hi - lo + 1))
  pure (integerText v)

||| A divisor: never 0.
nonzeroLit : Ty -> Rnd String
nonzeroLit t = do
  s <- intLit t
  pure (if s == "0" then "3" else s)

doubleLit : Rnd String
doubleLit = oneOf "0.0"
  [ "1.0", "0.1", "0.5", "2.5", "3.0", "100.0", "1.0e10", "1.0e-10", "123456.789"
  , "1.7976931348623157e308", "2.2250738585072014e-308", "4.9e-324", "1.0e-320"
  , "(-0.1)", "(-2.5)", "(-1.0e300)", "6.02214076e23", "0.3", "(-7.0)" ]

||| A Double an integer cast takes: finite, and small.
finiteLit : Rnd String
finiteLit = oneOf "0.0" ["1.5", "(-2.75)", "1000.25", "(-1.0e6)", "0.999", "12345.5"]

charLit : Rnd String
charLit = oneOf "'a'" ["'Z'", "'0'", "' '", "'\\233'", "'\\955'", "'\\8364'", "'\\128512'", "'~'"]

||| A code point prim__cast_IntChar takes.
codePointLit : Rnd String
codePointLit = oneOf "65" ["233", "955", "8364", "128512", "0", "55295", "57344", "1114111"]

||| Strings, none of them empty, with non-ASCII characters.
nonEmptyStrings : List String
nonEmptyStrings =
  [ "\"a\"", "\"hello\"", "\"h\\233llo\"", "\"\\955x.x\"", "\"\\8364 5\"", "\"\\128512!\""
  , "\"abc def\"", "\"Z\"" ]

stringLit : Rnd String
stringLit = oneOf "\"\"" nonEmptyStrings

nonEmptyLit : Rnd String
nonEmptyLit = oneOf "\"a\"" nonEmptyStrings

||| The length of one of the strings above, in characters: without its
||| quotes, and an escape `\233` being one character.
strLen : String -> Nat
strLen s = length (dropEscapes (unpack s)) `minus` 2
  where
    -- `\233` is one character.
    dropEscapes : List Char -> List Char
    dropEscapes [] = []
    dropEscapes ('\\' :: rest) = 'e' :: dropEscapes (dropWhile isDigit rest)
    dropEscapes (c :: rest) = c :: dropEscapes rest

intText : Nat -> String
intText = show

numericString : Rnd String
numericString = oneOf "\"0\"" ["\"42\"", "\"-17\"", "\"9223372036854775807\"", "\"123456\""]

decimalString : Rnd String
decimalString = oneOf "\"0.5\"" ["\"-2.25\"", "\"1e10\"", "\"3.0\"", "\"0.1\""]

bigLit : Rnd String
bigLit = oneOf "0"
  [ "1", "(-1)", "12345678901234567890", "(-98765432109876543210)", "9223372036854775807"
  , "9223372036854775808", "18446744073709551616", "340282366920938463463374607431768211456"
  , "(-9223372036854775809)", "42" ]

nonzeroBig : Rnd String
nonzeroBig = do
  s <- bigLit
  pure (if s == "0" then "7" else s)

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------

||| Which part a program is: what exists at runtime, or what exists at
||| compile time only.
public export
data Part = Runtime | Static

isStatic : Part -> Bool
isStatic Static = True
isStatic Runtime = False

prim : String -> Ty -> String
prim op t = "prim__" ++ op ++ "_" ++ tyName t

cast : Ty -> Ty -> String
cast from to = "prim__cast_" ++ tyName from ++ tyName to

||| libm functions whose results the two C libraries may round differently.
hostDependent : List String
hostDependent =
  [ "prim__doubleExp", "prim__doubleLog", "prim__doublePow", "prim__doubleSin"
  , "prim__doubleCos", "prim__doubleTan", "prim__doubleASin", "prim__doubleACos"
  , "prim__doubleATan" ]

usesLibm : Expr -> Bool
usesLibm (Leaf _ _) = False
usesLibm (App f as) = elem f hostDependent || any usesLibm as

leaf : Ty -> Rnd Expr
leaf t = case t of
  TDbl => Leaf TDbl <$> doubleLit
  TChr => Leaf TChr <$> charLit
  TStr => Leaf TStr <$> stringLit
  TBig => Leaf TBig <$> bigLit
  _ => Leaf t <$> intLit t

mutual
  ||| An expression of a type, at most `d` deep.
  gen : Part -> Ty -> Nat -> Rnd Expr
  gen p t Z = special p t
  gen p t (S d) = do
    k <- below 10
    if k < 2 then special p t else case t of
      TDbl => genDouble p d
      TChr => genChar p d
      TStr => genString p d
      TBig => genBig d
      _ => genInt p t d

  ||| A leaf, or one of the special values of Double.
  special : Part -> Ty -> Rnd Expr
  special p TDbl = do
    k <- below 8
    case k of
      0 => pure (App "prim__div_Double" [Leaf TDbl "0.0", Leaf TDbl "0.0"])
      1 => pure (App "prim__div_Double" [Leaf TDbl "1.0", Leaf TDbl "0.0"])
      2 => pure (App "prim__div_Double" [Leaf TDbl "(-1.0)", Leaf TDbl "0.0"])
      3 => pure (App "prim__negate_Double" [Leaf TDbl "0.0"])
      _ => leaf TDbl
  special p t = leaf t

  genInt : Part -> Ty -> Nat -> Rnd Expr
  genInt p t d = do
    k <- below (if t == TInt then 12 else 5)
    case k of
      0 => do op <- oneOf "add" ["sub", "mul", "and", "or", "xor"]
              a <- gen p t d
              b <- gen p t d
              pure (App (prim op t) [a, b])
      1 => do op <- oneOf "div" ["mod"]
              a <- gen p t d
              b <- Leaf t <$> nonzeroLit t
              pure (App (prim op t) [a, b])
      2 => do s <- oneOf TInt intTys
              if s == t then genInt p t d else do
                a <- gen p s d
                pure (App (cast s t) [a])
      3 => if isStatic p then do a <- gen p TBig d
                                 pure (App (cast TBig t) [a])
                         else leaf t
      4 => do a <- Leaf TDbl <$> finiteLit
              pure (App (cast TDbl t) [a])
      5 => do c <- oneOf TInt (intTys ++ [TDbl, TChr])
              op <- oneOf "lt" ["lte", "eq", "gte", "gt"]
              a <- gen p c d
              b <- gen p c d
              pure (App (prim op c) [a, b])
      6 => do op <- oneOf "lt" ["lte", "eq", "gte", "gt"]
              a <- stringArg p d
              b <- stringArg p d
              pure (App (prim op TStr) [a, b])
      7 => do a <- gen p TChr d
              pure (App "prim__cast_CharInt" [a])
      8 => do a <- stringArg p d
              pure (App "prim__strLength" [a])
      9 => do a <- Leaf TStr <$> numericString
              pure (App "prim__cast_StringInt" [a])
      10 => do k' <- Leaf TInt . show <$> below 3
               i <- gen p TInt d
               x <- gen p TDbl d
               pure (App "sdata" [k', i, x])
      _ => if isStatic p
              then do op <- oneOf "lt" ["lte", "eq", "gte", "gt"]
                      a <- genBig d
                      b <- genBig d
                      pure (App (prim op TBig) [a, b])
              else leaf t

  ||| A string that an operation takes apart: at runtime, one that exists, a
  ||| leaf.
  stringArg : Part -> Nat -> Rnd Expr
  stringArg Runtime _ = leaf TStr
  stringArg Static d = gen Static TStr d

  genDouble : Part -> Nat -> Rnd Expr
  genDouble p d = do
    k <- below 7
    case k of
      0 => do op <- oneOf "add" ["sub", "mul", "div"]
              a <- gen p TDbl d
              b <- gen p TDbl d
              pure (App (prim op TDbl) [a, b])
      1 => do a <- gen p TDbl d
              pure (App "prim__negate_Double" [a])
      2 => do f <- oneOf "prim__doubleExp"
                     [ "prim__doubleLog", "prim__doubleSin", "prim__doubleCos", "prim__doubleTan"
                     , "prim__doubleASin", "prim__doubleACos", "prim__doubleATan"
                     , "prim__doubleSqrt", "prim__doubleFloor", "prim__doubleCeiling" ]
              a <- gen p TDbl d
              pure (App f [a])
      3 => do a <- gen p TDbl d
              b <- gen p TDbl d
              pure (App "prim__doublePow" [a, b])
      4 => do s <- oneOf TInt intTys
              a <- gen p s d
              pure (App (cast s TDbl) [a])
      5 => do a <- Leaf TStr <$> decimalString
              pure (App "prim__cast_StringDouble" [a])
      _ => if isStatic p then do a <- genBig d
                                 pure (App (cast TBig TDbl) [a])
                         else special p TDbl

  genChar : Part -> Nat -> Rnd Expr
  genChar p d = do
    k <- below 4
    case k of
      0 => do a <- Leaf TInt <$> codePointLit
              pure (App "prim__cast_IntChar" [a])
      1 => do s <- Leaf TStr <$> nonEmptyLit
              pure (App "prim__strHead" [s])
      2 => do s <- nonEmptyLit
              i <- below (strLen s)
              pure (App "prim__strIndex" [Leaf TStr s, Leaf TInt (intText i)])
      _ => leaf TChr

  ||| A string. At runtime, only what output fusion writes without building
  ||| it: appends, conses and numbers and characters shown.
  genString : Part -> Nat -> Rnd Expr
  genString p d = do
    k <- below (if isStatic p then 10 else 6)
    case k of
      0 => do a <- gen p TStr d
              b <- gen p TStr d
              pure (App "prim__strAppend" [a, b])
      1 => do c <- gen p TChr d
              s <- gen p TStr d
              pure (App "prim__strCons" [c, s])
      2 => do s <- oneOf TInt intTys
              a <- gen p s d
              pure (App (cast s TStr) [a])
      3 => do a <- gen p TDbl d
              pure (App "prim__cast_DoubleString" [a])
      4 => do a <- gen p TChr d
              pure (App "prim__cast_CharString" [a])
      6 => do a <- gen p TStr d
              pure (App "prim__strReverse" [a])
      7 => do s <- nonEmptyLit
              let n = strLen s
              start <- below (S n)
              len <- below (S (n `minus` start))
              pure (App "prim__strSubstr" [Leaf TInt (intText start), Leaf TInt (intText len), Leaf TStr s])
      8 => do s <- Leaf TStr <$> nonEmptyLit
              pure (App "prim__strTail" [s])
      9 => do a <- genBig d
              pure (App "prim__cast_IntegerString" [a])
      _ => leaf TStr

  genBig : Nat -> Rnd Expr
  genBig d = do
    k <- below 6
    case k of
      0 => do op <- oneOf "add" ["sub", "mul", "and", "or", "xor"]
              a <- gen Static TBig d
              b <- gen Static TBig d
              pure (App (prim op TBig) [a, b])
      1 => do op <- oneOf "div" ["mod"]
              a <- gen Static TBig d
              b <- Leaf TBig <$> nonzeroBig
              pure (App (prim op TBig) [a, b])
      2 => do s <- oneOf TInt intTys
              a <- gen Static s d
              pure (App (cast s TBig) [a])
      3 => do a <- Leaf TDbl <$> finiteLit
              pure (App (cast TDbl TBig) [a])
      4 => do a <- Leaf TStr <$> numericString
              pure (App "prim__cast_StringInteger" [a])
      _ => leaf TBig

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| How a value of a type is printed: as a string, written by output fusion.
printer : Ty -> String -> String
printer TStr e = e
printer TChr e = "(prim__cast_IntString (prim__cast_CharInt " ++ e ++ "))"
printer t e = "(" ++ cast t TStr ++ " " ++ e ++ ")"

line : String -> Ty -> String -> String
line label t e = "  putStrLn (prim__strAppend \"" ++ label ++ " \" " ++ printer t e ++ ")"

||| The types a part's cases have.
caseTys : Part -> List Ty
caseTys Runtime = intTys ++ [TDbl, TChr, TStr]
caseTys Static = [TBig, TStr, TInt, TDbl]

||| One case: its function, for `j`, and its lines.
record Case where
  constructor MkCase
  fn : List String
  out : List String
  hides : List Ty

genCase : Part -> Nat -> Rnd Case
genCase p n = do
  t <- oneOf TInt (caseTys p)
  depth <- below 4
  e <- gen p t (S depth)
  let tag = (if usesLibm e then "L" else "") ++ show n
  let ls = leaves e
  let d = evalState 0 (render D e)
  let r = evalState 0 (render R e)
  let j = evalState 0 (render J e)
  let params = zipWith (\i, (lt, _) => (i, lt)) [0 .. length ls] ls
  let name = "c" ++ show n
  let sig = name ++ " : List () -> " ++ concatMap (\(_, lt) => tyName lt ++ " -> ") params ++ tyName t
  let xs = concatMap (\(i, _) => " x" ++ show i) params
  let fn = [ sig
           , name ++ " []" ++ xs ++ " = " ++ j
           , name ++ " (_ :: k)" ++ xs ++ " = " ++ name ++ " k" ++ xs
           , "" ]
  let call = "(" ++ name ++ " [()]" ++ concatMap (\(_, s) => " " ++ s) ls ++ ")"
  let runtime = case p of
                  Runtime => [line ("r" ++ tag) t r]
                  Static => []
  pure (MkCase fn ([line ("d" ++ tag) t d, line ("j" ++ tag) t call] ++ runtime) (map fst ls))

||| The helpers every program has: lit<T> and hide<T> for every type, and the
||| small sum type.
helpers : List String
helpers = concatMap helper (intTys ++ [TDbl, TChr, TStr, TBig]) ++
  [ "data S = SA Int | SB Double Int | SC", ""
  , "mkS : Int -> Int -> Double -> S"
  , "mkS 0 i x = SA i"
  , "mkS 1 i x = SB x i"
  , "mkS _ _ _ = SC", ""
  , "useS : S -> Int"
  , "useS (SA i) = prim__add_Int i 1"
  , "useS (SB x i) = prim__add_Int i (prim__lt_Double x 0.0)"
  , "useS SC = 7", ""
  , "sdata : Int -> Int -> Double -> Int"
  , "sdata k i x = useS (mkS k i x)", "" ]
  where
    helper : Ty -> List String
    helper t =
      let n = tyName t in
      [ "lit" ++ n ++ " : " ++ n ++ " -> " ++ n
      , "lit" ++ n ++ " x = x", ""
      , "hide" ++ n ++ " : Int -> " ++ n ++ " -> " ++ n
      , "hide" ++ n ++ " 0 x = x"
      , "hide" ++ n ++ " k x = hide" ++ n ++ " (prim__sub_Int k 1) x", "" ]

||| Two calls of hide<T> with different values, so that no analysis sees one
||| constant for its parameter.
barrier : Ty -> Rnd (List String)
barrier t = do
  a <- leaf t
  b <- leaf t
  pure [line "b" t (hidden a), line "b" t (hidden b)]
  where
    hidden : Expr -> String
    hidden e = evalState 0 (render R e)

||| The program of a seed, a number of cases and a part.
export
program : Integer -> Nat -> Part -> String
program seed n p = evalState (seed `mod` 18446744073709551616) $ do
  cases <- traverse (genCase p) [1 .. n]
  let used = nub (concatMap (.hides) cases)
  barriers <- the (Rnd (List (List String))) $ case p of
                Runtime => traverse barrier used
                Static => pure []
  pure $ unlines $
    [ "module Main", ""
    , "-- Generated by tests/Fuzz.idr: runtests --fuzz-program " ++ show seed ++ " " ++ show n ++ " "
        ++ (case p of Runtime => "runtime"; Static => "static"), ""
    , "import Prelude", ""
    , "%default partial", "" ]
    ++ helpers ++ concatMap (.fn) cases ++
    [ "main : IO ()", "main = do" ] ++ concatMap (.out) cases ++ concat barriers

||| `runtests --fuzz-program SEED CASES PART`.
export
programOf : List String -> Maybe String
programOf [seed, n, part] = do
  s <- parseInteger seed
  k <- parsePositive n
  p <- case part of
         "runtime" => Just Runtime
         "static" => Just Static
         _ => Nothing
  pure (program s k p)
programOf _ = Nothing
