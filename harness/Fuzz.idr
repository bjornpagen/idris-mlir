-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fuzzer: programs of closed expressions over every primitive, each
||| written four ways, whose values must agree with each other and, over
||| the integers, with what the primitives mean (`fuzz` in
||| harness/lib/fuzz.sh).
|||
|||     runtests --fuzz-program program <seed> <cases> runtime|static main|stdin
|||     runtests --fuzz-program threads <seed>
|||     runtests --fuzz-program tape <seed> <case> runtime|static
|||     runtests --fuzz-program replay <tape> runtime|static main|stdin
|||     runtests --fuzz-program shrink <tape>
|||     runtests --fuzz-program two-hosts
|||     runtests --fuzz-check overran <request>
|||     runtests --fuzz-check agree|model|first <request> <stdout-file>
|||
||| where a check's request is `program <seed> <cases> runtime|static` or
||| `replay <tape> runtime|static`.
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
||| the value their documented meaning gives. A case through libm's
||| functions (Exp, Log, Pow and the trigonometric ones), which are not
||| correctly rounded, so that the last places of their values are the
||| platform's, has no `d` line and no model. The check regenerates a
||| request's cases and reads the program's output by their labels, so
||| what the generator knows of a case is never written into the program
||| for a reader to parse back.
|||
||| The `runtime` part holds what may exist at run time: the fixed-width
||| integers, Double, Char, a small sum type, and strings only as output
||| fusion writes them, so a string anything takes apart is a literal. The
||| `static` part holds Integer and every string builder too.
module Fuzz

import Prelude
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.Maybe
import Data.Nat
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect
import Decidable.Equality
import Gen
import Prims
import Sem
import TwoLevels

%default total

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
resultOf SDataOf = int

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
  all (/= integer) (paramTys p.args) && p.result /= integer && (p.result /= TString || writes p)

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

