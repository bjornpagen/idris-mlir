-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The lifetime's declarations: the types `!idr.lifetime<kind>` and
||| `!idr.lifetime.package<…>`, the closed sets of `Kind` and their tables,
||| the interfaces by which an op states the lifetime of a scoped value it
||| makes and an opener says where its memory comes from, and the ops: the
||| five openers, this call's own lifetime, the loan, the cast to a view, a
||| room reserved in a cursor, and the pack and unpack that split a lifetime
||| around a framed call.
|||
||| A lifetime value is bound only here: an opener's, a loan's or an
||| unpack's entry argument, `idr.activation`'s result, a function's
||| parameter, and the results of the two ops that derive one lifetime from
||| another (`forget`, `reserve`), each of the extent of its operand. No
||| terminator, field or join parameter takes one, so MLIR's value scoping
||| keeps every lifetime inside its region.
module IdrisMLIR.Spec.Lifetimes.Declarations

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Counting.Types
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Lifetimes.Kind

import Data.Fin
import Data.List.Elem
import Data.List1
-- `op`'s automatic proof is searched where it is written.
import public Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The closed sets
--------------------------------------------------------------------------------

||| A kind's case: the keyword of `!idr.lifetime`'s parameter, and the C++
||| `LifetimeKindCase` whose order `::idr::LifetimeKind`'s alternatives keep.
export
kindCaseClosed : Closed KindCase
kindCaseClosed = MkClosed
  { name = ident "LifetimeKindCase"
  , shape = OneOf
  , every = ViewCase ::: [RoomCase, CursorCase, HomeCase]
  , complete = \case
      ViewCase => Here
      RoomCase => There Here
      CursorCase => There (There Here)
      HomeCase => There (There (There Here))
  , describe = \case
      ViewCase => MkCase (ident "View") (word "view" ::: []) (line "nothing allocates into it: no value at run time")
      RoomCase => MkCase (ident "Room") (word "room" ::: []) (line "a block of static size: a pointer in")
      CursorCase => MkCase (ident "Cursor") (word "cursor" ::: []) (line "an unbounded bump: a pointer in and out")
      HomeCase => MkCase (ident "Home") (word "home" ::: []) (line "the per-shard home of a site: no value")
  , doc = brief (line "what a lifetime value is at run time")
  }

export
loweredClosed : Closed Lowered
loweredClosed = MkClosed
  { name = ident "Lowered"
  , shape = OneOf
  , every = NoValue ::: [PointerIn, PointerInOut]
  , complete = \case
      NoValue => Here
      PointerIn => There Here
      PointerInOut => There (There Here)
  , describe = \case
      NoValue => MkCase (ident "NoValue") (word "no_value" ::: []) (line "dropped from every signature, call and frame")
      PointerIn => MkCase (ident "PointerIn") (word "pointer_in" ::: []) (line "a pointer passed in")
      PointerInOut => MkCase (ident "PointerInOut") (word "pointer_in_out" ::: []) (line "a pointer passed in and given back")
  , doc = brief (line "what a lifetime value lowers to")
  }

export
openerClosed : Closed Opener
openerClosed = MkClosed
  { name = ident "Opener"
  , shape = OneOf
  , every = NoMemory ::: [AtHome, InBlock, OnStack, InChain]
  , complete = \case
      NoMemory => Here
      AtHome => There Here
      InBlock => There (There Here)
      OnStack => There (There (There Here))
      InChain => There (There (There (There Here)))
  , describe = \case
      NoMemory => MkCase (ident "NoMemory") (word "no_memory" ::: []) (line "none: nothing allocates into it")
      AtHome => MkCase (ident "AtHome") (word "at_home" ::: []) (line "the per-shard home of its site")
      InBlock => MkCase (ident "InBlock") (word "in_block" ::: []) (line "a block in the opener's frame")
      OnStack => MkCase (ident "OnStack") (word "on_stack" ::: []) (line "its base cursor's stack, reset at its end")
      InChain => MkCase (ident "InChain") (word "in_chain" ::: []) (line "its own chain of chunks")
  , doc = brief (line "where a lifetime's memory comes from")
  }

export
packedClosed : Closed Packed
packedClosed = MkClosed
  { name = ident "Packed"
  , shape = OneOf
  , every = FromStack ::: [FromChain]
  , complete = \case
      FromStack => Here
      FromChain => There Here
  , describe = \case
      FromStack => MkCase (ident "FromStack") (word "stack" ::: []) (line "a stack lifetime's mark")
      FromChain => MkCase (ident "FromChain") (word "chain" ::: []) (line "a chained lifetime's chain")
  , doc = brief (line "what a per-level lifetime's package holds")
  }

