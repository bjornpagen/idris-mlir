-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Destinations: the right to write a place once. A self call modulo a
||| context becomes a tail call because the cells its result goes into are
||| built first, its field a hole, and the call is handed the hole's
||| destination; a framed run, which returns nothing, gives its answer to
||| the base frame's destinations, each a place on the frame of the call
||| that started it.
|||
||| A destination is used exactly once by its type, so it takes no grade,
||| and the one rule of linearity holds every value of it to one use on
||| every path that goes on: passed on, to a call or into a frame, or
||| written, by `dest.write`, which gives nothing back. A second write is a
||| second use of a value already used, and a path that forgets it leaves
||| it unused; neither can be written.
|||
||| Its type says only what is written through it. Where the place is (a
||| hole of a cell an init built, a slot on a frame) is the op's that made
||| it, so one destination type serves every hole of one type, whichever
||| constructor and field it is: an insertion into a tree hands on the hole
||| of a node's left field on one path and of its right on the other, and
||| one clone takes either.
module IdrisMLIR.Spec.Tail.Declarations

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration

import Data.Fin
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The type
--------------------------------------------------------------------------------

||| `!idr.dest<T>`, C++ `DestType`: a place to be written once with a value
||| of `T`. `T` is a carrier: what the place holds, never a grade of it, so a
||| value at any grade that fills a field of `T` is written through it. Its
||| verifier refuses a grade, a type used once by its type (a destination,
||| a cell, a frame stack: each is consumed where it is, never stored to be
||| read back) and a lifetime, which no place holds. At run time it is one
||| address per runtime component of `T`, each that component's slot in
||| the place, so a value whose components a cell lays out apart is written
||| whole; a value of one word is one address.
export
destType : TypeDef 1
destType = MkTypeDef
  { mnemonic = "dest"
  , params =
      [ MkParameter "value" TypeValue AlwaysWritten
          "the carrier of the value written through it" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsNoReference UsedOnceByType Uncounted MayBeOtherWord)
  , doc = brief "a place to be written once with a value of its type"
  }

--------------------------------------------------------------------------------
-- The op
--------------------------------------------------------------------------------

||| `idr.dest.write %d, %v : !idr.dest<T>, U`, C++ `DestWriteOp`: `%v`
||| written into the place `%d` stands for, which it consumes: it gives no
||| destination back, so nothing writes the place again. The value moves its
||| reference into the place, as a field an init writes does, so it is taken
||| over where it owns its count. It fills a field of `T` wherever the place
||| is: its carrier `T` or `T` refined to fewer constructors, freed by its
||| count or never (static data), and used freely, since the place's own
||| uses are its field's, which the destination does not keep; its verifier
||| holds it to that.
|||
||| Legal once counting has placed every reference: idr-trmc and idr-frames
||| make destinations, after counting, and the lowering stores the value's
||| components through the addresses.
export
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

--------------------------------------------------------------------------------
-- The area
--------------------------------------------------------------------------------

||| The tail area's declarations: the destination and its one write.
export
declarations : Declarations
declarations = { ops := [SomeOp destWrite], types := [SomeType destType] } nothing
