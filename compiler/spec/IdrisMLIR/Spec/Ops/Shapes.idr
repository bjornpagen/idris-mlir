-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the ops of this area share: the constraints their values meet,
||| their effects as the runtime functions they call have them, and their
||| syntax. Each is a value or a function of its constants, so an op says
||| which it has and never restates one.
module IdrisMLIR.Spec.Ops.Shapes

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings

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
  [ strReadP, strValueP, bigReadP, bigValueP, natReadP, natValueP, bigOrNatReadP
  , bigOrNatValueP, charListP, strListP, byteBufferP, rank1ArrayP ]

public export
strRead : TypeC
strRead = SatisfiesType strReadP

public export
strValue : TypeC
strValue = SatisfiesType strValueP

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
||| restricts states its guard where it is admitted.
arithOp : Ident -> List UpLaw -> Admitted
arithOp r laws = MkAdmitted Arith r Always FrontendWrites [] laws

||| A word or a Double as its literal; folding materializes one too.
public export
arithConstant : Admitted
arithConstant = arithOp "Arith_ConstantOp" []

-- The wrapping arithmetic and the bitwise ops of signless words, which the
-- rules build and the big ops name as what they compute on words.

public export
addI : Admitted
addI = arithOp "Arith_AddIOp" [UpAssociative, UpIdentity 0]

public export
subI : Admitted
subI = arithOp "Arith_SubIOp" []

public export
mulI : Admitted
mulI = arithOp "Arith_MulIOp" [UpAssociative, UpIdentity 1]

public export
andI : Admitted
andI = arithOp "Arith_AndIOp" [UpAssociative, UpIdentity (-1)]

public export
orI : Admitted
orI = arithOp "Arith_OrIOp" [UpAssociative, UpIdentity 0]

public export
xorI : Admitted
xorI = arithOp "Arith_XOrIOp" [UpAssociative, UpIdentity 0]

||| A clock reading's seconds, by the constant bits of its nanoseconds: an
||| amount below the width, the only shift of arith's the frontend writes.
||| Idris's own shifts are the dialect's total ones.
public export
shrUI : Admitted
shrUI = arithOp "Arith_ShRUIOp" []

public export
cmpI : Admitted
cmpI = arithOp "Arith_CmpIOp" []

public export
maxSI : Admitted
maxSI = arithOp "Arith_MaxSIOp" []

public export
arithSelect : Admitted
arithSelect = arithOp "SelectOp" []

-- Conversions between words of two widths, a word and an index, and a word
-- and a Double: the sign on the op where the computation differs.

public export
truncI : Admitted
truncI = arithOp "Arith_TruncIOp" []

public export
extUI : Admitted
extUI = arithOp "Arith_ExtUIOp" []

public export
extSI : Admitted
extSI = arithOp "Arith_ExtSIOp" []

public export
indexCast : Admitted
indexCast = arithOp "Arith_IndexCastOp" []

public export
indexCastUI : Admitted
indexCastUI = arithOp "Arith_IndexCastUIOp" []

public export
uiToFP : Admitted
uiToFP = arithOp "Arith_UIToFPOp" []

public export
siToFP : Admitted
siToFP = arithOp "Arith_SIToFPOp" []

-- A Double's arithmetic is IEEE 754's binary64 as upstream's arith means
-- it: rounded to nearest, ties to even, and written with no fast-math flag,
-- so no rewrite assumes an algebra IEEE does not have. The runtime's
-- Doubles are the same arithmetic, built without contraction on every
-- target.

public export
addF : Admitted
addF = arithOp "Arith_AddFOp" []

public export
subF : Admitted
subF = arithOp "Arith_SubFOp" []

public export
mulF : Admitted
mulF = arithOp "Arith_MulFOp" []

public export
divF : Admitted
divF = arithOp "Arith_DivFOp" []

public export
negF : Admitted
negF = arithOp "Arith_NegFOp" []

public export
cmpF : Admitted
cmpF = arithOp "Arith_CmpFOp" []

-- An unsigned quotient and remainder, upstream's meaning: their divisor is
-- the result of idr.check.nonzero, which the frontend builds before each
-- from the guard stated here, so each stands below its guard by data
-- dependence, as every total op does, and upstream speculates neither
-- unless its divisor is a constant other than zero.

||| The divisor, upstream's second operand group, is not zero.
divisorNonzero : Guard Nat
divisorNonzero = MkGuard "check.nonzero" (1 ::: []) (caseRef causeClosed DivisionByZero)

public export
divUI : Admitted
divUI = { guards := [divisorNonzero] } (arithOp "Arith_DivUIOp" [])

public export
remUI : Admitted
remUI = { guards := [divisorNonzero] } (arithOp "Arith_RemUIOp" [])

||| Every upstream op the dialect admits, once.
public export
opAdmitted : List Admitted
opAdmitted =
  [ arithConstant, addI, subI, mulI, andI, orI, xorI, shrUI, cmpI, maxSI, arithSelect, truncI
  , extUI, extSI, indexCast, indexCastUI, uiToFP, siToFP, addF, subF, mulF, divF, negF, cmpF
  , divUI, remUI ]

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