--------------------------------------------------------------------------------
-- The tables
--------------------------------------------------------------------------------

boolCell : Dec p -> Cell
boolCell (Yes _) = IntCell 1
boolCell (No _) = IntCell 0

passesCell : (arg, param : LifetimeKind) -> Cell
passesCell arg param = case (caseOf arg, caseOf param) of
  (_, ViewCase) => IntCell 1
  (a, p) => if position kindCaseClosed a == position kindCaseClosed p then IntCell 1 else IntCell 0

||| Each case's facts: whether something may allocate into it, what it
||| lowers to, and, a column per parameter's case, whether it may be passed
||| where that case is asked (a home only to its own site, which the value
||| class compares beside the case).
export
kindTable : Table
kindTable = table kindCaseClosed
  [ MkColumn (ident "kindSpelling") TextColumn (\c => TextCell (spellingText (kindCaseClosed.describe c)))
      (line "the case's keyword")
  , MkColumn (ident "kindAdmitsPuts") Unsigned8 (\c => boolCell (puts (kindOfCase c)))
      (line "whether something may allocate into a lifetime of the case")
  , MkColumn (ident "kindLowered") (EnumColumn (enumDef loweredClosed))
      (\c => CaseCell (caseRef loweredClosed (lowered (kindOfCase c)))) (line "what a lifetime of the case lowers to")
  , MkColumn (ident "kindPassesAsView") Unsigned8 (\c => passesCell (kindOfCase c) View)
      (line "passed where a view is asked")
  , MkColumn (ident "kindPassesAsRoom") Unsigned8 (\c => passesCell (kindOfCase c) Room)
      (line "passed where a room is asked")
  , MkColumn (ident "kindPassesAsCursor") Unsigned8 (\c => passesCell (kindOfCase c) Cursor)
      (line "passed where a cursor is asked")
  , MkColumn (ident "kindPassesAsHome") Unsigned8 (\c => passesCell (kindOfCase c) (Home 0))
      (line "passed where a home is asked, its site compared beside")
  ]

||| The case each opener binds (`bound`).
export
openerTable : Table
openerTable = table openerClosed
  [ MkColumn (ident "openerBinds") (EnumColumn (enumDef kindCaseClosed))
      (\o => CaseCell (caseRef kindCaseClosed (bound o))) (line "the kind the opener's lifetime is")
  ]

--------------------------------------------------------------------------------
-- The types
--------------------------------------------------------------------------------

||| Each kind's alternative: a home alone holds its site, in 32 bits.
public export
kindAlternative : KindCase -> Composite
kindAlternative ViewCase = MkComposite (ident "LifetimeKindView") (code "::idr::LifetimeKindView")
  (Fields []) (brief (line "a view: nothing allocates into it"))
kindAlternative RoomCase = MkComposite (ident "LifetimeKindRoom") (code "::idr::LifetimeKindRoom")
  (Fields []) (brief (line "a room: a block of static size"))
kindAlternative CursorCase = MkComposite (ident "LifetimeKindCursor") (code "::idr::LifetimeKindCursor")
  (Fields []) (brief (line "a cursor: an unbounded bump"))
kindAlternative HomeCase = MkComposite (ident "LifetimeKindHome") (code "::idr::LifetimeKindHome")
  (Fields [MkWireField (ident "site") (WireLeaf LeafWord32)])
  (brief (line "the per-shard home of a site"))

||| A lifetime's kind on the wire: its case, then that case's alternative,
||| so no kind but a home can carry a site.
public export
kindWire : Composite
kindWire = MkComposite (ident "LifetimeKindOf") (code "::idr::LifetimeKind")
  (variant kindCaseClosed kindAlternative) (brief (line "a lifetime's kind, its alternative its case"))

||| The kind's text, `view`, `room`, `cursor` or `home k`; its bytecode is
||| the wire's.
kindDirective : Directive
kindDirective = MkDirective
  { name = ident "LifetimeKind"
  , args = []
  , doc = brief (line "a lifetime's kind, a home with its site")
  }

||| `!idr.lifetime<view | room | cursor | home k>`, C++ `LifetimeType`. Uses
||| many and no grade: a lifetime is never consumed, returned or threaded in
||| the IR, and holds no reference a count accounts for.
export
lifetimeType : TypeDef 1
lifetimeType = MkTypeDef
  { mnemonic = "lifetime"
  , params =
      [ MkParameter (ident "kind") (WiredValue (WiredOf kindWire) kindDirective)
          AlwaysWritten (line "what the lifetime is at run time") ]
  , syntax = Declarative [Keyword (line "<"), ParamAt FZ, Keyword (line ">")]
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsNoReference UsedAsGraded Uncounted MayBeOtherWord)
  , doc = brief (line "a lifetime: what it is at run time is its kind; its opener says where its memory comes from")
  }

