-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The dialect's types and attributes, as declarations: their parameters
||| (indexed by count, so a format names a parameter by its position and
||| cannot name one the declaration lacks), their syntax, their bytecode
||| layout (derived from the parameters, so the reader, the writer and the
||| frontend's encoder cannot disagree), their interfaces and hooks.
module IdrisMLIR.Spec.Core.Types

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Interfaces

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Wires
------------------------------------------------------------------------------

||| One value bytecode lays out as a whole, which the C++ holds as itself: a
||| number of 64 bits; one of 32, a wider one refused by the reader; a case
||| of a closed set of ours, as its position, which the frontend writes
||| typed, from where its source says; a label, a string the C++ holds
||| uniqued; a type or an attribute of a class (`::mlir::Type` or
||| `::mlir::Attribute` for any), or an attribute of a class that may be
||| absent.
public export
data Leaf
  = LeafCount
  | LeafWord32
  | LeafCase ImportedEnum
  | LeafLabel
  | LeafType Code
  | LeafAttr Code
  | LeafMaybeAttr Code

mutual
  ||| How bytecode lays out a part of a value the dialect's parameters
  ||| hold, the C++ reader and writer and the frontend's encoder all
  ||| printed from it, so the three cannot disagree: a leaf; an array, its
  ||| count first, which the C++ holds as a view kept in the arena of the
  ||| read until the storage copies it; or a composite's value.
  public export
  data Wire
    = WireLeaf Leaf
    | WireArray Wire
    | WireOf Composite

  ||| A part of a composite: the C++ member that holds it, whose name the
  ||| frontend's binder takes too, and its wire.
  public export
  data WireField = MkWireField Ident Wire

  ||| How a composite's C++ class holds its parts, which decides their
  ||| layout: a struct of members, each laid out in order; a struct whose
  ||| tag member holds a case of a closed set and whose other members each
  ||| case gives meaning to, laid out as the case's position and then the
  ||| case's members (one list per case, in the set's order, which `flat`
  ||| makes); or a variant whose alternatives are composites in the set's
  ||| order, laid out as the case's position and then the alternative
  ||| (which `variant` makes). The frontend holds such a value as one
  ||| constructor per case, so it never holds the case beside it.
  public export
  data CompositeBody
    = Fields (List WireField)
    | Flat EnumDef Ident (List (List WireField))
    | Variant EnumDef (List Composite)

  ||| A value the dialect's parameters hold, laid out from its parts: its
  ||| name, which its codec and the frontend's type of it take; its C++
  ||| class; how the class holds its parts; and what it is.
  public export
  data Composite = MkComposite Ident Code CompositeBody Doc

public export
fieldName : WireField -> Ident
fieldName (MkWireField n _) = n

public export
fieldWire : WireField -> Wire
fieldWire (MkWireField _ w) = w

public export
compositeName : Composite -> Ident
compositeName (MkComposite n _ _ _) = n

public export
compositeCpp : Composite -> Code
compositeCpp (MkComposite _ c _ _) = c

||| A flat composite's body over a closed set: its tag member, and the
||| members each case gives meaning to, a total function, so a case the set
||| gains without its members does not build.
public export
flat : (c : Closed a) -> (tag : Ident) -> (a -> List WireField) -> CompositeBody
flat c tag fields = Flat (enumDef c) tag (map fields (forget c.every))

||| A variant composite's body over a closed set: each case's alternative,
||| a total function.
public export
variant : (c : Closed a) -> (a -> Composite) -> CompositeBody
variant c alternative = Variant (enumDef c) (map alternative (forget c.every))

||| What a wired parameter holds, as its storage keeps it: an array of a
||| wire's values, read into the arena that keeps every array they view
||| until the storage copies them; or one leaf, which views nothing.
public export
data Wired = WiredArray Wire | WiredOne Leaf

------------------------------------------------------------------------------
-- Parameters
------------------------------------------------------------------------------

