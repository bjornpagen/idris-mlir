-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Destinations: the right to write a place once. A self call modulo a
||| context becomes a tail call because the cells its result goes into are
||| built first, its field a hole, and the call is handed the hole's
||| destination; a framed run, which returns nothing, gives each of its
||| results to a destination the base frame holds, one per result of the
||| row, each the slot of the call that started it.
|||
||| A destination is used exactly once by its type, so it takes no grade of
||| its own, and the one rule of linearity holds every value of it to one
||| use on every path that goes on: passed on, to a call or into a frame,
||| or written, by `dest.write`, which gives nothing back. A second write is
||| a second use of a value already used, and a path that forgets it leaves
||| it unused; neither can be written.
|||
||| Its type says what is written through it at the grade the place keeps:
||| the claim a write must meet and the slot gives back, so a result's
||| `unique` or `static` is not lost on its way through a frame. Where the
||| place is (a hole of a cell an init built, a slot of `dest.answer`) is
||| the op's that made it, so one destination type serves every hole of one
||| type, whichever constructor and field it is: an insertion into a tree
||| hands on the hole of a node's left field on one path and of its right on
||| the other, and one clone takes either.
|||
||| What lets a call stay the tail when an op takes its result is the op's
||| own answer: whether it gives that value on with no run-time work. One
||| interface asks it of every op that gives its operand on, so neither the
||| rule of tail position nor that of a tail modulo a context names an op.
module IdrisMLIR.Spec.Tail.Declarations

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Lifetimes.Declarations

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The type
--------------------------------------------------------------------------------

||| `!idr.dest<T>`, C++ `DestType`: a place to be written once with a value
||| of `T`, at `T`'s grade where `T` is graded: what the place keeps of the
||| value, which a write must meet and the slot gives back. Its verifier
||| refuses a type used once by its type (a destination, a cell, a frame
||| stack: each is consumed where it is, never stored to be read back) and a
||| lifetime, which no place holds; a graded type is neither. At run time it
||| is one address per runtime component of `T`, each that component's slot
||| in the place, so a value whose components a cell lays out apart is
||| written whole; a value of one word is one address.
export
destType : TypeDef 1
destType = MkTypeDef
  { mnemonic = "dest"
  , stages = between Owned Owned
  , params =
      [ MkParameter "value" TypeValue AlwaysWritten
          "the type of the value written through it, at the grade the place keeps" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsNoReference UsedOnceByType Uncounted MayBeOtherWord ByParameters
                      (Always NoLabels) NotMemory)
  , doc = brief "a place to be written once with a value of its type"
  }

--------------------------------------------------------------------------------
-- The ops
--------------------------------------------------------------------------------

