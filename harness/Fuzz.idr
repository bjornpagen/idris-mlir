-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fuzzer: programs of closed expressions over every builtin, each
||| written four ways, whose values must agree with each other and, over
||| the integers, with what the builtins mean, and whose run must end as the
||| oracle says: returned, or crashed at the first case that reaches a
||| guard that fails, by its cause (`fuzz`, FuzzRun.idr).
|||
|||     runtests --fuzz-program program <seed> <cases> runtime|static main|stdin
|||     runtests --fuzz-program threads <seed>
|||     runtests --fuzz-program tape <seed> <case> runtime|static
|||     runtests --fuzz-program replay <tape> runtime|static main|stdin
|||     runtests --fuzz-program shrink <tape>
|||     runtests --fuzz-program two-hosts
|||
||| and checks a run of one: a check's request is `program <seed> <cases>
||| runtime|static` or `replay <tape> runtime|static`, and the status is
||| how the run ended as the shell saw it, `code <n>` or `signal <name>`.
|||
||| A case is one expression, well typed by construction, which Gen draws on
||| the case's own seed (output n of splitmix64 from the program's seed), so
||| a case is reproducible alone, from its seed or from its tape. An
||| argument a builtin's guard reads is a literal, drawn inside the guard
||| far more often than outside it, as the specification states the guard,
||| so most programs run to their end and some crash. A case that runs is
||| written four ways:
|||
||| - `d<n>`, in `main`, directly: its leaves are literals, which the
|||   builtins are applied to as written, so the folders compute it (Idris
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
||| Its lines must print one value, and a case over the integers alone the
||| value their documented meaning gives. A case with a builtin the
||| compiler never folds (a C library's function, whose last digits are the
||| platform's) has no `d` line. A case that crashes is written its lead
||| way alone, drawn on its tape, since the crash ends the program there:
||| so the crash is met by the folder, a call at run time, a value hidden
||| from the compiler or one read from stdin. The check regenerates a
||| request's cases and reads the program's output by their labels, so
||| what the generator knows of a case is never written into the program
||| for a reader to parse back.
|||
||| The `runtime` part holds what may exist at run time: no Integer. The
||| `static` part holds Integer too.
module Fuzz

import Prelude
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect
import Decidable.Equality
import Facts
import Gen
import Prims
import Sem

import IdrisMLIR.Spec.Core.Op
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Runtime.Endings

-- The op vocabulary is imported for a guard and its kind; its Sized, a
-- region's count of blocks, is not an integer type of a width.
%hide IdrisMLIR.Spec.Core.Op.Sized
-- The numeric ops' module is imported for the signedness a width carries;
-- its Part, a division's quotient or remainder, is not a program's part.
%hide IdrisMLIR.Spec.Ops.Numeric.Part

%default total

------------------------------------------------------------------------------
-- What a case may hold
------------------------------------------------------------------------------

||| A program's part: what may exist at run time, or what may exist at
||| compile time too.
data Part = Runtime | Static

||| How many families the table has, the swarm's options.
FamilyCount : Nat
FamilyCount = S (length families.tail)

||| What an expression of a type is, past a leaf: a builtin applied, of the
||| family the swarm weighs it by, with its guards; or the sum type's
||| helper.
data Production = Apply (Fin FamilyCount) Builtin (List (Guard Nat)) | SDataOf

resultOf : Production -> Ty
resultOf (Apply _ b _) = b.gives
resultOf SDataOf = Prims.tInt

||| Whether a part holds a production. At run time no Integer exists.
has : Part -> Production -> Bool
has Static _ = True
has Runtime SDataOf = True
has Runtime (Apply _ b _) = all (/= Prims.tInteger) b.takes && b.gives /= Prims.tInteger

||| Each element of a list with its place in it.
indexed : (xs : List a) -> List (Fin (length xs), a)
indexed [] = []
indexed (x :: xs) = (FZ, x) :: map (\(i, y) => (FS i, y)) (indexed xs)

||| Every builtin, as a production of its family, with its guards.
applications : List Production
applications =
  [ Apply i b (guardings b.op) | (i, family) <- (FZ, families.head) :: map (\(i, f) => (FS i, f)) (indexed families.tail)
                               , b <- family ]

||| The productions of a type in a part, each with the proof of its type.
productions : Part -> (t : Ty) -> List (pr : Production ** resultOf pr = t)
productions part t =
  mapMaybe (\pr => (\same => (pr ** same)) <$> sameTy (resultOf pr) t)
           (filter (has part) (SDataOf :: applications))

||| The families, each as likely. A case's swarm zeroes each with
||| probability one half, so a case is built of a few ops of the dialect,
||| and the interactions among them, rather than a thin mix of all.
familyWeights : Weights FamilyCount
familyWeights = MkWeights (1 :: replicate (length families.tail) 1)

||| A production's weight in a case: its family's after the swarm, so every
||| builtin of a kept family is as likely as each other, and the helper as
||| likely as one of them.
weightIn : Vect FamilyCount Nat -> Production -> Nat
weightIn kept (Apply i _ _) = index i kept
weightIn _ SDataOf = 1

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| Whether a draw of an integer may give 0.
data Zero = WithZero | WithoutZero

||| Any value from `lo` to `hi`, each as likely; without 0 when asked, the
||| range then being `lo` to -1 followed by 1 to `hi` (every fixed width's
||| range holds 0).
anyIn : (lo, hi : Integer) -> Zero -> Gen Integer
anyIn lo hi WithoutZero =
  (\i => let v = lo + natToInteger (finToNat i) in if v >= 0 then v + 1 else v)
    <$> draw (S (integerToNat (hi - lo - 1)))
anyIn lo hi WithZero = (\i => lo + natToInteger (finToNat i)) <$> draw (S (integerToNat (hi - lo)))

||| A value of a fixed width: any of its values, twice as likely as each of
||| its edges and small values; not 0 when asked. An unsigned width's
||| least value is 0, which the set holds once.
fixedLiteral : FixedTy -> Zero -> Gen Integer
fixedLiteral f z =
  let (lo, hi) = bounds f
      (near, far) = the (Integer, Integer) $ case (width f).signedness of
        Signed => (-1, -100)
        Unsigned => (2, 100)
      small = nub [lo, hi, 0, 1, near, 7, far]
      vs = Vect.fromList (case z of WithoutZero => filter (/= 0) small; WithZero => small)
  in do i <- weighted (MkWeights (2 :: map (const 1) vs))
        case i.fst of
          FZ => anyIn lo hi z
          FS j => pure (index j vs)

||| Integer's values: small ones, the edges of the fixed widths and past
||| them, and values past any word; with 0 unless asked not.
bigLiteral : Zero -> Gen Integer
bigLiteral z =
  let nonzero = [ -1, 12345678901234567890, -98765432109876543210, 9223372036854775807
                , 9223372036854775808, 18446744073709551616, 340282366920938463463374607431768211456
                , -9223372036854775809, 42 ]
  in case z of
       WithoutZero => oneOf 1 nonzero
       WithZero => oneOf 0 (1 :: nonzero)

||| A value of an integer type.
integerLiteral : IntTy -> Zero -> Gen Integer
integerLiteral (Sized f) z = fixedLiteral f z
integerLiteral Big z = bigLiteral z

||| Finite Doubles, edges among them.
doubleLiteral : Gen (Sign, Magnitude)
doubleLiteral =
  oneOf (NonNegative, Written "0.0")
    [ (NonNegative, Written "1.0"), (NonNegative, Written "0.1"), (NonNegative, Written "0.5")
    , (NonNegative, Written "2.5"), (NonNegative, Written "3.0"), (NonNegative, Written "100.0")
    , (NonNegative, Written "1.0e10"), (NonNegative, Written "1.0e-10"), (NonNegative, Written "123456.789")
    , (NonNegative, Written "1.7976931348623157e308"), (NonNegative, Written "2.2250738585072014e-308")
    , (NonNegative, Written "4.9e-324"), (NonNegative, Written "1.0e-320"), (Negative, Written "0.1")
    , (Negative, Written "2.5"), (Negative, Written "1.0e300"), (NonNegative, Written "6.02214076e23")
    , (NonNegative, Written "0.3"), (Negative, Written "7.0") ]

||| Finite Doubles a cast to an integer type takes as a small value.
smallDouble : Gen (Sign, Magnitude)
smallDouble =
  oneOf (NonNegative, Written "0.0")
    [ (NonNegative, Written "1.5"), (Negative, Written "2.75"), (NonNegative, Written "1000.25")
    , (Negative, Written "1.0e6"), (NonNegative, Written "0.999"), (NonNegative, Written "12345.5") ]

charLiteral : Gen Char
charLiteral = oneOf 'a' ['Z', '0', ' ', '\233', '\955', '\8364', '\128512', '~']

||| Strings with non-ASCII characters, each as its first character and the
||| rest; `"a"` aside, which a pool puts first.
nonEmptyStrings : List (Char, String)
nonEmptyStrings =
  [ ('h', "ello"), ('h', "\233llo"), ('\955', "x.x"), ('\8364', " 5"), ('\128512', "!")
  , ('a', "bc def"), ('Z', "") ]

nonEmptyString : Gen String
nonEmptyString = (\(c, rest) => strCons c rest) <$> oneOf ('a', "") nonEmptyStrings

stringLiteral : Gen String
stringLiteral = oneOf "" (map (\(c, rest) => strCons c rest) (('a', "") :: nonEmptyStrings))

||| A literal of a type's own pool.
literalOf : (t : Ty) -> Gen (Literal t)
literalOf (TIntegral i) = IntLit i <$> integerLiteral i WithZero
literalOf TDouble = uncurry DoubleLit <$> doubleLiteral
literalOf TChar = CharLit <$> charLiteral
literalOf TString = StringLit <$> stringLiteral

||| Which side of its guard a guarded argument is drawn on: inside, so the
||| program runs on, thirty-one times as often as outside, where it
||| crashes. A program reaches a few dozen guards, so most run to their
||| end and some crash.
data Side = Inside | Outside

side : Gen Side
side = (\i => case i.fst of FZ => Inside; FS _ => Outside) <$> weighted (MkWeights [31, 1])

||| An index on a side of the bounds of a string of `room` scalars: inside
||| one of its scalars; outside one before it, at its end or past it. An
||| empty string has no inside.
indexOn : Side -> (room : Nat) -> Gen Integer
indexOn Inside (S k) = (\i => natToInteger (finToNat i)) <$> draw (S k)
indexOn _ room = oneOf (-1) [natToInteger room, natToInteger room + 7, -100]

||| A literal for the argument a guard guards, on a side of it: what its
||| kind's condition lets through, or what it stops, given the literals
||| drawn for the guard's other arguments, one per other operand of the
||| kind's op; nothing where no draw of the argument's type is written for
||| the kind (a range's offset, a handle, which no literal is), and the
||| argument comes from its pool.
guardedLiteral : (kind : GuardKind) -> Side -> (t : Ty) -> Vect (guardOthers kind) (Maybe AnyLit)
              -> Maybe (Gen (Literal t))
guardedLiteral NonZero Inside (TIntegral i) [] = Just (IntLit i <$> integerLiteral i WithoutZero)
guardedLiteral NonZero Outside (TIntegral i) [] = Just (pure (IntLit i 0))
guardedLiteral NonEmpty Inside TString [] = Just (StringLit <$> nonEmptyString)
guardedLiteral NonEmpty Outside TString [] = Just (pure (StringLit ""))
guardedLiteral InBounds s (TIntegral i) [Just (MkAnyLit (StringLit str))] =
  Just (IntLit i <$> indexOn s (length (unpack str)))
guardedLiteral Finite Inside TDouble [] = Just (uncurry DoubleLit <$> smallDouble)
guardedLiteral Finite Outside TDouble [] = Just ((\sg => DoubleLit sg PastLargest) <$> oneOf NonNegative [Negative])
guardedLiteral _ _ _ _ = Nothing

------------------------------------------------------------------------------
-- Cases
------------------------------------------------------------------------------

||| A leaf: a literal of the type's own pool.
leaf : (t : Ty) -> Gen (Expr t)
leaf t = Lit <$> literalOf t

||| What a guard does with the argument at a position: guards it, is given
||| it besides, or does neither.
data Role = Guarded (Guard Nat) | GivenTo | Free

roleAt : Nat -> List (Guard Nat) -> Role
roleAt k gs = case find (\g => head g.given == k) gs of
  Just g => Guarded g
  Nothing => if any (\g => elem k (tail g.given)) gs then GivenTo else Free

||| The literal an argument is, if it is one.
asLiteral : Expr t -> Maybe AnyLit
asLiteral (Lit l) = Just (MkAnyLit l)
asLiteral _ = Nothing

mutual
  ||| An expression of type `t` at most `depth` deep: above the bottom, a
  ||| leaf one node in five, else a production of `t`.
  expr : Part -> Vect FamilyCount Nat -> (t : Ty) -> (depth : Nat) -> Gen (Expr t)
  expr _ _ t Z = leaf t
  expr part kept t (S d) = do
    i <- weighted (MkWeights [1, 4])
    case i.fst of
      FZ => leaf t
      FS _ => node part kept t d

  ||| A production of `t`, each as likely as its weight in the case; a leaf
  ||| when the case has none of weight.
  node : Part -> Vect FamilyCount Nat -> (t : Ty) -> Nat -> Gen (Expr t)
  node part kept t d =
    let options = Vect.fromList (productions part t) in
    case weightsOf (map (\(pr ** _) => weightIn kept pr) options) of
      Nothing => leaf t
      Just w => do
        i <- weighted w
        let (pr ** same) = index i.fst options
        build part kept pr same d

  build : Part -> Vect FamilyCount Nat -> (pr : Production) -> (0 _ : resultOf pr = t) -> Nat -> Gen (Expr t)
  build part kept (Apply _ b gs) Refl d = App b <$> arguments part kept gs d 0 [<] b.takes b.sources
  build part kept SDataOf Refl d =
    [| SData ((\i => Lit (IntLit (Sized FInt) (natToInteger (finToNat i)))) <$> draw 3)
             (expr part kept Prims.tInt d) (expr part kept TDouble d) |]

  ||| A builtin's arguments, left to right, from the position `at` on, the
  ||| literals drawn before in `drawn`: an argument a guard guards is a
  ||| literal on a side of it, one a guard is given besides a literal of
  ||| its pool, and any other comes from its source.
  arguments : Part -> Vect FamilyCount Nat -> List (Guard Nat) -> Nat -> (at : Nat)
           -> SnocList (Maybe AnyLit) -> (ts : List Ty) -> Sources ts -> Gen (Args ts)
  arguments _ _ _ _ _ _ [] [] = pure []
  arguments part kept gs d at drawn (t :: ts) (src :: srcs) = do
    e <- argument part kept d (roleAt at gs) (drawn <>> []) t src
    rest <- arguments part kept gs d (S at) (drawn :< asLiteral e) ts srcs
    pure (e :: rest)

  argument : Part -> Vect FamilyCount Nat -> Nat -> Role -> List (Maybe AnyLit) -> (t : Ty) -> Source t
          -> Gen (Expr t)
  argument _ _ _ (Guarded g) drawn t src = do
    s <- side
    let others = map (\k => join (getAt k drawn)) (tail g.given)
    case guardedLiteral g.check s t others of
      Just pool => Lit <$> pool
      Nothing => pooled t src
  argument _ _ _ GivenTo _ t src = pooled t src
  argument _ _ _ Free _ _ (Pooled x xs) = Lit <$> oneOf x xs
  argument part kept d Free _ t AnyOf = expr part kept t d

  ||| A literal of an argument's pool, or of its type's.
  pooled : (t : Ty) -> Source t -> Gen (Expr t)
  pooled _ (Pooled x xs) = Lit <$> oneOf x xs
  pooled t AnyOf = leaf t

||| How a case's leaves are written: as the literals (`d`), behind
||| `hide<T> 1` (`r`), as the parameters of the case's function (`j`), or
||| read from stdin (`s`).
data Mode = Direct | Hidden | Parameter | Read

||| A case: an expression and its type, and the way it is written alone if
||| it crashes.
record Case where
  constructor MkCase
  ty : Ty
  body : Expr ty
  lead : Mode

||| The ways a case's expression may be written in a part: directly where
||| the folders compute it, hidden where values exist at run time.
ways : Part -> Expr t -> List1 Mode
ways part e =
  let late = (case part of Runtime => [Hidden]; Static => []) ++ [Read] in
  case whereComputed e of
    WhileCompiling => Direct ::: Parameter :: late
    WhereItRuns => Parameter ::: late

||| A case's depth is from 1 to this, each as likely. With a leaf one node
||| in five above the bottom, these are the proportions the fuzzer's
||| thirty-case programs compiled within the test's limits with.
depthBound : Nat
depthBound = 4

||| A case's type, each of its part's as likely: no type is favoured.
caseTy : Part -> Gen Ty
caseTy Runtime = oneOf TDouble (map (TIntegral . Sized) fixedTys ++ [TChar, TString])
caseTy Static = oneOf Prims.tInteger [TString, Prims.tInt, TDouble]

||| A case of a part: the families it keeps, its type, its depth, its
||| expression, then its lead.
genCase : Part -> Gen Case
genCase part = do
  MkWeights kept <- swarm familyWeights
  t <- caseTy part
  depth <- draw depthBound
  body <- expr part kept t (S (finToNat depth))
  let ms = ways part body
  lead <- oneOf ms.head ms.tail
  pure (MkCase t body lead)

||| The cells a case's tape needs: the swarm's draws (one weighted, a coin
||| per family), the type's and the depth's; then at most three a node
||| (whether it is a leaf, then its production or its literal, a literal
||| being at most an entry of its pool and a value; a literal a guard reads
||| a side, an entry and a value), over as many nodes as a tree of the
||| deepest depth and the largest arity holds; and the lead's. A derivation
||| that falls short shows as an overran case, which fails the check.
caseCapacity : Nat
caseCapacity =
  let widest = foldr (\b, a => max (length b.takes) a) 3 builtins  -- 3: the helper's
      nodes = sum [ power widest level | level <- [0 .. depthBound] ]
  in 1 + FamilyCount + 1 + 1 + 3 * nodes + 1

------------------------------------------------------------------------------
-- Writing a case
------------------------------------------------------------------------------

||| A leaf as the renderings see it: its type and the literal.
record Leaf where
  constructor MkLeaf
  ty : Ty
  lit : Literal ty

||| A literal as a leaf, its type read off its value.
leafOf : Literal t -> Leaf
leafOf l@(IntLit i _) = MkLeaf (TIntegral i) l
leafOf l@(DoubleLit _ _) = MkLeaf TDouble l
leafOf l@(CharLit _) = MkLeaf TChar l
leafOf l@(StringLit _) = MkLeaf TString l

||| How a line of stdin, `x`, is read as a value of a type.
reader : Ty -> String -> String
reader TChar x = appliedText (spellingText (MkSpelling "strHead" [])) [x]
reader TString x = x
reader t x = appliedText (castNamed TString t) [x]

written : Mode -> Leaf -> Nat -> String
written Direct l _ = literalSource l.lit
written Hidden l _ = "(hide" ++ tyName l.ty ++ " 1 " ++ literalSource l.lit ++ ")"
written Parameter _ k = "x" ++ show k
written Read l k = reader l.ty ("x" ++ show k)

mutual
  ||| An expression's text, its leaves numbered on from those already met,
  ||| which it adds to: one walk numbers the leaves of every rendering.
  render : Mode -> Expr t -> SnocList Leaf -> (String, SnocList Leaf)
  render m (Lit l) ls = let f = leafOf l in (written m f (length ls), ls :< f)
  render m (App b as) ls = let (texts, ls') = renderArgs m as ls in (appliedText (spellingText b.spelling) texts, ls')
  render m (SData k i x) ls =
    let (a, l1) = render m k ls
        (b, l2) = render m i l1
        (c, l3) = render m x l2
    in (appliedText "sdata" [a, b, c], l3)

  renderArgs : Mode -> Args ps -> SnocList Leaf -> (List String, SnocList Leaf)
  renderArgs _ [] ls = ([], ls)
  renderArgs m (e :: es) ls =
    let (a, l1) = render m e ls
        (as, l2) = renderArgs m es l1
    in (a :: as, l2)

text : Mode -> Expr t -> String
text m e = fst (render m e [<])

leaves : Expr t -> List Leaf
leaves e = toList (snd (render Direct e [<]))

line : String -> Ty -> String -> String
line label t e = "  " ++ printLine label t e

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

||| Where a program writes a case's renderings: in `main`, before any case
||| runs; in its own run, before its stdin is read; or after.
record Shown where
  constructor MkShown
  inMain : List Mode
  beforeInput : List Mode
  afterInput : List Mode

||| A case's renderings, by the oracle: a case that runs is written every
||| way its part has (directly where the folders compute it), and one that
||| crashes its lead way alone, which ends the program there.
shown : Part -> Case -> Shown
shown part c = case outcome c.body of
  Crashes _ => alone c.lead
  _ => MkShown (case whereComputed c.body of WhileCompiling => [Direct]; WhereItRuns => [])
               (Parameter :: case part of Runtime => [Hidden]; Static => [])
               [Read]
  where
    alone : Mode -> Shown
    alone Direct = MkShown [Direct] [] []
    alone Read = MkShown [] [] [Read]
    alone m = MkShown [] [m] []

||| A program's statements that print, case by case, in the order it runs
||| them: `main`'s first, then each case's run.
statements : Part -> List (Nat, Case) -> List (Nat, Mode)
statements part numbered =
  (numbered >>= \(n, c) => map (\m => (n, m)) (shown part c).inMain)
  ++ (numbered >>= \(n, c) => let s = shown part c in map (\m => (n, m)) (s.beforeInput ++ s.afterInput))

||| A case written into the places of a program.
record Placed where
  constructor MkPlaced
  function : List String
  direct : List String
  runner : List String
  inputs : List String
  hides : List Ty

||| Case `n` of a part, written.
write : Part -> Nat -> Case -> Placed
write part n c@(MkCase t e _) =
  let ls = leaves e
      numbered = zip [0 .. length ls] ls
      name = "c" ++ show n
      xs = foldr (\(k, _), rest => " x" ++ show k ++ rest) "" numbered
      fn = [ name ++ " : List () -> " ++ foldr (\l, rest => tyName l.ty ++ " -> " ++ rest) (tyName t) ls
           , name ++ " []" ++ xs ++ " = " ++ text Parameter e
           , name ++ " (_ :: k)" ++ xs ++ " = " ++ name ++ " k" ++ xs
           , "" ]
      call = "(" ++ name ++ " [()]" ++ foldr (\l, rest => " " ++ literalSource l.lit ++ rest) ")" ls
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
  in MkPlaced fn (map statement places.inMain) runner (map (\l => literalInput l.lit) ls) hides

||| The helpers every program has: hide<T> for every type, and the small sum
||| type.
helpers : List String
helpers = ((map (TIntegral . Sized) fixedTys ++ [TDouble, TChar, TString, Prims.tInteger]) >>= helper) ++
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
  [line "b" t (text Hidden (Lit a)), line "b" t (text Hidden (Lit b))]
  where
    twoOf : (u : Ty) -> (Literal u, Literal u)
    twoOf (TIntegral i) = (IntLit i 0, IntLit i 1)
    twoOf TDouble = (DoubleLit NonNegative (Written "0.0"), DoubleLit NonNegative (Written "1.0"))
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
||| all on one tape, each with its tape's fit.
cases : Bits64 -> Nat -> Part -> List (Case, Fit)
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
-- How a run must go
------------------------------------------------------------------------------

||| How a program's run must end, as the oracle predicts its statements:
||| it returns; it crashes at the first statement whose case crashes, by
||| one of that case's causes; or the oracle cannot say, at the first
||| statement whose case it cannot decide.
data Expected = Returns | CrashesAt Nat (List1 Cause) | Unpredicted Nat

||| A run as the oracle predicts it: the statements that print, in order,
||| and how it ends.
record Run where
  constructor MkRun
  printed : List (Nat, Mode)
  ending : Expected

||| The run of a program's cases.
expectedRun : Part -> List (Nat, Case) -> Run
expectedRun part numbered = go [<] (statements part numbered)
  where
    outcomes : SortedMap Nat Outcome
    outcomes = SortedMap.fromList (map (\(n, c) => (n, outcome c.body)) numbered)
    go : SnocList (Nat, Mode) -> List (Nat, Mode) -> Run
    go acc [] = MkRun (acc <>> []) Returns
    go acc ((n, m) :: rest) = case fromMaybe Runs (lookup n outcomes) of
      Runs => go (acc :< (n, m)) rest
      Crashes why => MkRun (acc <>> []) (CrashesAt n why)
      Undecided => MkRun (acc <>> []) (Unpredicted n)

------------------------------------------------------------------------------
-- The check
------------------------------------------------------------------------------

||| The cases a request names, each with its tape's fit, and the
||| request's name in what the check prints: a program's (`program <seed>
||| <cases> <part>`, named by its seed) or a tape's one (`replay <tape>
||| <part>`, named by its tape).
casesOf : List String -> Maybe (String, Part, List (Case, Fit))
casesOf ["program", seed, n, part] = do
  s <- parseSeed seed
  k <- parseCases n
  p <- parsePart part
  pure (seed, p, cases s k p)
casesOf ["replay", tape, part] = do
  t <- parseTape tape
  p <- parsePart part
  let d = replay t (genCase p)
  pure (tape, p, [(d.value, d.fit)])
casesOf _ = Nothing

||| How a program's run went, as the shell saw it: its output, how it
||| ended (`code <n>` or `signal <name>`), and its standard error.
export
record Observed where
  constructor MkObserved
  output : String
  status : String
  errors : String

||| How a case fails a check.
data Failure = Ends | Disagrees | MissesModel

failureWord : Failure -> String
failureWord Ends = "ending"
failureWord Disagrees = "agree"
failureWord MissesModel = "model"

||| What a program's run says of its cases.
record Report where
  constructor MkReport
  ||| How the run ended, where that is not how the oracle says.
  ending : List String
  ||| Each case whose lines print two values, at its first line that
  ||| differs from its first.
  agree : List String
  ||| Each case the model covers that prints another value, at its first
  ||| such line, then each that prints nothing.
  model : List String
  ||| The first case that fails, and how: its ending first, then a
  ||| disagreement.
  first : Maybe (Nat, Failure)

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

||| Whether the run ended as the oracle says: a return with nothing on
||| standard error; or a crash, the status a crash gives, and one line of
||| the runtime's on standard error, its phrase one of the causes the
||| case may meet first. The site before the phrase is the program's, so
||| the check does not read it.
endedAs : Expected -> Observed -> Maybe String
endedAs Returns run =
  if run.status == statusLine Returned && run.errors == "" then Nothing
  else Just ("ended by " ++ run.status ++ (if run.errors == "" then "" else ", with stderr " ++ show run.errors)
             ++ ", not returned")
endedAs (CrashesAt _ why) run =
  let crash = Crashed (Failed (head why))
      phrases = map (\c => ": " ++ causePhraseOf c ++ "\n") (forget why)
      oneLine = length (lines run.errors) == 1
  in if run.status == statusLine crash && oneLine && any (\p => isSuffixOf p run.errors) phrases
        then Nothing
        else Just ("ended by " ++ run.status ++ " with stderr " ++ show run.errors ++ ", not "
                   ++ joinBy " or " (map crashedText (forget why)))
endedAs (Unpredicted n) _ = Just ("the oracle cannot decide case " ++ show n)

||| The verdict on a run of a request's cases: its ending held to the
||| oracle's; its lines read back by their labels, each held to its case's
||| first line and to its case's model, and each statement the oracle says
||| prints printed exactly once, so that an output missing a line, or
||| saying one twice, cannot agree by saying less.
checked : (name : String) -> Part -> List Case -> Observed -> Report
checked name part cs run =
  let numbered = zip [the Nat 1 .. length cs] cs
      expected = expectedRun part numbered
      expectedLabels = map (\(n, m) => (label m n, n)) expected.printed
      byLabel = SortedMap.fromList expectedLabels
      shownCases = SortedSet.fromList (map fst expected.printed)
      models = SortedMap.fromList (mapMaybe (\(n, c) =>
                 if contains n shownCases then (\v => (n, show v)) <$> modelled c.body else Nothing) numbered)
      scanned = foldl (step byLabel models) (MkScan empty empty empty empty [<] [<]) (lines run.output)
      miscounted = mapMaybe (\(l, n) => case fromMaybe 0 (lookup l scanned.printed) of
                                          1 => Nothing
                                          k => Just (n, l, k)) expectedLabels
      disagreed = foldr (\(n, _, _) => insert n) scanned.disagreed miscounted
      miscounts = map (\(n, l, k) => name ++ ": case " ++ show n ++ ": " ++ l ++ " printed " ++ show k ++ " times, not once") miscounted
      silent = mapMaybe (unprintedModel models scanned.firsts) numbered
      missed = foldr (\(n, _) => insert n) scanned.missed silent
      unprinted = map (\(n, m) => name ++ ": case " ++ show n ++ ": m" ++ show n ++ " " ++ m ++ ", but no line") silent
      ended = endedAs expected.ending run
      endingAt = ended >>= \_ => caseOfEnding expected scanned.printed
      failed = mapMaybe (howFails disagreed missed) numbered
  in MkReport (map (\why => name ++ ": " ++ why) (toList ended))
              ((scanned.agreeing <>> []) ++ miscounts) ((scanned.modelling <>> []) ++ unprinted)
               (map (\n => (n, Ends)) endingAt <|> head' failed)
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
    -- The case a wrong ending is of: the one the oracle says crashes, or,
    -- for a run that should have returned, the one whose statement the
    -- output stopped before.
    caseOfEnding : Run -> SortedMap String Nat -> Maybe Nat
    caseOfEnding (MkRun _ (CrashesAt n _)) _ = Just n
    caseOfEnding (MkRun _ (Unpredicted n)) _ = Just n
    caseOfEnding (MkRun shownAll Returns) printed =
      fst <$> find (\(n, m) => isNothing (lookup (label m n) printed)) shownAll
    howFails : SortedSet Nat -> SortedSet Nat -> (Nat, Case) -> Maybe (Nat, Failure)
    howFails disagreed missed (n, _) =
      if contains n disagreed then Just (n, Disagrees)
      else if contains n missed then Just (n, MissesModel) else Nothing

||| What a check reports of a run.
data Check = OfEnding | OfAgreement | OfModel | OfFirst | OfModelled

parseCheck : String -> Maybe Check
parseCheck "ending" = Just OfEnding
parseCheck "agree" = Just OfAgreement
parseCheck "model" = Just OfModel
parseCheck "first" = Just OfFirst
parseCheck "modelled" = Just OfModelled
parseCheck _ = Nothing

||| The check `overran` of a request: the first case of the request whose
||| tape ran out, a valid case but not the one its seed drew,
||| as `<name>: overran: case <n>`, or nothing.
export covering
overranOf : List String -> Maybe String
overranOf request = do
  (name, _, cs) <- casesOf request
  pure $ case find (\(_, (_, fit)) => fit == Overran) (zip [the Nat 1 .. length cs] cs) of
    Just (n, _) => name ++ ": overran: case " ++ show n ++ "\n"
    Nothing => ""

||| The checks `ending`, `agree`, `model`, `first` and `modelled` of a
||| request, of the run's output, status and stderr: how the run's ending differs from the oracle's, the cases whose
||| lines disagree, the cases that miss their model, a line each, or the
||| first case that fails and how (`<n> ending`, `<n> agree` or `<n>
||| model`); or how many of the cases the run prints have a model, which
||| the model's check needs one of to check anything.
export covering
checkOf : (how : String) -> List String -> Observed -> Maybe String
checkOf how request run = do
  check <- parseCheck how
  (name, part, cs) <- casesOf request
  let report = checked name part (map fst cs) run
  pure $ case check of
    OfEnding => unlines report.ending
    OfAgreement => unlines report.agree
    OfModel => unlines report.model
    OfFirst => maybe "" (\(n, f) => show n ++ " " ++ failureWord f ++ "\n") report.first
    OfModelled =>
      let numbered = zip [the Nat 1 .. length cs] (map fst cs)
          shownCases = map fst (expectedRun part numbered).printed
      in show (length (mapMaybe (\(n, c) => if elem n shownCases then modelled c.body else Nothing) numbered)) ++ "\n"

||| An observed run, as the check reads it.
export
observed : (output : String) -> (status : String) -> (errors : String) -> Observed
observed = MkObserved

||| The check's own checks. On the cases of seed 1's program of three cases
||| at run time: the run the oracle predicts, each line printing the case's
||| model or one value of its own, names no case; with one more line of the
||| first printed case that prints another value, it names that case; with
||| that line missing, it names that case; an empty output names every case
||| that should print, the first of them first. On one case of
||| `prim__div_Int 1 0`: a run that crashes by division by zero names no
||| case, and one that returns names it by its ending. Then the table's own
||| checks.
export covering
checkerChecks : List (String, Bool)
checkerChecks =
  let cs = map fst (cases 1 3 Runtime)
      numbered = zip [the Nat 1 .. length cs] cs
      run = expectedRun Runtime numbered
      models = SortedMap.fromList (mapMaybe (\(n, c) => (\v => (n, show v)) <$> modelled c.body) numbered)
      agreeing = unlines (map (\(n, m) => label m n ++ " " ++ fromMaybe ("v" ++ show n) (lookup n models)) run.printed)
      ending = observedEnding run.ending
      ok = checked "1" Runtime cs (MkObserved agreeing (fst ending) (snd ending))
      firstShown = head' run.printed
      bad = checked "1" Runtime cs
              (MkObserved (agreeing ++ maybe "" (\(n, m) => label m n ++ " x\n") firstShown) (fst ending) (snd ending))
      dropped = lines agreeing
      short = checked "1" Runtime cs (MkObserved (unlines (drop 1 dropped)) (fst ending) (snd ending))
      silent = checked "1" Runtime cs (MkObserved "" (fst ending) (snd ending))
      crash = map (\e => MkCase Prims.tInt e Direct) dividedByZero
      crashed = checked "c" Runtime crash
                  (MkObserved "" (statusLine (Crashed (Failed DivisionByZero)))
                     ("prog: fatal: Main.idr:1:1: " ++ causePhraseOf DivisionByZero ++ "\n"))
      returned = checked "c" Runtime crash (MkObserved "" (statusLine Returned) "") in
  [ ("an agreeing output names no case",
     null ok.ending && null ok.agree && null ok.model && isNothing ok.first)
  , ("an output with one disagreeing line names that case",
     map fst bad.first == map fst firstShown && map (failureWord . snd) bad.first == Just "agree")
  , ("an output missing one line of a case names that case",
     map fst short.first == map fst firstShown && map (failureWord . snd) short.first == Just "agree")
  , ("an empty output names every case",
     length silent.agree == length run.printed && map fst silent.first == head' (sort (map fst run.printed)))
  , ("seed 1's run prints a line", not (null run.printed))
  , ("a crash the oracle predicts, met by its cause, names no case",
     not (null crash) && null crashed.ending && isNothing crashed.first)
  , ("a run that returns where the oracle predicts a crash names the case by its ending",
     map (\(n, f) => show n ++ " " ++ failureWord f) returned.first == Just "1 ending") ]
  ++ Prims.checks
  where
    -- The status and stderr of a run that ends as the oracle says.
    observedEnding : Expected -> (String, String)
    observedEnding Returns = (statusLine Returned, "")
    observedEnding (CrashesAt _ why) =
      (statusLine (Crashed (Failed (head why))), "prog: fatal: Main.idr:1:1: " ++ causePhraseOf (head why) ++ "\n")
    observedEnding (Unpredicted _) = (statusLine Returned, "")
    -- Int's division of 1 by 0, the one case of a program that crashes.
    dividedByZero : List (Expr Prims.tInt)
    dividedByZero =
      mapMaybe (\b => do same <- sameTy b.gives Prims.tInt
                         e <- appliedTo b [1, 0]
                         pure (replace {p = Expr} same e))
               (filter (\b => spellingText b.spelling == "prim__div_Int") builtins)

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
  unlines (checkLines "gen" Gen.checks ++ checkLines "fuzz-check" Fuzz.checkerChecks)
  ++ (the (List (String, String))
       [ ("program 1 3 runtime main", programText "program 1 3 runtime main" Runtime MainFile (map fst (cases 1 3 Runtime)))
       , ("program 1 3 runtime stdin", programText "program 1 3 runtime stdin" Runtime StdinFile (map fst (cases 1 3 Runtime)))
       , ("program 1 3 static main", programText "program 1 3 static main" Static MainFile (map fst (cases 1 3 Static)))
       , ("threads 1", show (threads 1) ++ "\n")
       , ("tape 1 2 runtime", tapeText tape ++ "\n")
       , ("shrink " ++ tapeText tape, unlines (map (tapeText . fst) (candidates tape)))
       , ("sem prim-int-add", fromMaybe "no program\n" (Sem.programOf InProgram "prim-int-add"))
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
