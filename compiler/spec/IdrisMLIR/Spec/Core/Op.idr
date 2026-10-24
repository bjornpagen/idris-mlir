-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| An op of the dialect, as one value: indexed by its operand, result,
||| attribute and region group counts, so every reference inside it (its
||| format, its effects, its guards, its runtime call, its grade rule) is a
||| position it has, and no name is looked up. A family of ops is a function
||| of the family's constants; each member is that function applied, so a
||| member cannot lose its family's facts. Its C++ class is ODS's default
||| from its mnemonic: `idr.str.length` is `StrLengthOp`.
module IdrisMLIR.Spec.Core.Op

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Dialect
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Upstream
import IdrisMLIR.Spec.Core.Interfaces
import IdrisMLIR.Spec.Core.Constraints
import IdrisMLIR.Spec.Core.Format
import IdrisMLIR.Spec.Core.Ods
import IdrisMLIR.Spec.Core.Admitted
import IdrisMLIR.Spec.Pipeline.Stage
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings

import Data.Fin
import Data.List
import Data.List1
-- An op's automatic `So` proof of distinct names is searched where the op is written.
import public Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------------

||| How many values a group holds: one, one or none, or any number.
public export
data Arity = Single | Optional | Variadic

public export
record Operand where
  constructor MkOperand
  name : Ident
  arity : Arity
  type : TypeC

public export
record Result where
  constructor MkResult
  name : Ident
  arity : Arity
  type : TypeC

||| One operand, one result.
public export
single : Ident -> TypeC -> Operand
single n t = MkOperand n Single t

||| One operand or none.
public export
optional : Ident -> TypeC -> Operand
optional n t = MkOperand n Optional t

||| Any number of operands.
public export
variadic : Ident -> TypeC -> Operand
variadic n t = MkOperand n Variadic t

public export
result : Ident -> TypeC -> Result
result n t = MkResult n Single t

public export
results : Ident -> TypeC -> Result
results n t = MkResult n Variadic t

||| Whether an op's operand or result groups need their sizes stated: each
||| holds what its count says, or more than one may hold any number (an
||| optional group or a variadic one), so the count alone cannot tell where
||| one ends, and the op carries each group's size (upstream's segment
||| sizes). The groups decide it, so no op declares it beside them.
public export
data Segments = FixedByCount | SizesStated

public export
segmentsOf : List Arity -> Segments
segmentsOf as = case filter unfixed as of
  (_ :: _ :: _) => SizesStated
  _ => FixedByCount
  where
    unfixed : Arity -> Bool
    unfixed Single = False
    unfixed Optional = True
    unfixed Variadic = True

||| How an attribute is present: always, possibly not, or with a default
||| when not written: its C++ expression, which for one of our attributes
||| is the attribute itself, built in full.
public export
data AttrPresence = Required | MayBeAbsent | DefaultValued Code

||| An inherent attribute, or a property: an op's configuration is one of
||| these, never a discardable attribute, which a pass could drop.
public export
data AttrKind = AnAttribute AttrC AttrPresence | AProperty PropertyC

public export
record Attr where
  constructor MkAttr
  name : Ident
  kind : AttrKind

public export
attr : Ident -> AttrC -> Attr
attr n c = MkAttr n (AnAttribute c Required)

public export
property : Ident -> PropertyC -> Attr
property n c = MkAttr n (AProperty c)

||| How many regions a group holds.
public export
data RegionArity = OneRegion | AnyRegions

||| How many blocks each region of a group may have: any number, a fixed
||| number (one, for a scope), or at most a number.
public export
data Blocks = AnyBlocks | Sized Nat | AtMost Nat

public export
record Region where
  constructor MkRegion
  name : Ident
  arity : RegionArity
  blocks : Blocks

||| A region of `n` blocks.
public export
sized : Ident -> Nat -> Region
sized n k = MkRegion n OneRegion (Sized k)

||| Any number of regions of `n` blocks each.
public export
sizedRegions : Ident -> Nat -> Region
sizedRegions n k = MkRegion n AnyRegions (Sized k)

------------------------------------------------------------------------------
-- What an op is besides its groups
------------------------------------------------------------------------------