||| Any value from `lo` to `hi`, each as likely; without 0 when the domain
||| says so, the range then being `lo` to -1 followed by 1 to `hi` (every
||| fixed width's range holds 0).
anyIn : (lo, hi : Integer) -> Domain before -> Gen Integer
anyIn lo hi NonZero =
  (\i => let v = lo + natToInteger (finToNat i) in if v >= 0 then v + 1 else v)
    <$> draw (S (integerToNat (hi - lo - 1)))
anyIn lo hi _ = (\i => lo + natToInteger (finToNat i)) <$> draw (S (integerToNat (hi - lo)))

||| A literal of a fixed width: any of its values, twice as likely as each
||| of its edges and small values; not 0 when the domain says so. An
||| unsigned width's least value is 0, which the set holds once.
fixedLiteral : (lo, hi : Integer) -> Domain before -> Gen Integer
fixedLiteral lo hi d =
  let signed = lo < 0
      small = nub [lo, hi, 0, 1, if signed then -1 else 2, 7, if signed then -100 else 100]
      vs = Vect.fromList (case d of NonZero => filter (/= 0) small; _ => small)
  in do i <- weighted (MkWeights (2 :: map (const 1) vs))
        case i.fst of
          FZ => anyIn lo hi d
          FS j => pure (index j vs)

||| Integer's literals: small ones, the edges of the fixed widths and past
||| them, and values past any word; with 0 unless the domain says not.
bigLiteral : Domain before -> Gen Integer
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

||| What the arguments drawn so far offer the next, the latest first: the
||| room of each string an index may point into, `S k` scalars written as
||| its `k`, so that such a string offers at least one; and nothing for
||| any other argument.
data Drawn : List Earlier -> Type where
  None : Drawn []
  Room : (k : Nat) -> Drawn before -> Drawn (IndexableString :: before)
  Past : Drawn before -> Drawn (Opaque :: before)

||| The room, less one, of the string `el` points at.
reach : Elem IndexableString before -> Drawn before -> Nat
reach Here (Room k _) = k
reach (There el) (Room _ drawn) = reach el drawn
reach (There el) (Past drawn) = reach el drawn

integerLiteral : Drawn before -> IntTy -> Domain before -> Gen Integer
integerLiteral drawn _ (IndexInto el) = (\i => natToInteger (finToNat i)) <$> draw (S (reach el drawn))
integerLiteral _ _ SmallShift = shiftAmounts
integerLiteral _ (Fixed f) d = let (lo, hi) = bounds f in fixedLiteral lo hi d
integerLiteral _ Big d = bigLiteral d

doubleLiteral : Domain before -> Gen (Sign, String)
-- Finite, and small: a cast to an integer type takes it.
doubleLiteral Finite =
  oneOf (NonNegative, "0.0")
    [ (NonNegative, "1.5"), (Negative, "2.75"), (NonNegative, "1000.25"), (Negative, "1.0e6")
    , (NonNegative, "0.999"), (NonNegative, "12345.5") ]
doubleLiteral _ =
  oneOf (NonNegative, "0.0")
    [ (NonNegative, "1.0"), (NonNegative, "0.1"), (NonNegative, "0.5"), (NonNegative, "2.5")
    , (NonNegative, "3.0"), (NonNegative, "100.0"), (NonNegative, "1.0e10"), (NonNegative, "1.0e-10")
    , (NonNegative, "123456.789"), (NonNegative, "1.7976931348623157e308")
    , (NonNegative, "2.2250738585072014e-308"), (NonNegative, "4.9e-324"), (NonNegative, "1.0e-320")
    , (Negative, "0.1"), (Negative, "2.5"), (Negative, "1.0e300"), (NonNegative, "6.02214076e23")
    , (NonNegative, "0.3"), (Negative, "7.0") ]

charLiteral : Gen Char
charLiteral = oneOf 'a' ['Z', '0', ' ', '\233', '\955', '\8364', '\128512', '~']

||| Strings with non-ASCII characters, each as its first character and the
||| rest; `"a"` aside, which a pool puts first.
nonEmptyStrings : List (Char, String)
nonEmptyStrings =
  [ ('h', "ello"), ('h', "\233llo"), ('\955', "x.x"), ('\8364', " 5"), ('\128512', "!")
  , ('a', "bc def"), ('Z', "") ]

||| A string of the NonEmpty pool, as its first character and the rest.
nonEmptyString : Gen (Char, String)
nonEmptyString = oneOf ('a', "") nonEmptyStrings

stringLiteral : Domain before -> Gen String
stringLiteral NonEmpty = (\(c, rest) => strCons c rest) <$> nonEmptyString
stringLiteral _ = oneOf "" (map (\(c, rest) => strCons c rest) (('a', "") :: nonEmptyStrings))

||| A literal of a type in a domain, from the type's pool for that domain;
||| `drawn` holds what the arguments before offer to index into.
literal : Drawn before -> (t : Ty) -> Domain before -> Gen (Expr t)
literal drawn (TIntegral i) d = IntLit i <$> integerLiteral drawn i d
literal _ TDouble d = uncurry DoubleLit <$> doubleLiteral d
literal _ TChar _ = CharLit <$> charLiteral
literal _ TString d = StringLit <$> stringLiteral d

||| A code point a value of an integer type holds: scalar values across
||| UTF-8's lengths and at the edges of the surrogates and of Unicode, and
||| values that are no scalar (a negative one, a surrogate, one past
||| U+10FFFF), which cast to 0. Every integer type holds 65 and 0.
codePoint : (i : IntTy) -> Gen (Expr (TIntegral i))
codePoint i =
  IntLit i <$> oneOf 65 (filter holds [233, 955, 8364, 128512, 0, 55295, 57344, 1114111, -1, 55296, 57343, 1114112])
  where
    holds : Integer -> Bool
    holds v = case i of
      Fixed f => let (lo, hi) = bounds f in lo <= v && v <= hi
      Big => True

||| The pool of a cast's operand, for the casts that read few values
||| meaningfully: to Char, a code point (almost every other integer is no
||| scalar and casts to 0); from String, a number's text (almost every
||| other string reads as 0).
castPool : Op -> (from : Ty) -> (to : Ty) -> Maybe (Gen (Expr from))
castPool Convert (TIntegral i) TChar = Just (codePoint i)
castPool Convert TString (TIntegral _) =
  Just (StringLit <$> oneOf "0" ["42", "-17", "9223372036854775807", "123456"])
castPool Convert TString TDouble = Just (StringLit <$> oneOf "0.5" ["-2.25", "1e10", "3.0", "0.1"])
castPool _ _ _ = Nothing

