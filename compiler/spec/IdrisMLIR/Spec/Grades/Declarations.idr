-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The grade's declarations: the type `!idr.graded<uses, hold, T>`, the
||| closed sets of its axes, and the tables of its algebra, which the C++
||| reads in place of a second statement of each law (`Grade` proves them).
|||
||| Printed: `!idr.graded<once, counted unique deep, !List>`,
||| `!idr.graded<many, scoped, !Tree>`, `!idr.graded<many, static, !String>`,
||| `!idr.graded<once, i64>`. A bare type is its carrier's bare grade
||| (`bare`): a word used freely, or a value that holds references used
||| freely, counted and claiming nothing; the builder gives the carrier for
||| it, so one fact has one spelling and upstream's ops take it as it is.
module IdrisMLIR.Spec.Grades.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Grades.Grade

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
      Self => MkCase (ident "Self") (word "unique" ::: [word "self"]) (line "its own family's cells are reached through it alone")
      Deep => MkCase (ident "Deep") (word "unique" ::: [word "deep"]) (line "nothing it reaches is shared")
  , doc = brief (line "what is known of a value's sharing")
  }

export
recursionClosed : Closed Recursion
recursionClosed = MkClosed
  { name = ident "Recursion"
  , shape = OneOf
  , every = OwnFamily ::: [Other]
  , complete = \case
      OwnFamily => Here
      Other => There Here
  , describe = \case
      OwnFamily => MkCase (ident "OwnFamily") (word "own_family" ::: []) (line "a field of its family's own recursive group")
      Other => MkCase (ident "Other") (word "other" ::: []) (line "a field of another type")
  , doc = brief (line "whether a field is of its value's own family")
  }

||| The seven holds, as the C++ `HoldCase` the value class `::idr::Hold`
||| wraps; each spelled as the type prints it.
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
      Counted Self => MkCase (ident "CountedSelf") (word "counted" ::: [word "unique", word "self"]) (line "counted, its family's own cells unshared")
      Counted Deep => MkCase (ident "CountedDeep") (word "counted" ::: [word "unique", word "deep"]) (line "counted, nothing it reaches shared")
      Scoped None => MkCase (ident "Scoped") (word "scoped" ::: []) (line "scoped, claiming nothing")
      Scoped Self => MkCase (ident "ScopedSelf") (word "scoped" ::: [word "unique", word "self"]) (line "scoped, its family's own cells unshared")
      Scoped Deep => MkCase (ident "ScopedDeep") (word "scoped" ::: [word "unique", word "deep"]) (line "scoped, nothing it reaches shared")
      Static => MkCase (ident "Static") (word "static" ::: []) (line "static data")
  , doc = brief (line "a hold: who frees a value, and what is known of its sharing")
  }

||| Which way a cast between types equal but for their uses goes: into a
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

||| Each hold's axes, where it fits, and what a field read from a value at it
||| holds.
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
  , MkColumn (ident "holdReadOwnFamily") (EnumColumn (enumDef holdClosed))
      (\h => CaseCell (caseRef holdClosed (readHold OwnFamily h))) (line "a field of the value's own family read from it")
  , MkColumn (ident "holdReadOther") (EnumColumn (enumDef holdClosed))
      (\h => CaseCell (caseRef holdClosed (readHold Other h))) (line "a field of another type read from it")
  ]

--------------------------------------------------------------------------------
-- The type
--------------------------------------------------------------------------------

||| The hold parameter, read and written within the type's own syntax.
holdDirective : Directive
holdDirective = MkDirective
  { name = ident "Hold"
  , args = []
  , doc = brief (line "a hold, absent on a carrier that holds no reference")
  }

||| `!idr.graded`, C++ `GradedType`: its uses, its hold (`::idr::Hold`,
||| present exactly when the carrier holds references, which the carrier
||| says), its carrier. Its syntax is the hand printer's, which reads a hold
||| by its first word; its verifier holds the canonical form: never a grade
||| of a grade, none of a type used once by its type, a hold exactly on a
||| carrier that holds references, never the carrier's bare grade.
export
graded : TypeDef 3
graded = MkTypeDef
  { mnemonic = word "graded" ::: []
  , params =
      [ MkParameter (ident "uses") (EnumValue (enumDef usesClosed)) AlwaysWritten
          (line "how often the value may be used")
      , MkParameter (ident "hold") (HandValue (code "::std::optional<::idr::Hold>") holdDirective)
          AlwaysWritten (line "who frees what it holds and what is known of its sharing")
      , MkParameter (ident "carrier") TypeValue AlwaysWritten (line "the value itself") ]
  , syntax = HandSyntax
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , doc = brief (line "a value at a grade: its uses and, on a carrier that holds references, its hold")
  }

--------------------------------------------------------------------------------
-- The grade's one op
--------------------------------------------------------------------------------

||| `idr.lin.cast %v : T -> U`, C++ `LinCastOp`: a value cast between types
||| equal but for their uses, into a linear position (Idris lets any value
||| fill a binder of quantity 1) or out of one (the one use of a linear
||| value, where it becomes an ordinary one), its direction what its types
||| say (`getDirection`). A fresh identity both ways: two casts of one value
||| stay two linear values, and an unused one goes. Its fold is the one QTT
||| rule: a cast back of a cast with no other use is the value itself.
linCast : Op 1 1 0 0
linCast = MkOp
  { home = InIdr
  , mnemonic = "lin.cast"
  , ins = [single "value" (UpstreamType AnyTypeC)]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = [OurTrait resultCarriesOperand, OurTrait sameValue]
  , interfaces = [Declares InferIntRange ["inferResultRangesFromOptional"]]
  , effects = Executes [OnValues Allocate Identity (Results FZ)] [] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared [ValueOf (OperandRef FZ), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef FZ)),
                       Lit "->", TypeOf (OfGroup (ResultRef FZ))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = [MkMember OnObject "::idr::QuantityChange" "getDirection" []]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a value cast into or out of a linear position"
  }

||| The header the grade's C++ includes (`Generated/Grades.h.inc`): the
||| axes as enums, the holds and their facts, the product of uses. `Uses`
||| is an ODS enum besides, since the type's parameter is one; its header
||| reads it from there.
gradesHeader : Header
gradesHeader = MkHeader "Grades"
  [ ("idr" ::: [],
      [ EnumOf (enumDef releaseClosed), EnumOf (enumDef uniqueClosed)
      , EnumOf (enumDef recursionClosed), EnumOf (enumDef quantityChangeClosed)
      , TableOf holdTable, usesTimes ]) ]
  (brief "the grade's axes, its holds and their algebra")

||| The grade's area: its one op, its type, `Uses` (the type's enum
||| parameter), and its header.
export
declarations : Declarations
declarations = { ops := [SomeOp linCast]
               , types := [SomeType graded]
               , enums := [enumDef usesClosed]
               , directives := [holdDirective]
               , headers := [gradesHeader]
               } nothing
