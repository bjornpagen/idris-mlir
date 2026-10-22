-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the ops of this area share: the constraints their values meet,
||| their effects as the runtime functions they call have them, and their
||| syntax. Each is a value or a function of its constants, so an op says
||| which it has and never restates one.
module IdrisMLIR.Spec.Ops.Shapes

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration

import Data.Fin
import Data.List
import Data.List1

%default total

------------------------------------------------------------------------------
-- Constraints
------------------------------------------------------------------------------

public export
i1 : TypeC
i1 = UpstreamType I1C

public export
i32 : TypeC
i32 = UpstreamType I32C

public export
i64 : TypeC
i64 = UpstreamType I64C

public export
f64 : TypeC
f64 = UpstreamType F64C

||| Idris's IntN and BitsN share one signless type of their width; the op
||| says how it reads the bits.
public export
int : TypeC
int = AnyOfTypes (UpstreamType I8C ::: [UpstreamType I16C, UpstreamType I32C, UpstreamType I64C])
        "an integer of 8, 16, 32 or 64 bits"

||| A value a hand predicate decides, its C++ `::idr::<name>(::mlir::Type)`
||| defined in `lib/IR/Ops/Constraints.cpp`: a grade's facts (Grades.h) and
||| a family's shape, which data here cannot say.
public export
predicate : Ident -> Line -> Predicate
predicate n d = MkPredicate n OnType (brief d)

||| A string an op reads in place: used any number of times, at any hold.
||| A primitive never takes a linear value in place: a value used once
||| reaches one only through a cast to many.
public export
strReadP : Predicate
strReadP = predicate "isStrRead" "a string, used any number of times, read in place"

||| A string an op makes, at the grade its result has.
public export
strValueP : Predicate
strValueP = predicate "isStrValue" "a string at any grade"

||| A string that is static data, used any number of times: what an op
||| whose one meaning is its fold makes, since the constant it folds to is
||| static and stands only at a static hold.
public export
strStaticP : Predicate
strStaticP = predicate "isStrStatic" "a string held static, used any number of times"

public export
bigReadP : Predicate
bigReadP = predicate "isBigRead" "an Integer, used any number of times, read in place"

public export
bigValueP : Predicate
bigValueP = predicate "isBigValue" "an Integer at any grade"

public export
natReadP : Predicate
natReadP = predicate "isNatRead" "a natural, used any number of times, read in place"

public export
natValueP : Predicate
natValueP = predicate "isNatValue" "a natural at any grade, of any index term"

||| Nat's plus and mult are Integer's: two naturals' sum and product are
||| natural.
public export
bigOrNatReadP : Predicate
bigOrNatReadP = predicate "isBigOrNatRead" "an Integer or a natural, read in place"

public export
bigOrNatValueP : Predicate
bigOrNatValueP = predicate "isBigOrNatValue" "an Integer or a natural at any grade"

||| Base's list, which pack and concat walk: a family of a nil and a cons
||| of an element and the list, read off its shape.
public export
charListP : Predicate
charListP = predicate "isListOfChars" "a list of characters, read in place"

public export
strListP : Predicate
strListP = predicate "isListOfStrings" "a list of strings, read in place"

||| A buffer: an array of mutable memory of one dimension whose elements are
||| bytes.
public export
byteBufferP : Predicate
byteBufferP = predicate "isByteBuffer" "a buffer of bytes, an array of mutable memory of i8 of one dimension"

||| What has a length: an array of mutable memory of one dimension.
public export
rank1ArrayP : Predicate
rank1ArrayP = predicate "isRank1Array" "an array of mutable memory of one dimension"

public export
opPredicates : List Predicate
opPredicates =
  [ strReadP, strValueP, strStaticP, bigReadP, bigValueP, natReadP, natValueP, bigOrNatReadP
  , bigOrNatValueP, charListP, strListP, byteBufferP, rank1ArrayP ]

public export
strRead : TypeC
strRead = SatisfiesType strReadP

public export
strValue : TypeC
strValue = SatisfiesType strValueP

