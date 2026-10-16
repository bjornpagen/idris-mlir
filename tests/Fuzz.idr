-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fuzzer: programs of closed expressions over every primitive, each
||| written four ways, whose values must agree with each other and, over
||| the integers, with what the primitives mean (`fuzz` in
||| tests/lib/fuzz.sh).
|||
|||     runtests --fuzz-program program <seed> <cases> runtime|static main|stdin|model
|||     runtests --fuzz-program threads <seed>
|||     runtests --fuzz-program tape <seed> <case> runtime|static
|||     runtests --fuzz-program replay <tape> runtime|static main|stdin|model
|||     runtests --fuzz-program shrink <tape>
|||     runtests --fuzz-program two-hosts
|||
||| A case is one expression, well typed by construction, which Gen draws on
||| the case's own seed (output n of splitmix64 from the program's seed), so
||| a case is reproducible alone, from its seed or from its tape. A case's
||| expression is written four ways:
|||
||| - `d<n>`, in `main`, directly: its leaves are literals, which the
|||   primitives are applied to as written, so the folders compute it (Idris
|||   leaves the calls in the checked term:
|||   upstream/18-elaboration-primitive-folding);
||| - `j<n>`, in a function of its leaves, total and self recursive over a
|||   list of units, called with the literals: a closed call of a total
|||   function, which runs at run time;
||| - `r<n>`, in the runtime part, with its leaves behind `hide<T> 1`, a
|||   partial identity (it recurses on an Int, so Idris does not prove it
|||   terminating): a closed call of partial code, which runs at run time;
||| - `s<n>`, with its leaves read from stdin, which nothing before the run
|||   knows.
|||
||| A case's lines must print one value, and a case over the integers alone
||| the value their documented meaning gives (`model`, a line `m<n>` each). A
||| case through libm's functions (Exp, Log, Pow and the trigonometric
||| ones), which are not correctly rounded, so that the last places of their
||| values are the platform's, has its lines labelled `L`, and no `d` line
||| and no model.
|||
||| The `runtime` part holds what may exist at run time: the fixed-width
||| integers, Double, Char, a small sum type, and strings only as output
||| fusion writes them, so a string anything takes apart is a literal. The
||| `static` part holds Integer and every string builder too.
module Fuzz

import Prelude
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.SnocList
import Data.String
import Data.Vect
import Decidable.Equality
import Gen
import Prims
import Sem
import TwoLevels

%default total

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------

mutual
  ||| A primitive's arguments: an expression of each argument's type.
  data Args : List (Ty, Domain) -> Type where
    Nil : Args []
    (::) : {0 t : Ty} -> {0 d : Domain} -> {0 tds : List (Ty, Domain)} ->
           Expr t -> Args tds -> Args ((t, d) :: tds)

  ||| An expression, well typed by construction. An argument whose domain
  ||| says more than its type is a literal from that domain's pool.
  data Expr : Ty -> Type where
    ||| Inside its type's bounds (Integer's: any).
    IntLit : (t : Ty) -> {auto 0 isInt : IsInteger t} -> Integer -> Expr t
    ||| From the pool, as written: "(-0.1)".
    DoubleLit : (source : String) -> Expr TDouble
    ||| From the pool, as written: "'\955'".
    CharLit : (source : String) -> Expr TChar
    ||| From the pool, as written: "\"h\233llo\"".
    StringLit : (source : String) -> Expr TString
    App : (p : Prim) -> Args p.args -> Expr p.result
    ||| The sum type's helper; `k` is a literal from 0 to 2, its constructor.
    SData : (k : Expr TInt) -> Expr TInt -> Expr TDouble -> Expr TInt

||| What a type's literals are: an integer type's, Double's, Char's or
||| String's.
data Kind : Ty -> Type where
  AnInteger : (0 _ : IsInteger t) -> Kind t
  ADouble : Kind TDouble
  AChar : Kind TChar
  AString : Kind TString

kind : (t : Ty) -> Kind t
kind TInt = AnInteger IInt
kind TInt8 = AnInteger IInt8
kind TInt16 = AnInteger IInt16
kind TInt32 = AnInteger IInt32
kind TInt64 = AnInteger IInt64
kind TBits8 = AnInteger IBits8
kind TBits16 = AnInteger IBits16
kind TBits32 = AnInteger IBits32
kind TBits64 = AnInteger IBits64
kind TInteger = AnInteger IInteger
kind TDouble = ADouble
kind TChar = AChar
kind TString = AString

