-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops that build, read and refine a constructor value, what their
||| operands are, and the rules that rewrite them: a field is a total read
||| of a value refined to its constructor, a tag folds where the type leaves
||| one constructor possible, and a numeral converts to and from a natural
||| with no range check, its bound its type's.
module IdrisMLIR.Spec.Families.Ops

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Types
import IdrisMLIR.Spec.Lifetimes.Declarations
import IdrisMLIR.Spec.Tail.Declarations

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What an operand of ours is
------------------------------------------------------------------------------

||| A value of a data type, at any grade: what a match takes apart and a tag
||| reads.
export
dataValue : Predicate
dataValue = MkPredicate "isDataValue" OnType (brief "a value of a data type, at any grade")

||| A value of a data type refined to one constructor whose binders it
||| determines, at any grade: what a field is a total read of.
export
refinedValue : Predicate
refinedValue = MkPredicate "isRefinedValue" OnType
  (brief "a value of a data type refined to one constructor, at any grade")

||| A value whose layout is a cell, at any grade: the only values counting's
||| ops take and a destination writes.
export
cellValue : Predicate
cellValue = MkPredicate "isCellValue" OnType (brief "a value of a data type held in a cell")

||| A value of a numeral family, whose layout is a number.
export
numeralValue : Predicate
numeralValue = MkPredicate "isNumeralValue" OnType (brief "a value of a family of numeral shape")

||| A natural, at any grade.
export
naturalValue : Predicate
naturalValue = MkPredicate "isNaturalValue" OnType (brief "a natural, at any grade")

||| A lifetime a scoped result lives in.
lifetimeOperand : TypeC
lifetimeOperand = OurType (SomeType lifetimeType)

||| What every op that can make a scoped value defines of the interface that
||| states its lifetime.
lifetimeMethods : List Ident
lifetimeMethods = ["getStatedLifetime", "setStatedLifetime"]

||| `in (%l : !idr.lifetime<view>)`: the lifetime a scoped result lives in,
||| written with its type, whose kind no format can infer; nothing where the
||| result is not scoped.
statedIn : Fin i -> Item i o a r
statedIn k =
  OptionalGroup [Lit "in", Lit "("] (ValueOf (OperandRef k)) [Lit ":", TypeOf (OfGroup (OperandRef k)), Lit ")"]

------------------------------------------------------------------------------
-- The ops
------------------------------------------------------------------------------