public export
strStatic : TypeC
strStatic = SatisfiesType strStaticP

public export
bigRead : TypeC
bigRead = SatisfiesType bigReadP

public export
bigValue : TypeC
bigValue = SatisfiesType bigValueP

public export
natRead : TypeC
natRead = SatisfiesType natReadP

public export
natValue : TypeC
natValue = SatisfiesType natValueP

public export
bigOrNatRead : TypeC
bigOrNatRead = SatisfiesType bigOrNatReadP

public export
bigOrNatValue : TypeC
bigOrNatValue = SatisfiesType bigOrNatValueP

public export
byteBuffer : TypeC
byteBuffer = SatisfiesType byteBufferP

------------------------------------------------------------------------------
-- The upstream ops this area admits
------------------------------------------------------------------------------

||| An op of arith the frontend writes, legal at every stage: the words and
||| Doubles of a program from its first form to its lowering. Upstream's
||| record holds its meaning and its effects, which the specification never
||| restates: none has a memory effect, so only its uses order it. Its laws
||| are the ones upstream has no trait for, which the e-graph and the
||| accumulator read. It takes no guard: an op whose operands a condition
||| restricts states its guard where it is admitted. Its range is the
||| function upstream computes its interval with, by which a node a rule
||| built gets one with no op standing for it; none where upstream has no
||| one function for it. Its fold is upstream's, exact on every machine: an
||| integer's is arithmetic on its bits, a Double's IEEE's own rounding,
||| which upstream computes without the C library. Its record's name carries
||| its dialect, so it is its own alias.
public export
arithOp : Ident -> List UpLaw -> Maybe RangeFunction -> Admitted
arithOp r ls rf = MkAdmitted
  { dialect = Arith, upstreamRecord = r, alias = r, legal = Always, writer = FrontendWrites
  , guards = [], laws = ls, range = rf, folding = UpstreamFold }

||| Upstream's range function of an op, by its name in upstream's common
||| integer range inference.
public export
rangedBy : Ident -> Maybe RangeFunction
rangedBy f = Just (InIntRange f)

||| A word or a Double as its literal; folding materializes one too. A
||| node of one is its constant, so it needs no range function.
public export
arithConstant : Admitted
arithConstant = arithOp "Arith_ConstantOp" [] Nothing

-- The wrapping arithmetic and the bitwise ops of signless words, which the
-- rules build and the big ops name as what they compute on words. A rule's
-- node is written with no overflow flag, so it wraps, and its interval is
-- upstream's with none.

public export
addI : Admitted
addI = arithOp "Arith_AddIOp" [UpAssociative, UpIdentity 0] (rangedBy "inferAdd")

public export
subI : Admitted
subI = arithOp "Arith_SubIOp" [] (rangedBy "inferSub")

public export
mulI : Admitted
mulI = arithOp "Arith_MulIOp" [UpAssociative, UpIdentity 1] (rangedBy "inferMul")

public export
andI : Admitted
andI = arithOp "Arith_AndIOp" [UpAssociative, UpIdentity (-1)] (rangedBy "inferAnd")

public export
orI : Admitted
orI = arithOp "Arith_OrIOp" [UpAssociative, UpIdentity 0] (rangedBy "inferOr")

public export
xorI : Admitted
xorI = arithOp "Arith_XOrIOp" [UpAssociative, UpIdentity 0] (rangedBy "inferXor")

||| A clock reading's seconds, by the constant bits of its nanoseconds: an
||| amount below the width, the only shift of arith's the frontend writes.
||| Idris's own shifts are the dialect's total ones.
public export
shrUI : Admitted
shrUI = arithOp "Arith_ShRUIOp" [] (rangedBy "inferShrU")

||| A comparison's interval is a truth its predicate decides, which no one
||| range function of its operands computes.
public export
cmpI : Admitted
cmpI = arithOp "Arith_CmpIOp" [] Nothing

public export
maxSI : Admitted
maxSI = arithOp "Arith_MaxSIOp" [] (rangedBy "inferMaxS")