||| Where an argument comes from.
data Origin : Ty -> Type where
  Pool : Gen (Expr t) -> Origin t
  Expression : Origin t

||| Where an argument of type `t` of `p` comes from: a literal of its
||| domain, when that says more than the type; a literal of the cast's pool,
||| for a cast that has one; at run time, a literal for a string that `p`
||| takes apart, since there a string is only what output fusion writes;
||| otherwise any expression of its type.
origin : Part -> Prim -> Drawn before -> (t : Ty) -> Domain before -> Origin t
origin part p drawn t Anything =
  case castPool p.op t p.result of
    Just pool => Pool pool
    Nothing => case part of
      Runtime => if t == TString && not (writes p) then Pool (literal drawn t Anything) else Expression
      Static => Expression
origin _ _ drawn t d = Pool (literal drawn t d)

||| A parameter as `arguments` draws it: the NonEmpty string, whose
||| scalars the parameters after it may index, or any other, which offers
||| them nothing.
data Drawing : (t : Ty) -> Domain before -> Type where
  Indexable : Drawing TString NonEmpty
  Plain : (0 _ : offers t d = Opaque) -> Drawing t d

drawing : (t : Ty) -> (d : Domain before) -> Drawing t d
drawing TString NonEmpty = Indexable
drawing (TIntegral _) NonEmpty = Plain Refl
drawing TDouble NonEmpty = Plain Refl
drawing TChar NonEmpty = Plain Refl
drawing _ Anything = Plain Refl
drawing _ NonZero = Plain Refl
drawing _ Finite = Plain Refl
drawing _ SmallShift = Plain Refl
drawing _ (IndexInto _) = Plain Refl

------------------------------------------------------------------------------
-- Cases
------------------------------------------------------------------------------

||| A leaf: a literal of the type's own pool.
leaf : (t : Ty) -> Gen (Expr t)
leaf t = literal None t Anything

mutual
  ||| An expression of type `t` at most `depth` deep: above the bottom, a
  ||| leaf one node in five, else a production of `t`.
  expr : Part -> Vect 9 Nat -> (t : Ty) -> (depth : Nat) -> Gen (Expr t)
  expr _ _ t Z = leaf t
  expr part kept t (S d) = do
    i <- weighted (MkWeights [1, 4])
    case i.fst of
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
        let (pr ** same) = index i.fst options
        build part kept pr same d

  build : Part -> Vect 9 Nat -> (pr : Production) -> (0 _ : resultOf pr = t) -> Nat -> Gen (Expr t)
  build part kept (Apply p) Refl d = App p <$> arguments part kept p d None p.args
  build part kept SDataOf Refl d =
    [| SData ((\i => IntLit (Fixed FInt) (natToInteger (finToNat i))) <$> draw 3)
             (expr part kept int d) (expr part kept TDouble d) |]

  ||| A primitive's arguments, left to right; `drawn` holds what the
  ||| arguments before offer to index into.
  arguments : Part -> Vect 9 Nat -> Prim -> Nat -> Drawn before -> (ps : Params before) -> Gen (Args ps)
  arguments _ _ _ _ _ Done = pure []
  arguments part kept p d drawn (Param t dom rest) with (drawing t dom)
    arguments part kept p d drawn (Param TString NonEmpty rest) | Indexable = do
      (c, more) <- nonEmptyString
      args <- arguments part kept p d (Room (length more) drawn) rest
      pure (StringLit (strCons c more) :: args)
    arguments part kept p d drawn (Param t dom rest) | Plain opaque = do
      e <- case origin part p drawn t dom of
             Pool pool => pool
             Expression => expr part kept t d
      args <- arguments part kept p d (rewrite opaque in Past drawn) rest
      pure (e :: args)

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
caseTy Runtime = oneOf TDouble (map (TIntegral . Fixed) fixedTys ++ [TChar, TString])
caseTy Static = oneOf integer [TString, int, TDouble]

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
      widest = foldr (\p, a => max (arity p.args) a) 3 prims  -- 3: the helper's
      nodes = sum [ power widest level | level <- [0 .. depthBound] ]
  in 1 + length coins + 1 + 1 + 3 * nodes

------------------------------------------------------------------------------
-- Writing a case
------------------------------------------------------------------------------

