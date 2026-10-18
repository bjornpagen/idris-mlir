-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The two levels: closed terms, over every primitive and over a corpus of
||| total Prelude functions, each with its value as an Idris term, which the
||| corpus's expected file records (tests/two-levels/terms/expected-<corpus>),
||| and as the compiled program computes it, which must be the same.
|||
|||     runtests --two-levels-program primitives|prelude terms|main
|||     runtests --two-levels-check primitives|prelude <stdout-file> <expected-file>
|||
||| The first prints `Terms.idr`, the terms `t1`, `t2`, ... (`public
||| export`), or `Main.idr`, which prints each as `t<n> <value>`. The second
||| reads what that program printed against the expected file, whose lines
||| are `<term> = <value>`, each term written as the corpus writes it: a
||| term is known by its text, which is unique and holds no ` = `, so a
||| term added, removed or moved changes one line.
|||
||| The primitives' corpus is the table's own: every primitive of
||| `Prims.prims`, applied to each of its argument sets, and a primitive
||| the table gains has no argument set until it is given one, which
||| `checks` reports. A primitive is applied to literals as they are: Idris
||| leaves the call in the checked term
||| (upstream/18-elaboration-primitive-folding), so the value printed is
||| this compiler's. The corpus of Prelude functions gives a literal its
||| type with `the`, where nothing else would.
|||
||| Values are printed as the programs print them: integers in decimal, a
||| Char as its code point, a String as itself, a Double as Idris's `show`.
|||
||| Terms whose value depends on the target by design are listed but not
||| compared: the libm functions, which are not correctly rounded, so that
||| the last places of their values are the platform libm's, while the
||| expected files are every target's. A cast from String reads a literal
||| of its type alike everywhere, so the casts here, of literals, are
||| compared.
module TwoLevels

import Prelude
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Prims

%default covering

||| A term: its type, its text, and why it is host-dependent, if it is.
record Term where
  constructor MkTerm
  ty : Ty
  text : String
  host : Maybe String

------------------------------------------------------------------------------
-- Every primitive
------------------------------------------------------------------------------

||| An Integer past any word, and a negative one past a word.
bigA, bigB : Integer
bigA = 340282366920938463463374607431768211457
bigB = -98765432109876543210

||| Doubles: seven literals, then NaN, the infinities and -0.0, made by the
||| terms' own arithmetic.
ds : List (Expr TDouble)
ds =
  [ DoubleLit NonNegative "0.1", DoubleLit Negative "2.5", DoubleLit NonNegative "1.0e300"
  , DoubleLit NonNegative "4.9e-324", DoubleLit NonNegative "2.2250738585072014e-308"
  , DoubleLit NonNegative "0.0", DoubleLit NonNegative "123456.789"
  , App (divOn TDouble) [DoubleLit NonNegative "0.0", DoubleLit NonNegative "0.0"]
  , App (divOn TDouble) [DoubleLit NonNegative "1.0", DoubleLit NonNegative "0.0"]
  , App (divOn TDouble) [DoubleLit Negative "1.0", DoubleLit NonNegative "0.0"]
  , App (negateOn TDouble) [DoubleLit NonNegative "0.0"] ]

||| Characters of each UTF-8 length.
cs : List (Expr TChar)
cs = map CharLit ['a', '\233', '\8364', '\128512']

||| Strings with characters of each UTF-8 length.
ss : List (Expr TString)
ss = map StringLit ["hello", "h\233llo", "\955x.x", "\128512!"]

||| Code points of each UTF-8 length, and the last scalar.
codePoints : List Integer
codePoints = [65, 955, 128512, 1114111]

||| A list beside itself turned once: each element with the next.
rotated : List a -> List (a, a)
rotated xs = zip xs (drop 1 xs ++ take 1 xs)

||| A list beside itself reversed.
mirrored : List a -> List (a, a)
mirrored xs = zip xs (reverse xs)

