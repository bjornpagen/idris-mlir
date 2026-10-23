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
import Data.List.Elem
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

||| Whether reading a value keeps an array, which then needs an arena that
||| outlives the reading: a composite whose parts hold none is read without
||| one.
public export
data Keeping = KeepsArrays | KeepsNothing

||| What two parts' readings keep together.
public export
keepingOfBoth : Keeping -> Keeping -> Keeping
keepingOfBoth KeepsNothing k = k
keepingOfBoth KeepsArrays _ = KeepsArrays

mutual
  public export
  wireKeeping : Wire -> Keeping
  wireKeeping (WireLeaf _) = KeepsNothing
  wireKeeping (WireArray _) = KeepsArrays
  wireKeeping (WireOf (MkComposite _ _ b _)) = bodyKeeping b

  public export
  bodyKeeping : CompositeBody -> Keeping
  bodyKeeping (Fields fs) = fieldsKeeping fs
  bodyKeeping (Flat _ _ cases) = casesKeeping cases
  bodyKeeping (Variant _ alternatives) = alternativesKeeping alternatives

  public export
  fieldsKeeping : List WireField -> Keeping
  fieldsKeeping [] = KeepsNothing
  fieldsKeeping (MkWireField _ w :: fs) = keepingOfBoth (wireKeeping w) (fieldsKeeping fs)

  public export
  casesKeeping : List (List WireField) -> Keeping
  casesKeeping [] = KeepsNothing
  casesKeeping (fs :: rest) = keepingOfBoth (fieldsKeeping fs) (casesKeeping rest)

  public export
  alternativesKeeping : List Composite -> Keeping
  alternativesKeeping [] = KeepsNothing
  alternativesKeeping (MkComposite _ _ b _ :: rest) = keepingOfBoth (bodyKeeping b) (alternativesKeeping rest)

||| Whether reading a composite keeps an array.
public export
compositeKeeping : Composite -> Keeping
compositeKeeping (MkComposite _ _ b _) = bodyKeeping b

||| What a wired parameter holds, as its storage keeps it: an array of a
||| wire's values, read into the arena that keeps every array they view
||| until the storage copies them; one leaf, which views nothing; or one
||| composite's value, held and read as its C++ class (a struct, a flat
||| struct over a closed set, or a variant whose alternatives carry fields
||| or none), which holds no array, so it too views nothing and its reading
||| needs no arena.
public export
data Wired : Type where
  WiredArray : Wire -> Wired
  WiredOne : Leaf -> Wired
  WiredOf : (c : Composite) -> {auto 0 viewsNothing : compositeKeeping c = KeepsNothing} -> Wired

------------------------------------------------------------------------------
-- Parameters
------------------------------------------------------------------------------

||| What a parameter holds, which decides its C++ storage, its syntax and
||| its bytecode member: a type, an attribute, a case of an enum of ours
||| (which the frontend writes typed, from where its source says), a case
||| of one held in a hand class over its cases (the class's spelling), or
||| none, a string, an integer of any width, a 64-bit count, a list of any
||| of these, or a value a wire lays out (its text the directive's, its
||| bytecode printed for both sides from the wire). An array is held as a view and read into the vector that owns
||| its elements until the storage copies them, so no reader interns what
||| it read to have somewhere to keep it. A case held
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

||| How the parser tells an optional group's two forms apart: by a literal
||| the group begins with where its anchor holds other than its default
||| (`(`,` $held^)?`), or by one printed alone where it holds its default
||| (`(`)`) : ($inputs^ `)`)?`). Either way the form read first begins with
||| a literal, the one thing upstream's parser can look for to choose.
public export
data GroupLead = BeginsWith Line | AloneAtDefault Line

||| One element of a declarative type or attribute syntax, over `p`
||| parameters: a literal, a parameter, the parameters as a struct, a custom
||| directive over parameters, or an optional group: its anchor, a parameter
||| with a default, and the items after it, printed where the anchor holds
||| other than its default, so a list whose default is empty prints as
||| nothing where it is empty and parses back.
public export
data ParamItem : (p : Nat) -> Type where
  Keyword : Line -> ParamItem p
  ParamAt : Fin p -> ParamItem p
  Struct : List (Fin p) -> ParamItem p
  CustomParams : Directive -> List (Fin p) -> ParamItem p
  OptionalParams : GroupLead -> (anchor : Fin p) -> (after : List (ParamItem p)) -> ParamItem p

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

||| How a type fixes its values' uses: each exactly once (a cell, a
||| destination), or freely, never consumed (a lifetime), so no grade is
||| written on it; or as the grade a value carries says.
public export
data ByType = UsedOnceByType | UsedFreelyByType | UsedAsGraded

