-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The grade's declarations: the type `!idr.graded<uses, hold, T>`, the
||| closed sets of its axes, and the tables of its algebra, which the C++
||| reads in place of a second statement of each law (`Grade` proves them).
|||
||| Printed: `!idr.graded<once, counted unique deep, !List>`,
||| `!idr.graded<many, scoped, !Tree>`, `!idr.graded<many, static, !String>`,
||| `!idr.graded<once, i64>`. A bare type is its carrier's bare grade: a
||| word used freely, or a value that holds references used freely, counted
||| and claiming nothing; the builder gives the carrier for
||| it, so one fact has one spelling and upstream's ops take it as it is.
module IdrisMLIR.Spec.Grades.Declarations

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Lifetimes.Declarations

import Decidable.Decidable
import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The closed sets
--------------------------------------------------------------------------------

export
usesClosed : Closed Uses
usesClosed = MkClosed
  { name = ident "Uses"
  , shape = OneOf
  , every = Once ::: [Many]
  , complete = \case
      Once => Here
      Many => There Here
  , describe = \case
      Once => MkCase (ident "Once") (word "once" ::: []) (line "used at most once")
      Many => MkCase (ident "Many") (word "many" ::: []) (line "used any number of times")
  , doc = brief (line "how often Idris lets a value be used")
  }

export
releaseClosed : Closed Release
releaseClosed = MkClosed
  { name = ident "Release"
  , shape = OneOf
  , every = Counted ::: [Scoped, Static]
  , complete = \case
      Counted => Here
      Scoped => There Here
      Static => There (There Here)
  , describe = \case
      Counted => MkCase (ident "Counted") (word "counted" ::: []) (line "freed when its count reaches zero")
      Scoped => MkCase (ident "Scoped") (word "scoped" ::: []) (line "freed when the lifetime of the op that made it ends")
      Static => MkCase (ident "Static") (word "static" ::: []) (line "never freed: static data")
  , doc = brief (line "who frees what a value holds")
  }

export
uniqueClosed : Closed Unique
uniqueClosed = MkClosed
  { name = ident "Unique"
  , shape = OneOf
  , every = None ::: [Self, Deep]
  , complete = \case
      None => Here
      Self => There Here
      Deep => There (There Here)
  , describe = \case
      None => MkCase (ident "None") (word "none" ::: []) (line "nothing is known of its sharing")
      Self => MkCase (ident "Self") (word "unique" ::: [word "self"]) (line "its own cells are reached through it alone: its family's, its in_place fields', and the storage of the buffers they hold, never their elements")
      Deep => MkCase (ident "Deep") (word "unique" ::: [word "deep"]) (line "nothing it reaches is shared")
  , doc = brief (line "what is known of a value's sharing")
  }

export
fieldReachClosed : Closed FieldReach
fieldReachClosed = MkClosed
  { name = ident "FieldReach"
  , shape = OneOf
  , every = OwnFamily ::: [InPlaceFamily, HeldBuffer, Other]
  , complete = \case
      OwnFamily => Here
      InPlaceFamily => There Here
      HeldBuffer => There (There Here)
      Other => There (There (There Here))
  , describe = \case
      OwnFamily => MkCase (ident "OwnFamily") (word "own_family" ::: []) (line "a field of its family's own recursive group")
      InPlaceFamily => MkCase (ident "InPlaceFamily") (word "in_place_family" ::: []) (line "a field of an in_place family, whose own cells are the value's")
      HeldBuffer => MkCase (ident "HeldBuffer") (word "held_buffer" ::: []) (line "a buffer an own cell holds, whose storage is the value's and whose elements are not")
      Other => MkCase (ident "Other") (word "other" ::: []) (line "a field of any other type")
  , doc = brief (line "how far a value's claim on its own cells reaches into a field")
  }