||| Where an op of ours is defined: in the dialect, or in upstream's
||| transform dialect as an extension, its class named there (its record's
||| name is its class, as upstream's extensions write it).
public export
data Home = InIdr | InTransform CppName

||| The dialect an op of ours is defined in, which its name is under.
public export
homeDialect : Home -> Dialect
homeDialect InIdr = Idr
homeDialect (InTransform _) = Transform

||| Another op of the dialect named by an op's trait: by its mnemonic,
||| whose class is ODS's default. A name, since two ops may name each other
||| (a match and its yield), which values cannot.
public export
OpRef : Type
OpRef = Mnemonic

||| An op's class from a reference.
public export
opRefClass : OpRef -> String
opRefClass m = camelMnemonic m ++ "Op"

||| A trait: upstream's, ours, one that names other ops, or the grade's rule
||| over the op's groups. Commutativity and its kin are laws (below), from
||| which their traits are printed; speculation and memory effects have
||| their own fields.
public export
data Trait : (i, o : Nat) -> Type where
  Terminator : Trait i o
  ReturnLike : Trait i o
  IsolatedFromAbove : Trait i o
  SingleBlock : Trait i o
  NoTerminator : Trait i o
  NoRegionArguments : Trait i o
  SymbolTable : Trait i o
  SymbolOp : Trait i o
  ||| A symbol whose name is its `sym_name` attribute: upstream's trait gives
  ||| the name accessors the symbol interface asks for from it.
  SymbolName : Trait i o
  AffineScope : Trait i o
  AutomaticAllocationScope : Trait i o
  ConstantLike : Trait i o
  SameOperandsAndResultType : Trait i o
  ||| Every operand holds one carrier, each at whatever grade it has: a
  ||| literal held static beside a counted value, or a small beside a big,
  ||| is one Integer. Upstream's `SameTypeOperands` compares grades too;
  ||| this compares `unrestricted` types, printed as upstream's predicate
  ||| trait over the operands, each a group of one.
  SameCarrierOperands : Trait i o
  PropagateControlFlowBreak : Trait i o
  ReportTrackingListenerFailures : Trait i o
  ||| An op whose results or region arguments may be upstream's `token`.
  TokenProducer : Trait i o
  ||| An op whose operands may be upstream's `token`.
  TokenConsumer : Trait i o
  ||| An op whose nested regions end only in the named terminators.
  HasNestedTerminator : List1 OpRef -> Trait i o
  OurTrait : TraitDef -> Trait i o
  HasParent : List1 OpRef -> Trait i o
  ||| A parent outside the dialect, by its class: `::mlir::ModuleOp`.
  HasUpstreamParent : CppName -> Trait i o
  ImplicitTerminator : OpRef -> Trait i o
  ||| The result is used once exactly when one of the operands is (a
  ||| closure over a linear capture is linear): the grade's own rule over
  ||| the op's groups, printed to the C++ check and to the frontend's
  ||| builder, which computes the result's grade from it.
  ResultUsesMaxOf : (res : Fin o) -> (from : List (Fin i)) -> Trait i o

||| Whether an op may be moved where it would not have run: never, always,
||| when its regions are, or as a hand method decides from its operands.
public export
data Speculation = NotSpeculatable | AlwaysSpeculatable | RecursivelySpeculatable | Conditionally

||| What an op's hand verifier checks: nothing beyond its declaration, the
||| op alone, its regions once verified, or both.
public export
data Verify = DeclarationOnly | VerifiesOp | VerifiesRegions | VerifiesOpAndRegions

||| The meaning of an op, one sum (one meaning, held once): a runtime
||| function with effects, never folded; one such function per case of an
||| enum the op's variant is (an `io.clock <kind>`: each case's symbol is the
||| call's stem and the case's spelling, the runtime's entries one template
||| instantiated per case); a pure runtime function, which the folder
||| computes by calling it; an inline operation whose one meaning is a C++
||| template generic over a numeric domain (the hand function object `fn`
||| of `Numeric/Inline.h`); a guard whose condition is such a meaning (its
||| operand passes where the condition holds, which its hand folder and
||| every reader of intervals ask of the one template); a hand folder; or no
||| fold.
public export
data Meaning : (i, o : Nat) -> Type where
  CallsRuntime : RuntimeCall i o -> Meaning i o
  CallsRuntimeByCase : EnumDef -> RuntimeCall i o -> Meaning i o
  ComputedByRuntime : RuntimeCall i o -> Meaning i o
  Inline : (fn : Ident) -> Meaning i o
  InlineCondition : (fn : Ident) -> Meaning i o
  HandFolder : Meaning i o
  NoFold : Meaning i o

