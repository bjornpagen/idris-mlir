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

||| Whether a method needs an object, or is the class's.
public export
data MethodBinding = PerObject | PerClass

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

||| Whether an interface's verifier needs the op's regions verified first.
public export
data VerifyOrder = BeforeRegions | AfterRegions

||| The interface's own verifier, a hand function, or none.
public export
data InterfaceVerifier = Unverified | Verifies Ident VerifyOrder

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
||| a match on a closure sum, a read of one's field, a string's output. It
||| ends the chain of single uses that raising moves into a clone of the
||| callee building the operand, so raising finds it by this trait rather
||| than by naming each op.
public export
eliminatesOperand : TraitDef
eliminatesOperand = MkTraitDef (MkIdent "EliminatesOperand" Oh)
  (MkDoc (MkLine "the op eliminates its first operand, and does nothing else with it" Oh) (MkProse "" Oh))

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