||| Whether a carrier holds references, the fact that decides whether its
||| grade has a hold: a data type computes it when it is made, and a family
||| at an unknown index.
export
refsClosed : Closed Refs
refsClosed = MkClosed
  { name = ident "Refs"
  , shape = OneOf
  , every = Words ::: [References]
  , complete = \case
      Words => Here
      References => There Here
  , describe = \case
      Words => MkCase (ident "Words") (word "words" ::: []) (line "words alone, no reference a count accounts for")
      References => MkCase (ident "References") (word "references" ::: []) (line "a reference a count accounts for")
  , doc = brief (line "whether a value holds references")
  }

||| The seven holds, as the C++ `HoldCase` the value class `::idr::Hold`
||| wraps; each spelled as the type prints it. The graded type's hold is one
||| of them or none, written by the codec generated for both sides.
export
holdClosed : Closed Hold
holdClosed = MkClosed
  { name = ident "HoldCase"
  , shape = OneOf
  , every = Counted None ::: [Counted Self, Counted Deep, Scoped None, Scoped Self, Scoped Deep, Static]
  , complete = \case
      Counted None => Here
      Counted Self => There Here
      Counted Deep => There (There Here)
      Scoped None => There (There (There Here))
      Scoped Self => There (There (There (There Here)))
      Scoped Deep => There (There (There (There (There Here))))
      Static => There (There (There (There (There (There Here)))))
  , describe = \case
      Counted None => MkCase (ident "Counted") (word "counted" ::: []) (line "counted, claiming nothing")
      Counted Self => MkCase (ident "CountedSelf") (word "counted" ::: [word "unique", word "self"]) (line "counted, its own cells unshared")
      Counted Deep => MkCase (ident "CountedDeep") (word "counted" ::: [word "unique", word "deep"]) (line "counted, nothing it reaches shared")
      Scoped None => MkCase (ident "Scoped") (word "scoped" ::: []) (line "scoped, claiming nothing")
      Scoped Self => MkCase (ident "ScopedSelf") (word "scoped" ::: [word "unique", word "self"]) (line "scoped, its own cells unshared")
      Scoped Deep => MkCase (ident "ScopedDeep") (word "scoped" ::: [word "unique", word "deep"]) (line "scoped, nothing it reaches shared")
      Static => MkCase (ident "Static") (word "static" ::: []) (line "static data")
  , doc = brief (line "a hold: who frees a value, and what is known of its sharing")
  }

||| Which way a cast between types of one carrier at other uses goes: into a
||| linear position, or out of one.
public export
data QuantityChange = Enter | Leave

export
quantityChangeClosed : Closed QuantityChange
quantityChangeClosed = MkClosed
  { name = ident "QuantityChange"
  , shape = OneOf
  , every = Enter ::: [Leave]
  , complete = \case
      Enter => Here
      Leave => There Here
  , describe = \case
      Enter => MkCase (ident "Enter") (word "enter" ::: []) (line "a value given to a binder of quantity 1")
      Leave => MkCase (ident "Leave") (word "leave" ::: []) (line "the one use of a linear value")
  , doc = brief (line "which way a cast of a value's uses goes")
  }

--------------------------------------------------------------------------------
-- The tables: each law the C++ reads, as the specification computes it
--------------------------------------------------------------------------------

||| Idris's product of uses, `usesTimes[a][b]`.
usesTimes : CppDecl
usesTimes = Array2 "usesTimes" (EnumColumn (enumDef usesClosed))
  (map (\a => map (\b => CaseCell (caseRef usesClosed (times a b))) (forget usesClosed.every))
       (forget usesClosed.every))
  "the product of two uses"

||| Bit `j` of a hold's row is set when it fits where the `j`th hold is asked.
fitsMask : Hold -> Integer
fitsMask h = go 0 (forget holdClosed.every)
  where
    go : Nat -> List Hold -> Integer
    go _ [] = 0
    go j (s :: ss) = (if isYes (fits h s) then 2 `pow` j else 0) + go (S j) ss
      where
        pow : Integer -> Nat -> Integer
        pow b Z = 1
        pow b (S k) = b * pow b k

