||| The two levels: closed terms, over every primitive and over a corpus of
||| total Prelude functions, each with its value as an Idris term, which the
||| corpus's expected file records (tests/two-levels/terms/expected-<corpus>),
||| and as the compiled program computes it, which must be the same.
|||
|||     runtests --two-levels-program primitives|prelude terms|main
|||
||| prints `Terms.idr`, the terms `t1`, `t2`, ... (`public export`), or
||| `Main.idr`, which prints each as `t<n> <value>`, the lines of the
||| expected file.
|||
||| A primitive is applied to literals as they are: Idris leaves the call in
||| the checked term (upstream/18-elaboration-primitive-folding), so the
||| value printed is this compiler's. The corpus of Prelude functions gives
||| a literal its type with `the`, where nothing else would.
|||
||| Values are printed as the programs print them: integers in decimal, a
||| Char as its code point, a String as itself, a Double as Idris's `show`.
|||
||| Terms whose value depends on the target by design are marked in Terms.idr
||| with `-- host-dependent: t<n> <reason>`, and are listed but not compared:
||| the libm functions, which are not correctly rounded, so that the last
||| places of their values are the platform libm's, while the expected files
||| are every target's. A cast from String reads a literal of its type alike
||| everywhere, so the casts here, of literals, are compared.
|||
||| A change to the terms, or to their order, changes the expected files,
||| which are then written again from the program's output, the
||| host-dependent terms aside, and reviewed as any expected output.
module TwoLevels

import Data.List
import Data.String

%default covering

||| A term: its type, its text, and why it is host-dependent, if it is.
record Term where
  constructor MkTerm
  ty : String
  text : String
  host : Maybe String

term : String -> String -> Term
term t e = MkTerm t e Nothing

hostTerm : String -> String -> String -> Term
hostTerm reason t e = MkTerm t e (Just reason)

intTys : List String
intTys = ["Int", "Int8", "Int16", "Int32", "Int64", "Bits8", "Bits16", "Bits32", "Bits64"]

signed : String -> Bool
signed t = isPrefixOf "Int" t

||| The bounds of an integer type.
bounds : String -> (Integer, Integer)
bounds "Int8" = (-128, 127)
bounds "Int16" = (-32768, 32767)
bounds "Int32" = (-2147483648, 2147483647)
bounds "Bits8" = (0, 255)
bounds "Bits16" = (0, 65535)
bounds "Bits32" = (0, 4294967295)
bounds "Bits64" = (0, 18446744073709551615)
bounds _ = (-9223372036854775808, 9223372036854775807)

||| A literal of a type that nothing around it says.
typed : String -> String -> String
typed t v = "(the " ++ t ++ " " ++ v ++ ")"

num : Integer -> String
num n = if n < 0 then "(" ++ show n ++ ")" else show n

app : String -> List String -> String
app f as = "(" ++ f ++ concatMap (" " ++) as ++ ")"

prim : String -> String -> String
prim op t = "prim__" ++ op ++ "_" ++ t

------------------------------------------------------------------------------
-- Every primitive
------------------------------------------------------------------------------

||| The integer primitives of one type, at the edges of its range.
intTerms : String -> List Term
intTerms t =
  let (lo, hi) = bounds t
      a = hi
      b = if signed t then -7 else 7
      l = num
  in [ term t (app (prim op t) [l a, l b]) | op <- ["add", "sub", "mul", "and", "or", "xor"] ]
  ++ [ term t (app (prim op t) [l x, l y])
     | op <- ["div", "mod"]
     , (x, y) <- if signed t then [(lo, -1), (-17, 5), (17, -5), (hi, 7)] else [(hi, 7), (17, 5)] ]
  ++ [ term "Int" (app (prim op t) [l x, l y])
     | op <- ["lt", "lte", "eq", "gte", "gt"], (x, y) <- [(lo, hi), (b, b)] ]
  ++ [ term u (app ("prim__cast_" ++ t ++ u) [l v]) | u <- intTys, u /= t, v <- [lo, hi] ]
  ++ [ term "Double" (app ("prim__cast_" ++ t ++ "Double") [l hi])
     , term "String" (app ("prim__cast_" ++ t ++ "String") [l lo])
     , term "Integer" (app ("prim__cast_" ++ t ++ "Integer") [l lo])
     , term t (app ("prim__cast_Integer" ++ t) ["340282366920938463463374607431768211457"])
     , term t (app ("prim__cast_Double" ++ t) ["(-2.75)"])
     ]