||| The pairs of values a two-integer primitive is applied to, by its
||| operation's family and its type: a fixed width's at its edges (`b` is
||| -7 signed, 7 unsigned), Integer's past any word.
integerPairs : Family -> IntTy -> List (Integer, Integer)
integerPairs kind (Fixed f) =
  let (lo, hi) = bounds f
      signed = (width f).signed
      b = the Integer (if signed then -7 else 7) in
  case kind of
    Arith => [(hi, b)]
    Bitwise => [(hi, b)]
    DivMod => if signed then [(lo, -1), (-17, 5), (17, -5), (hi, 7)] else [(hi, 7), (17, 5)]
    Shift => [(hi, 1), (b, 3)]
    Compare => [(lo, hi), (b, b)]
    _ => []
integerPairs kind Big = case kind of
  Arith => [(bigA, bigB)]
  Bitwise => [(bigA, bigB)]
  DivMod => [(bigA, bigB), (-17, 5), (17, -5), (-17, -5)]
  Shift => [(bigA, 3), (bigB, 64)]
  Compare => [(bigA, bigB)]
  _ => []

||| The argument pairs of a primitive of two parameters, by its operation
||| and their types.
binaryArgs : Op -> (t, u : Ty) -> List (Expr t, Expr u)
binaryArgs op (TIntegral i) (TIntegral j) =
  map (\(x, y) => (IntLit i x, IntLit j y)) (integerPairs (family op) i)
binaryArgs op TDouble TDouble = case family op of
  Arith => rotated ds
  DivMod => rotated ds
  Compare => mirrored ds
  DoubleFn => [(DoubleLit NonNegative "2.5", DoubleLit NonNegative "3.5")]
  _ => []
binaryArgs _ TChar TChar = mirrored cs
binaryArgs _ TString TString = mirrored ss
binaryArgs _ TString (TIntegral i) = map (\s => (s, IntLit i 1)) ss
binaryArgs _ TChar TString = map (\s => (CharLit '\955', s)) ss
binaryArgs _ _ _ = []

||| The arguments of a cast, by its source and target types.
castArgs : (from, to : Ty) -> List (Expr from)
castArgs (TIntegral (Fixed f)) to =
  let (lo, hi) = bounds f in
  case to of
    TIntegral (Fixed _) => [IntLit _ lo, IntLit _ hi]
    TIntegral Big => [IntLit _ lo]
    TDouble => [IntLit _ hi]
    TString => [IntLit _ lo]
    TChar => map (IntLit _) (filter (\v => lo <= v && v <= hi) codePoints)
castArgs (TIntegral Big) to = case to of
  TIntegral (Fixed _) => [IntLit Big bigA]
  TIntegral Big => []
  TDouble => [IntLit Big bigA]
  TString => [IntLit Big bigB]
  TChar => map (IntLit Big) codePoints
castArgs TDouble to = case to of
  TIntegral (Fixed _) => [DoubleLit Negative "2.75"]
  TIntegral Big => [DoubleLit NonNegative "1.0e20"]
  TString => ds
  _ => []
castArgs TChar to = case to of
  TIntegral _ => cs
  TString => cs
  _ => []
castArgs TString to = case to of
  TIntegral (Fixed _) => [StringLit "-1234"]
  TIntegral Big => [StringLit "123456789012345678901234567890"]
  TDouble => [StringLit "2.5e-3"]
  _ => []

||| The arguments of a primitive of one parameter, by its operation, its
||| parameter's type and its result's.
unaryArgs : Op -> (t : Ty) -> (result : Ty) -> List (Expr t)
unaryArgs Neg (TIntegral (Fixed f)) _ = let (lo, hi) = bounds f in [IntLit _ lo, IntLit _ hi]
unaryArgs Neg (TIntegral Big) _ = [IntLit Big bigA]
unaryArgs Neg TDouble _ = ds
unaryArgs Convert from to = castArgs from to
unaryArgs _ TString _ = ss
-- A libm function is not correctly rounded: its one term is listed, not
-- compared.
unaryArgs op TDouble _ = case hostOf op of
  Just _ => [DoubleLit NonNegative "0.5"]
  Nothing => ds
unaryArgs _ _ _ = []