||| The hold of a field read from a value at a hold, `holdReadsOnce[hold][reach]`
||| for a read at one use and `holdReadsMany[hold][reach]` for one at many, by
||| how far the value's claim on its own cells reaches into the field.
holdReads : Ident -> Uses -> CppDecl
holdReads name uses = Array2 name (EnumColumn (enumDef holdClosed))
  (map (\h => map (\r => CaseCell (caseRef holdClosed (readHold r uses h))) (forget fieldReachClosed.every))
       (forget holdClosed.every))
  "the hold of a field read from a value, by how far the value's claim reaches into it"

||| What a part gives a value built of it, `givenClaims[uses][held]` by how
||| often the part is used and what it claims (`givenClaim`).
givenClaims : CppDecl
givenClaims = Array2 "givenClaims" (EnumColumn (enumDef uniqueClosed))
  (map (\us => map (\u => CaseCell (caseRef uniqueClosed (givenClaim us u))) (forget uniqueClosed.every))
       (forget usesClosed.every))
  "what a part gives a value built of it, by how often it is used and what it claims"

||| The most a fresh value may claim, built of a part,
||| `freshestClaims[reach][given]` by how far its claim on its own cells
||| reaches into the part and what the part gives it (`freshest`).
freshestClaims : CppDecl
freshestClaims = Array2 "freshestClaims" (EnumColumn (enumDef uniqueClosed))
  (map (\r => map (\u => CaseCell (caseRef uniqueClosed (freshest r u))) (forget uniqueClosed.every))
       (forget fieldReachClosed.every))
  "the most a fresh value may claim, by how far its claim reaches into a part and what the part gives it"

||| Each hold's axes and where it fits.
export
holdTable : Table
holdTable = table holdClosed
  [ MkColumn (ident "holdSpelling") TextColumn
      (\h => TextCell (spellingText (holdClosed.describe h))) (line "the hold as the type prints it")
  , MkColumn (ident "holdRelease") (EnumColumn (enumDef releaseClosed))
      (\h => CaseCell (caseRef releaseClosed (release h))) (line "who frees a value at the hold")
  , MkColumn (ident "holdClaim") (EnumColumn (enumDef uniqueClosed))
      (\h => CaseCell (caseRef uniqueClosed (claim h))) (line "what the hold claims of sharing")
  , MkColumn (ident "holdFitsMask") Unsigned8
      (\h => IntCell (fitsMask h)) (line "bit j: the hold fits where the jth hold is asked")
  ]

--------------------------------------------------------------------------------
-- The type
--------------------------------------------------------------------------------

||| `!idr.graded`, C++ `GradedType`: its uses, its hold (`::idr::Hold`,
||| present exactly when the carrier holds references, which the carrier
||| says), its carrier. Its syntax is the hand printer's, which reads a hold
||| by its first word; its verifier holds the canonical form: never a grade
||| of a grade, none of a type used once by its type, a hold exactly on a
||| carrier that holds references, never the carrier's bare grade. What a
||| value of it holds is its carrier's, so its value facts are a hand unit's
||| answers that ask the carrier, which no constant answer could say, and a
||| value of it prints with its carrier's name.
export
graded : TypeDef 3
graded = MkTypeDef
  { mnemonic = "graded"
  , params =
      [ MkParameter (ident "uses")
          (EnumValue (imported usesClosed
            (MkSource ("IdrisMLIR" ::: ["Spec", "Grades", "Grade"]) "Uses"
                      ("IdrisMLIR" ::: ["Spec", "Grades", "Declarations"]) "usesClosed")))
          AlwaysWritten
          (line "how often the value may be used")
      , MkParameter (ident "hold")
          (OptionalCase
            (imported holdClosed
              (MkSource ("IdrisMLIR" ::: ["Spec", "Grades", "Hold"]) "Hold"
                        ("IdrisMLIR" ::: ["Spec", "Grades", "Declarations"]) "holdClosed"))
            (code "::idr::Hold"))
          AlwaysWritten (line "who frees what it holds and what is known of its sharing")
      , MkParameter (ident "carrier") TypeValue AlwaysWritten (line "the value itself") ]
  , syntax = HandSyntax
  , interfaces = [Declares OpAsmType ["getAsmName"], Implements patternTypeInterface ["matchInstance"]]
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , facts = HandAnswers
  , doc = brief (line "a value at a grade: its uses and, on a carrier that holds references, its hold")
  }