||| A leaf as the renderings see it: its type and the literal.
record Leaf where
  constructor MkLeaf
  ty : Ty
  lit : Expr ty

||| How a line of stdin, `x`, is read as a value of a type.
reader : Ty -> String -> String
reader TChar x = "(prim__strHead " ++ x ++ ")"
reader TString x = x
reader t x = "(" ++ castNamed TString t ++ " " ++ x ++ ")"

||| How a case's leaves are written: as the literals (`d`), behind
||| `hide<T> 1` (`r`), as the parameters of the case's function (`j`), or
||| read from stdin (`s`).
data Mode = Direct | Hidden | Parameter | Read

written : Mode -> Leaf -> Nat -> String
written Direct l _ = source l.lit
written Hidden l _ = "(hide" ++ tyName l.ty ++ " 1 " ++ source l.lit ++ ")"
written Parameter _ k = "x" ++ show k
written Read l k = reader l.ty ("x" ++ show k)

mutual
  ||| An expression's text, its leaves numbered on from those already met,
  ||| which it adds to: one walk numbers the leaves of every rendering.
  render : Mode -> Expr t -> SnocList Leaf -> (String, SnocList Leaf)
  render m e@(IntLit i _) ls = leafIn m (MkLeaf (TIntegral i) e) ls
  render m e@(DoubleLit _ _) ls = leafIn m (MkLeaf TDouble e) ls
  render m e@(CharLit _) ls = leafIn m (MkLeaf TChar e) ls
  render m e@(StringLit _) ls = leafIn m (MkLeaf TString e) ls
  render m (App p as) ls = let (texts, ls') = renderArgs m as ls in (applied p.name texts, ls')
  render m (SData k i x) ls =
    let (a, l1) = render m k ls
        (b, l2) = render m i l1
        (c, l3) = render m x l2
    in (applied "sdata" [a, b, c], l3)

  renderArgs : Mode -> Args ps -> SnocList Leaf -> (List String, SnocList Leaf)
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

line : String -> Ty -> String -> String
line label t e = "  " ++ printLine label t e

------------------------------------------------------------------------------
-- The integers' documented meaning
------------------------------------------------------------------------------

inRange : IntTy -> Integer -> Integer
inRange (Fixed f) v = wrap (width f) v
inRange Big v = v

divide : IntTy -> Integer -> Integer -> Integer
divide (Fixed f) a b = quotient (width f) a b
divide Big a b = fst (euclid a b)

modulus : IntTy -> Integer -> Integer -> Integer
modulus (Fixed f) a b = remainder (width f) a b
modulus Big a b = snd (euclid a b)

bitwiseIn : IntTy -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bitwiseIn (Fixed f) = bitwise (width f)
bitwiseIn Big = bigBitwise

shiftIn : IntTy -> (left : Bool) -> Integer -> Integer -> Integer
shiftIn (Fixed f) = shifted (width f)
shiftIn Big = bigShifted

||| What the other operations of two integers mean at an integer type, by
||| operation: the arithmetic and bitwise ones, the shifts, the
||| comparisons.
twoIntegers : SortedMap Op (IntTy -> Integer -> Integer -> Integer)
twoIntegers = fromList $
  map (\(op, f) => (op, \r, a, b => inRange r (f a b))) arithmetic
  ++ map (\(op, f) => (op, \r => bitwiseIn r f)) logical
  ++ map (\(op, left) => (op, \r => shiftIn r left)) shifts
  ++ map (\(op, f) => (op, \_, a, b => if f a b then 1 else 0)) comparisons

||| What a primitive gives on integer values, as the runtime documents it;
||| Nothing for a primitive the model leaves out, every one whose result
||| or operands are not integers.
meaning : Prim -> List Integer -> Maybe Integer
meaning p vs = case p.result of
  TIntegral r => case (p.op, vs) of
    (Neg, [a]) => Just (inRange r (negate a))
    (Div, [a, b]) => Just (divide r a b)
    (Mod, [a, b]) => Just (modulus r a b)
    (Convert, [a]) => Just (inRange r a)
    (op, [a, b]) => (\f => f r a b) <$> lookup op twoIntegers
    _ => Nothing
  _ => Nothing