||| `!idr.lifetime.package<stack | chain, T…>`, C++ `LifetimePackageType`:
||| a per-level lifetime's memory and the values held in it, moved out of
||| its region by `idr.lifetime.pack` and reopened by `idr.lifetime.unpack`.
||| Used exactly once by its type, with no grade, so a second unpack is a
||| second use and a package no unpack takes holds memory nothing gives
||| back. Its held values live in its lifetime, so it holds no reference a
||| count accounts for.
export
packageType : TypeDef 2
packageType = MkTypeDef
  { mnemonic = "lifetime.package"
  , params =
      [ MkParameter (ident "packed")
          (EnumValue (imported packedClosed
            (MkSource ("IdrisMLIR" ::: ["Spec", "Lifetimes", "Kind"]) "Packed"
                      ("IdrisMLIR" ::: ["Spec", "Lifetimes", "Declarations"]) "packedClosed")))
          AlwaysWritten
          (line "what the package holds of the lifetime")
      , MkParameter (ident "held") (ListOf TypeValue) AlwaysWritten
          (line "the values held in the lifetime, in order") ]
  , syntax = Declarative [Keyword (line "<"), ParamAt FZ, Keyword (line ","), ParamAt (FS FZ), Keyword (line ">")]
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsNoReference UsedOnceByType Uncounted MayBeOtherWord)
  , doc = brief (line "a per-level lifetime packed around a framed call, with the values it holds")
  }

--------------------------------------------------------------------------------
-- What other ops' operands ask of a lifetime
--------------------------------------------------------------------------------

export
anyLifetime : TypeC
anyLifetime = OurType (SomeType lifetimeType)

predicate : Ident -> Line -> Predicate
predicate n d = MkPredicate n OnType (brief d)

putsPredicate : Predicate
putsPredicate = predicate (ident "admitsPuts") (line "a lifetime something may allocate into")

cursorPredicate : Predicate
cursorPredicate = predicate (ident "isCursorLifetime") (line "a cursor lifetime")

roomPredicate : Predicate
roomPredicate = predicate (ident "isRoomLifetime") (line "a room lifetime")

viewPredicate : Predicate
viewPredicate = predicate (ident "isViewLifetime") (line "a view lifetime")

||| A lifetime something may allocate into: what `idr.cell.arena` takes,
||| so an allocation into a view cannot be written.
export
putLifetime : TypeC
putLifetime = SatisfiesType putsPredicate

export
cursorLifetime : TypeC
cursorLifetime = SatisfiesType cursorPredicate

export
viewLifetime : TypeC
viewLifetime = SatisfiesType viewPredicate

roomLifetime : TypeC
roomLifetime = SatisfiesType roomPredicate

anyValue : TypeC
anyValue = UpstreamType AnyTypeC

--------------------------------------------------------------------------------
-- Interfaces and traits
--------------------------------------------------------------------------------

||| `StatesLifetimeOpInterface`: the lifetime an op states for a scoped
||| value it makes, a result or an argument of a block of its regions; null
||| for a value that is not scoped. Every op that makes a scoped value holds
||| it, so a value's lifetime is one hop from it and no check follows a
||| def-use chain; a function states its parameters' in its signature.
export
statesLifetime : InterfaceDef
statesLifetime = MkInterfaceDef
  { name = ident "StatesLifetimeOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::mlir::Value") (ident "getStatedLifetime")
          [param (code "::mlir::Value") (ident "made")] EveryImplementer
          (line "the lifetime this op states for a scoped value it makes; null for any other")
      , MkMethod PerObject (code "void") (ident "setStatedLifetime")
          [param (code "::mlir::Value") (ident "made"), param (code "::mlir::Value") (ident "lifetime")]
          EveryImplementer
          (line "states the lifetime for the value and every value this op states one lifetime for with it; a null lifetime states none, for an op left with no scoped value") ]
  , verifier = Unverified
  , doc = brief (line "the lifetime an op states for a scoped value it makes")
  }