doubles : List String
doubles = ["0.1", "(-2.5)", "1.0e300", "4.9e-324", "2.2250738585072014e-308", "0.0", "123456.789"]

||| NaN, the infinities and -0.0, made by the terms' own arithmetic.
specials : List String
specials =
  [ app "prim__div_Double" ["0.0", "0.0"]
  , app "prim__div_Double" ["1.0", "0.0"]
  , app "prim__div_Double" ["(-1.0)", "0.0"]
  , app "prim__negate_Double" ["0.0"] ]

libm : List String
libm = ["Exp", "Log", "Sin", "Cos", "Tan", "ASin", "ACos", "ATan"]

doubleTerms : List Term
doubleTerms =
  let ds = doubles ++ specials in
  [ term "Double" (app (prim op "Double") [x, y])
  | op <- ["add", "sub", "mul", "div"], (x, y) <- zip ds (drop 1 ds ++ take 1 ds) ]
  ++ [ term "Double" (app "prim__negate_Double" [x]) | x <- ds ]
  ++ [ term "Int" (app (prim op "Double") [x, y])
     | op <- ["lt", "lte", "eq", "gte", "gt"], (x, y) <- zip ds (reverse ds) ]
  ++ [ term "Double" (app ("prim__double" ++ f) [x]) | f <- ["Sqrt", "Floor", "Ceiling"], x <- ds ]
  ++ [ hostTerm ("prim__double" ++ f ++ ": libm") "Double" (app ("prim__double" ++ f) ["0.5"])
     | f <- libm ]
  ++ [ hostTerm "prim__doublePow: libm" "Double" (app "prim__doublePow" ["2.5", "3.5"])
     , term "String" (app "prim__cast_DoubleString" ["0.1"])
     , term "Integer" (app "prim__cast_DoubleInteger" ["1.0e20"])
     , term "Double" (app "prim__cast_StringDouble" ["\"2.5e-3\""])
     ]
  ++ [ term "String" (app "prim__cast_DoubleString" [x]) | x <- ds ]

strings : List String
strings = ["\"hello\"", "\"h\\233llo\"", "\"\\955x.x\"", "\"\\128512!\""]

charTerms : List Term
charTerms =
  let cs = ["'a'", "'\\233'", "'\\8364'", "'\\128512'"] in
  [ term "Int" (app (prim op "Char") [x, y])
  | op <- ["lt", "lte", "eq", "gte", "gt"], (x, y) <- zip cs (reverse cs) ]
  ++ [ term "Int" (app "prim__cast_CharInt" [c]) | c <- cs ]
  ++ [ term "String" (app "prim__cast_CharString" [c]) | c <- cs ]
  ++ [ term "Char" (app "prim__cast_IntChar" [num v]) | v <- [65, 955, 128512, 1114111] ]