||| A constant a law names: an integer, or a string (the empty string is
||| `str.append`'s identity). Written as a literal of either kind.
public export
data LawConstant = IntegerConstant Integer | StringConstant String

namespace LawConstant
  public export
  fromInteger : Integer -> LawConstant
  fromInteger = IntegerConstant

  public export
  fromString : String -> LawConstant
  fromString = StringConstant

  ||| A negative integer literal's constant, its magnitude an integer.
  public export
  negate : Integer -> LawConstant
  negate i = IntegerConstant (negate i)

||| A law of an op, from which the e-graph's rules are generated, each
||| one-way and narrowly triggered (a law whose only rule would connect
||| equal forms both ways gives none), and the accumulator's operations;
||| the traits upstream has for them are printed from them too. A rule's
||| literal is a value of the op's integers, so an identity that is a
||| string gives the accumulator its start and no rule.
public export
data Law = Associative | Commutative | Idempotent | Involution | Identity LawConstant | Annihilator Integer

||| Whether ODS writes an op's default builders, besides its declared ones.
public export
data DefaultBuilders = WithDefaults | DeclaredOnly

||| A builder the op's class declares and a hand unit defines.
public export
record Builder where
  constructor MkBuilder
  params : List Param

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| The check a guard makes, one case per guard op. A guard names its check
||| by this and not by its op's value: a reader of a guard's condition (the
||| test harness's oracle among them) matches on the kind, total, where an
||| op could be told apart only by its mnemonic; `guardOpOf`, beside the
||| guard ops, maps each kind to its op by one total function.
public export
data GuardKind = NonZero | InBounds | NonEmpty | Finite | Range | HoldsString | Byte

||| How many operands a guard's op takes besides the one it checks: an index
||| is checked against what it indexes, a byte offset against the count of
||| bytes from it and the size they must lie in, and every other check reads
||| its one operand alone. Each kind is its own clause, so a new kind states
||| its count.
public export
guardOthers : GuardKind -> Nat
guardOthers NonZero = 0
guardOthers InBounds = 1
guardOthers NonEmpty = 0
guardOthers Finite = 0
guardOthers Range = 2
guardOthers HoldsString = 0
guardOthers Byte = 0

||| A guard a partial op takes, an op of ours or an admitted upstream one,
||| which the frontend builds before the op from what the specification
||| states, so no writer places it by hand and no op is written without
||| it: the check it makes, by its kind; the guarded op's operand groups it
||| is given, one per operand of the kind's op, the first the one it checks
||| and gives back, so a guard given the wrong number does not type; and
||| the crash cause it names. A group is named by its position among the
||| guarded op's operand groups, of the type `position`: a `Fin` for an op
||| of ours, whose groups the specification holds; a number for an admitted
||| op, whose groups are upstream's record's, so the backend that reads that
||| record is where a position past its groups is refused.
public export
record Guard (position : Type) where
  constructor MkGuard
  check : GuardKind
  given : Vect (S (guardOthers check)) position
  cause : Cause

||| Where the frontend finds the crash causes a guard names, as its printed
||| builders write one.
public export
causeEnum : ImportedEnum
causeEnum = imported causeClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Runtime", "Endings"]) "Cause"
            ("IdrisMLIR" ::: ["Spec", "Runtime", "Endings"]) "causeClosed")

------------------------------------------------------------------------------
-- The op
------------------------------------------------------------------------------

||| A builtin type ODS can build with no operand to read it from: the
||| types a result's type may be fixed to.
public export
data Buildable = BuiltI1 | BuiltI8 | BuiltI16 | BuiltI32 | BuiltI64 | BuiltIndex | BuiltF64 | BuiltNone

||| How one result's type follows from the op's operands, where a simple
||| rule fixes it: an operand's own type; the element type of an operand's
||| array, as MLIR's element type or self gives it on both sides; or one
||| fixed type, which the result's constraint is. Each is printed into the
||| C++ type inference upstream's ODS generates and into the op's Idris
||| builder, which computes the type, so no writer states a type the op
||| fixes.
public export
data TypeRule : (i : Nat) -> Type where
  OperandType : Fin i -> TypeRule i
  ElementTypeOf : Fin i -> TypeRule i
  FixedType : Buildable -> TypeRule i

||| How an op's result types are known: given to it when it is built, or
||| each fixed by its rule.
public export
data ResultTyping : (i, o : Nat) -> Type where
  StatedTypes : ResultTyping i o
  InferredTypes : Vect o (TypeRule i) -> ResultTyping i o

||| The group names of an op, every one.
public export
groupNames : Vect i Operand -> Vect o Result -> Vect a Attr -> Vect r Region -> List Ident
groupNames ins outs as rs =
  map (.name) (toList ins) ++ map (.name) (toList outs) ++ map (.name) (toList as) ++ map (.name) (toList rs)

||| Whether no identifier occurs twice.
public export
distinct : List Ident -> Bool
distinct [] = True
distinct (x :: xs) = not (elem x xs) && distinct xs

||| An admitted op. Its alias names it among every admitted op of every
||| dialect, where upstream's record names it only among its own dialect's
||| (`scf.yield`'s record and `transform.yield`'s are both `YieldOp`): the
||| C++ class, the per-op tables' key and the e-graph's kind read it, so it
||| carries its dialect where the record does not (`SCF_YieldOp`, and
||| `Arith_AddIOp` as the record already is). Its guards are what upstream
||| leaves undefined and Idris crashes on (`arith.divui`'s zero divisor), as
||| an op of ours states its own: each position is among upstream's operand
||| groups. Its range is absent where upstream has no range function for it
||| (`arith.cmpi` reads its predicate, `arith.select` is arith's own). Its
||| folding says whether upstream's fold may run at compile time.
public export
record Admitted where
  constructor MkAdmitted
  dialect : Dialect
  upstreamRecord : Ident
  alias : Ident
  legal : Legal
  writer : Writer
  guards : List (Guard Nat)
  laws : List UpLaw
  range : Maybe RangeFunction
  folding : UpFold

||| A constant of an op's member of a C++ class template the generator
||| specializes per op (its family's constants, its word op): a case of an
||| enum of the specification's, in the namespace its header declares it
||| in; an integer; an admitted upstream op's class; no class, where the
||| member names none (a big op whose word is the value itself); a runtime
||| function the lowering calls, by the helper's row of the runtime's ABI
||| (a show's writer); or the runtime function that is the meaning of an
||| op of the dialect, by that op's row (what a builder over a list calls
||| on one element, which that op does to one).
public export
data Constant : Type where
  EnumConstant : CaseRef -> Constant
  IntConstant : Integer -> Constant
  UpstreamClass : Admitted -> Constant
  NoClass : Constant
  HelperConstant : RuntimeHelper -> Constant
  OpEntry : OpRef -> Constant

||| A class template of hand C++ in `::idr`, specialized for each op that
||| is a member, its members the op's constants: the one carrier of a
||| family's facts, and of membership itself.
public export
record Specialized where
  constructor MkSpecialized
  template : Ident
  constants : List (Ident, Constant)

public export
record Op (i, o, a, r : Nat) where
  constructor MkOp
  home : Home
  mnemonic : Mnemonic
  ins : Vect i Operand
  outs : Vect o Result
  attrs : Vect a Attr
  regions : Vect r Region
  traits : List (Trait i o)
  interfaces : List InterfaceUse
  effects : Declaration i o
  speculation : Speculation
  stages : Legal
  meaning : Meaning i o
  verify : Verify
  format : Format i o a r
  builders : List Builder
  defaultBuilders : DefaultBuilders
  members : List Member
  guards : List (Guard (Fin i))
  specializations : List Specialized
  laws : List Law
  doc : Doc
  {default StatedTypes typing : ResultTyping i o}
  {auto 0 named : So (distinct (groupNames ins outs attrs regions))}

||| The admitted op's name in the C++ table the backend prints:
||| `::idr::admitted::SCF_YieldOp`, an alias of upstream's class.
public export
admittedAlias : Admitted -> String
admittedAlias a = "::idr::admitted::" ++ identText a.alias

||| An op of any counts, as a list of the dialect's holds them.
public export
data AnyOp : Type where
  SomeOp : {0 i, o, a, r : Nat} -> Op i o a r -> AnyOp

||| The op's C++ class, within its namespace.
public export
opClass : Op i o a r -> String
opClass op = case op.home of
  InIdr => camelMnemonic op.mnemonic ++ "Op"
  InTransform cls => identText (cppLeaf cls)

||| The op's class from the global namespace.
public export
opQualifiedClass : Op i o a r -> String
opQualifiedClass op = case op.home of
  InIdr => "::idr::" ++ camelMnemonic op.mnemonic ++ "Op"
  InTransform cls => cppText cls

||| The op's name in the IR, its dialect's namespace first.
public export
opName : Op i o a r -> String
opName op = case op.home of
  InIdr => "idr." ++ mnemonicText op.mnemonic
  InTransform _ => "transform." ++ mnemonicText op.mnemonic