||| `idr.dest.write %d, %v : !idr.dest<T>, U`, C++ `DestWriteOp`: `%v`
||| written into the place `%d` stands for, which it consumes: it gives no
||| destination back, so nothing writes the place again. The value moves its
||| reference into the place, as a field an init writes does, so it is taken
||| over where it owns its count. It stands where `T` is asked: `T`'s
||| carrier or one refined to fewer constructors, used once only where `T`
||| is, and claiming at least what `T` claims, by the grades' own order (a
||| claim forgotten down to `T`'s, static data standing for a value that
||| claims nothing); its verifier holds it to that.
|||
||| Legal once counting has placed every reference: idr-trmc and idr-frames
||| make destinations, after counting, and the lowering stores the value's
||| components through the addresses.
public export
destWrite : Op 2 0 0 0
destWrite = MkOp
  { home = InIdr
  , mnemonic = "dest.write"
  , ins = [single "dest" (OurType (SomeType destType)), single "value" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [OnValues Write Contents (Operands 0)] [Consumes 1] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Owned Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared [ ValueOf (OperandRef 0), Lit ",", ValueOf (OperandRef 1), AttrDict, Lit ":"
                      , QualifiedTypeOf (OfGroup (OperandRef 0)), Lit ",", TypeOf (OfGroup (OperandRef 1)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "writes the place a destination stands for, consuming the destination"
  }

||| `%r:2 = idr.dest.answer in(%l : !L) -> (R1, R2) { ^bb0(%d1 :
||| !idr.dest<R1>, %d2 : !idr.dest<R2>): … idr.yield }`, C++
||| `DestAnswerOp`: where a function waits for a row of results written
||| through destinations, their slots. Its region, run once, binds one
||| destination per result, at the result's own type, and nothing else; each
||| destination is used once on every path by its type and cannot leave the
||| region, so each slot is written exactly once wherever the write is (in a
||| framed run, in the resume that pops the base frame). Each result is
||| exactly the type of its destination, grade and all, read out of its slot
||| when the region ends; a row of no result and one of several are the
||| same op. The region's end gives the op nothing, so no jump leaves the
||| region and no call in it is in tail position, since the reads come after
||| it.
|||
||| A scoped result lives in the lifetime its own operand of `outers`
||| states, one per scoped result in the order of the results, the pairing
||| read off the results' types: two results may live in two lifetimes, and
||| neither is narrowed to the other's span.
|||
||| The slots are frame memory the lowering makes, a place of the
||| function's own: made once in its entry, one slot per runtime component
||| of each result, which the destinations' addresses name and the results
||| load. A result is a value some callee wrote, which may be shared, never
||| a fresh allocation, so the op declares no effect of its own: what its
||| region does is its region's.
public export
destAnswer : Op 1 1 0 1
destAnswer = MkOp
  { home = InIdr
  , mnemonic = "dest.answer"
  , ins = [variadic "outers" (OurType (SomeType lifetimeType))]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = [sized "body" 1]
  , traits = [SingleBlock]
  , interfaces = [ Declares RegionBranch ["getSuccessorRegions", "getSuccessorInputs", "getRegionInvocationBounds"]
                 , Implements flowInterface ["getFlowEdges"]
                 , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"]
                 , Implements statesOuters [] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = NotSpeculatable
  , stages = between Owned Owned
  , meaning = NoFold
  , verify = VerifiesRegions
  , format = Declared
      [ OptionalGroup [Lit "in", Lit "("] (ValueOf (OperandRef 0))
          [Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit ")"]
      , AttrDictWithKeyword, OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) []
      , ValueOf (RegionRef 0) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the slots a row of results is written into through the destinations its region binds"
  }

--------------------------------------------------------------------------------
-- Giving a value on
--------------------------------------------------------------------------------

||| What an op whose result is its first operand's value does at run time
||| to give it on: nothing, so a call whose result it takes may still be the
||| tail; or work, which comes after the value it takes, so the call is not.
public export
data Carry = Free | Works

||| The C++ `Carry`, the answer of `CarriesOnOpInterface`, as upstream's
||| speculatability is an op's answer of its own.
export
carryClosed : Closed Carry
carryClosed = MkClosed
  { name = "Carry"
  , shape = OneOf
  , every = Free ::: [Works]
  , complete = \case
      Free => Here
      Works => There Here
  , describe = \case
      Free => MkCase "Free" (word "free" ::: []) "no run-time work: the result is the operand's own words"
      Works => MkCase "Works" (word "works" ::: []) "run-time work, after the value it takes"
  , doc = brief "what an op does at run time to give its operand on"
  }

||| `CarriesOnOpInterface`: an op whose result is its first operand's value
||| says what it does at run time to give it on, and at what type its result
||| takes that value where the operand is of another type. A change of
||| grade has no run-time form, so its trait's class derives from this
||| interface's trait and answers `Free` once for every op of the trait, and
||| gives its operand on at the weakest hold its operand's and its own fit;
||| an op whose two types decide its work answers from them, and gives the
||| type its own rule gives (a reindex: a fresh value where it builds, the
||| operand's hold where it builds nothing). The tail rule and the rule of a
||| tail modulo a context ask the first and look through a free one, and
||| the specializer's re-grading of what a weaker claim reaches asks the
||| second, each naming no op.
export
carriesOnInterface : InterfaceDef
carriesOnInterface = MkInterfaceDef
  { name = "CarriesOnOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::idr::Carry" "getCarry" [] EveryImplementer
          "what this op does at run time to give its first operand's value on as its result"
      , MkMethod PerObject "::mlir::Type" "getCarriedType" [param "::mlir::Type" "operand"]
          EveryImplementer
          "the type its result takes where its first operand is of type `operand`: its own carrier, at the grade the op gives that operand on at" ]
  , verifier = Unverified
  , doc = brief "an op whose result is its first operand's value, given on with or without run-time work"
  }

||| The answer's enum, which the trait's class names before the generated
||| interfaces are declared, and so is its own header.
carryHeader : Header
carryHeader = MkHeader "Carry" [(DialectNamespace, [EnumOf (enumDef carryClosed)])]
  (brief "what an op does at run time to give its operand on")

--------------------------------------------------------------------------------
-- The area
--------------------------------------------------------------------------------

||| The tail area's declarations: the destination, its one write, the
||| answer slots, and the interface by which an op says whether it gives its
||| operand on with no run-time work.
public export
declarations : Declarations
declarations =
  { ops := [SomeOp destWrite, SomeOp destAnswer]
  , types := [SomeType destType]
  , interfaces := [carriesOnInterface]
  , headers := [carryHeader]
  } nothing