||| `idr.data.con`: a constructor value, every field given. Its constructor is
||| the one its refined result type leaves possible, so no tag stands beside
||| the type. Building an immutable value acquires nothing before counting,
||| so two equal ones are one and an unused one goes; a result whose identity
||| is read (used once, of a family rebuilt in place, or an unforced memo
||| cell) is a fresh identity, never merged. Its cell is new, so its value
||| is shared only through what its fields hold: `freshClaim` is the most a
||| constructor of those fields claims, `unique deep` where each field leaves
||| everything it reaches unshared, `unique self` where each field its claim
||| on its own cells reaches (a field of its group or of an `in_place`
||| family, and a buffer it holds, whose storage that claim covers) claims
||| its own cells unshared, so a cell holding a shared buffer claims neither;
||| each is read off the grade's table of field reads, not restated here.
||| The builder from a carrier gives the result that claim.
|||
||| It takes over each field that owns its count, so moving it where it
||| would not have run would give that field up on a path that keeps it: it
||| may be speculated only where it takes no field over and uses none once.
||| A scoped result lives in the lifetime `outers` states, one its scoped
||| fields all outlive. Asked how its result is built, it answers its
||| constructor and its fields, so a reader that looks through construction
||| names no op.
public export
conOp : Op 2 1 0 0
conOp = MkOp
  { home = InIdr
  , mnemonic = "data.con"
  , ins = [variadic "fields" (UpstreamType AnyTypeC), variadic "outers" lifetimeOperand]
  , outs = [result "result" (SatisfiesType refinedValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Implements flowInterface ["getFlowEdges"], Implements statesLifetime lifetimeMethods
      , Implements statesOuters [], Implements structureInterface ["getStructure"] ]
  , effects = Executes [] [Consumes 0, NewIdentity 0] Covered Untouched
  , speculation = Conditionally
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ Custom fieldsDirective [Group (OperandRef 0), TypeOfGroup (OperandRef 0)]
      , statedIn 1, AttrDict, Lit ":", TypeOf (OfGroup (ResultRef 0)) ]
  , builders =
      [ MkBuilder [param "::idr::DataType" "carrier", param "::idr::Uses" "uses", param "::mlir::ValueRange" "fields"]
      , MkBuilder [param "::mlir::Type" "result", param "::mlir::ValueRange" "fields"] ]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::idr::DataType" "getDataType" []
      , MkMember OnObject "::idr::Tag" "getTag" []
      , MkMember OnClass "::idr::Unique" "freshClaim" [param "::idr::DataType" "carrier", param "::mlir::TypeRange" "fields"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "builds a constructor value"
      """
      `idr.data.con(%x : i64, %xs : !idr.data<#List>) : !idr.data<#List @Cons>`:
      the fields, then the value's type, refined to its constructor.
      """
  }

||| `idr.data.field`: field `index` of a value refined to one constructor, read
||| at the value's uses times the field's, as a match binds it: a total read,
||| since the type fixes the constructor, so it may run anywhere its operand
||| is. A memo cell's field reads its state, which a force writes. Its type
||| is inferred from the value's (`fieldReadType`), so a read follows its
||| value's grade wherever a pass changes it. A field of a scoped value is
||| scoped, and `outers` states its lifetime: the value's, or one that
||| lifetime encloses. Projecting the value is all it does with it, so a
||| chain of single uses ends at it, as at a match.
public export
fieldOp : Op 2 1 1 0
fieldOp = MkOp
  { home = InIdr
  , mnemonic = "data.field"
  , ins = [single "value" (SatisfiesType refinedValue), variadic "outers" lifetimeOperand]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = [attr "index" (UpstreamAttr I64AttrC)]
  , regions = []
  , traits = [OurTrait eliminatesOperand]
  , interfaces =
      [ InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]
      , Implements statesLifetime lifetimeMethods, Implements statesOuters []
      , Implements valueSourceInterface ["getValueSource"] ]
  , effects = Executes [] [ReadsMemo 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (AttrRef 0), Lit "]", statedIn 1, AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = [MkBuilder [param "::mlir::Value" "value", param "unsigned" "index"]]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::idr::DataType" "getDataType" []
      , MkMember OnObject "::idr::Tag" "getTag" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "reads a field of a value refined to its constructor"
  }

||| `idr.data.tag`: the constructor of a data value, in [0, n-1] for its n
||| declared constructors, an `i64` its result's rule fixes, so no builder
||| states it; it folds where the type leaves one possible.
public export
tagOp : Op 1 1 0 0
tagOp = MkOp
  { home = InIdr
  , mnemonic = "data.tag"
  , ins = [single "value" (SatisfiesType dataValue)]
  , outs = [result "result" (UpstreamType I64C)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [] [ReadsMemo 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the constructor tag of a data value"
  , typing = InferredTypes [FixedType BuiltI64]
  }

||| `idr.data.reindex`: the same value at a type equal to its own under the
||| refinements of the enclosing scopes (a case's equation, an assumed
||| equality), or a refined data type given where its unrefined one is
||| asked. Whether it does work is a fact of its two types (`isFree`): none
||| where they are the same words at run time, a bounded re-pack where an
||| index known inside a function changes the layout, which builds the cells
||| a result held in a cell needs. It answers the same when asked whether it
||| gives its operand on with no run-time work, so a call whose result a free
||| one takes may still be the tail, and one a re-pack takes is not. One that
||| builds a cell or an array gives
||| a fresh value, counted and claimed unique whatever the operand's hold;
||| one that builds nothing, free or not (a cell taken apart in place, a
||| numeral widened), keeps the operand's hold, its result's memory the
||| operand's. Either way it takes its operand over, and its effects follow
||| from its two types.
||| Checked by the function's scope walk, which holds the refinements. A
||| scoped value stays scoped, and `outers` states its lifetime: the
||| operand's, or one that lifetime encloses.
public export
dataReindexOp : Op 2 1 0 0
dataReindexOp = MkOp
  { home = InIdr
  , mnemonic = "data.reindex"
  , ins = [single "value" (UpstreamType AnyTypeC), variadic "outers" lifetimeOperand]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Implements flowInterface ["getFlowEdges"], Implements statesLifetime lifetimeMethods
      , Implements statesOuters [], Implements carriesOnInterface ["getCarry"]
      , Implements scopeRuleInterface ["verifyScopeRule"] ]
  , effects = Executes [] [Repacks 0 0] Covered Untouched
  , speculation = Conditionally
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), statedIn 1, AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "to", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = [MkBuilder [param "::mlir::Type" "result", param "::mlir::Value" "value"]]
  , defaultBuilders = WithDefaults
  , members = [MkMember OnObject "bool" "isFree" []]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a value at a type its enclosing refinements make equal to its own"
  }

||| `idr.index.assume`: a region in which an erased equality Idris proved holds
||| (`replace`, `rewrite`, a match on an erased `Refl`), the values whose
||| types mention its terms forwarded into it refined. The one place a fact
||| enters the IR on Idris's word alone; inside it, every cast is checked as
||| any other. An equality that clashes makes the region unreachable.
public export
assumeOp : Op 1 1 1 1
assumeOp = MkOp
  { home = InIdr
  , mnemonic = "index.assume"
  , ins = [variadic "forwarded" (UpstreamType AnyTypeC)]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "equation" (OurAttr (SomeAttr equationAttr))]
  , regions = [sized "body" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch ["getSuccessorRegions", "getEntrySuccessorOperands", "getSuccessorInputs", "areTypesCompatible"]
      , Implements erasedBinderInterface ["getBoundSorts", "getRefinement"] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOp
  , format = HandFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a region in which an erased equality of index terms holds"
  }

||| `idr.numeral.to_nat`: a numeral's value as a natural: the identity at a
||| natural's layout, a widening at a fixed width. At a width whose numbers
||| may pass a natural's small range, the natural is a big the runtime
||| builds, big.from_uint's function, so the op builds a value as that op
||| does: new memory once counting makes the result own its count, its
||| limbs written straight into the result's cell, so the runtime holds no
||| memory besides. Which
||| width a numeral has is its type's layout, one op for every width. Its
||| result is at most the largest value its operand's type allows, so the
||| bound Idris proved of an index reaches the range a check is decided by.
public export
numeralToNatOp : Op 1 1 0 0
numeralToNatOp = MkOp
  { home = InIdr
  , mnemonic = "numeral.to_nat"
  , ins = [single "value" (SatisfiesType numeralValue)]
  , outs = [result "result" (SatisfiesType naturalValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [] [Acquires 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a numeral's value as a natural"
  }

||| `idr.numeral.of_nat`: a natural as a numeral of the bound Idris proved
||| it below, with no range check: a narrowing at a fixed width.
public export
numeralOfNatOp : Op 1 1 0 0
numeralOfNatOp = MkOp
  { home = InIdr
  , mnemonic = "numeral.of_nat"
  , ins = [single "value" (SatisfiesType naturalValue)]
  , outs = [result "result" (SatisfiesType numeralValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a natural as a numeral, with no range check"
  }

------------------------------------------------------------------------------
-- The rules that rewrite the ops above
------------------------------------------------------------------------------

||| A field of a value an `idr.data.con` built is the field it was given; a
||| constructor rebuilt from every field of a value refined to it is that
||| value (record eta), except where its result's identity is read. Each
||| reads a variadic group by position, so each is a skeleton rule.
export
familySkeleton : List SkeletonRule
familySkeleton =
  [ MkSkeletonRule "FieldOfCon" rules "data.field" "a field of a value idr.data.con built is the field it was given"
  , MkSkeletonRule "ConEta" rules "data.con" "a constructor rebuilt from every field of a value refined to it is that value" ]
  where
    rules : Path
    rules = "idr" ::: ["IR", "Families", "Rules.h"]