||| `StatesOutersOpInterface`: an op that states the lifetime of each scoped
||| value it makes by its own operand of one group, `outers`, in the order
||| the values' types pair them, the group its generated accessor gives. A
||| pass that remakes such an op with other results restates the whole
||| group through it at once (`lifetimes::restateOuters`). A function and a
||| call state their lifetimes in their signatures, through no group, so
||| this is no method of the stating interface every such op holds.
export
statesOuters : InterfaceDef
statesOuters = MkInterfaceDef
  { name = ident "StatesOutersOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::mlir::MutableOperandRange") (ident "getOutersMutable") [] EveryImplementer
          (line "the operands that state the lifetimes of the scoped values this op makes, in their order") ]
  , verifier = Unverified
  , doc = brief (line "an op stating its scoped values' lifetimes by one operand group")
  }

||| `OpensLifetimeOpInterface`: where the memory of the lifetime an opener
||| binds comes from, the constant of its class (`LifetimeOpener<Op>`), so a
||| reader asks the op and lists no op.
export
opensLifetime : InterfaceDef
opensLifetime = MkInterfaceDef
  { name = ident "OpensLifetimeOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::idr::Opener") (ident "getOpener") [] (DelegatesByClass (ident "openerOfOp"))
          (line "where the memory of the lifetime this op binds comes from") ]
  , verifier = Unverified
  , doc = brief (line "where an opener's memory comes from")
  }

||| `LifetimePutOpInterface`: an op that puts into a lifetime, the lifetime
||| and how many bytes, as the target lays them out: what the function's
||| record of each lifetime parameter's amount is summed from, and what a
||| room's block is sized by.
export
putsIntoLifetime : InterfaceDef
putsIntoLifetime = MkInterfaceDef
  { name = ident "LifetimePutOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "::mlir::Value") (ident "getPutLifetime") [] EveryImplementer
          (line "the lifetime this op puts into")
      , MkMethod PerObject (code "std::uint64_t") (ident "getPutBytes")
          [param (code "const ::idr::Layouts &") (ident "layouts")] EveryImplementer
          (line "the bytes this op puts there, as the module's layouts lay them out") ]
  , verifier = Unverified
  , doc = brief (line "an op that puts into a lifetime, and how much")
  }

||| An op whose one region runs once and gives back what it yields: its
||| `outers` hold one lifetime per scoped result, in result order, each
||| result's own, and an opener's region binds the kind it opens
||| (`openerBinds`), which no region constraint of ODS can say.
runsOnce : TraitDef
runsOnce = MkTraitDef (ident "RunsOnce") (brief (line "one region, run once, giving back what it yields"))