||| A primitive's argument sets, by its operation and the types of its
||| parameters and result. A primitive of a shape none of these knows has
||| none, which `checks` reports.
total
argumentSets : (p : Prim) -> List (Args p.args)
argumentSets (MkPrim _ op ps result) = setsOf op ps
  where
    setsOf : Op -> (qs : Params []) -> List (Args qs)
    setsOf op (Param t _ Done) = map (\e => [e]) (unaryArgs op t result)
    setsOf op (Param t _ (Param u _ Done)) = map (\(x, y) => [x, y]) (binaryArgs op t u)
    setsOf _ (Param (TIntegral i) _ (Param (TIntegral j) _ (Param TString _ Done))) =
      map (\s => [IntLit i 1, IntLit j 3, s]) ss
    setsOf _ _ = []

||| A primitive applied to arguments, as a term.
term : (p : Prim) -> Args p.args -> Term
term p as = MkTerm p.result (source (App p as)) (hostReason (App p as))

primitiveTerms : List Term
primitiveTerms = prims >>= \p => map (term p) (argumentSets p)

------------------------------------------------------------------------------
-- A corpus of total Prelude functions
------------------------------------------------------------------------------

||| A literal of a type that nothing around it says.
typed : Ty -> String -> String
typed t v = "(the " ++ tyName t ++ " " ++ v ++ ")"

||| Why a Prelude function's value is the host's: it is a primitive's that
||| is, named as the program writes it.
through : Op -> String -> Maybe String
through op name = map (\why => name ++ ": " ++ why) (hostOf op)

preludeTerms : List Term
preludeTerms =
  let i = typed int . integerText
      d = typed TDouble
      s = typed TString
      c = typed TChar
      big = typed integer . integerText
      xs = "[" ++ joinBy ", " (map i [3, -1, 4, 1, -5, 9]) ++ "]" in
  [ term int ("sum " ++ xs)
  , term int ("product " ++ xs)
  , term int ("foldr (\\x, acc => x - acc) " ++ i 0 ++ " " ++ xs)
  , term int ("foldl (\\acc, x => acc * 2 + x) " ++ i 0 ++ " " ++ xs)
  , term integer ("natToInteger (length " ++ xs ++ ")")
  , term TString ("show " ++ xs)
  , term TString ("show (map (\\x => x * x) " ++ xs ++ ")")
  , term TString ("show (filter (\\x => x > 0) " ++ xs ++ ")")
  , term TString ("show (reverse " ++ xs ++ ")")
  , term TString ("show (elem " ++ i 4 ++ " " ++ xs ++ ")")
  , term TString ("show (all (\\x => x > " ++ i (-10) ++ ") " ++ xs ++ ", any (\\x => x > 10) " ++ xs ++ ")")
  , term TString ("show (Just " ++ i (-5) ++ ")")
  , term TString ("show (the (Maybe Int) Nothing)")
  , term TString ("show (the (Either Int String) (Left " ++ i 3 ++ "))")
  , term TString ("show (" ++ i 1 ++ ", " ++ s "\"a\"" ++ ", " ++ c "'b'" ++ ")")
  , term TString ("show " ++ i (-42))
  , term TString ("show " ++ d "0.1")
  , term TString ("show " ++ d "(-1.0e-7)")
  , term TString ("show " ++ c "'x'")
  , term TString ("show " ++ c "'\\n'")
  , term TString ("show " ++ s "\"q\\\"u\\n\\233\"")
  , term TString ("show " ++ big 12345678901234567890)
  , term TString ("show (compare " ++ i 3 ++ " " ++ i 9 ++ ")")
  , term int ("max " ++ i 3 ++ " " ++ i 9 ++ " + min " ++ i 3 ++ " " ++ i 9)
  , term int ("abs " ++ i (-5))
  , term int ("div " ++ i (-17) ++ " " ++ i 5 ++ " * 100 + mod " ++ i (-17) ++ " " ++ i 5)
  , term integer ("div " ++ big (-17) ++ " " ++ big 5 ++ " * 100 + mod " ++ big (-17) ++ " " ++ big 5)
  , term integer (big 2 ++ " * " ++ big 340282366920938463463374607431768211457 ++ " - " ++ big 1)
  , term TDouble ("cast " ++ i 7 ++ " / " ++ d "2.0")
  , term int ("cast " ++ d "2.9")
  , term int ("ord " ++ c "'A'")
  , term TChar ("chr " ++ i 955)
  , term integer ("natToInteger (length " ++ s "\"h\\233llo\"" ++ ")")
  , term TString ("reverse " ++ s "\"h\\233llo\"")
  , term TString ("pack (reverse (unpack " ++ s "\"abc\"" ++ "))")
  , term TString ("concat [" ++ s "\"a\"" ++ ", " ++ s "\"\\955\"" ++ ", " ++ s "\"c\"" ++ "]")
  , term TString ("substr 1 3 " ++ s "\"hello\"")
  , term TString (s "\"ab\"" ++ " ++ " ++ s "\"cd\"")
  , term TString ("show (maybe " ++ i 0 ++ " (\\x => x + 1) (Just " ++ i 9 ++ "))")
  , term TString ("show (either (\\x => x) (const " ++ i 1 ++ ") (the (Either Int String) (Left " ++ i 4 ++ ")))")
  , term TString ("show (fst (" ++ i 1 ++ ", " ++ i 2 ++ ") + snd (" ++ i 3 ++ ", " ++ i 4 ++ "))")
  , term TString ("show (" ++ i 3 ++ " == " ++ i 3 ++ " && not (" ++ i 1 ++ " > " ++ i 2 ++ ") || False)")
  , term TString ("show [" ++ i 1 ++ " .. " ++ i 5 ++ "]")
  , term TDouble ("sqrt " ++ d "2.0")
  , term TDouble ("floor " ++ d "(-2.5)" ++ " + ceiling " ++ d "2.5")
  , MkTerm TDouble ("exp " ++ d "1.0") (through DoubleExp "exp")
  , MkTerm TDouble ("sin " ++ d "1.0") (through DoubleSin "sin")
  , term integer ("cast " ++ s "\"123456789012345678901234567890\"")
  ]
  where
    term : Ty -> String -> Term
    term t e = MkTerm t e Nothing