mutual
  ||| The value of an expression over the integers alone.
  modelled : Expr t -> Maybe Integer
  modelled (IntLit _ v) = Just v
  modelled (App p as) = modelledArgs as >>= meaning p
  modelled (DoubleLit _ _) = Nothing
  modelled (CharLit _) = Nothing
  modelled (StringLit _) = Nothing
  modelled (SData _ _ _) = Nothing

  modelledArgs : Args ps -> Maybe (List Integer)
  modelledArgs [] = Just []
  modelledArgs (e :: es) = [| modelled e :: modelledArgs es |]

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| The label of case `n`'s line of a rendering: the rendering's letter and
||| the case's number.
label : Mode -> Nat -> String
label Direct n = "d" ++ show n
label Hidden n = "r" ++ show n
label Parameter n = "j" ++ show n
label Read n = "s" ++ show n

||| Where a program prints a case's renderings: the direct one in `main`,
||| unless the case's value is the host's, which the folders would compute
||| where the program is compiled; the function's, and at run time the
||| hidden one, before the case's stdin is read; stdin's after.
record Shown where
  constructor MkShown
  inMain : List Mode
  beforeInput : List Mode
  afterInput : List Mode

shown : Part -> Case -> Shown
shown part (MkCase _ e) =
  MkShown (if onHost e then [] else [Direct])
          (Parameter :: case part of Runtime => [Hidden]; Static => [])
          [Read]

||| The renderings a program prints of a case.
renderings : Part -> Case -> List Mode
renderings part c = let s = shown part c in s.inMain ++ s.beforeInput ++ s.afterInput

||| A case written into the places of a program.
record Written where
  constructor MkWritten
  function : List String
  direct : List String
  runner : List String
  inputs : List String
  hides : List Ty

||| Case `n` of a part, written.
write : Part -> Nat -> Case -> Written
write part n c@(MkCase t e) =
  let ls = leaves e
      numbered = zip [0 .. length ls] ls
      name = "c" ++ show n
      xs = foldr (\(k, _), rest => " x" ++ show k ++ rest) "" numbered
      fn = [ name ++ " : List () -> " ++ foldr (\l, rest => tyName l.ty ++ " -> " ++ rest) (tyName t) ls
           , name ++ " []" ++ xs ++ " = " ++ text Parameter e
           , name ++ " (_ :: k)" ++ xs ++ " = " ++ name ++ " k" ++ xs
           , "" ]
      call = "(" ++ name ++ " [()]" ++ foldr (\l, rest => " " ++ source l.lit ++ rest) ")" ls
      statement : Mode -> String
      statement Parameter = line (label Parameter n) t call
      statement m = line (label m n) t (text m e)
      places = shown part c
      -- Only what exists at run time is hidden behind hide<T>, whose
      -- barriers then need the leaves' types.
      hides = the (List Ty) $ case part of
                Runtime => map (.ty) ls
                Static => []
      runner = [ "run" ++ show n ++ " : IO ()"
               , "run" ++ show n ++ " = do" ]
               ++ map statement places.beforeInput
               ++ map (\(k, _) => "  x" ++ show k ++ " <- getLine") numbered
               ++ map statement places.afterInput ++ [""]
  in MkWritten fn (map statement places.inMain) runner (map (\l => input l.lit) ls) hides

||| The helpers every program has: hide<T> for every type, and the small sum
||| type.
helpers : List String
helpers = ((map (TIntegral . Fixed) fixedTys ++ [TDouble, TChar, TString, integer]) >>= helper) ++
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
  let (a, b) = twoOf t in
  [line "b" t (text Hidden a), line "b" t (text Hidden b)]
  where
    twoOf : (u : Ty) -> (Expr u, Expr u)
    twoOf (TIntegral i) = (IntLit i 0, IntLit i 1)
    twoOf TDouble = (DoubleLit NonNegative "0.0", DoubleLit NonNegative "1.0")
    twoOf TChar = (CharLit 'a', CharLit 'Z')
    twoOf TString = (StringLit "", StringLit "a")

||| The files of a program.
data File = MainFile | StdinFile