||| The same, after a first result of its own (a loan's owner, given back).
runsOnceGivingBack : TraitDef
runsOnceGivingBack = MkTraitDef (ident "RunsOnceGivingBack")
  (brief (line "one region, run once, giving back its operand and what it yields"))

||| The methods each op of a region run once defines, one shared template
||| each: where control goes, what a successor takes, how often the region
||| runs; and the lifetime it states for what it gives.
onceMethods : List Ident
onceMethods = ["getSuccessorRegions", "getSuccessorInputs", "getRegionInvocationBounds"]

export
statedMethods : List Ident
statedMethods = ["getStatedLifetime", "setStatedLifetime"]

putMethods : List Ident
putMethods = ["getPutLifetime", "getPutBytes"]

||| The ops whose result is a lifetime value, which the function verifier
||| reads: no other op gives one.
givesLifetime : TraitDef
givesLifetime = MkTraitDef (ident "GivesLifetime") (brief (line "its result is a lifetime"))

||| A result whose type is its operand's, read and written as nothing.
sameType : Directive
sameType = MkDirective (ident "SameType") [TypeArg, RefTypeArg]
  (brief (line "a result of its operand's type, written once"))

||| A result whose type is the one lifetime type of its kind, written as
||| nothing.
viewOf : Directive
viewOf = MkDirective (ident "ViewLifetime") [TypeArg] (brief (line "a view lifetime, written as nothing"))

roomOf : Directive
roomOf = MkDirective (ident "RoomLifetime") [TypeArg] (brief (line "a room lifetime, written as nothing"))

--------------------------------------------------------------------------------
-- The openers
--------------------------------------------------------------------------------

||| The end of a lifetime: the memory it took comes back to the runtime,
||| which no value names. No cell of a lifetime holds a counted field, so
||| its end touches no count. Reporting only: nothing is ordered for the
||| sake of memory.
closes : RuntimeMemory -> Declaration i o
closes memory = Executes [] [] Recursive memory

||| The format of an opener without a base: `idr.lifetime in %l, %m :
||| !idr.lifetime<k>, !idr.lifetime<j> -> (T…) { … }`, the lifetimes of its
||| scoped results. A lifetime's type is written where its value is, since
||| its kind is a parameter no format can infer.
plainFormat : Format 1 1 0 1
plainFormat = Declared
  [ OptionalGroup [Lit (line "in")] (ValueOf (OperandRef FZ)) [Lit (line ":"), TypeOf (OfGroup (OperandRef FZ))]
  , AttrDictWithKeyword
  , OptionalGroup [Lit (line "->")] (TypeOf (OfGroup (ResultRef FZ))) []
  , ValueOf (RegionRef FZ) ]

||| An opener of every source but the stack's, one op each (C++
||| `LifetimeOp`, `LifetimeHomeOp`, `LifetimeBlockOp`, `LifetimeChainOp`):
||| one region of one block, whose entry argument is the lifetime, of the
||| kind the opener binds, fed by no operand; its results are what the
||| region yields, each scoped one stated by its own entry of `outers`, so
||| two results of two lifetimes keep each its own span. No jump leaves one,
||| so no call in it is in tail position: its end follows its region.
plainOpener : Opener -> Op 1 1 0 1
plainOpener o = MkOp
  { home = InIdr
  , mnemonic = openerMnemonic o
  , ins = [variadic (ident "outers") anyLifetime]
  , outs = [results (ident "results") anyValue]
  , attrs = []
  , regions = [sized (ident "body") 1]
  , traits = [SingleBlock, OurTrait runsOnce]
  , interfaces = [ Implements statesLifetime statedMethods, Implements statesOuters [], Implements opensLifetime []
                   , Declares RegionBranch onceMethods ]
  , effects = closes (memoryOf o)
  , speculation = NotSpeculatable
  , stages = stagesOf o
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = plainFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [MkSpecialized (ident "LifetimeOpener") [(ident "opener", EnumConstant (caseRef openerClosed o))]]
  , laws = []
  , doc = brief (summaryOf o)
  }
  where
    openerMnemonic : Opener -> Mnemonic
    openerMnemonic NoMemory = "lifetime"
    openerMnemonic AtHome = "lifetime.home"
    openerMnemonic InBlock = "lifetime.block"
    openerMnemonic OnStack = "lifetime.stack"
    openerMnemonic InChain = "lifetime.chain"

    -- The memory a lifetime's end gives back to the runtime, which no
    -- value names: none for a lifetime without memory or a block in the
    -- frame, a home's chunks or a chain's otherwise.
    memoryOf : Opener -> RuntimeMemory
    memoryOf NoMemory = Untouched
    memoryOf InBlock = Untouched
    memoryOf _ = Touched

    -- Every lifetime is born decided: the openers with memory exist from
    -- the decide step on (the graded stage) until the lowering; the one
    -- without, at any stage.
    stagesOf : Opener -> Legal
    stagesOf NoMemory = Always
    stagesOf _ = between Graded Owned

    summaryOf : Opener -> Line
    summaryOf NoMemory = "opens a lifetime nothing allocates into"
    summaryOf AtHome = "opens a lifetime in the per-shard home of its site"
    summaryOf InBlock = "opens a lifetime in a block of the opener's frame"
    summaryOf OnStack = "opens a lifetime on its base cursor's stack"
    summaryOf InChain = "opens a lifetime in its own chain of chunks"

