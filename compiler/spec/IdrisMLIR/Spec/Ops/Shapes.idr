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

||| An op of arith the frontend writes: the inline arithmetic of words, which
||| the rules build and the big ops name as what they compute on words.
arithOp : Ident -> Admitted
arithOp r = MkAdmitted Arith r Always FrontendWrites []

public export
addI : Admitted
addI = arithOp "Arith_AddIOp"

public export
subI : Admitted
subI = arithOp "Arith_SubIOp"

public export
mulI : Admitted
mulI = arithOp "Arith_MulIOp"

public export
andI : Admitted
andI = arithOp "Arith_AndIOp"

public export
cmpI : Admitted
cmpI = arithOp "Arith_CmpIOp"

public export
maxSI : Admitted
maxSI = arithOp "Arith_MaxSIOp"

public export
truncI : Admitted
truncI = arithOp "Arith_TruncIOp"

public export
opAdmitted : List Admitted
opAdmitted = [addI, subI, mulI, andI, cmpI, maxSI, truncI]

------------------------------------------------------------------------------
-- Effects, as each runtime function has them
------------------------------------------------------------------------------

||| Computes its results, and nothing more.
public export
computes : Declaration i o
computes = noEffects

||| A guard: the run ends by a crash where its condition fails.
public export
mayCrash : Declaration i o
mayCrash = Executes [OnState Write Crash] [] Covered Untouched

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