||| A choice's interval is its condition's side, or both sides joined,
||| which arith computes itself and no range function of upstream's does.
||| Its record's name holds no dialect, so its alias does.
public export
arithSelect : Admitted
arithSelect = { alias := "Arith_SelectOp" } (arithOp "SelectOp" [] Nothing)

-- Conversions between words of two widths, a word and an index, and a word
-- and a Double: the sign on the op where the computation differs. A change
-- of width has upstream's interval at the result's width; an index cast
-- extends or truncates as the two widths fall, which no one range function
-- says, and a Double holds no interval.

public export
truncI : Admitted
truncI = arithOp "Arith_TruncIOp" [] (rangedBy "truncRange")

public export
extUI : Admitted
extUI = arithOp "Arith_ExtUIOp" [] (rangedBy "extUIRange")

public export
extSI : Admitted
extSI = arithOp "Arith_ExtSIOp" [] (rangedBy "extSIRange")

public export
indexCast : Admitted
indexCast = arithOp "Arith_IndexCastOp" [] Nothing

public export
indexCastUI : Admitted
indexCastUI = arithOp "Arith_IndexCastUIOp" [] Nothing

public export
uiToFP : Admitted
uiToFP = arithOp "Arith_UIToFPOp" [] Nothing

public export
siToFP : Admitted
siToFP = arithOp "Arith_SIToFPOp" [] Nothing

-- A Double's arithmetic is IEEE 754's binary64 as upstream's arith means
-- it: rounded to nearest, ties to even, and written with no fast-math flag,
-- so no rewrite assumes an algebra IEEE does not have. The runtime's
-- Doubles are the same arithmetic, built without contraction on every
-- target.

public export
addF : Admitted
addF = arithOp "Arith_AddFOp" [] Nothing

public export
subF : Admitted
subF = arithOp "Arith_SubFOp" [] Nothing

public export
mulF : Admitted
mulF = arithOp "Arith_MulFOp" [] Nothing

public export
divF : Admitted
divF = arithOp "Arith_DivFOp" [] Nothing

public export
negF : Admitted
negF = arithOp "Arith_NegFOp" [] Nothing

public export
cmpF : Admitted
cmpF = arithOp "Arith_CmpFOp" [] Nothing

-- A Double's functions of the C library and its exact ones (a root, a
-- floor, a ceiling) are IEEE 754's binary64 as upstream's math means them,
-- each the C library's function, written with no fast-math flag.

||| An op of math the frontend writes, legal at every stage as arith's ops
||| are: the lowering leaves it to upstream's conversion. Upstream's record
||| holds its meaning and its effects: none, so only its uses order it. It
||| takes no guard, since it is defined on every Double: a value outside
||| the function's domain gives IEEE's NaN, as the C library's does. Its
||| values are Doubles, so it has no range. Its fold is the one it states:
||| upstream folds a C library function by calling the compiling machine's,
||| whose last digit IEEE leaves to each library, so a folded constant could
||| differ from what the target computes and removing the fold would change
||| a result; such an op is never folded and runs on the target as written.
||| A root, a floor and a ceiling are exact under IEEE, so their folds stay.
||| Its record's name carries its dialect, so it is its own alias.
mathOp : UpFold -> Ident -> Admitted
mathOp f r = MkAdmitted
  { dialect = Math, upstreamRecord = r, alias = r, legal = Always, writer = FrontendWrites
  , guards = [], laws = [], range = Nothing, folding = f }

public export
expF : Admitted
expF = mathOp NeverFolded "Math_ExpOp"

public export
logF : Admitted
logF = mathOp NeverFolded "Math_LogOp"

public export
sinF : Admitted
sinF = mathOp NeverFolded "Math_SinOp"

public export
cosF : Admitted
cosF = mathOp NeverFolded "Math_CosOp"

public export
tanF : Admitted
tanF = mathOp NeverFolded "Math_TanOp"

public export
asinF : Admitted
asinF = mathOp NeverFolded "Math_AsinOp"

public export
acosF : Admitted
acosF = mathOp NeverFolded "Math_AcosOp"