stringTerms : List Term
stringTerms =
  let ss = strings
      l = num in
  [ term "Int" (app "prim__strLength" [s]) | s <- ss ]
  ++ [ term "Char" (app "prim__strHead" [s]) | s <- ss ]
  ++ [ term "String" (app "prim__strTail" [s]) | s <- ss ]
  ++ [ term "Char" (app "prim__strIndex" [s, l 1]) | s <- ss ]
  ++ [ term "String" (app "prim__strCons" ["'\\955'", s]) | s <- ss ]
  ++ [ term "String" (app "prim__strAppend" [s, s']) | (s, s') <- zip ss (reverse ss) ]
  ++ [ term "String" (app "prim__strReverse" [s]) | s <- ss ]
  ++ [ term "String" (app "prim__strSubstr" [l 1, l 3, s]) | s <- ss ]
  ++ [ term "Int" (app (prim op "String") [x, y])
     | op <- ["lt", "lte", "eq", "gte", "gt"], (x, y) <- zip ss (reverse ss) ]
  ++ [ term "Int" (app "prim__cast_StringInt" ["\"-1234\""])
     , term "Integer" (app "prim__cast_StringInteger" ["\"123456789012345678901234567890\""])
     ]

bigTerms : List Term
bigTerms =
  let l = num
      a = 340282366920938463463374607431768211457
      b = -98765432109876543210 in
  [ term "Integer" (app (prim op "Integer") [l a, l b])
  | op <- ["add", "sub", "mul", "and", "or", "xor", "div", "mod"] ]
  ++ [ term "Integer" (app (prim op "Integer") [l x, l y])
     | op <- ["div", "mod"], (x, y) <- [(-17, 5), (17, -5), (-17, -5)] ]
  ++ [ term "Int" (app (prim op "Integer") [l a, l b]) | op <- ["lt", "lte", "eq", "gte", "gt"] ]
  ++ [ term "Double" (app "prim__cast_IntegerDouble" [l a])
     , term "String" (app "prim__cast_IntegerString" [l b]) ]

primitiveTerms : List Term
primitiveTerms =
  concatMap intTerms intTys ++ doubleTerms ++ charTerms ++ stringTerms ++ bigTerms

------------------------------------------------------------------------------
-- A corpus of total Prelude functions
------------------------------------------------------------------------------

preludeTerms : List Term
preludeTerms =
  let i = typed "Int" . num
      d = typed "Double"
      s = typed "String"
      c = typed "Char"
      big = typed "Integer" . num
      xs = "[" ++ joinBy ", " (map i [3, -1, 4, 1, -5, 9]) ++ "]" in
  [ term "Int" ("sum " ++ xs)
  , term "Int" ("product " ++ xs)
  , term "Int" ("foldr (\\x, acc => x - acc) " ++ i 0 ++ " " ++ xs)
  , term "Int" ("foldl (\\acc, x => acc * 2 + x) " ++ i 0 ++ " " ++ xs)
  , term "Integer" ("natToInteger (length " ++ xs ++ ")")
  , term "String" ("show " ++ xs)
  , term "String" ("show (map (\\x => x * x) " ++ xs ++ ")")
  , term "String" ("show (filter (\\x => x > 0) " ++ xs ++ ")")
  , term "String" ("show (reverse " ++ xs ++ ")")
  , term "String" ("show (elem " ++ i 4 ++ " " ++ xs ++ ")")
  , term "String" ("show (all (\\x => x > " ++ i (-10) ++ ") " ++ xs ++ ", any (\\x => x > 10) " ++ xs ++ ")")
  , term "String" ("show (Just " ++ i (-5) ++ ")")
  , term "String" ("show (the (Maybe Int) Nothing)")
  , term "String" ("show (the (Either Int String) (Left " ++ i 3 ++ "))")
  , term "String" ("show (" ++ i 1 ++ ", " ++ s "\"a\"" ++ ", " ++ c "'b'" ++ ")")
  , term "String" ("show " ++ i (-42))
  , term "String" ("show " ++ d "0.1")
  , term "String" ("show " ++ d "(-1.0e-7)")
  , term "String" ("show " ++ c "'x'")
  , term "String" ("show " ++ c "'\\n'")
  , term "String" ("show " ++ s "\"q\\\"u\\n\\233\"")
  , term "String" ("show " ++ big 12345678901234567890)
  , term "String" ("show (compare " ++ i 3 ++ " " ++ i 9 ++ ")")
  , term "Int" ("max " ++ i 3 ++ " " ++ i 9 ++ " + min " ++ i 3 ++ " " ++ i 9)
  , term "Int" ("abs " ++ i (-5))
  , term "Int" ("div " ++ i (-17) ++ " " ++ i 5 ++ " * 100 + mod " ++ i (-17) ++ " " ++ i 5)
  , term "Integer" ("div " ++ big (-17) ++ " " ++ big 5 ++ " * 100 + mod " ++ big (-17) ++ " " ++ big 5)
  , term "Integer" (big 2 ++ " * " ++ big 340282366920938463463374607431768211457 ++ " - " ++ big 1)
  , term "Double" ("cast " ++ i 7 ++ " / " ++ d "2.0")
  , term "Int" ("cast " ++ d "2.9")
  , term "Int" ("ord " ++ c "'A'")
  , term "Char" ("chr " ++ i 955)
  , term "Integer" ("natToInteger (length " ++ s "\"h\\233llo\"" ++ ")")
  , term "String" ("reverse " ++ s "\"h\\233llo\"")
  , term "String" ("pack (reverse (unpack " ++ s "\"abc\"" ++ "))")
  , term "String" ("concat [" ++ s "\"a\"" ++ ", " ++ s "\"\\955\"" ++ ", " ++ s "\"c\"" ++ "]")
  , term "String" ("substr 1 3 " ++ s "\"hello\"")
  , term "String" (s "\"ab\"" ++ " ++ " ++ s "\"cd\"")
  , term "String" ("show (maybe " ++ i 0 ++ " (\\x => x + 1) (Just " ++ i 9 ++ "))")
  , term "String" ("show (either (\\x => x) (const " ++ i 1 ++ ") (the (Either Int String) (Left " ++ i 4 ++ ")))")
  , term "String" ("show (fst (" ++ i 1 ++ ", " ++ i 2 ++ ") + snd (" ++ i 3 ++ ", " ++ i 4 ++ "))")
  , term "String" ("show (" ++ i 3 ++ " == " ++ i 3 ++ " && not (" ++ i 1 ++ " > " ++ i 2 ++ ") || False)")
  , term "String" ("show [" ++ i 1 ++ " .. " ++ i 5 ++ "]")
  , term "Double" ("sqrt " ++ d "2.0")
  , term "Double" ("floor " ++ d "(-2.5)" ++ " + ceiling " ++ d "2.5")
  , hostTerm "exp: libm" "Double" ("exp " ++ d "1.0")
  , hostTerm "sin: libm" "Double" ("sin " ++ d "1.0")
  , term "Integer" ("cast " ++ s "\"123456789012345678901234567890\"")
  ]

------------------------------------------------------------------------------
-- The programs
------------------------------------------------------------------------------

||| How a value of a type is printed.
printer : String -> String -> String
printer "String" e = e
printer "Char" e = "(prim__cast_IntString (prim__cast_CharInt " ++ e ++ "))"
printer t e = "(prim__cast_" ++ t ++ "String " ++ e ++ ")"

termsModule : List Term -> String
termsModule ts =
  let numbered = zip [1 .. length ts] ts in
  unlines $
    [ "module Terms", ""
    , "-- Generated by tests/TwoLevels.idr.", ""
    , "import Prelude", ""
    , "%default partial", "" ]
    ++ concatMap (\(n, t) =>
                    maybe [] (\r => ["-- host-dependent: t" ++ show n ++ " " ++ r]) t.host
                    ++ [ "public export", "t" ++ show n ++ " : " ++ t.ty
                       , "t" ++ show n ++ " = " ++ t.text, "" ])
                 numbered

||| The statements of `main` in groups of this many, each group a function
||| of its own. Idris elaborates a `do` block in time that grows faster than
||| its length: one block of the 662 primitive terms took 42 s to check,
||| most of the time a test command has, before anything was compiled, and
||| the same statements in groups of 32 take 2 s.
groupSize : Nat
groupSize = 32

||| `xs` in consecutive groups of `n` (the last may be shorter).
groups : Nat -> List a -> List (List a)
groups _ [] = []
groups n xs = take n xs :: groups n (drop n xs)

mainModule : List Term -> String
mainModule ts =
  let numbered = zip [1 .. length ts] ts
      parts = zip [1 .. length (groups groupSize numbered)] (groups groupSize numbered) in
  unlines $
    [ "module Main", ""
    , "-- Generated by tests/TwoLevels.idr.", ""
    , "import Prelude"
    , "import Terms", ""
    , "%default partial", "" ]
    ++ concatMap (\(k, part) =>
                    [ "part" ++ show k ++ " : IO ()"
                    , "part" ++ show k ++ " = do" ]
                    ++ map (\(n, t) => "  putStrLn (prim__strAppend \"t" ++ show n ++ " \" "
                                          ++ printer t.ty ("Terms.t" ++ show n) ++ ")") part
                    ++ [""])
                 parts
    ++ [ "main : IO ()"
       , "main = do" ]
    ++ map (\(k, _) => "  part" ++ show k) parts

||| `runtests --two-levels-program primitives|prelude terms|main`.
export
programOf : List String -> Maybe String
programOf [corpus, file] = do
  ts <- the (Maybe (List Term)) $ case corpus of
          "primitives" => Just primitiveTerms
          "prelude" => Just preludeTerms
          _ => Nothing
  case file of
    "terms" => Just (termsModule ts)
    "main" => Just (mainModule ts)
    _ => Nothing
programOf _ = Nothing