||| A corpus by its name.
corpusOf : String -> Maybe (List Term)
corpusOf "primitives" = Just primitiveTerms
corpusOf "prelude" = Just preludeTerms
corpusOf _ = Nothing

||| What both hosts check of the corpora: every primitive has an argument
||| set, so the primitives' corpus holds every primitive of the table; and
||| every term is known by its text, as the expected files key it.
export
checks : List (String, Bool)
checks =
  [ ("every primitive has an argument set", all (\p => not (null (argumentSets p))) prims)
  , ("every term's text is unique", all unique corpora)
  , ("no term's text holds \" = \"", all (all (\t => not (" = " `isInfixOf` t.text))) corpora) ]
  where
    corpora : List (List Term)
    corpora = [primitiveTerms, preludeTerms]
    unique : List Term -> Bool
    unique ts = length (Prelude.toList (SortedSet.fromList (map (.text) ts))) == length ts

------------------------------------------------------------------------------
-- The programs
------------------------------------------------------------------------------

||| A term's name in the programs: `t<n>`, counted from 1.
numbered : List Term -> List (String, Term)
numbered ts = zip (map (\n => "t" ++ show n) [the Nat 1 .. length ts]) ts

termsModule : List Term -> String
termsModule ts =
  unlines $
    [ "module Terms", ""
    , "-- Generated by tests/TwoLevels.idr.", ""
    , "import Prelude", ""
    , "%default partial", "" ]
    ++ (numbered ts >>= \(name, t) =>
          [ "public export", name ++ " : " ++ tyName t.ty, name ++ " = " ++ t.text, "" ])

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
  let parts = zip [the Nat 1 .. length (groups groupSize (numbered ts))] (groups groupSize (numbered ts)) in
  unlines $
    [ "module Main", ""
    , "-- Generated by tests/TwoLevels.idr.", ""
    , "import Prelude"
    , "import Terms", ""
    , "%default partial", "" ]
    ++ (parts >>= \(k, part) =>
          [ "part" ++ show k ++ " : IO ()"
          , "part" ++ show k ++ " = do" ]
          ++ map (\(name, t) => "  " ++ printLine name t.ty ("Terms." ++ name)) part
          ++ [""])
    ++ [ "main : IO ()"
       , "main = do" ]
    ++ map (\(k, _) => "  part" ++ show k) parts

