-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What ODS and the generated C++ can say of an op's effects and of the
||| runtime's C ABI: MLIR's four kinds of effect on a resource of the tree,
||| on the op or on one of its values; the typed rules that read a value's
||| type; the C kinds a runtime function takes and gives. The effect
||| system's meaning, its forms and their laws are the effect
||| specification's (`IdrisMLIR.Spec.Effects`), which lowers each op's
||| declaration to this; the generator prints this and nothing else.
module IdrisMLIR.Spec.Core.Ods

import IdrisMLIR.Spec.Core.Text

import Data.Fin
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| Upstream's four kinds of memory effect, and no other, by ODS's names.
public export
data EffectKind = MemRead | MemWrite | MemAlloc | MemFree

mutual
  ||| A resource of the effect tree as the C++ holds it: its class in
  ||| `::idr::effects`, its printed name, its parent. Every resource of ours
  ||| comes from the effect specification's tree, in its order.
  public export
  record ResourceDef where
    constructor MkResourceDef
    name : Ident
    printed : Line
    parent : ResourceParent

  ||| Where a resource of ours sits in the tree: under upstream's root, or
  ||| under another of ours, declared before it.
  public export
  data ResourceParent = ResourceAtRoot | ResourceUnder ResourceDef

||| A resource an effect is on: upstream's root, upstream's frame (an
||| automatic allocation scope's), or one of ours.
public export
data OdsResource = UpstreamRoot | UpstreamFrame | OurResource ResourceDef

||| What an effect is on, among an op's `i` operand and `o` result groups.
public export
data Subject : (i, o : Nat) -> Type where
  OfOp : Subject i o
  OfOperand : Fin i -> Subject i o
  OfResult : Fin o -> Subject i o

public export
record OdsEffect (i, o : Nat) where
  constructor MkOdsEffect
  kind : EffectKind
  resource : OdsResource
  subject : Subject i o

||| A rule that gives an effect by a value's type (consumption of an owned
||| operand, a fresh identity of a linear result): the hand C++ rule class
||| in `::idr::effects` the generated table names, and the value it reads.
public export
record OdsRule (i, o : Nat) where
  constructor MkOdsRule
  rule : Ident
  subject : Subject i o

||| Whether the op's regions' effects are its own too (upstream's
||| `RecursiveMemoryEffects`).
public export
data OdsBodies = OwnOnly | WithBodies

||| An op's effects as ODS and the C++ tables hold them: its own static
||| effects and typed rules, and whether its regions' count; or every
||| effect, for an op that runs code no declaration bounds.
public export
data OdsEffects : (i, o : Nat) -> Type where
  Declares : List (OdsEffect i o) -> List (OdsRule i o) -> OdsBodies -> OdsEffects i o
  EveryEffect : OdsEffects i o

------------------------------------------------------------------------------
-- The runtime's C ABI
------------------------------------------------------------------------------

||| How a runtime function takes a value: a C integer of 32 or 64 bits, a
||| double, an integer of the op's width extended by its sign or by zeros,
||| a string, a big, a buffer's cell, a pointer the lowering made to a C
||| type of the runtime's (its spelling, `const idris_rt_text`), or a C
||| `bool`, which the C ABI extends with zeros. A pointer names what it
||| points to, so the prototype the runtime is checked against says it and
||| no definition takes a `void *` where it means a cell.
public export
data OperandKind
  = TakesInt32 | TakesInt64 | TakesDouble | TakesSigned | TakesUnsigned
  | TakesStr | TakesBig | TakesBuffer | TakesPointerTo Code | TakesBool

||| How a runtime function gives a value: as an operand is given, or an
||| integer modulo 2^64 the op wraps to its width, or a three-way order the
||| op compares with zero by its predicate.
public export
data ResultKind
  = GivesInt32 | GivesInt64 | GivesDouble | GivesWrapped | GivesOrder
  | GivesStr | GivesBig | GivesPointerTo Code | GivesBool

||| How a runtime function gives an op's `o` results.
public export
data Gives : (o : Nat) -> Type where
  ||| No result, and it returns.
  NoResult : Gives 0
  ||| No result: it never returns (a crash, an exit).
  NeverReturns : Gives 0
  ||| The one result.
  Returns : ResultKind -> Gives 1
  ||| Each result through a pointer its caller passes, in order.
  ThroughPointers : Vect (S (S k)) ResultKind -> Gives (S (S k))

||| The runtime function an op calls, and how it takes each of the op's `i`
||| operand groups and gives its `o` results.
public export
record RuntimeCall (i, o : Nat) where
  constructor MkRuntimeCall
  symbol : Symbol
  takes : Vect i OperandKind
  gives : Gives o

||| A function of the runtime the lowering calls by itself, not as an op's
||| meaning: its symbol, its parameters' kinds and names, how it gives its
||| result.
public export
data HelperGives = HelperNothing | HelperNeverReturns | HelperReturns ResultKind

public export
record RuntimeHelper where
  constructor MkRuntimeHelper
  name : Ident
  symbol : Symbol
  params : List (OperandKind, Ident)
  gives : HelperGives
  doc : Line