||| `idr.lifetime.stack on %base : !idr.lifetime<cursor> in %outers : … ->
||| (T…) { … }`, C++ `LifetimeStackOp`: a lifetime on the stack of the
||| cursor `base`, its mark that cursor, its end resetting it.
stackOpener : Op 2 1 0 1
stackOpener = MkOp
  { home = InIdr
  , mnemonic = "lifetime.stack"
  , ins = [single (ident "base") cursorLifetime, variadic (ident "outers") anyLifetime]
  , outs = [results (ident "results") anyValue]
  , attrs = []
  , regions = [sized (ident "body") 1]
  , traits = [SingleBlock, OurTrait runsOnce]
  , interfaces = [ Implements statesLifetime statedMethods, Implements statesOuters [], Implements opensLifetime []
                   , Declares RegionBranch onceMethods ]
  , effects = closes Untouched
  , speculation = NotSpeculatable
  , stages = between Graded Owned
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [ Lit (line "on"), ValueOf (OperandRef FZ), Lit (line ":"), TypeOf (OfGroup (OperandRef FZ))
      , OptionalGroup [Lit (line "in")] (ValueOf (OperandRef (FS FZ)))
          [Lit (line ":"), TypeOf (OfGroup (OperandRef (FS FZ)))]
      , AttrDictWithKeyword
      , OptionalGroup [Lit (line "->")] (TypeOf (OfGroup (ResultRef FZ))) []
      , ValueOf (RegionRef FZ) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [MkSpecialized (ident "LifetimeOpener") [(ident "opener", EnumConstant (caseRef openerClosed OnStack))]]
  , laws = []
  , doc = brief "opens a lifetime on its base cursor's stack"
  }

||| Every opener, each its own op.
openers : List AnyOp
openers = [SomeOp (plainOpener NoMemory), SomeOp (plainOpener AtHome), SomeOp (plainOpener InBlock),
           SomeOp stackOpener, SomeOp (plainOpener InChain)]

--------------------------------------------------------------------------------
-- This call's lifetime, the loan, and the derived lifetimes
--------------------------------------------------------------------------------

||| An op with nothing else to say: no guard, law, member or builder of its
||| own, its default builders kept.
op : Mnemonic -> (ins : Vect i Operand) -> (outs : Vect o Result) -> (attrs : Vect a Attr)
  -> (regions : Vect r Region) -> List (Trait i o) -> List InterfaceUse -> Declaration i o
  -> Speculation -> Legal -> Verify -> Format i o a r -> List Member -> Doc
  -> {auto 0 named : So (distinct (groupNames ins outs attrs regions))} -> Op i o a r
op m ins outs attrs regions traits interfaces effects speculation stages verify format members doc =
  MkOp
    { home = InIdr, mnemonic = m, ins, outs, attrs, regions, traits, interfaces, effects
    , speculation, stages, meaning = NoFold, verify, format, builders = []
    , defaultBuilders = WithDefaults, members, guards = [], specializations = [], laws = [], doc }

||| `idr.activation`, C++ `ActivationOp`: this activation's lifetime, a
||| view, the extent of the rest of its region. Slots (`idr.cell.stack`)
||| stated in it are entry-block allocations; parameters that live for one
||| call are passed it. A fresh identity: never merged or hoisted, deleted
||| when unused.
activation : Op 0 1 0 0
activation = op "activation" [] [result "lifetime" viewLifetime] [] []
  [OurTrait givesLifetime] []
  (Executes [OnValues Allocate Identity (Results FZ)] [] Covered Untouched)
  NotSpeculatable Always DeclarationOnly
  (Declared [AttrDict, Custom viewOf [TypeOfGroup (ResultRef FZ)]]) []
  (brief "this activation's lifetime: a view, the extent of the rest of its region")

||| `idr.lend %owner : T in %outers : … -> (U…) { ^(%l, %view): … }`, C++
||| `LendOp`: a counted value lent for a region. The region binds the
||| loan's lifetime, a view, and the view of the owner, scoped to it at the
||| owner's claim; the owner comes back as the first result, the same value,
||| so a use of it during the loan is a second use and a view read after the
||| owner is dropped cannot be written. A temporary that dies with the loan
||| goes into an `idr.lifetime` nested in its region, so a loan has one
||| meaning.
lend : Op 2 2 0 1
lend = op "lend" [single "owner" anyValue, variadic "outers" anyLifetime]
  [result "returned" anyValue, results "results" anyValue] [] [sized "body" 1]
  [SingleBlock, OurTrait runsOnceGivingBack]
  [Implements statesLifetime statedMethods, Implements statesOuters [], Declares RegionBranch onceMethods]
  (Executes [] [] Recursive Untouched) NotSpeculatable Always VerifiesRegions
  (Declared
    [ ValueOf (OperandRef FZ), Lit ":", TypeOf (OfGroup (OperandRef FZ))
    , Custom sameType [TypeOfGroup (ResultRef FZ), TypeAgain (OperandRef FZ)]
    , OptionalGroup [Lit "in"] (ValueOf (OperandRef (FS FZ))) [Lit ":", TypeOf (OfGroup (OperandRef (FS FZ)))]
    , AttrDictWithKeyword
    , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef (FS FZ)))) []
    , ValueOf (RegionRef FZ) ])
  [MkMember OnObject "::mlir::Value" "getView" []]
  (brief "lends a counted value for a region, giving it back")

||| `idr.lifetime.forget %l : !idr.lifetime<K>`, C++ `LifetimeForgetOp`: the
||| view of its operand's lifetime, of the same extent; what the inliner
||| writes where a view parameter is given another kind. Pure.
forget : Op 1 1 0 0
forget = op "lifetime.forget" [single "lifetime" anyLifetime] [result "view" viewLifetime] [] []
  [OurTrait givesLifetime] [] noEffects AlwaysSpeculatable Always DeclarationOnly
  (Declared [ValueOf (OperandRef FZ), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef FZ)),
             Custom viewOf [TypeOfGroup (ResultRef FZ)]]) []
  (brief "the view of a lifetime, of its extent")