||| The closed set of `ByType`, printed as the C++ enum the value facts
||| answer in.
export
byTypeClosed : Closed ByType
byTypeClosed = MkClosed
  { name = ident "ByType"
  , shape = OneOf
  , every = UsedOnceByType ::: [UsedFreelyByType, UsedAsGraded]
  , complete = \case
      UsedOnceByType => Here
      UsedFreelyByType => There Here
      UsedAsGraded => There (There Here)
  , describe = \case
      UsedOnceByType => MkCase (ident "UsedOnceByType") (word "once" ::: []) (line "every value is used exactly once, by its type")
      UsedFreelyByType => MkCase (ident "UsedFreelyByType") (word "freely" ::: []) (line "no value is consumed: each is used any number of times, by its type")
      UsedAsGraded => MkCase (ident "UsedAsGraded") (word "graded" ::: []) (line "each value is used as its grade says")
  , doc = brief (line "how a type fixes its values' uses")
  }

||| Whether a reference a value holds is counted.
public export
data Counting = Counted | Uncounted

||| Whether a value's word is always a cell's address, or may be another
||| word (a small integer).
public export
data CellWord = AlwaysCell | MayBeOtherWord

||| What every value of a type is at run time, where the type's parameters
||| decide nothing: one pointer no count is kept of (a cell before its
||| init, a package), one cell's address (a string, a closure, a
||| suspension), or one big's word of 64 bits, a small integer or a cell's
||| address (an Integer, a natural).
public export
data RunTimeWord = UncountedPointer | CellAddress | BigWord

||| What a value of a type carries for the label solve besides the
||| reference it holds: no label, or the labels of a closure or of a
||| suspension, which are cells, so only a type that holds references
||| carries them.
public export
data Labels : Holding -> Type where
  NoLabels : Labels holding
  ClosureLabels : Labels HoldsReferences
  SuspensionLabels : Labels HoldsReferences

||| Whether a value of a type is a cell's memory, what counting builds a
||| constructor into and a test of sharing gives for what it took apart (a
||| cell before its init, a reuse token), or a value.
public export
data Memory = CellMemory | NotMemory

||| One answer of a type to the value facts: the same for every value of
||| it, which the generator prints as the method's body; or one its
||| parameters decide (a lifetime's words are its kind's, a cell's labels
||| its value's), which a hand unit defines.
public export
data Answer a = Always a | ByParameters

||| A type's answers to `ValueFactsTypeInterface`, printed as its methods,
||| so no hand answer restates them.
public export
record ValueFacts where
  constructor MkValueFacts
  holding : Holding
  byType : ByType
  counting : Counting
  word : CellWord
  words : Answer RunTimeWord
  labels : Answer (Labels holding)
  memory : Memory

||| Whether a type answers the value facts: none; its answers, each the same
||| for every value of it, which the generator prints as the method's body,
||| or one its parameters decide, which a hand unit defines; or answers all
||| computed from its parameters (a grade's are its carrier's, a data type's
||| its family's), which a hand unit defines. A type that answers
||| takes the interface through this field alone, its methods declared on its
||| class by ODS, so no type lists the interface or restates its methods.
public export
data TypeFacts = NoValueFacts | Answers ValueFacts | HandAnswers

||| The interface every type that answers the value facts takes, through its
||| facts: what a value of it holds, what it is at run time, what it carries
||| where it moves and whether it is a cell's memory, read by counting, the
||| lifetimes, the label solve and the lowering, so none of them tests a
||| type's class.
public export
valueFactsInterface : InterfaceDef
valueFactsInterface = MkInterfaceDef
  { name = MkIdent "ValueFactsTypeInterface" Oh
  , subject = OverTypes
  , bases = []
  , methods =
      [ MkMethod PerObject (MkCode "bool" Oh) (MkIdent "holdsReferences" Oh) [] EveryImplementer (MkLine "whether a value holds a reference" Oh)
      , MkMethod PerObject (MkCode "::idr::ByType" Oh) (MkIdent "getByType" Oh) [] EveryImplementer (MkLine "how the type fixes its values' uses: once, freely, or as their grade says" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isCounted" Oh) [] EveryImplementer (MkLine "whether a reference a value holds is counted" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isCellPointer" Oh) [] EveryImplementer (MkLine "whether a value's word is always a cell's address" Oh)
      , MkMethod PerObject (MkCode "::idr::RunTimeWords" Oh) (MkIdent "getRunTimeWords" Oh)
          [MkParam (MkCode "::std::optional<::idr::Hold>" Oh) (MkIdent "hold" Oh)] EveryImplementer
          (MkLine "what a value is at run time, its words, held at `hold` where a grade around it says so" Oh)
      , MkMethod PerObject (MkCode "::idr::Carrying" Oh) (MkIdent "getCarrying" Oh) [] EveryImplementer
          (MkLine "what a value carries where it moves: a closure's or a suspension's labels, a counted reference alone, or nothing" Oh)
      , MkMethod PerObject (MkCode "bool" Oh) (MkIdent "isCellMemory" Oh) [] EveryImplementer
          (MkLine "whether a value is a cell's memory: a cell before its init, or a reuse token" Oh)
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