||| Two types of one index are one type. The coverage of these clauses is
||| the proof: no two types share an index.
sameIndex : (a, b : Ty) -> (0 _ : tyIndex a = tyIndex b) -> a = b
sameIndex TInt TInt _ = Refl
sameIndex TInt8 TInt8 _ = Refl
sameIndex TInt16 TInt16 _ = Refl
sameIndex TInt32 TInt32 _ = Refl
sameIndex TInt64 TInt64 _ = Refl
sameIndex TBits8 TBits8 _ = Refl
sameIndex TBits16 TBits16 _ = Refl
sameIndex TBits32 TBits32 _ = Refl
sameIndex TBits64 TBits64 _ = Refl
sameIndex TInteger TInteger _ = Refl
sameIndex TDouble TDouble _ = Refl
sameIndex TChar TChar _ = Refl
sameIndex TString TString _ = Refl

sameTy : (a, b : Ty) -> Maybe (a = b)
sameTy a b = case decEq (tyIndex a) (tyIndex b) of
  Yes same => Just (sameIndex a b same)
  No _ => Nothing

------------------------------------------------------------------------------
-- What a case may hold
------------------------------------------------------------------------------

||| A program's part: what may exist at run time, or what may exist at
||| compile time too.
data Part = Runtime | Static

||| What an expression of a type is, past a leaf: a primitive applied, or
||| the sum type's helper.
data Production = Apply Prim | SDataOf

resultOf : Production -> Ty
resultOf (Apply p) = p.result
resultOf SDataOf = TInt

||| What output fusion writes without building it: an append, a cons, and
||| a value's text.
writes : Prim -> Bool
writes p = case p.op of
  StrAppend => True
  StrCons => True
  Convert => p.result == TString
  _ => False

||| Whether a part holds a production. At run time no Integer exists, and a
||| string only as output fusion writes it.
has : Part -> Production -> Bool
has Static _ = True
has Runtime SDataOf = True
has Runtime (Apply p) =
  all (\(t, _) => t /= TInteger) p.args && p.result /= TInteger && (p.result /= TString || writes p)

||| The productions of a type in a part, each with the proof of its type.
productions : Part -> (t : Ty) -> List (pr : Production ** resultOf pr = t)
productions part t =
  mapMaybe (\pr => (\same => (pr ** same)) <$> sameTy (resultOf pr) t)
           (filter (has part) (SDataOf :: map Apply prims))

||| A family's place among a case's weights of the families.
familyIndex : Family -> Fin 9
familyIndex Arith = 0
familyIndex Negate = 1
familyIndex DivMod = 2
familyIndex Bitwise = 3
familyIndex Shift = 4
familyIndex Compare = 5
familyIndex Cast = 6
familyIndex Text = 7
familyIndex DoubleFn = 8

||| The families, each as likely. A case's swarm zeroes each with
||| probability one half, so a case is built of a few families, and the
||| interactions within them, rather than a thin mix of all.
families : Weights 9
families = MkWeights [1, 1, 1, 1, 1, 1, 1, 1, 1]

||| A production's weight in a case: its family's after the swarm, so every
||| primitive of a kept family is as likely as each other, and the helper
||| as likely as one of them.
weightIn : Vect 9 Nat -> Production -> Nat
weightIn kept (Apply p) = index (familyIndex (family p.op)) kept
weightIn _ SDataOf = 1

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| A literal as written: in parentheses when negative.
integerText : Integer -> String
integerText n = if n < 0 then "(" ++ show n ++ ")" else show n