||| `idr.lifetime.reserve %l, 64 : !idr.lifetime<cursor>`, C++
||| `LifetimeReserveOp`: a room of `bytes` taken from a cursor lifetime, of
||| the cursor's extent, for a callee compiled for a room: one check and a
||| bump, taking a chunk where the cursor's has no room. Its own op, never
||| a conversion at the call, which would hide the effect.
reserve : Op 1 1 1 0
reserve = op "lifetime.reserve" [single "lifetime" cursorLifetime] [result "room" roomLifetime]
  [attr "bytes" (UpstreamAttr I64AttrC)] []
  [OurTrait givesLifetime] [Implements putsIntoLifetime putMethods]
  (Executes [OnValues Allocate Heap (Results FZ)] [] Covered Untouched)
  NotSpeculatable (between Graded Owned) DeclarationOnly
  (Declared [ValueOf (OperandRef FZ), Lit ",", ValueOf (AttrRef FZ), AttrDict, Lit ":",
             TypeOf (OfGroup (OperandRef FZ)), Custom roomOf [TypeOfGroup (ResultRef FZ)]]) []
  (brief "a room reserved in a cursor lifetime")

--------------------------------------------------------------------------------
-- Cells allocated into a lifetime
--------------------------------------------------------------------------------

||| A cell, counting's type: the memory of one cell of a constructor, its
||| header written, its fields not yet.
cell : TypeC
cell = OurType (SomeType cellType)

||| `idr.cell.stack in %l : !idr.lifetime<k> -> !idr.cell<…>`, C++
||| `CellStackOp`: a slot of its function's frame, an entry-block allocation
||| rewritten at each run of its lifetime, which is bound in this function
||| (the function verifier holds it to that lifetime's own run). Uncounted,
||| and its cell holds no counted field, so its lifetime's end frees
||| nothing. Its cell is the lifetime's, new to no one: it declares no move.
cellStack : Op 1 1 0 0
cellStack = op "cell.stack" [single "lifetime" anyLifetime] [result "cell" cell] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Allocate Frame (Results FZ)] [] Covered Untouched)
  NotSpeculatable (between Graded Owned) DeclarationOnly
  (Declared [Lit "in", ValueOf (OperandRef FZ), Lit ":", TypeOf (OfGroup (OperandRef FZ)), AttrDict,
             Lit "->", QualifiedTypeOf (OfGroup (ResultRef FZ))]) []
  (brief "a slot of its function's frame, in a lifetime of this function")

||| `idr.cell.arena %l : !idr.lifetime<k> -> !idr.cell<…>`, C++
||| `CellArenaOp`: a cell bumped in a lifetime something may allocate into
||| (a room, a cursor, a home), so an allocation into a view cannot be
||| written. Uncounted, and its cell holds no counted field, so its
||| lifetime's end gives its memory back with the rest and drops nothing.
||| Its cell is the lifetime's, new to no one, as a slot's is: it declares
||| no move.
cellArena : Op 1 1 0 0
cellArena = op "cell.arena" [single "lifetime" putLifetime] [result "cell" cell] [] [] []
  [Implements putsIntoLifetime putMethods, Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Allocate Heap (Results FZ)] [] Covered Untouched)
  NotSpeculatable (between Graded Owned) DeclarationOnly
  (Declared [ValueOf (OperandRef FZ), Lit ":", TypeOf (OfGroup (OperandRef FZ)), AttrDict,
             Lit "->", QualifiedTypeOf (OfGroup (ResultRef FZ))]) []
  (brief "a cell bumped in a lifetime something may allocate into")

--------------------------------------------------------------------------------
-- A lifetime split around a framed call
--------------------------------------------------------------------------------

||| `idr.lifetime.pack %l (%held : T…) : !idr.lifetime<cursor> ->
||| !idr.lifetime.package<…>`, C++ `LifetimePackOp`: the end of a per-level
||| lifetime's region before a frame's push. It moves the lifetime's memory
||| and the values held in it into one package, used once by its type, which
||| its region yields; nothing of the lifetime is freed. The last op before
||| its region's terminator; its lifetime is its region's own, of a stack or
||| a chain, never a block.
pack : Op 2 1 0 0
pack = op "lifetime.pack" [single "lifetime" cursorLifetime, variadic "held" anyValue]
  [result "package" (OurType (SomeType packageType))] [] []
  [] [] (Executes [OnValues Allocate Identity (Results FZ)] [] Covered Untouched)
  NotSpeculatable (between Graded Owned) VerifiesOp
  (Declared [ ValueOf (OperandRef FZ)
            , OptionalGroup [Lit "("] (ValueOf (OperandRef (FS FZ)))
                [Lit ":", TypeOf (OfGroup (OperandRef (FS FZ))), Lit ")"]
            , AttrDict, Lit ":", TypeOf (OfGroup (OperandRef FZ)), Lit "->"
            , TypeOf (OfGroup (ResultRef FZ)) ]) []
  (brief "packs a per-level lifetime and the values it holds")