||| `runtests --two-levels-program primitives|prelude terms|main`.
export
programOf : List String -> Maybe String
programOf [corpus, file] = do
  ts <- corpusOf corpus
  case file of
    "terms" => Just (termsModule ts)
    "main" => Just (mainModule ts)
    _ => Nothing
programOf _ = Nothing

------------------------------------------------------------------------------
-- The check
------------------------------------------------------------------------------

||| A line of an expected file, `<term> = <value>`, split at its first
||| ` = `, which no term's text holds.
keyed : String -> Maybe (String, String)
keyed l = go [<] (unpack l)
  where
    go : SnocList Char -> List Char -> Maybe (String, String)
    go seen (' ' :: '=' :: ' ' :: value) = Just (pack (seen <>> []), pack value)
    go seen (c :: rest) = go (seen :< c) rest
    go _ [] = Nothing

||| What the program printed, by term: each line `t<n> <value>`, the term
||| its label names, the first line of a term kept.
printedValues : List Term -> String -> SortedMap String String
printedValues ts printed =
  let byLabel = SortedMap.fromList (map (\(name, t) => (name, t.text)) (numbered ts)) in
  foldr (\l, values => let (label, value) = labelled l in
                       case lookup label byLabel of
                         Just text => insert text value values
                         Nothing => values)
        empty (lines printed)

||| How the printed values differ from the expected ones, by term, in the
||| corpus's order, then the expected terms no longer in it, in the order
||| of their text.
differences : List Term -> SortedMap String String -> SortedMap String String -> List String
differences ts printed expected =
  (ts >>= \t => case (lookup t.text printed, t.host, lookup t.text expected) of
     (Nothing, _, _) => ["printed nothing: " ++ t.text]
     (Just _, Just _, _) => []
     (Just value, Nothing, Nothing) => ["no expected value: " ++ t.text ++ " = " ++ value]
     (Just value, Nothing, Just recorded) =>
       if value == recorded then [] else [t.text ++ " = " ++ recorded ++ ", printed " ++ value])
  ++ map ("not in the corpus: " ++) (filter (\text => not (contains text texts)) (keys expected))
  where
    texts : SortedSet String
    texts = SortedSet.fromList (map (.text) ts)

||| The lines `--two-levels-check` prints of a corpus's terms: the terms not
||| compared and why, then whether the program printed the expected values
||| and at most twenty differences.
verdict : String -> List Term -> String -> Maybe String -> List String
verdict corpus ts printed expected =
  mapMaybe (\t => (\why => corpus ++ ": not compared, host-dependent: " ++ why ++ ": " ++ t.text) <$> t.host) ts
  ++ case expected of
       Nothing => [corpus ++ ": no expected-" ++ corpus]
       Just recorded =>
         case differences ts (printedValues ts printed) (SortedMap.fromList (mapMaybe keyed (lines recorded))) of
           [] => [corpus ++ ": prints expected-" ++ corpus ++ ", the host-dependent terms aside"]
           found => (corpus ++ ": prints otherwise") :: map ("  | " ++) (take 20 found)

||| `runtests --two-levels-check <corpus> <stdout-file> <expected-file>`, of
||| the files' text (the expected file's when it could be read).
export
checkOf : (corpus : String) -> (printed : String) -> (expected : Maybe String) -> Maybe (List String)
checkOf corpus printed expected = (\ts => verdict corpus ts printed expected) <$> corpusOf corpus

||| The check's own checks, on two terms recorded as 1 and 2: an output
||| that prints them so names no term, and one that prints the second
||| otherwise names it.
export
checkerChecks : List (String, Bool)
checkerChecks =
  let ts = [MkTerm int "(one)" Nothing, MkTerm int "(two)" Nothing]
      run = \printed => verdict "unit" ts printed (Just "(one) = 1\n(two) = 2\n") in
  [ ("an agreeing output names no term",
     run "t1 1\nt2 2\n" == ["unit: prints expected-unit, the host-dependent terms aside"])
  , ("an output with one disagreeing line names that term",
     run "t1 1\nt2 3\n" == ["unit: prints otherwise", "  | (two) = 2, printed 3"]) ]