--------------------------------------------------------------------------------
-- The grade's one op
--------------------------------------------------------------------------------

||| `idr.lin.cast %v in (%l : !idr.lifetime<view>) : T -> U`, C++
||| `LinCastOp`: a value cast between types of one carrier at other uses,
||| into a linear position (Idris lets any value fill a binder of quantity
||| 1) or out of one (the one use of a linear value, where it becomes an
||| ordinary one), its direction what its types say (`getDirection`). Its
||| hold is the operand's or one that hold fits (`Fits`): a claim may be
||| forgotten on the way, never raised. Given a bare carrier it makes a
||| reference of its own, so a loan's alias never enters one. A fresh
||| identity both ways: two casts of one value stay two linear values, and
||| an unused one goes. A scoped result
||| lives in the lifetime `outers` states, its operand's or one that
||| lifetime encloses; the builder from a type states its operand's. Its
||| fold is the one QTT rule: a cast back of a cast with no other use is the
||| value itself, which only a cast that forgot nothing can have, since
||| fitting is antisymmetric.
public export
linCast : Op 2 1 0 0
linCast = MkOp
  { home = InIdr
  , mnemonic = "lin.cast"
  , ins = [single "value" (UpstreamType AnyTypeC), variadic "outers" anyLifetime]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = [OurTrait resultCarriesOperand, OurTrait sameValue, OurTrait adoptsCarrier]
  , interfaces = [ Declares InferIntRange ["inferResultRangesFromOptional"], Implements flowInterface ["getFlowEdges"]
                 , Implements statesLifetime statedMethods, Implements statesOuters [] ]
  , effects = Executes [OnValues Allocate Identity (Results FZ)] [] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared [ ValueOf (OperandRef FZ)
                      , OptionalGroup [Lit "in", Lit "("] (ValueOf (OperandRef (FS FZ)))
                          [Lit ":", TypeOf (OfGroup (OperandRef (FS FZ))), Lit ")"]
                      , AttrDict, Lit ":", TypeOf (OfGroup (OperandRef FZ))
                      , Lit "->", TypeOf (OfGroup (ResultRef FZ)) ]
  , builders = [MkBuilder [param "::mlir::Type" "result", param "::mlir::Value" "value"]]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::idr::QuantityChange" "getDirection" []
      , structuralMeaning "::idr::LinCastOp" ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a value cast into or out of a linear position"
  }

||| The header the grade's C++ includes (`Generated/Grades.h.inc`): the
||| axes as enums, whether a carrier holds references, the holds and their
||| facts, what a field read gives, what a part gives a value built of it
||| and what a fresh value may claim, the product of uses. `Uses` is an ODS
||| enum besides, since the type's parameter is one; its header reads it
||| from there.
gradesHeader : Header
gradesHeader = MkHeader "Grades"
  [ (DialectNamespace,
      [ EnumOf (enumDef releaseClosed), EnumOf (enumDef uniqueClosed)
      , EnumOf (enumDef refsClosed)
      , EnumOf (enumDef fieldReachClosed), EnumOf (enumDef quantityChangeClosed)
      , EnumOf (enumDef byTypeClosed)
      , EnumOf (enumDef holdClosed), TableOf holdTable
      , holdReads "holdReadsOnce" Once, holdReads "holdReadsMany" Many
      , givenClaims, freshestClaims, usesTimes ]) ]
  (brief "the grade's axes, its holds and their algebra")

||| The grade's area: its one op, its type, `Uses` (the type's enum
||| parameter), and its header.
public export
declarations : Declarations
declarations = { ops := [SomeOp linCast]
               , types := [SomeType graded]
               , enums := [enumDef usesClosed]
               , headers := [gradesHeader]
               } nothing
