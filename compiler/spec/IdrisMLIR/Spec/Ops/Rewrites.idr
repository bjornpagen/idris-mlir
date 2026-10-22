-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The rules of the e-graph pass on this area's ops, where greedy
||| canonicalization and hand folders once were. A rule over pure values is
||| a `Rewrite`, printed into the engine's tables and never run in Idris; a
||| rule over an op the skeleton orders (a guard, output) is a skeleton rule,
||| a hand class `::idr::egraph::<name>` (`idr/IR/Ops/Rules.h`) the engine
||| runs where its root op is.
|||
||| Every rule on the inline ops comes from a law (`Spec.Ops.Numeric`),
||| which the C++ checks against the ops' meanings when the compiler is
||| built: a rule cannot exist without its check. A rule whose constant is a
||| power of two is one rule per exponent, each a literal, so the engine
||| matches a constant and computes nothing. A literal matches a constant
||| whose value at its width is the literal's, and one outside the width's
||| range matches none. Every rule is one-way and constant-triggered: the
||| algebra that only connects equal forms is left out, which on real code
||| found nothing extraction kept and caused every budget stop.
module IdrisMLIR.Spec.Ops.Rewrites

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Scalars
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Strings

import Data.List1
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The admitted upstream ops the rules build
------------------------------------------------------------------------------

public export
subI : Admitted
subI = MkAdmitted Arith "Arith_SubIOp" Always FrontendWrites []

public export
andI : Admitted
andI = MkAdmitted Arith "Arith_AndIOp" Always FrontendWrites []

------------------------------------------------------------------------------
-- How a rule is made
------------------------------------------------------------------------------

||| A one-way rule: its right side replaces its left, which is never kept.
simplify : {n : Nat} -> (vars : Vect n VarUses) -> (lhs : Root n) -> (rhs : Pat n) -> Line
        -> {auto 0 bound : So (covers lhs rhs)}
        -> {auto 0 linear : So (linearIn vars rhs)}
        -> AnyRewrite
simplify vars lhs rhs doc = SomeRewrite (MkRewrite vars lhs rhs [] Simplify doc)

||| 2^k.
power : Nat -> Integer
power Z = 1
power (S k) = 2 * power k

||| The exponents a power-of-two rule is written for: every one a 64-bit
||| divisor may be, each rule meeting only the widths its literal fits.
exponents : List Nat
exponents = [1 .. 62]

||| The amounts a negative shift is turned for: below every width but 8's
||| largest, and representable, with its negation, at every width.
amounts : List Nat
amounts = [1 .. 63]

------------------------------------------------------------------------------
-- The rules of each law
------------------------------------------------------------------------------

||| The rules a law licenses, each an instance of it: the only way a rule
||| on the inline ops is made.
public export
rulesOf : NumericLaw -> List AnyRewrite
rulesOf QuotientByOne =
  [simplify [UsedMany] (RootedAt divs 0 [Var 0, Literal 1]) (Var 0) "a quotient by 1 is the dividend"]
rulesOf QuotientByMinusOne =
  [ simplify [UsedMany] (RootedAt divs 0 [Var 0, Literal (-1)]) (UpstreamNode subI [Literal 0, Var 0])
      "a quotient by -1 is the negation, wrapping at the least value as the quotient does" ]
rulesOf RemainderByUnit =
  [ simplify [UsedMany] (RootedAt mods 0 [Var 0, Literal 1]) (Literal 0) "a remainder by 1 is 0"
  , simplify [UsedMany] (RootedAt mods 0 [Var 0, Literal (-1)]) (Literal 0) "a remainder by -1 is 0" ]
rulesOf QuotientByPowerOfTwo =
  map (\k => simplify [UsedMany] (RootedAt divs 0 [Var 0, Literal (power k)])
                (Node shrs 0 [Var 0, Literal (cast k)])
                "a quotient by 2^k is the arithmetic shift right by k")
      exponents
rulesOf RemainderByPowerOfTwo =
  map (\k => simplify [UsedMany] (RootedAt mods 0 [Var 0, Literal (power k)])
                (UpstreamNode andI [Var 0, Literal (power k - 1)])
                "a remainder by 2^k is the low k bits")
      exponents
rulesOf RemainderByNegativePowerOfTwo =
  map (\k => simplify [UsedMany] (RootedAt mods 0 [Var 0, Literal (negate (power k))])
                (UpstreamNode andI [Var 0, Literal (power k - 1)])
                "a remainder by -2^k is the low k bits")
      amounts
rulesOf ShiftByZero =
  map (\s => simplify [UsedMany] (RootedAt s 0 [Var 0, Literal 0]) (Var 0) "a shift by 0 is its value")
      [shls, shlu, shrs, shru]
