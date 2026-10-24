-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The dialect's own interfaces and traits: shared shape over ops, types
||| and attributes is MLIR's dispatch (an interface or a trait), declared
||| here and implemented by hand. A method's signature is C++ the
||| specification cannot type; its default, when it has one, is a call of a
||| hand function the specification names, never a body.
module IdrisMLIR.Spec.Core.Interfaces

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Upstream

%default total

||| What an interface is over.
public export
data InterfaceSubject = OverOps | OverTypes | OverAttributes

||| A method needs an object.
public export
data MethodBinding = PerObject

||| What a method does when its implementer says nothing: every implementer
||| defines it; it calls the hand function `fn` with the object (an op as an
||| `Operation *`, a type, an attribute) and the method's arguments, which
||| the generator declares; or it calls the hand function template `fn` with
||| the op as its own class, which a hand header declares before the
||| interface, since only a template keeps the class the default is
||| instantiated for, and the generator declares nothing.
public export
data MethodDefault = EveryImplementer | Delegates Ident | DelegatesByClass Ident

public export
record Method where
  constructor MkMethod
  binding : MethodBinding
  result : Code
  name : Ident
  params : List Param
  fallback : MethodDefault
  doc : Line

||| The interface's own verifier, a hand function run once the op's
||| regions are verified, or none.
public export
data InterfaceVerifier = Unverified | Verifies Ident

||| An interface of the dialect's: its C++ name in `::idr`, what it is
||| over, its bases (interfaces of ours it extends), its methods.
public export
record InterfaceDef where
  constructor MkInterfaceDef
  name : Ident
  subject : InterfaceSubject
  bases : List InterfaceDef
  methods : List Method
  verifier : InterfaceVerifier
  doc : Doc

||| A trait of ours: a C++ class template in `::idr` a hand header defines,
||| its op's base. Whether it verifies is its C++ class's (`verifyTrait`).
public export
record TraitDef where
  constructor MkTraitDef
  name : Ident
  doc : Doc

||| An op whose result is its operand's value at whatever grade the result
||| has, which a pass looks through: an op that only changes a grade.
public export
resultCarriesOperand : TraitDef
resultCarriesOperand = MkTraitDef (MkIdent "ResultCarriesOperand" Oh)
  (MkDoc (MkLine "the result is the operand's value, at whatever grade the result has" Oh) (MkProse "" Oh))

||| A grade op whose result keeps its operand's identity and exclusivity,
||| which a value's source looks through.
public export
sameValue : TraitDef
sameValue = MkTraitDef (MkIdent "SameValue" Oh)
  (MkDoc (MkLine "the result is the operand's value, its identity and exclusivity kept" Oh) (MkProse "" Oh))

||| An op that eliminates its first operand, and does nothing else with it:
||| a match on a closure sum, a read of one's field, a string's output. Two
||| readers find it by this trait rather than by naming each op: raising,
||| where it ends the chain of single uses raising moves into a clone of the
||| callee building the operand; and the string lowering, where it is the
||| output of a string made only to be written, which the lowering writes
||| from the string's maker instead. That lowering knows one output of a
||| string, so the generator refuses a second op that eliminates a string.
public export
eliminatesOperand : TraitDef
eliminatesOperand = MkTraitDef (MkIdent "EliminatesOperand" Oh)
  (MkDoc (MkLine "the op eliminates its first operand, and does nothing else with it" Oh) (MkProse "" Oh))

||| How an op's result is built of its operands: a constructor of its
||| fields, or a natural's successor or predecessor of another, or none of
||| these where the op runs (a sum neither of whose operands is a constant
||| one). A reader that looks through construction asks the op and folds
||| the answer, a closed sum (`::idr::Structure`, which the traits' header
||| declares before the interfaces), so it names no op, and an op that
||| gains a structure joins every reader by implementing this.
public export
structureInterface : InterfaceDef
structureInterface = MkInterfaceDef
  { name = ident "StructureOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::Structure") (ident "getStructure") [] EveryImplementer
          (line "how its result is built of its operands: a constructor of its fields, a natural's successor or predecessor of one, or none of these") ]
  , verifier = Unverified
  , doc = brief (line "an op whose result may be built of its operands by a constructor or a natural's successor or predecessor")
  }