||| A program's file, of its cases, for the request written in its header.
programText : String -> Part -> File -> List Case -> String
programText request part file cases =
  let numbered = zip [the Nat 1 .. length cases] cases
      ws = map (\(n, c) => write part n c) numbered
  in case file of
       StdinFile => unlines (ws >>= (.inputs))
       MainFile => unlines $
         [ "module Main", ""
         , "-- Generated by harness/Fuzz.idr: runtests --fuzz-program " ++ request, ""
         , "import Prelude", ""
         , "%default partial", "" ]
         ++ helpers ++ (ws >>= (.function)) ++ (ws >>= (.runner)) ++
         [ "main : IO ()", "main = do" ]
         ++ (ws >>= (.direct))
         ++ map (\(n, _) => "  run" ++ show n) numbered
         ++ (nub (ws >>= (.hides)) >>= barrier)

||| The cases of a program: case n on output n of splitmix64 from the seed,
||| all on one tape, each with whether its tape overran.
cases : Bits64 -> Nat -> Part -> List (Case, Bool)
cases seed n part = seededEach caseCapacity (map (caseSeed seed) [1 .. n]) (genCase part)

||| A seed's thread count: one of 1, 3, 5 and 13, each as likely, on the
||| seed's output 0, which no case is drawn on. The compiler's output must
||| not depend on it, and these are the counts its determinism is held to.
threads : Bits64 -> Nat
threads seed =
  index (seeded 1 (caseSeed seed 0) (weighted (MkWeights [1, 1, 1, 1]))).value.fst [1, 3, 5, 13]

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
parseFile _ = Nothing

||| A seed: any integer, taken modulo 2^64.
parseSeed : String -> Maybe Bits64
parseSeed s = cast {to = Bits64} <$> parseInteger {a = Integer} s

||| A program's number of cases: at least one, so `main` has a statement.
parseCases : String -> Maybe Nat
parseCases s = case parsePositive {a = Nat} s of
  Just (S k) => Just (S k)
  _ => Nothing

------------------------------------------------------------------------------
-- The check
------------------------------------------------------------------------------

