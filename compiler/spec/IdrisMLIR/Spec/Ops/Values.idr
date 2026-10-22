-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runtime's values and the ops that make one without computing: the
||| types `!idr.str`, `!idr.big` and `!idr.nat`, what a value of each holds,
||| how a literal of each is written, the comparison an op of strings or
||| bigs makes, a constant (`idr.constant`), and the operating system the
||| target names (`idr.target.os`).
module IdrisMLIR.Spec.Ops.Values

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Ops.Shapes

import Data.List.Elem
import Data.List1

%default total

------------------------------------------------------------------------------
-- The runtime's values
------------------------------------------------------------------------------

||| The values the runtime holds of its own: a string, an Integer, a
||| natural, which is an Integer never negative.
public export
data Scalar = Str | Big | Nat

public export
scalarClosed : Closed Scalar
scalarClosed = MkClosed
  { name = "RuntimeValue"
  , shape = OneOf
  , every = Str ::: [Big, Nat]
  , complete = \case
      Str => Here
      Big => There Here
      Nat => There (There Here)
  , describe = \case
      Str => MkCase "Str" ("str" ::: []) "a string, UTF-8"
      Big => MkCase "Big" ("big" ::: []) "an Integer: a small in its word, or a cell"
      Nat => MkCase "Nat" ("nat" ::: []) "a natural: an Integer never negative"
  , doc = brief "a value the runtime holds of its own"
  }

||| What a value of each holds, as the type's ValueFactsTypeInterface answers
||| it: each holds a reference and is counted; a string's word is always its
||| cell, an Integer's a small or a cell. None is used once by its type.
public export
scalarFacts : Table
scalarFacts = table scalarClosed
  [ MkColumn "holdsReferences" TruthColumn (\_ => TruthCell True) "whether a value holds a reference"
  , MkColumn "isLinearByType" TruthColumn (\_ => TruthCell False) "whether every value is used exactly once by its type"
  , MkColumn "isCounted" TruthColumn (\_ => TruthCell True) "whether a reference is counted"
  , MkColumn "isCellPointer" TruthColumn cellPointer "whether its word is always a cell's address"
  ]
  where
    cellPointer : Scalar -> Cell
    cellPointer Str = TruthCell True
    cellPointer Big = TruthCell False
    cellPointer Nat = TruthCell False

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
      [ MkMethod Instance "bool" "isLiteral" [param "::mlir::Attribute" "literal"]
          EveryImplementer "whether the attribute is a literal of this type"
      , MkMethod Instance "::mlir::ParseResult" "parseLiteral"
          [param "::mlir::AsmParser &" "parser", param "::mlir::Attribute &" "literal"]
          EveryImplementer "reads a literal of this type"
      ]
  , verifier = NoVerifier
  , doc = brief "how a literal of a type is written and read"
  }

||| A runtime value's type: no parameter, its name the one an SSA value of it
||| is printed with, its literal its own.
scalarType : Mnemonic -> Doc -> TypeDef 0
scalarType m d = MkTypeDef
  { mnemonic = m
  , params = []
  , syntax = Declarative []
  , interfaces =
      [ Upstream MemRefElementTypeInterfaceI []
      , Upstream OpAsmOpInterfaceI ["getAsmName"]
      , Ours literalType ["isLiteral", "parseLiteral"] ]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = d
  }

public export
strType : TypeDef 0
strType = scalarType "str" (says "a string (UTF-8)")

public export
bigType : TypeDef 0
bigType = scalarType "big" (says "an Integer")

||| Nat, and every type Idris shapes like it: a big at run time, never
||| negative. Every op that makes one keeps it so, and the one way in from
||| an Integer, idr.nat.from_big, clamps, so the type proves the range.
public export
natType : TypeDef 0
natType = scalarType "nat" (says "a natural number: an Integer never negative")

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

------------------------------------------------------------------------------
-- idr.constant
------------------------------------------------------------------------------

||| A constant: a constructor, a closure, or a literal of a runtime value
||| (an integer's and a Double's are arith.constant's, which every fold of
||| arith reads). Static data, used any number of times, held static where
||| its type holds references. Its verifier checks the value against its
||| type through its fields and captures, once per module verify.
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
      [ Upstream SymbolUserOpInterfaceI ["verifySymbolUses"]
      , Upstream OpAsmOpInterfaceI ["getAsmResultNames"]
      , Upstream InferIntRangeInterfaceI ["inferResultRanges"] ]
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
||| a module that names no target keeps the op.
public export
platformOsOp : Op 0 1 0 0
platformOsOp = MkOp
  { home = InIdr
  , mnemonic = "platform.os"
  , ins = []
  , outs = [result "result" strValue]
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