||| The questions the C++ asked by a chain of tests over our own ops, types
||| and attributes, each now one method its subject answers, so a reader
||| asks the interface and names no class. The vocabulary their signatures
||| name is the hand header `idr/IR/Interfaces/Vocabulary.h`, which the
||| dialect's header includes before the interfaces.

||| `IndexedTypeInterface`: the index terms a type names directly, and how a
||| walk over a scope reads it: the levels those terms leave free, the group
||| member it names by position, and whether its parts must still be walked.
public export
indexedTypeInterface : InterfaceDef
indexedTypeInterface = MkInterfaceDef
  { name = ident "IndexedTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::llvm::SmallVector<::llvm::ArrayRef<::idr::families::TermNode>, 2>") (ident "getIndexTermRuns") [] EveryImplementer
          (line "the runs of index terms this type names directly, each whole terms one after the other, not those of its parts")
      , MkMethod PerObject (code "std::uint32_t") (ident "getFreeLevels") [] (Delegates (ident "freeLevelsOfTerms"))
          (line "how many index levels the terms it names leave free")
      , MkMethod PerObject (code "std::optional<std::uint32_t>") (ident "getPositionalMember") [] (Delegates (ident "noPositionalMember"))
          (line "the member of the group being declared that it names by position; none for a type that names none")
      , MkMethod PerObject (code "bool") (ident "scopeHoldsParts") [] (Delegates (ident "scopeHoldsEveryPart"))
          (line "whether a walk over a scope must still read its parts: false where its own fact already holds what they name") ]
  , verifier = Unverified
  , doc = brief (line "the index terms a type names, and how a scope's walk reads it")
  }

||| `IndexPositionsTypeInterface`: the index positions a value type is keyed
||| by, which defunctionalization reads to key a type by where its terms
||| stand: their sorts and terms, and the type with each at a fresh level.
public export
indexPositionsInterface : InterfaceDef
indexPositionsInterface = MkInterfaceDef
  { name = ident "IndexPositionsTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "void") (ident "appendIndexPositions")
          [ param (code "::llvm::SmallVectorImpl<::idr::families::Sort> &") (ident "sorts")
          , param (code "::llvm::SmallVectorImpl<::idr::families::TermNode> &") (ident "nodes") ]
          EveryImplementer
          (line "appends the sorts of the index terms this type is keyed by, and the terms, in one order")
      , MkMethod PerObject (code "::mlir::Type") (ident "atFreshPositions")
          [param (code "::llvm::function_ref<::idr::families::TermNode()>") (ident "next")] EveryImplementer
          (line "this type with each index term it is keyed by the next fresh level, its refinement kept") ]
  , verifier = Unverified
  , doc = brief (line "the index positions a value type is keyed by")
  }

||| `PatternTypeInterface`: how a pattern type matches an instance of its
||| own class, given the match in progress, which compares terms and queues
||| the parts it pairs. A type without it matches part by part.
public export
patternTypeInterface : InterfaceDef
patternTypeInterface = MkInterfaceDef
  { name = ident "PatternTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "bool") (ident "matchInstance")
          [param (code "::mlir::Type") (ident "instance"), param (code "::idr::families::PatternMatch &") (ident "match")]
          EveryImplementer
          (line "whether this pattern matches `instance`, a type of the same class, queueing in `match` the parts that must match too") ]
  , verifier = Unverified
  , doc = brief (line "how a pattern type matches an instance of its class")
  }

||| `FieldTypeInterface`: what a field of a type reaches, which decides how
||| a read of it is held.
public export
fieldTypeInterface : InterfaceDef
fieldTypeInterface = MkInterfaceDef
  { name = ident "FieldTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::FieldReach") (ident "getFieldReach") [] EveryImplementer
          (line "what a field of this type reaches") ]
  , verifier = Unverified
  , doc = brief (line "what a field of a type reaches")
  }