||| What a parameter holds, which decides its C++ storage, its syntax and
||| its bytecode member: a type, an attribute, a case of an enum of ours
||| (which the frontend writes typed, from where its source says), a case
||| of one held in a hand class over its cases (the class's spelling), or
||| none, a string, an integer of any width, a 64-bit count, a list of any
||| of these, a C++ value of a hand class (its spelling and the custom
||| directive that reads and writes it), an array of a hand class's
||| elements (the element's spelling and the directive), or a value a wire
||| lays out (its text the directive's, its bytecode printed for both
||| sides from the wire). An array is held as a view and read into the
||| vector that owns its elements until the storage copies them, so no
||| reader interns what it read to have somewhere to keep it. A case held
||| in a class is written as zero for none, else one more than the case's
||| position, by a codec generated for both sides; the class gives its case
||| and is made from one.
public export
data ParamKind
  = TypeValue
  | AttrValue
  | EnumValue ImportedEnum
  | OptionalCase ImportedEnum Code
  | StringValue
  | IntegerValue
  | CountValue
  | ListOf ParamKind
  | HandValue Code Directive
  | HandArray Code Directive
  | WiredValue Wired Directive

||| Whether a parameter is always written, or has a default that the
||| syntax and the encoder leave out: the default's C++ expression.
public export
data Presence = AlwaysWritten | DefaultsTo Code

public export
record Parameter where
  constructor MkParameter
  name : Ident
  kind : ParamKind
  presence : Presence
  doc : Line

------------------------------------------------------------------------------
-- Syntax
------------------------------------------------------------------------------

||| One element of a declarative type or attribute syntax, over `p`
||| parameters: a literal, a parameter, the parameters as a struct, or a
||| custom directive over parameters.
public export
data ParamItem : (p : Nat) -> Type where
  Keyword : Line -> ParamItem p
  ParamAt : Fin p -> ParamItem p
  Struct : List (Fin p) -> ParamItem p
  CustomParams : Directive -> List (Fin p) -> ParamItem p
  OptionalParams : List (ParamItem p) -> ParamItem p

||| A declaration's syntax: declarative over its parameters, or written by
||| hand (its parser and printer a hand unit defines).
public export
data Syntax : (p : Nat) -> Type where
  Declarative : List (ParamItem p) -> Syntax p
  HandSyntax : Syntax p

------------------------------------------------------------------------------
-- Bytecode
------------------------------------------------------------------------------

||| How the dialect's bytecode writes a type or an attribute: its members
||| one per parameter in order, each by its kind, read back through the
||| generated getter; or through a hand builder that checks what it reads
||| (the hand function `fn`, given the reader, the context and the members).
public export
data Bytecode = Derived | CheckedBy Ident

------------------------------------------------------------------------------
-- What a value of a type holds
------------------------------------------------------------------------------

||| Whether a value of the type holds a reference.
public export
data Holding = HoldsReferences | HoldsNoReference

||| Whether every value of the type is used exactly once by its type (a
||| cell, a destination), so no grade is written on it.
public export
data ByType = UsedOnceByType | UsedAsGraded

||| Whether a reference a value holds is counted.
public export
data Counting = Counted | Uncounted

||| Whether a value's word is always a cell's address, or may be another
||| word (a small integer).
public export
data CellWord = AlwaysCell | MayBeOtherWord

||| A type's answers to `ValueFactsTypeInterface`, printed as its methods,
||| so no hand answer restates them.
public export
record ValueFacts where
  constructor MkValueFacts
  holding : Holding
  byType : ByType
  counting : Counting
  word : CellWord

||| Whether a type answers the value facts: none, or its answers.
public export
data TypeFacts = NoValueFacts | Answers ValueFacts

||| The interface every type that answers the value facts takes: what a
||| value of it holds, read by counting, the lifetimes and the lowering.
public export
valueFactsInterface : InterfaceDef
valueFactsInterface = MkInterfaceDef
  { name = MkIdent "ValueFactsTypeInterface" Oh
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (MkCode "bool" Oh) (MkIdent "holdsReferences" Oh) [] EveryImplementer (MkLine "whether a value holds a reference" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isLinearByType" Oh) [] EveryImplementer (MkLine "whether every value is used exactly once by its type" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isCounted" Oh) [] EveryImplementer (MkLine "whether a reference a value holds is counted" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isCellPointer" Oh) [] EveryImplementer (MkLine "whether a value's word is always a cell's address" Oh)
      ]
  , verifier = Unverified
  , doc = MkDoc (MkLine "what a value of a type holds" Oh) (MkProse "" Oh)
  }

------------------------------------------------------------------------------
-- Declarations
------------------------------------------------------------------------------

||| Whether a type or an attribute verifies its parameters (a hand
||| `verify`).
public export
data ParamVerifier = AnyParameters | VerifiesParameters

||| Where a type's or an attribute's storage comes from: ODS's, holding its
||| parameters alone; or a hand class, `::idr::detail::<Class>Storage`,
||| which keeps beside its key what is computed of it when it is made, so no
||| reader computes it again.
public export
data Storage = GeneratedStorage | HandStorage

||| A type of the dialect, its C++ class `<Camel>Type` from its mnemonic:
||| `!idr.graded` is `GradedType`.
public export
record TypeDef (p : Nat) where
  constructor MkTypeDef
  mnemonic : Mnemonic
  params : Vect p Parameter
  syntax : Syntax p
  interfaces : List InterfaceUse
  verifier : ParamVerifier
  bytecode : Bytecode
  {default GeneratedStorage storage : Storage}
  members : List Member
  facts : TypeFacts
  doc : Doc

||| An attribute of the dialect, its C++ class `<Camel>Attr`: `#idr.family`
||| is `FamilyAttr`. A typed attribute names the parameter that is its
||| type.
public export
data Typed : (p : Nat) -> Type where
  Untyped : Typed p
  TypedBy : Fin p -> Typed p

public export
record AttrDef (p : Nat) where
  constructor MkAttrDef
  mnemonic : Mnemonic
  params : Vect p Parameter
  syntax : Syntax p
  typed : Typed p
  interfaces : List InterfaceUse
  verifier : ParamVerifier
  bytecode : Bytecode
  {default GeneratedStorage storage : Storage}
  members : List Member
  doc : Doc

||| A type of any arity, as a list of the dialect's holds them.
public export
data AnyTypeDef : Type where
  SomeType : {0 p : Nat} -> TypeDef p -> AnyTypeDef

public export
data AnyAttrDef : Type where
  SomeAttr : {0 p : Nat} -> AttrDef p -> AnyAttrDef

||| A type's C++ class: ODS's default from its mnemonic.
public export
typeClass : TypeDef p -> String
typeClass t = camelMnemonic t.mnemonic ++ "Type"

public export
attrClass : AttrDef p -> String
attrClass a = camelMnemonic a.mnemonic ++ "Attr"