||| Any value from `lo` to `hi`, each as likely; without 0 when the domain
||| says so, the range then being `lo` to -1 followed by 1 to `hi` (every
||| fixed width's range holds 0).
anyIn : (lo, hi : Integer) -> Domain -> Gen Integer
anyIn lo hi NonZero =
  (\i => let v = lo + natToInteger (finToNat i) in if v >= 0 then v + 1 else v)
    <$> draw (S (integerToNat (hi - lo - 1)))
anyIn lo hi _ = (\i => lo + natToInteger (finToNat i)) <$> draw (S (integerToNat (hi - lo)))

||| A literal of a fixed width: any of its values, twice as likely as each
||| of its edges and small values; not 0 when the domain says so. An
||| unsigned width's least value is 0, which the set holds once.
fixedLiteral : (lo, hi : Integer) -> Domain -> Gen Integer
fixedLiteral lo hi d =
  let signed = lo < 0
      small = nub [lo, hi, 0, 1, if signed then -1 else 2, 7, if signed then -100 else 100]
      vs = Vect.fromList (case d of NonZero => filter (/= 0) small; _ => small)
  in do i <- weighted (MkWeights (2 :: map (const 1) vs))
        case i of
          FZ => anyIn lo hi d
          FS j => pure (index j vs)

||| Integer's literals: small ones, the edges of the fixed widths and past
||| them, and values past any word; with 0 unless the domain says not.
bigLiteral : Domain -> Gen Integer
bigLiteral d =
  let nonzero = [ -1, 12345678901234567890, -98765432109876543210, 9223372036854775807
                , 9223372036854775808, 18446744073709551616, 340282366920938463463374607431768211456
                , -9223372036854775809, 42 ]
  in case d of
       NonZero => oneOf 1 nonzero
       _ => oneOf 0 (1 :: nonzero)

||| How far an Integer shifts: within and past the fixed widths, both ways,
||| so that a value of the pool above still fits in a few words.
shiftAmounts : Gen Integer
shiftAmounts = oneOf 0 [1, 3, 31, 32, 63, 64, 65, 100, -1, -3, -64, -100]

||| How many indices the argument at `k` offers: a string literal's scalars;
||| any other argument, and none there, offers none.
roomAt : Nat -> List Nat -> Nat
roomAt _ [] = 0
roomAt Z (r :: _) = r
roomAt (S k) (_ :: rs) = roomAt k rs

integerLiteral : List Nat -> Ty -> Domain -> Gen Integer
-- The argument indexed is a string of the NonEmpty pool, so its room is
-- the successor of one less.
integerLiteral rooms _ (IndexInto k) =
  (\i => natToInteger (finToNat i)) <$> draw (S (pred (roomAt k rooms)))
integerLiteral _ _ SmallShift = shiftAmounts
integerLiteral _ t d = case bounds t of
  Just (lo, hi) => fixedLiteral lo hi d
  Nothing => bigLiteral d

doubleLiteral : Domain -> Gen String
-- Finite, and small: a cast to an integer type takes it.
doubleLiteral Finite = oneOf "0.0" ["1.5", "(-2.75)", "1000.25", "(-1.0e6)", "0.999", "12345.5"]
doubleLiteral _ =
  oneOf "0.0"
    [ "1.0", "0.1", "0.5", "2.5", "3.0", "100.0", "1.0e10", "1.0e-10", "123456.789"
    , "1.7976931348623157e308", "2.2250738585072014e-308", "4.9e-324", "1.0e-320"
    , "(-0.1)", "(-2.5)", "(-1.0e300)", "6.02214076e23", "0.3", "(-7.0)" ]

charLiteral : Gen String
charLiteral = oneOf "'a'" ["'Z'", "'0'", "' '", "'\\233'", "'\\955'", "'\\8364'", "'\\128512'", "'~'"]

||| Strings with non-ASCII characters; `"a"` aside, which a pool puts first.
nonEmptyStrings : List String
nonEmptyStrings =
  [ "\"hello\"", "\"h\\233llo\"", "\"\\955x.x\"", "\"\\8364 5\"", "\"\\128512!\""
  , "\"abc def\"", "\"Z\"" ]

stringLiteral : Domain -> Gen String
stringLiteral NonEmpty = oneOf "\"a\"" nonEmptyStrings
stringLiteral _ = oneOf "\"\"" ("\"a\"" :: nonEmptyStrings)

||| A literal of a type in a domain, from the type's pool for that domain;
||| `rooms` holds what the arguments before offer to index into.
literal : List Nat -> (t : Ty) -> Domain -> Gen (Expr t)
literal rooms t d = case kind t of
  AnInteger isInt => IntLit t {isInt} <$> integerLiteral rooms t d
  ADouble => DoubleLit <$> doubleLiteral d
  AChar => CharLit <$> charLiteral
  AString => StringLit <$> stringLiteral d

||| A code point a value of an integer type holds: scalar values across
||| UTF-8's lengths and at the edges of the surrogates and of Unicode, and
||| values that are no scalar (a negative one, a surrogate, one past
||| U+10FFFF), which cast to 0. Every integer type holds 65 and 0.
codePoint : (t : Ty) -> (0 _ : IsInteger t) -> Gen (Expr t)
codePoint t isInt =
  IntLit t {isInt} <$> oneOf 65 (filter holds [233, 955, 8364, 128512, 0, 55295, 57344, 1114111, -1, 55296, 57343, 1114112])
  where
    holds : Integer -> Bool
    holds v = case bounds t of
      Just (lo, hi) => lo <= v && v <= hi
      Nothing => True

||| The pool of a cast's operand, for the casts that read few values
||| meaningfully: to Char, a code point (almost every other integer is no
||| scalar and casts to 0); from String, a number's text (almost every
||| other string reads as 0).
castPool : Op -> (from : Ty) -> Kind from -> Kind to -> Maybe (Gen (Expr from))
castPool Convert from (AnInteger isInt) AChar = Just (codePoint from isInt)
castPool Convert _ AString (AnInteger _) =
  Just (StringLit <$> oneOf "\"0\"" ["\"42\"", "\"-17\"", "\"9223372036854775807\"", "\"123456\""])