||| `idr.lifetime.unpack %p : !idr.lifetime.package<…> on %base : …
||| entering (%r : T…) in %outers : … -> (T…) { ^(%l, %held…, %entered…):
||| … }`, C++ `LifetimeUnpackOp`: the resume's reopening of a packed
||| lifetime. It consumes the package and binds a fresh cursor lifetime and
||| the held values, restated in it; its end closes the lifetime as its
||| package's source does, unless it packs again. A stack's package holds
||| its mark, which its end gives back to the cursor whose stack it is, so a
||| stack's unpack names that cursor `on %base`, as the stack's opener did,
||| and a chain's names none: the package's type says which, so the operand
||| is no flag. What the framed call put into that cursor while the level
||| was packed lies above the mark, so the level's end frees it: each such
||| value enters the reopened level (`entering`), bound after the held
||| values and restated there, so none is stated in a lifetime that outlives
||| its memory. A chain lies on no cursor, so nothing enters its level.
unpack : Op 4 1 0 1
unpack = op "lifetime.unpack"
  [ single "package" (OurType (SomeType packageType)), optional "base" cursorLifetime
  , variadic "entering" anyValue, variadic "outers" anyLifetime ]
  [results "results" anyValue] [] [sized "body" 1]
  [SingleBlock, OurTrait runsOnce]
  [Implements statesLifetime statedMethods, Implements statesOuters [], Declares RegionBranch onceMethods]
  (closes Touched) NotSpeculatable (between Graded Owned) VerifiesRegions
  (Declared [ ValueOf (OperandRef FZ), Lit ":", TypeOf (OfGroup (OperandRef FZ))
            , OptionalGroup [Lit "on"] (ValueOf (OperandRef (FS FZ)))
                [Lit ":", TypeOf (OfGroup (OperandRef (FS FZ)))]
            , OptionalGroup [Lit "entering", Lit "("] (ValueOf (OperandRef (FS (FS FZ))))
                [Lit ":", TypeOf (OfGroup (OperandRef (FS (FS FZ)))), Lit ")"]
            , OptionalGroup [Lit "in"] (ValueOf (OperandRef (FS (FS (FS FZ)))))
                [Lit ":", TypeOf (OfGroup (OperandRef (FS (FS (FS FZ)))))]
            , AttrDictWithKeyword
            , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef FZ))) []
            , ValueOf (RegionRef FZ) ]) []
  (brief "reopens a packed lifetime, binding it, what it holds and what entered its base since")

--------------------------------------------------------------------------------
-- The area
--------------------------------------------------------------------------------

||| The header the lifetime's C++ includes (`Generated/Lifetimes.h.inc`):
||| what a lowered lifetime is, the kinds and their facts, the openers and
||| the kind each binds. Its block is the dialect's namespace, where a
||| table's enum is declared only where the block names it, so each is
||| named before its table. `Packed` is an ODS enum besides, since the
||| package's parameter is one.
lifetimesHeader : Header
lifetimesHeader = MkHeader "Lifetimes"
  [ ("idr" ::: [], [ EnumOf (enumDef loweredClosed), EnumOf (enumDef kindCaseClosed)
                   , EnumOf (enumDef openerClosed), TableOf kindTable, TableOf openerTable ]) ]
  (brief "a lifetime's kinds and openers and their facts")

export
declarations : Declarations
declarations =
  { ops := openers ++ [SomeOp activation, SomeOp lend, SomeOp forget, SomeOp reserve,
                       SomeOp cellStack, SomeOp cellArena, SomeOp pack, SomeOp unpack]
  , types := [SomeType lifetimeType, SomeType packageType]
  , enums := [enumDef packedClosed]
  , interfaces := [statesLifetime, statesOuters, opensLifetime, putsIntoLifetime]
  , traits := [runsOnce, runsOnceGivingBack, givesLifetime]
  , directives := [sameType, viewOf, roomOf]
  , predicates := [putsPredicate, cursorPredicate, roomPredicate, viewPredicate]
  , headers := [lifetimesHeader]
  } nothing