||| `NumericTypeInterface`: how a type's values are read as numbers, and
||| whether they are Integers the big ops take.
public export
numericTypeInterface : InterfaceDef
numericTypeInterface = MkInterfaceDef
  { name = ident "NumericTypeInterface"
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::NumericReading") (ident "getNumericReading") [] EveryImplementer
          (line "how a value of this type is read as a number")
      , MkMethod PerObject (code "bool") (ident "isCarriedAsBig") [] EveryImplementer
          (line "whether a value of this type is an Integer the big ops take, its constant a #idr.big") ]
  , verifier = Unverified
  , doc = brief (line "how a type's values are read as numbers")
  }

||| `ConstantAttrInterface`: a constant value, at which types idr.constant
||| holds it, how it is laid out as static data, that it agrees with what it
||| names, how it holds closures, and what a fold reads of it. Ours take it
||| in their declarations; upstream's strings, integers and floats, which a
||| constant's fields and static data hold, take it as external models, so
||| no reader names one. The layout, the closures and the fold's value are
||| closed sums (`::idr::StaticForm`, `::idr::ClosureHolding`,
||| `::idr::FoldValue`), which the vocabulary's header defines before the
||| interfaces, each attribute or type they hold by a handle complete before
||| its class, so a writer of static data, a reader that walks a constant's
||| closures and the e-graph reading a constant fold the answer and name no
||| attribute.
public export
constantAttrInterface : InterfaceDef
constantAttrInterface = MkInterfaceDef
  { name = ident "ConstantAttrInterface"
  , subject = OverAttributes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "bool") (ident "isBuildableAt") [param (code "::mlir::Type") (ident "type")] EveryImplementer
          (line "whether idr.constant holds this value at `type`")
      , MkMethod PerObject (code "::idr::StaticForm") (ident "getStaticForm") [param (code "::mlir::Type") (ident "held")] EveryImplementer
          (line "how this value, held at `held`, is laid out as static data")
      , MkMethod PerObject (code "::mlir::LogicalResult") (ident "verifyParts")
          [ param (code "::mlir::Operation *") (ident "holder")
          , param (code "::mlir::SymbolTableCollection &") (ident "symbols")
          , param (code "::mlir::Type") (ident "type")
          , param (code "::llvm::function_ref<void(::mlir::Attribute, ::mlir::Type)>") (ident "part") ]
          EveryImplementer
          (line "that this value, held at `type` by `holder`, agrees with what it names (a constructor's cells, a closure's function), handing each of its parts to `part` at the type it is checked at; a big, a string, an integer and a float have none")
      , MkMethod PerObject (code "::idr::ClosureHolding") (ident "getClosureHolding") [] EveryImplementer
          (line "how this value holds closures: a closure is one, a constructor holds those of its fields, any other holds none")
      , MkMethod PerObject (code "::idr::FoldValue") (ident "getFoldValue") [] EveryImplementer
          (line "what a fold reads of this value: an integer, a Double, a string or a big, or a constructor or closure whole; nothing of a float of another width") ]
  , verifier = Unverified
  , doc = brief (line "a constant value, and how it is held, laid out and read by a fold")
  }

||| `IntegerKeyAttrInterface`: a key of ours whose value is an integer.
public export
integerKeyAttrInterface : InterfaceDef
integerKeyAttrInterface = MkInterfaceDef
  { name = ident "IntegerKeyAttrInterface"
  , subject = OverAttributes
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::llvm::APInt") (ident "getKeyInteger") [] EveryImplementer
          (line "the integer this key is") ]
  , verifier = Unverified
  , doc = brief (line "a key whose value is an integer")
  }

||| `ReuseSourceOpInterface`: an op at which a cell may become free, and how
||| its token is made available there.
public export
reuseSourceInterface : InterfaceDef
reuseSourceInterface = MkInterfaceDef
  { name = ident "ReuseSourceOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::DataType") (ident "getFreedCellType") [] EveryImplementer
          (line "the data type, refined to its one constructor, whose cell may become free here; null where none may")
      , MkMethod PerObject (code "::mlir::Value") (ident "takeFreedToken") [param (code "::mlir::OpBuilder &") (ident "builder")] EveryImplementer
          (line "makes the freed cell's token available where the builder stands, right after the op, and gives it; the builder is left right after what stands in the op's place") ]
  , verifier = Unverified
  , doc = brief (line "an op at which a cell may become free")
  }