public export
atanF : Admitted
atanF = mathOp NeverFolded "Math_AtanOp"

public export
sqrtF : Admitted
sqrtF = mathOp UpstreamFold "Math_SqrtOp"

public export
floorF : Admitted
floorF = mathOp UpstreamFold "Math_FloorOp"

public export
ceilF : Admitted
ceilF = mathOp UpstreamFold "Math_CeilOp"

public export
powF : Admitted
powF = mathOp NeverFolded "Math_PowFOp"

||| What ends a region Idris proved never runs: a match none of whose cases
||| can be, a value of an empty type. The frontend writes it, every pass
||| keeps it, and the lowering ends a crash with it, so it stands at every
||| stage. Upstream's record holds its meaning, undefined where reached,
||| which no program the frontend accepts reaches, and its effects: none,
||| since nothing after it runs to see one. It has no value to fold. Its
||| record's name holds no dialect, so its alias does.
public export
ubUnreachable : Admitted
ubUnreachable = MkAdmitted
  { dialect = UB, upstreamRecord = "UnreachableOp", alias = "UB_UnreachableOp", legal = Always
  , writer = FrontendWrites, guards = [], laws = [], range = Nothing, folding = UpstreamFold }

||| Every upstream op the dialect admits that takes no guard, once; the
||| guarded ones are beside their guard (`Spec.Ops.Checks`).
public export
opAdmitted : List Admitted
opAdmitted =
  [ arithConstant, addI, subI, mulI, andI, orI, xorI, shrUI, cmpI, maxSI, arithSelect, truncI
  , extUI, extSI, indexCast, indexCastUI, uiToFP, siToFP, addF, subF, mulF, divF, negF, cmpF
  , expF, logF, sinF, cosF, tanF, asinF, acosF, atanF, sqrtF, floorF, ceilF, powF
  , ubUnreachable ]

------------------------------------------------------------------------------
-- Effects, as each runtime function has them
------------------------------------------------------------------------------

||| Computes its results, and nothing more.
public export
computes : Declaration i o
computes = noEffects

||| Builds a new immutable value: nothing before counting, so two equal
||| builds are one and an unused one goes; new memory once counting makes
||| the result own its count.
public export
builds : Fin o -> RuntimeMemory -> Declaration i o
builds r memory = Executes [] [Acquires r] Covered memory

||| Reads and writes the outside, one ordered state.
public export
outside : RuntimeMemory -> Declaration i o
outside memory = Executes [OnState Read IO, OnState Write IO] [] Covered memory

||| Reads and writes the outside and builds a new value.
public export
outsideBuilding : Fin o -> RuntimeMemory -> Declaration i o
outsideBuilding r memory =
  Executes [OnState Read IO, OnState Write IO] [Acquires r] Covered memory

||| Reads the runtime's own state, the handle table or the saved errno, and
||| writes nothing the outside sees.
public export
readsRuntimeState : Declaration i o
readsRuntimeState = Executes [OnState Read RuntimeState] [] Covered Untouched

------------------------------------------------------------------------------
-- Syntax
------------------------------------------------------------------------------

||| The operands, comma-separated.
public export
operandItems : (i : Nat) -> List (Item i o a r)
operandItems i = intersperse (Lit ",") (map (ValueOf . OperandRef) (allFins i))

||| `%a, %b attr-dict : (A, B) -> (R)`: every type written, so an op's
||| grades are read off its text as off its types.
public export
plain : (i : Nat) -> Format i o a r
plain i = Declared (operandItems i ++ [AttrDict, Lit ":", FunctionalType OfOperands OfResults])

||| An attribute or property first, then the operands: `lt %a, %b ...`.
public export
attrFirst : (i : Nat) -> Fin a -> Format i o a r
attrFirst i at =
  Declared ([ValueOf (AttrRef at)] ++ operandItems i ++ [AttrDict, Lit ":", FunctionalType OfOperands OfResults])

------------------------------------------------------------------------------
-- Docs
------------------------------------------------------------------------------

public export
says : Line -> Doc
says = brief