castPool Convert _ AString ADouble = Just (StringLit <$> oneOf "\"0.5\"" ["\"-2.25\"", "\"1e10\"", "\"3.0\"", "\"0.1\""])
castPool _ _ _ _ = Nothing

||| Where an argument comes from.
data Origin : Ty -> Type where
  Pool : Gen (Expr t) -> Origin t
  Expression : Origin t

||| Where an argument of type `t` of `p` comes from: a literal of its
||| domain, when that says more than the type; a literal of the cast's pool,
||| for a cast that has one; at run time, a literal for a string that `p`
||| takes apart, since there a string is only what output fusion writes;
||| otherwise any expression of its type.
origin : Part -> Prim -> List Nat -> (t : Ty) -> Domain -> Origin t
origin part p rooms t Anything =
  case castPool p.op t (kind t) (kind p.result) of
    Just pool => Pool pool
    Nothing => case part of
      Runtime => if t == TString && not (writes p) then Pool (literal rooms t Anything) else Expression
      Static => Expression
origin _ _ rooms t d = Pool (literal rooms t d)

||| A Char's or a String's source as its text: the quotes dropped, and each
||| escape, `\` and decimal digits, the scalar it names (no pool puts a
||| digit after an escape).
unescaped : String -> String
unescaped s = case split (== '\\') (substr 1 (minus (length s) 2) s) of
  first ::: escapes => concat (first :: map scalar escapes)
  where
    scalar : String -> String
    scalar e =
      let (digits, rest) = span isDigit (unpack e)
      in pack (chr (cast (foldl (\n, c => 10 * n + cast {to = Integer} (ord c - ord '0')) 0 digits)) :: rest)

||| How many indices an argument offers: a string literal's scalars.
roomOf : Expr t -> Nat
roomOf (StringLit s) = length (unescaped s)
roomOf _ = 0

------------------------------------------------------------------------------
-- Cases
------------------------------------------------------------------------------

||| A leaf: a literal of the type's own pool.
leaf : (t : Ty) -> Gen (Expr t)
leaf t = literal [] t Anything

mutual
  ||| An expression of type `t` at most `depth` deep: above the bottom, a
  ||| leaf one node in five, else a production of `t`.
  expr : Part -> Vect 9 Nat -> (t : Ty) -> (depth : Nat) -> Gen (Expr t)
  expr _ _ t Z = leaf t
  expr part kept t (S d) = do
    i <- weighted (MkWeights [1, 4])
    case i of
      FZ => leaf t
      FS _ => node part kept t d

  ||| A production of `t`, each as likely as its weight in the case; a leaf
  ||| when the case has none of weight.
  node : Part -> Vect 9 Nat -> (t : Ty) -> Nat -> Gen (Expr t)
  node part kept t d =
    let options = Vect.fromList (productions part t) in
    case weightsOf (map (\(pr ** _) => weightIn kept pr) options) of
      Nothing => leaf t
      Just w => do
        i <- weighted w
        let (pr ** same) = index i options
        build part kept pr same d

  build : Part -> Vect 9 Nat -> (pr : Production) -> (0 _ : resultOf pr = t) -> Nat -> Gen (Expr t)
  build part kept (Apply p) Refl d = App p <$> arguments part kept p d [] p.args
  build part kept SDataOf Refl d =
    [| SData ((\i => IntLit TInt (natToInteger (finToNat i))) <$> draw 3)
             (expr part kept TInt d) (expr part kept TDouble d) |]

  ||| A primitive's arguments, left to right; `rooms` holds, for each
  ||| argument before, how many indices it offers.
  arguments : Part -> Vect 9 Nat -> Prim -> Nat -> (rooms : List Nat) -> (tds : List (Ty, Domain)) -> Gen (Args tds)
  arguments _ _ _ _ _ [] = pure []
  arguments part kept p d rooms ((t, dom) :: tds) = do
    e <- case origin part p rooms t dom of
           Pool pool => pool
           Expression => expr part kept t d
    rest <- arguments part kept p d (rooms ++ [roomOf e]) tds
    pure (e :: rest)

||| A case: an expression and its type.
record Case where
  constructor MkCase
  ty : Ty
  body : Expr ty

||| A case's depth is from 1 to this, each as likely. With a leaf one node
||| in five above the bottom, these are the proportions the fuzzer's
||| thirty-case programs compiled within the test's limits with.
depthBound : Nat
depthBound = 4

||| A case's type, each of its part's as likely: no type is favoured.
caseTy : Part -> Gen Ty
caseTy Runtime = oneOf TDouble (fixedTys ++ [TChar, TString])
caseTy Static = oneOf TInteger [TString, TInt, TDouble]

||| A case of a part: the families it keeps, its type, its depth, then its
||| expression.
genCase : Part -> Gen Case
genCase part = do
  MkWeights kept <- swarm families
  t <- caseTy part
  depth <- draw depthBound
  MkCase t <$> expr part kept t (S (finToNat depth))

||| The cells a case's tape needs: the swarm's draws (one weighted, a coin
||| per family), the type's and the depth's; then at most three a node
||| (whether it is a leaf, then its production or its literal, a literal
||| being at most an entry of its pool and a value), over as many nodes as a
||| tree of the deepest depth and the largest arity holds. A derivation
||| that falls short shows as an overran case, which fails the check.
caseCapacity : Nat
caseCapacity =
  let MkWeights coins = families
      arity = foldr (\p, a => max (length p.args) a) 3 prims  -- 3: the helper's
      nodes = sum [ power arity level | level <- [0 .. depthBound] ]
  in 1 + length coins + 1 + 1 + 3 * nodes

------------------------------------------------------------------------------
-- Writing a case
------------------------------------------------------------------------------

||| A leaf as the renderings see it: its type, its text in a program, and
||| its line of stdin.
record Leaf where
  constructor MkLeaf
  ty : Ty
  source : String
  input : String

||| A Double's source without the parentheses a negative one is written in.
unparenthesized : String -> String
unparenthesized s = case unpack s of
  '(' :: rest => pack (take (minus (length rest) 1) rest)
  _ => s

||| How a line of stdin, `x`, is read as a value of a type.
reader : Ty -> String -> String
reader t x = case kind t of
  AChar => "(prim__strHead " ++ x ++ ")"
  AString => x
  _ => "(" ++ castNamed TString t ++ " " ++ x ++ ")"

||| How a case's leaves are written: as the literals (`d`), behind
||| `hide<T> 1` (`r`), as the parameters of the case's function (`j`), or
||| read from stdin (`s`).
data Mode = Direct | Hidden | Parameter | Read

written : Mode -> Leaf -> Nat -> String
written Direct l _ = l.source
written Hidden l _ = "(hide" ++ tyName l.ty ++ " 1 " ++ l.source ++ ")"
written Parameter _ k = "x" ++ show k
written Read l k = reader l.ty ("x" ++ show k)

applied : String -> List String -> String
applied f as = "(" ++ f ++ concatMap (" " ++) as ++ ")"

mutual
  ||| An expression's text, its leaves numbered on from those already met,
  ||| which it adds to: one walk numbers the leaves of every rendering.
  render : Mode -> Expr t -> SnocList Leaf -> (String, SnocList Leaf)
  render m (IntLit t v) ls = leafIn m (MkLeaf t (integerText v) (show v)) ls
  render m (DoubleLit s) ls = leafIn m (MkLeaf TDouble s (unparenthesized s)) ls
  render m (CharLit s) ls = leafIn m (MkLeaf TChar s (unescaped s)) ls
  render m (StringLit s) ls = leafIn m (MkLeaf TString s (unescaped s)) ls
  render m (App p as) ls = let (texts, ls') = renderArgs m as ls in (applied p.name texts, ls')
  render m (SData k i x) ls =
    let (a, l1) = render m k ls
        (b, l2) = render m i l1
        (c, l3) = render m x l2
    in (applied "sdata" [a, b, c], l3)

  renderArgs : Mode -> Args tds -> SnocList Leaf -> (List String, SnocList Leaf)
  renderArgs _ [] ls = ([], ls)
  renderArgs m (e :: es) ls =
    let (a, l1) = render m e ls
        (as, l2) = renderArgs m es l1
    in (a :: as, l2)

  leafIn : Mode -> Leaf -> SnocList Leaf -> (String, SnocList Leaf)
  leafIn m l ls = (written m l (length ls), ls :< l)

text : Mode -> Expr t -> String
text m e = fst (render m e [<])

leaves : Expr t -> List Leaf
leaves e = toList (snd (render Direct e [<]))

mutual
  ||| Whether an expression's value is the host's: some primitive of it is.
  onHost : Expr t -> Bool
  onHost (App p as) = isJust (hostOf p.op) || onHostArgs as
  onHost (SData k i x) = onHost k || onHost i || onHost x
  onHost (IntLit _ _) = False
  onHost (DoubleLit _) = False
  onHost (CharLit _) = False
  onHost (StringLit _) = False

  onHostArgs : Args tds -> Bool
  onHostArgs [] = False
  onHostArgs (e :: es) = onHost e || onHostArgs es

||| How a value of a type is printed: as a string, written by output fusion.
printer : Ty -> String -> String
printer t e = case kind t of
  AString => e
  AChar => "(" ++ castNamed TInt TString ++ " (" ++ castNamed TChar TInt ++ " " ++ e ++ "))"
  _ => "(" ++ castNamed t TString ++ " " ++ e ++ ")"

line : String -> Ty -> String -> String
line label t e = "  putStrLn (prim__strAppend \"" ++ label ++ " \" " ++ printer t e ++ ")"

------------------------------------------------------------------------------
-- The integers' documented meaning
------------------------------------------------------------------------------

||| An integer type's range: a fixed width, which every value wraps to, or
||| Integer's, which has no bound.
data Range = Fixed Width | Unbounded

rangeOf : Ty -> Maybe Range
rangeOf t = case kind t of
  AnInteger _ => Just (maybe Unbounded Fixed (widthOf t))
  _ => Nothing

inRange : Range -> Integer -> Integer
inRange (Fixed w) v = wrap w v
inRange Unbounded v = v

divide : Range -> Integer -> Integer -> Integer
divide (Fixed w) a b = quotient w a b
divide Unbounded a b = fst (euclid a b)

modulus : Range -> Integer -> Integer -> Integer
modulus (Fixed w) a b = remainder w a b
modulus Unbounded a b = snd (euclid a b)

bitwiseIn : Range -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bitwiseIn (Fixed w) = bitwise w
bitwiseIn Unbounded = bigBitwise

shiftIn : Range -> (left : Bool) -> Integer -> Integer -> Integer
shiftIn (Fixed w) = shifted w
shiftIn Unbounded = bigShifted

||| What a primitive gives on integer values, as the runtime documents it;
||| Nothing for a primitive the model leaves out, every one whose result
||| or operands are not integers.
meaning : Prim -> List Integer -> Maybe Integer
meaning p vs = do
  r <- rangeOf p.result
  case (p.op, vs) of
    (Neg, [a]) => Just (inRange r (negate a))
    (Div, [a, b]) => Just (divide r a b)
    (Mod, [a, b]) => Just (modulus r a b)
    (Convert, [a]) => Just (inRange r a)
    (op, [a, b]) =>
      (\f => inRange r (f a b)) <$> lookup op arithmetic
        <|> (\f => bitwiseIn r f a b) <$> lookup op logical
        <|> (\left => shiftIn r left a b) <$> lookup op shifts
        <|> (\f => if f a b then 1 else 0) <$> lookup op comparisons
    _ => Nothing

mutual
  ||| The value of an expression over the integers alone.
  modelled : Expr t -> Maybe Integer
  modelled (IntLit _ v) = Just v
  modelled (App p as) = modelledArgs as >>= meaning p
  modelled (DoubleLit _) = Nothing
  modelled (CharLit _) = Nothing
  modelled (StringLit _) = Nothing
  modelled (SData _ _ _) = Nothing

  modelledArgs : Args tds -> Maybe (List Integer)
  modelledArgs [] = Just []
  modelledArgs (e :: es) = [| modelled e :: modelledArgs es |]

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| A case written into the places of a program.
record Written where
  constructor MkWritten
  function : List String
  direct : List String
  runner : List String
  inputs : List String
  models : List String
  hides : List Ty

||| Case `n` of a part, written.
write : Part -> Nat -> Case -> Written
write part n (MkCase t e) =
  let host = onHost e
      tag = (if host then "L" else "") ++ show n
      ls = leaves e
      numbered = zip [0 .. length ls] ls
      name = "c" ++ show n
      xs = concatMap (\(k, _) => " x" ++ show k) numbered
      fn = [ name ++ " : List () -> " ++ concatMap (\l => tyName l.ty ++ " -> ") ls ++ tyName t
           , name ++ " []" ++ xs ++ " = " ++ text Parameter e
           , name ++ " (_ :: k)" ++ xs ++ " = " ++ name ++ " k" ++ xs
           , "" ]
      call = "(" ++ name ++ " [()]" ++ concatMap (\l => " " ++ l.source) ls ++ ")"
      -- Only what exists at run time is hidden behind hide<T>, whose
      -- barriers then need the leaves' types.
      (hidden, hides) = the (List String, List Ty) $ case part of
                          Runtime => ([line ("r" ++ tag) t (text Hidden e)], map (.ty) ls)
                          Static => ([], [])
      runner = [ "run" ++ show n ++ " : IO ()"
               , "run" ++ show n ++ " = do"
               , line ("j" ++ tag) t call ]
               ++ hidden
               ++ map (\(k, _) => "  x" ++ show k ++ " <- getLine") numbered
               ++ [ line ("s" ++ tag) t (text Read e), "" ]
      direct = if host then [] else [line ("d" ++ tag) t (text Direct e)]
      model = maybe [] (\v => ["m" ++ show n ++ " " ++ show v]) (modelled e)
  in MkWritten fn direct runner (map (.input) ls) model hides

||| The helpers every program has: hide<T> for every type, and the small sum
||| type.
helpers : List String
helpers = concatMap helper (fixedTys ++ [TDouble, TChar, TString, TInteger]) ++
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
      [ "hide" ++ n ++ " : Int -> " ++ n ++ " -> " ++ n
      , "hide" ++ n ++ " 0 x = x"
      , "hide" ++ n ++ " k x = hide" ++ n ++ " (prim__sub_Int k 1) x", "" ]

||| Two calls of hide<T> with different values, so that no analysis sees one
||| constant for its parameter.
barrier : Ty -> List String
barrier t =
  let (a, b) = twoOf t (kind t) in
  [line "b" t (text Hidden a), line "b" t (text Hidden b)]
  where
    twoOf : (u : Ty) -> Kind u -> (Expr u, Expr u)
    twoOf u (AnInteger isInt) = (IntLit u {isInt} 0, IntLit u {isInt} 1)
    twoOf _ ADouble = (DoubleLit "0.0", DoubleLit "1.0")
    twoOf _ AChar = (CharLit "'a'", CharLit "'Z'")
    twoOf _ AString = (StringLit "\"\"", StringLit "\"a\"")

||| The files of a program.
data File = MainFile | StdinFile | ModelFile

||| A program's file, of its cases (each with whether its tape overran), for
||| the request written in its header.
programText : String -> Part -> File -> List (Case, Bool) -> String
programText request part file cases =
  let numbered = zip [the Nat 1 .. length cases] cases
      ws = map (\(n, (c, _)) => write part n c) numbered
      overran = map (\(n, _) => n) (filter (\(_, (_, o)) => o) numbered)
  in case file of
       StdinFile => unlines (concatMap (.inputs) ws)
       ModelFile => unlines (concatMap (.models) ws)
       MainFile => unlines $
         map (\n => "-- overran: case " ++ show n) (take 1 overran) ++
         [ "module Main", ""
         , "-- Generated by tests/Fuzz.idr: runtests --fuzz-program " ++ request, ""
         , "import Prelude", ""
         , "%default partial", "" ]
         ++ helpers ++ concatMap (.function) ws ++ concatMap (.runner) ws ++
         [ "main : IO ()", "main = do" ]
         ++ concatMap (.direct) ws
         ++ map (\(n, _) => "  run" ++ show n) numbered
         ++ concatMap barrier (nub (concatMap (.hides) ws))

||| The cases of a program: case n on output n of splitmix64 from the seed,
||| all on one tape.
cases : Bits64 -> Nat -> Part -> List (Case, Bool)
cases seed n part = seededEach caseCapacity (map (caseSeed seed) [1 .. n]) (genCase part)

||| A seed's thread count: one of 1, 3, 5 and 13, each as likely, on the
||| seed's output 0, which no case is drawn on. The compiler's output must
||| not depend on it, and these are the counts its determinism is held to.
threads : Bits64 -> Nat
threads seed =
  index (seeded 1 (caseSeed seed 0) (weighted (MkWeights [1, 1, 1, 1]))).value [1, 3, 5, 13]

tapeText : List Nat -> String
tapeText vs = joinBy "," (map show vs)

||| Case `n`'s tape.
tapeOf : Bits64 -> Nat -> Part -> List Nat
tapeOf seed n part = (seeded caseCapacity (caseSeed seed n) (genCase part)).tape

||| The text of a tape: its values joined by `,`; an empty tape is empty.
parseTape : String -> Maybe (List Nat)
parseTape s = traverse parsePositive (words (pack (map (\c => if c == ',' then ' ' else c) (unpack s))))

parsePart : String -> Maybe Part
parsePart "runtime" = Just Runtime
parsePart "static" = Just Static
parsePart _ = Nothing

parseFile : String -> Maybe File
parseFile "main" = Just MainFile
parseFile "stdin" = Just StdinFile
parseFile "model" = Just ModelFile
parseFile _ = Nothing

||| A seed: any integer, taken modulo 2^64.
parseSeed : String -> Maybe Bits64
parseSeed s = cast {to = Bits64} <$> parseInteger {a = Integer} s

||| A program's number of cases: at least one, so `main` has a statement.
parseCases : String -> Maybe Nat
parseCases s = case parsePositive {a = Nat} s of
  Just (S k) => Just (S k)
  _ => Nothing

||| The text both hosts must print alike: Gen's checks, then what the
||| generators make of a few requests, each after a line `== <request>`.
export covering
twoHosts : String
twoHosts =
  let tape = tapeText (tapeOf 1 2 Runtime) in
  unlines (map (\(name, holds) => "gen: " ++ name ++ ": " ++ (if holds then "ok" else "failed")) checks)
  ++ concatMap section (the (List (String, String))
       [ ("program 1 3 runtime main", programText "program 1 3 runtime main" Runtime MainFile (cases 1 3 Runtime))
       , ("program 1 3 runtime stdin", programText "program 1 3 runtime stdin" Runtime StdinFile (cases 1 3 Runtime))
       , ("program 1 3 runtime model", programText "program 1 3 runtime model" Runtime ModelFile (cases 1 3 Runtime))
       , ("program 1 3 static main", programText "program 1 3 static main" Static MainFile (cases 1 3 Static))
       , ("threads 1", show (threads 1) ++ "\n")
       , ("tape 1 2 runtime", tape ++ "\n")
       , ("shrink " ++ tape, unlines (map tapeText (candidates (tapeOf 1 2 Runtime))))
       , ("sem prim-int-arith-0", fromMaybe "no program\n" (Sem.programOf "prim-int-arith-0"))
       , ("two-levels primitives terms", fromMaybe "no program\n" (TwoLevels.programOf ["primitives", "terms"]))
       , ("two-levels prelude main", fromMaybe "no program\n" (TwoLevels.programOf ["prelude", "main"]))
       ])
  where
    section : (String, String) -> String
    section (title, body) = "== " ++ title ++ "\n" ++ body

||| `runtests --fuzz-program ...`: the forms the module's header lists.
export covering
programOf : List String -> Maybe String
programOf request@["program", seed, n, part, file] = do
  s <- parseSeed seed
  k <- parseCases n
  p <- parsePart part
  f <- parseFile file
  pure (programText (unwords request) p f (cases s k p))
programOf ["threads", seed] = (\s => show (threads s) ++ "\n") <$> parseSeed seed
programOf ["tape", seed, n, part] = do
  s <- parseSeed seed
  k <- parsePositive n
  p <- parsePart part
  pure (tapeText (tapeOf s k p) ++ "\n")
programOf request@["replay", tape, part, file] = do
  t <- parseTape tape
  p <- parsePart part
  f <- parseFile file
  let d = replay t (genCase p)
  pure (programText (unwords request) p f [(d.value, d.overran)])
programOf ["shrink", tape] = (\t => unlines (map tapeText (candidates t))) <$> parseTape tape
programOf ["two-hosts"] = Just twoHosts
programOf _ = Nothing