||| `ReuseSinkOpInterface`: an op that fills a fresh cell, which a token
||| freed before it may supply.
public export
reuseSinkInterface : InterfaceDef
reuseSinkInterface = MkInterfaceDef
  { name = ident "ReuseSinkOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::CellType") (ident "getFilledCellType") [] EveryImplementer
          (line "the cell this op fills") ]
  , verifier = Unverified
  , doc = brief (line "an op that fills a fresh cell")
  }

||| `LifetimeUseOpInterface`: how an op uses a lifetime it takes, and its own
||| rule against the lifetimes open where it stands. An op without it only
||| names the lifetime.
public export
lifetimeUseInterface : InterfaceDef
lifetimeUseInterface = MkInterfaceDef
  { name = ident "LifetimeUseOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::LifetimeUse") (ident "getLifetimeUse")
          [param (code "::mlir::OpOperand &") (ident "lifetime")] (Delegates (ident "namesLifetime"))
          (line "how this op uses the lifetime `lifetime` holds")
      , MkMethod PerObject (code "::mlir::LogicalResult") (ident "verifyLifetimeUse")
          [param (code "const ::idr::OpenLifetimes &") (ident "open")] (Delegates (ident "acceptsLifetimeUse"))
          (line "this op's own rule against the lifetimes open where it stands") ]
  , verifier = Unverified
  , doc = brief (line "how an op uses a lifetime it takes")
  }

||| `CursorBinderOpInterface`: an op that binds a lifetime extending a
||| cursor's base, the cursor read from the op's own class.
public export
cursorBinderInterface : InterfaceDef
cursorBinderInterface = MkInterfaceDef
  { name = ident "CursorBinderOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::mlir::Value") (ident "getCursorBase") [] (DelegatesByClass (ident "cursorBaseOfOp"))
          (line "the cursor whose base the lifetime this op binds extends") ]
  , verifier = Unverified
  , doc = brief (line "an op that binds a lifetime extending a cursor's base")
  }

||| `ScopeRuleOpInterface`: what an op asks of the scope of index variables
||| where it stands, beyond its values' types, which the function's scope
||| walk checks everywhere: a cast's two types one under the refinements
||| around it, a jump's arguments its target's parameters at its terms.
public export
scopeRuleInterface : InterfaceDef
scopeRuleInterface = MkInterfaceDef
  { name = ident "ScopeRuleOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::mlir::LogicalResult") (ident "verifyScopeRule")
          [param (code "::idr::families::ScopeQuery &") (ident "scope")] EveryImplementer
          (line "this op's own rule against the scope where it stands") ]
  , verifier = Unverified
  , doc = brief (line "what an op asks of the scope of index variables where it stands")
  }

||| `ValueSourceOpInterface`: what a value an op makes is made of: the same
||| value as one it takes, a field of a value refined to one constructor, or
||| made here.
public export
valueSourceInterface : InterfaceDef
valueSourceInterface = MkInterfaceDef
  { name = ident "ValueSourceOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::Source") (ident "getValueSource") [param (code "::mlir::Value") (ident "made")] EveryImplementer
          (line "what `made`, a result of this op or an argument of one of its regions, is made of: the same value as one it takes, a field of a value refined to one constructor, or made here") ]
  , verifier = Unverified
  , doc = brief (line "an op that makes a value that is another value, or a field of one")
  }

||| Which methods an op that infers its result types defines, in upstream's
||| adaptor form, the one form our ops take: `inferReturnTypes` given the
||| op's adaptor alone; or, for an op whose results may hold types other
||| than the inferred ones, `isCompatibleReturnTypes` beside it.
public export
data Compatibility = InferredOnly | AlsoCompatible

||| How a declaration takes an interface: upstream's or ours, with the
||| methods its class declares and a hand unit defines (none when every
||| method has a default it keeps); or upstream's type inference, whose
||| methods its form fixes.
public export
data InterfaceUse
  = Declares UpInterface (List Ident)
  | Implements InterfaceDef (List Ident)
  | InfersTypes Compatibility
