-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runtime's values and the ops that make one without computing: the
||| types `!idr.str`, `!idr.big` and `!idr.nat`, what a value of each holds,
||| how a literal of each is written, the comparison an op of strings or
||| bigs makes, a constant (`idr.constant`), and the operating system the
||| target names (`idr.platform.os`).
module IdrisMLIR.Spec.Ops.Values

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Ops.Shapes

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The runtime's values
------------------------------------------------------------------------------

||| How a literal of a runtime value is written and read: a quoted string,
||| or a `#idr.big` for an Integer and a natural (never negative). Every op
||| that holds a literal (`idr.constant`, a literal match's keys) asks the
||| type.
public export
literalType : InterfaceDef
literalType = MkInterfaceDef
  { name = "LiteralTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject "bool" "isLiteral" [param "::mlir::Attribute" "literal"]
          EveryImplementer "whether the attribute is a literal of this type"
      , MkMethod PerObject "::mlir::ParseResult" "parseLiteral"
          [param "::mlir::AsmParser &" "parser", param "::mlir::Attribute &" "literal"]
          EveryImplementer "reads a literal of this type"
      ]
  , verifier = Unverified
  , doc = brief "how a literal of a type is written and read"
  }

||| What a runtime value's type is to MLIR: an element of an array, its
||| values printed with its own name, its literal its own.
scalarInterfaces : List InterfaceUse
scalarInterfaces =
  [ Declares MemRefElementType []
  , Declares OpAsmType ["getAsmName"]
  , Implements literalType ["isLiteral", "parseLiteral"] ]

||| What a value of a runtime value's type holds: a reference, counted, and
||| none is used once by its type; what its word is, the type says.
scalarFacts : CellWord -> TypeFacts
scalarFacts word = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted word)

||| A runtime value's type with no parameter.
scalarType : Mnemonic -> CellWord -> Doc -> TypeDef 0
scalarType m word d = MkTypeDef
  { mnemonic = m
  , params = []
  , syntax = Declarative []
  , interfaces = scalarInterfaces
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = scalarFacts word
  , doc = d
  }

||| A string's word is always its cell.
public export
strType : TypeDef 0
strType = scalarType "str" AlwaysCell (says "a string (UTF-8)")

||| An Integer's word is a small in the word, or a cell.
public export
bigType : TypeDef 0
bigType = scalarType "big" MayBeOtherWord (says "an Integer")

||| Nat, and every type Idris shapes like it: a big at run time, never
||| negative. Every op that makes one keeps it so, and the one way in from
||| an Integer, idr.nat.from_big, clamps, so the type proves the range. A
||| natural keeps its link to the index term it is, `!idr.nat<3>`,
||| `!idr.nat<v0>`, or `!idr.nat<_>` where no term is known, so a call that
||| passes one passes its term too. The term is read and printed by hand (a
||| natural's own syntax over the families' terms), held to one whole term
||| at the boundary, and laid out in bytecode by the families' wire of a
||| term, which the generator prints the codec of for both readers.
public export
natType : TypeDef 1
natType = MkTypeDef
  { mnemonic = "nat"
  , params =
      [ MkParameter "index" (WiredValue (WiredArray termWire) termsParam)
          AlwaysWritten "the index term the natural is, opaque where none is known" ]
  , syntax = HandSyntax
  , interfaces = scalarInterfaces
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , facts = scalarFacts MayBeOtherWord
  , doc = says "a natural number: an Integer never negative, linked to its index term"
  }

------------------------------------------------------------------------------
-- Comparisons
------------------------------------------------------------------------------

||| A comparison of two strings or two bigs, the one predicate an order the
||| runtime gives is compared with zero by.
public export
data Comparison = Eq | Lt | Lte | Gt | Gte

public export
comparisonClosed : Closed Comparison
comparisonClosed = MkClosed
  { name = "CmpPredicate"
  , shape = OneOf
  , every = Eq ::: [Lt, Lte, Gt, Gte]
  , complete = \case
      Eq => Here
      Lt => There Here
      Lte => There (There Here)
      Gt => There (There (There Here))
      Gte => There (There (There (There Here)))
  , describe = \case
      Eq => MkCase "eq" ("eq" ::: []) "equal"
      Lt => MkCase "lt" ("lt" ::: []) "less"
      Lte => MkCase "lte" ("lte" ::: []) "less or equal"
      Gt => MkCase "gt" ("gt" ::: []) "greater"
      Gte => MkCase "gte" ("gte" ::: []) "greater or equal"
  , doc = brief "a comparison of strings or bigs"
  }

||| The comparison as the frontend writes it, typed, where the ops hold it.
public export
comparisonEnum : ImportedEnum
comparisonEnum = imported comparisonClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Ops", "Values"]) "Comparison"
            ("IdrisMLIR" ::: ["Spec", "Ops", "Values"]) "comparisonClosed")

------------------------------------------------------------------------------
-- idr.constant
------------------------------------------------------------------------------

||| A constant: a constructor, a closure, or a literal of a runtime value
||| (an integer's and a Double's are arith.constant's, which every fold of
||| arith reads). Static data, used any number of times, held static where
||| its type holds references. Its verifier checks the value against its
||| type through its fields and captures, once per module verify. It holds
||| the flow interface because its edges are the one place a constant's
||| labels and references enter what the readers follow: a closure's label,
||| a constructor's fields at their anchors.
public export
constantOp : Op 0 1 1 0
constantOp = MkOp
  { home = InIdr
  , mnemonic = "constant"
  , ins = []
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = [attr "value" (UpstreamAttr AnyAttrC)]
  , regions = []
  , traits = [ConstantLike]
  , interfaces =
      [ Implements flowInterface ["getFlowEdges"]
      , Declares SymbolUser ["verifySymbolUses"]
      , Declares InferIntRange ["inferResultRanges"] ]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared [TypeOf (OfGroup (ResultRef 0)), ValueOf (AttrRef 0), AttrDict]
  , builders = []
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnClass "bool" "isBuildableWith"
          [param "::mlir::Attribute" "value", param "::mlir::Type" "type"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a constant: a constructor, closure, string or big"
      "`idr.constant !idr.str \"abc\"`: the type first, then the value, which carries none."
  }

------------------------------------------------------------------------------
-- idr.platform.os
------------------------------------------------------------------------------

||| The operating system the module's target triple names, in the spelling
||| Idris's Scheme backends share and base tests for: "darwin", "unix",
||| "windows" or "unknown". Folded from the triple, the target's one place;
||| a module that names no target keeps the op. Its text is static data,
||| which its result's type holds, so the constant it folds to stands
||| where it stood.
public export
platformOsOp : Op 0 1 0 0
platformOsOp = MkOp
  { home = InIdr
  , mnemonic = "platform.os"
  , ins = []
  , outs = [result "result" strStatic]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = plain 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the operating system the target triple names"
  }