||| The cases a request names, each with whether its tape overran, and the
||| request's name in what the check prints: a program's (`program <seed>
||| <cases> <part>`, named by its seed) or a tape's one (`replay <tape>
||| <part>`, named by its tape).
casesOf : List String -> Maybe (String, Part, List (Case, Bool))
casesOf ["program", seed, n, part] = do
  s <- parseSeed seed
  k <- parseCases n
  p <- parsePart part
  pure (seed, p, cases s k p)
casesOf ["replay", tape, part] = do
  t <- parseTape tape
  p <- parsePart part
  let d = replay t (genCase p)
  pure (tape, p, [(d.value, d.overran)])
casesOf _ = Nothing

||| What a program's output says of its cases.
record Verdict where
  constructor MkVerdict
  ||| Each case whose lines print two values, at its first line that
  ||| differs from its first.
  agree : List String
  ||| Each case the model covers that prints another value, at its first
  ||| such line, then each that prints nothing.
  model : List String
  ||| The first case that fails, and how: a disagreement first.
  first : Maybe String

||| What a scan of the output has met: each case's first line, how many
||| times each label was printed, the cases found to disagree and to miss
||| their model, and what was said of each.
record Scan where
  constructor MkScan
  firsts : SortedMap Nat (String, String)
  printed : SortedMap String Nat
  disagreed : SortedSet Nat
  missed : SortedSet Nat
  agreeing : SnocList String
  modelling : SnocList String

||| The verdict on the output of a request's cases: its lines read back by
||| their labels, each held to its case's first line and to its case's
||| model, and each of a case's renderings printed exactly once, so that an
||| output missing a line, or saying one twice, cannot agree by saying
||| less.
checked : (name : String) -> Part -> List Case -> (output : String) -> Verdict
checked name part cs output =
  let numbered = zip [the Nat 1 .. length cs] cs
      expected = numbered >>= \(n, c) => map (\m => (label m n, n)) (renderings part c)
      byLabel = SortedMap.fromList expected
      models = SortedMap.fromList (mapMaybe (\(n, c) => (\v => (n, show v)) <$> modelled c.body) numbered)
      scanned = foldl (step byLabel models) (MkScan empty empty empty empty [<] [<]) (lines output)
      miscounted = mapMaybe (\(l, n) => case fromMaybe 0 (lookup l scanned.printed) of
                                          1 => Nothing
                                          k => Just (n, l, k)) expected
      disagreed = foldr (\(n, _, _) => insert n) scanned.disagreed miscounted
      miscounts = map (\(n, l, k) => name ++ ": case " ++ show n ++ ": " ++ l ++ " printed " ++ show k ++ " times, not once") miscounted
      silent = mapMaybe (unprintedModel models scanned.firsts) numbered
      missed = foldr (\(n, _) => insert n) scanned.missed silent
      unprinted = map (\(n, m) => name ++ ": case " ++ show n ++ ": m" ++ show n ++ " " ++ m ++ ", but no line") silent
      failed = mapMaybe (howFails disagreed missed) numbered
  in MkVerdict ((scanned.agreeing <>> []) ++ miscounts) ((scanned.modelling <>> []) ++ unprinted)
               (map (\(n, how) => show n ++ " " ++ how) (head' failed))
  where
    said : Nat -> String -> String -> String
    said n what l = name ++ ": case " ++ show n ++ ": " ++ what ++ ", but " ++ l
    step : SortedMap String Nat -> SortedMap Nat String -> Scan -> String -> Scan
    step byLabel models scan l =
      let (lbl, value) = labelled l in
      case lookup lbl byLabel of
        Nothing => scan
        Just n =>
          let counted = { printed $= insert lbl (1 + fromMaybe 0 (lookup lbl scan.printed)) } scan
              afterFirst = case lookup n counted.firsts of
                Nothing => { firsts $= insert n (lbl, value) } counted
                Just (l1, v1) =>
                  if value /= v1 && not (contains n counted.disagreed)
                     then { disagreed $= insert n, agreeing $= (:< said n (l1 ++ " " ++ v1) l) } counted
                     else counted
          in case lookup n models of
               Just m =>
                 if value /= m && not (contains n afterFirst.missed)
                    then { missed $= insert n, modelling $= (:< said n ("m" ++ show n ++ " " ++ m) l) } afterFirst
                    else afterFirst
               Nothing => afterFirst
    unprintedModel : SortedMap Nat String -> SortedMap Nat (String, String) -> (Nat, Case) -> Maybe (Nat, String)
    unprintedModel models firsts (n, _) = case (lookup n models, lookup n firsts) of
      (Just m, Nothing) => Just (n, m)
      _ => Nothing
    howFails : SortedSet Nat -> SortedSet Nat -> (Nat, Case) -> Maybe (Nat, String)
    howFails disagreed missed (n, _) =
      if contains n disagreed then Just (n, "agree")
      else if contains n missed then Just (n, "model") else Nothing

data Check = Agree | Model | First | Modelled

parseCheck : String -> Maybe Check
parseCheck "agree" = Just Agree
parseCheck "model" = Just Model
parseCheck "first" = Just First
parseCheck "modelled" = Just Modelled
parseCheck _ = Nothing

||| `runtests --fuzz-check overran <request>`: the first case of the
||| request whose tape ran out, a valid case but not the one its seed drew,
||| as `<name>: overran: case <n>`, or nothing.
export covering
overranOf : List String -> Maybe String
overranOf request = do
  (name, _, cs) <- casesOf request
  pure $ case find (\(_, (_, overran)) => overran) (zip [the Nat 1 .. length cs] cs) of
    Just (n, _) => name ++ ": overran: case " ++ show n ++ "\n"
    Nothing => ""

||| `runtests --fuzz-check agree|model|first|modelled <request>
||| <stdout-file>`, of the file's text: the cases whose lines disagree, the
||| cases that miss their model, or the first case that fails and how
||| (`<n> agree` or `<n> model`), a line each; or how many of the cases
||| have a model, which the model's check needs one of to check anything.
export covering
checkOf : (how : String) -> List String -> (output : String) -> Maybe String
checkOf how request output = do
  check <- parseCheck how
  (name, part, cs) <- casesOf request
  let verdict = checked name part (map fst cs) output
  pure $ case check of
    Agree => unlines verdict.agree
    Model => unlines verdict.model
    First => maybe "" (++ "\n") verdict.first
    Modelled => show (length (mapMaybe (\(c, _) => modelled c.body) cs)) ++ "\n"

||| The check's own checks, on the cases of seed 1's program of three cases
||| at run time, each of whose lines prints the case's model, or one value
||| of its own: such an output names no case, and with one more line of
||| case 2 that prints another value, it names case 2 as the first failing.
export covering
checkerChecks : List (String, Bool)
checkerChecks =
  let cs = map fst (cases 1 3 Runtime)
      numbered = zip [the Nat 1 .. length cs] cs
      agreeing = unlines (numbered >>= \(n, c) =>
                   map (\m => label m n ++ " " ++ maybe ("v" ++ show n) show (modelled c.body)) (renderings Runtime c))
      ok = checked "1" Runtime cs agreeing
      bad = checked "1" Runtime cs (agreeing ++ label Read 2 ++ " x\n")
      before3 = sum (map (\c => length (renderings Runtime c)) (take 2 cs))
      dropped = lines agreeing
      short = checked "1" Runtime cs (unlines (take before3 dropped ++ drop (S before3) dropped))
      silent = checked "1" Runtime cs "" in
  [ ("an agreeing output names no case", null ok.agree && null ok.model && isNothing ok.first)
  , ("an output with one disagreeing line names that case",
     not (null bad.agree) && all (isPrefixOf "1: case 2: ") bad.agree && bad.first == Just "2 agree")
  , ("an output missing one line of a case names that case",
     map (\l => isPrefixOf "1: case 3: " l && isInfixOf " printed 0 times" l) short.agree == [True]
       && short.first == Just "3 agree")
  , ("an empty output names every case", length silent.agree >= 3 && silent.first == Just "1 agree") ]

------------------------------------------------------------------------------
-- The text both hosts print
------------------------------------------------------------------------------

||| A list of checks, each a line `<owner>: <name>: ok` or `failed`.
checkLines : String -> List (String, Bool) -> List String
checkLines owner = map (\(name, holds) => owner ++ ": " ++ name ++ ": " ++ (if holds then "ok" else "failed"))

||| The texts of a list's elements, one after another.
joinedBy : List a -> (a -> String) -> String
joinedBy xs f = foldr (\x, rest => f x ++ rest) "" xs

||| The text both hosts must print alike: the generators' checks, then what
||| the generators make of a few requests, each after a line `== <request>`.
export covering
twoHosts : String
twoHosts =
  let tape = tapeOf 1 2 Runtime in
  unlines (checkLines "gen" Gen.checks ++ checkLines "sem" Sem.checks
           ++ checkLines "two-levels" TwoLevels.checks ++ checkLines "fuzz-check" Fuzz.checkerChecks
           ++ checkLines "two-levels-check" TwoLevels.checkerChecks)
  ++ (the (List (String, String))
       [ ("program 1 3 runtime main", programText "program 1 3 runtime main" Runtime MainFile (map fst (cases 1 3 Runtime)))
       , ("program 1 3 runtime stdin", programText "program 1 3 runtime stdin" Runtime StdinFile (map fst (cases 1 3 Runtime)))
       , ("program 1 3 static main", programText "program 1 3 static main" Static MainFile (map fst (cases 1 3 Static)))
       , ("threads 1", show (threads 1) ++ "\n")
       , ("tape 1 2 runtime", tapeText tape ++ "\n")
       , ("shrink " ++ tapeText tape, unlines (map (tapeText . fst) (candidates tape)))
       , ("sem prim-int-add", fromMaybe "no program\n" (Sem.programOf "prim-int-add"))
       , ("two-levels primitives terms", fromMaybe "no program\n" (TwoLevels.programOf ["primitives", "terms"]))
       , ("two-levels prelude main", fromMaybe "no program\n" (TwoLevels.programOf ["prelude", "main"]))
       ] `joinedBy` \(title, body) => "== " ++ title ++ "\n" ++ body)

||| `runtests --fuzz-program ...`: the forms the module's header lists.
export covering
programOf : List String -> Maybe String
programOf request@["program", seed, n, part, file] = do
  s <- parseSeed seed
  k <- parseCases n
  p <- parsePart part
  f <- parseFile file
  pure (programText (unwords request) p f (map fst (cases s k p)))
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
  pure (programText (unwords request) p f [(replay t (genCase p)).value])
programOf ["shrink", tape] = (\t => unlines (map (tapeText . fst) (candidates t))) <$> parseTape tape
programOf ["two-hosts"] = Just twoHosts
programOf _ = Nothing