rulesOf ShiftByNegative =
  concatMap (\k =>
      [ simplify [UsedMany] (RootedAt shls 0 [Var 0, Literal (negate (cast k))])
          (Node shrs 0 [Var 0, Literal (cast k)]) "a signed left shift by -k is the right shift by k"
      , simplify [UsedMany] (RootedAt shrs 0 [Var 0, Literal (negate (cast k))])
          (Node shls 0 [Var 0, Literal (cast k)]) "a signed right shift by -k is the left shift by k" ])
    amounts
rulesOf CharOfChar =
  [ simplify [UsedMany] (RootedAt outer 0 [Node inner 0 [Var 0]]) (Node inner 0 [Var 0])
      "a char conversion of a char is that char"
  | outer <- [toCharS, toCharU], inner <- [toCharS, toCharU] ]
rulesOf IntegerRemainderByPowerOfTwo =
  map (\k => simplify [UsedMany] (RootedAt bigMod 0 [Var 0, Literal (power k)])
                (Node bigAnd 0 [Var 0, Literal (power k - 1)])
                "an Integer's remainder by 2^k is its low k bits")
      exponents
rulesOf IntegerQuotientByPowerOfTwo =
  map (\k => simplify [UsedMany] (RootedAt bigDiv 0 [Var 0, Literal (power k)])
                (Node bigShr 0 [Var 0, Literal (cast k)])
                "an Integer's quotient by 2^k is its shift right by k")
      exponents

------------------------------------------------------------------------------
-- The rules no law states
------------------------------------------------------------------------------

||| An integer made an Integer and back at its own width is itself, however
||| it was read: the e-graph's classes are typed, so the rule meets only a
||| conversion back to the integer's own type.
roundTrips : List AnyRewrite
roundTrips =
  [ simplify [UsedMany] (RootedAt bigToInt 0 [Node from 0 [Var 0]]) (Var 0)
      "an integer made an Integer and back at its width is itself"
  | from <- [bigFromInt Signed, bigFromInt Unsigned] ]
  ++
  [ simplify [UsedMany] (RootedAt bigToInt 0 [Node bigSmall 0 [Var 0]]) (Var 0)
      "a word made a small and back is itself" ]

||| The first character of a string its builder knows: the character a
||| cons or a one-character string is built with, the first of a number's
||| text by the runtime's head of that number. The builder's string is never
||| empty, so the head's guard has gone.
heads : List AnyRewrite
heads =
  [ simplify [UsedMany, UsedMany] (RootedAt strHead 0 [Node strCons 0 [Var 0, Var 1]]) (Var 0)
      "the head of a cons is its character"
  , simplify [UsedMany] (RootedAt strHead 0 [Node strFromChar 0 [Var 0]]) (Var 0)
      "the head of a one-character string is its character"
  , simplify [UsedMany] (RootedAt strHead 0 [Node strShowSint 0 [Var 0]]) (Node intHeadS 0 [Var 0])
      "the head of a signed integer's text is the runtime's head of it"
  , simplify [UsedMany] (RootedAt strHead 0 [Node strShowUint 0 [Var 0]]) (Node intHeadU 0 [Var 0])
      "the head of an unsigned integer's text is the runtime's head of it"
  , simplify [UsedMany] (RootedAt strHead 0 [Node strShowDouble 0 [Var 0]]) (Node f64Head 0 [Var 0])
      "the head of a Double's text is the runtime's head of it" ]

||| Every rule of the area over pure values.
public export
opRewrites : List AnyRewrite
opRewrites = concatMap rulesOf (forget lawClosed.every) ++ roundTrips ++ heads

------------------------------------------------------------------------------
-- Skeleton rules
------------------------------------------------------------------------------

||| One rule rooted at each op it rewrites.
rooted : Ident -> List OpRef -> Line -> List SkeletonRule
rooted name roots doc = map (\root => MkSkeletonRule name root doc) roots

guardRoots : List OpRef
guardRoots = ["check.nonzero", "check.in_bounds", "check.nonempty", "check.finite", "check.range"]

public export
skeletonRules : List SkeletonRule
skeletonRules = concat
  [ rooted "GuardDecided" guardRoots
      "a guard whose condition holds on its operands' constants or intervals goes; one whose condition fails is a crash of its cause at its site"
  , rooted "GuardRepeated" guardRoots
      "a guard of a value an identical guard gave goes: the first checked it"
  , rooted "NeverEmptyString" ["check.nonempty"]
      "a guard of a string a builder makes never empty, or an append of one, goes"
  , rooted "OutputOfAppend" ["io.put_str"]
      "writing an append writes its two strings in order"
  , rooted "OutputOfCons" ["io.put_str"]
      "writing a cons writes its character, then its string"
  , rooted "OutputOfChar" ["io.put_str"]
      "writing a one-character string writes the character"
  , rooted "OutputOfNothing" ["io.put_str"]
      "writing the empty string writes nothing"
  ]
