-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What an op declares of its effects: two independent facts. Its own
||| effects, each on a state of the tree, static or following from one
||| value's own type by a typed rule; and its regions' effects, covered by
||| its own or added to them. A definition, never executed where it stands,
||| declares nothing. Every op's declaration states what its runtime
||| function does, and none carries a counting decision early: before
||| counting nothing owns a count, so nothing consumes one.
|||
||| Indexed by the op's operand and result group counts, so every value an
||| effect names is a group the op has. An acquisition names the fresh value
||| it makes and a release the value it gives up; an effect naming a value
||| is on a state a value reaches; whatever ends the run normally does IO.
||| A declaration that breaks one does not check.
module IdrisMLIR.Spec.Effects.Declaration

import public IdrisMLIR.Spec.Effects.Resource
import public IdrisMLIR.Spec.Effects.Atom

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Ods

import Control.Relation
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Nat

%default total

------------------------------------------------------------------------------
-- Static effects
------------------------------------------------------------------------------

||| One of an op's value groups, by position among its `i` operand groups
||| and `o` result groups.
public export
data Values : (i, o : Nat) -> Type where
  Operands : Fin i -> Values i o
  Results : Fin o -> Values i o

||| The kinds an effect on a whole state may have. An acquisition names the
||| fresh value it makes and a release the value it gives up: an acquisition
||| naming no value would keep an op that only computes alive, and memory a
||| runtime function takes that no value names is its runtime memory, never
||| an effect.
public export
data Whole : Kind -> Type where
  WholeRead : Whole Read
  WholeWrite : Whole Write

||| Which values an effect of each kind may name: any, for a read or a
||| write; a result, for an acquisition; an operand, for a release.
public export
data Names : {0 i, o : Nat} -> Kind -> Values i o -> Type where
  NamesRead : Names Read values
  NamesWrite : Names Write values
  NamesResult : Names Allocate (Results g)
  NamesOperand : Names Free (Operands g)

||| An effect of an op with `i` operand and `o` result groups: one of MLIR's
||| four kinds on a state the kind is admitted on, either on the state as a
||| whole or on each value of one group.
public export
data Effect : (i, o : Nat) -> Type where
  ||| On the state as a whole: the outside, the runtime's tables, the ways
  ||| a run ends; or memory a callee no value names may act on.
  OnState : (k : Kind) -> (r : Resource.Resource)
         -> {auto 0 admitted : AdmitsKind r k}
         -> {auto 0 whole : Whole k}
         -> Effect i o
  ||| On each value of a group: the memory, count, memo state or identity
  ||| of that value.
  OnValues : (k : Kind) -> (r : Resource.Resource) -> (values : Values i o)
          -> {auto 0 admitted : AdmitsKind r k}
          -> {auto 0 addressed : Addressed (reach r)}
          -> {auto 0 named : Names k values}
          -> Effect i o

------------------------------------------------------------------------------
-- Typed rules
------------------------------------------------------------------------------

||| What a typed rule reads off one value's own type: a fact of its grade
||| or its family, never of where the value came from or how it is used.
||| One C++ predicate each.
public export
data Condition : Type where
  ||| Used once and freed by its count: a reference its holder gives up
  ||| exactly once, so whatever takes the value takes the count over.
  OwnsCount : Condition
  ||| Something reads which value it is: it is used once, its family is
  ||| rebuilt in place, or it is an unforced memo cell, the one cell that
  ||| changes while references to it live. Two equal builds of it are two.
  HasIdentity : Condition
  ||| A memo cell's value, whose state a force changes.
  MemoCell : Condition
  ||| Freed by its count with no claim that it is unshared: whether it is
  ||| shared is known only at run time, from its count.
  MayBeShared : Condition
  ||| A reuse token that holds its cell: unshared, never null.
  HoldsItsCell : Condition
  ||| A value that may reach a foreign cell, whose release may flush or
  ||| close.
  ReachesForeign : Condition
  ||| A buffer: memory written in place. A tensor is a value and has none.
  Buffer : Condition

public export
conditionClosed : Closed Condition
conditionClosed = MkClosed
  { name = ident "EffectCondition"
  , shape = OneOf
  , every = OwnsCount ::: [HasIdentity, MemoCell, MayBeShared, HoldsItsCell, ReachesForeign, Buffer]
  , complete = \case
      OwnsCount => Here
      HasIdentity => There Here
      MemoCell => There (There Here)
      MayBeShared => There (There (There Here))
      HoldsItsCell => There (There (There (There Here)))
      ReachesForeign => There (There (There (There (There Here))))
      Buffer => There (There (There (There (There (There Here)))))
  , describe = \case
      OwnsCount => MkCase (ident "OwnsCount") (word "owns_count" ::: []) (line "used once and freed by its count")
      HasIdentity => MkCase (ident "HasIdentity") (word "has_identity" ::: []) (line "something reads which value it is")
      MemoCell => MkCase (ident "MemoCell") (word "memo_cell" ::: []) (line "a memo cell's value")
      MayBeShared => MkCase (ident "MayBeShared") (word "may_be_shared" ::: []) (line "freed by its count with no claim that it is unshared")
      HoldsItsCell => MkCase (ident "HoldsItsCell") (word "holds_its_cell" ::: []) (line "a reuse token that holds its cell")
      ReachesForeign => MkCase (ident "ReachesForeign") (word "reaches_foreign" ::: []) (line "it may reach a foreign cell")
      Buffer => MkCase (ident "Buffer") (word "buffer" ::: []) (line "a buffer: memory written in place")
  , doc = brief (line "what a typed rule reads off one value's own type")
  }

||| Which side of an op a rule reads a value of.
public export
data Side = OperandSide | ResultSide | EitherSide

||| Where a rule's effects land: on each value it reads, on each result of
||| its op (as the one value it reads decides), or on the state as a whole
||| (as the one value it reads decides).
public export
data Landing = OnTheValues | OnEachResult | OnTheState

public export
landingClosed : Closed Landing
landingClosed = MkClosed
  { name = ident "EffectLanding"
  , shape = OneOf
  , every = OnTheValues ::: [OnEachResult, OnTheState]
  , complete = \case
      OnTheValues => Here
      OnEachResult => There Here
      OnTheState => There (There Here)
  , describe = \case
      OnTheValues => MkCase (ident "OnTheValues") (word "on_the_values" ::: []) (line "on each value the rule reads")
      OnEachResult => MkCase (ident "OnEachResult") (word "on_each_result" ::: []) (line "on each result of the op, as the value read decides")
      OnTheState => MkCase (ident "OnTheState") (word "on_the_state" ::: []) (line "on the state as a whole")
  , doc = brief (line "where a typed rule's effects land")
  }

||| Evidence that a rule reading a value of a side may put an effect of the
||| kind on the state where it lands: a read or a write on any value or the
||| whole state; a release only on an operand it reads; an acquisition only
||| on a result. An effect on a value is on a state a value reaches.
public export
data MayLand : Side -> Landing -> Kind -> Resource.Resource -> Type where
  ReadsOrWritesValues : Addressed (reach s) -> Whole k -> MayLand side OnTheValues k s
  FreesOperands : Addressed (reach s) -> MayLand OperandSide OnTheValues Free s
  AllocatesResults : Addressed (reach s) -> MayLand ResultSide OnTheValues Allocate s
  AllocatesEachResult : Addressed (reach s) -> MayLand side OnEachResult Allocate s
  ReadsOrWritesState : Whole k -> MayLand side OnTheState k s

||| What a rule gives where its condition holds, or where it fails: some
||| kinds of effect on one state, each admitted there and able to land
||| where the rule puts it; or nothing.
public export
data Given : Side -> Type where
  NothingGiven : Given side
  GivenOn : (kinds : List1 Kind) -> (state : Resource.Resource) -> (landing : Landing)
         -> {auto 0 admitted : All (\k => AdmitsKind state k) (forget kinds)}
         -> {auto 0 lands : All (\k => MayLand side landing k state) (forget kinds)}
         -> Given side

||| A rule's whole meaning: the condition it reads off a value's type, and
||| what it gives where the condition holds and where it fails.
public export
record Consequence (side : Side) where
  constructor MkConsequence
  condition : Condition
  holds : Given side
  fails : Given side

||| The rules by which an op's effects follow from one value's type.
public export
data RuleName : Type where
  ||| A value that owns its count is taken over: a free of the count. A
  ||| value that owns none (shared, scoped, static, or any value before
  ||| counting) is only read.
  Consumption : RuleName
  ||| A result whose identity something reads is a fresh identity, never
  ||| merged with an equal one: an allocation on `identity`, no memory.
  FreshIdentity : RuleName
  ||| A result that owns its count takes new memory. Before counting an
  ||| immutable value acquires nothing, so two equal builds are one value
  ||| and an unused one goes.
  Acquisition : RuleName
  ||| A memo cell's state is read.
  MemoRead : RuleName
  ||| A count is read and written where the type does not prove the value
  ||| unshared; an exclusive value's count is never read.
  SharedCount : RuleName
  ||| A token that holds its cell gives a fresh identity on its memory; one
  ||| that may be null, new memory.
  Recycling : RuleName
  ||| Releasing a value that may reach a foreign cell writes the outside,
  ||| since a destructor may flush or close.
  ForeignRelease : RuleName
  ||| A buffer operand's memory is read; a tensor is a value and is not.
  BufferRead : RuleName
  ||| A buffer operand's memory is written; a tensor is a value and is not.
  BufferWrite : RuleName

public export
ruleClosed : Closed RuleName
ruleClosed = MkClosed
  { name = ident "EffectRule"
  , shape = OneOf
  , every = Consumption ::: [FreshIdentity, Acquisition, MemoRead, SharedCount, Recycling, ForeignRelease, BufferRead, BufferWrite]
  , complete = \case
      Consumption => Here
      FreshIdentity => There Here
      Acquisition => There (There Here)
      MemoRead => There (There (There Here))
      SharedCount => There (There (There (There Here)))
      Recycling => There (There (There (There (There Here))))
      ForeignRelease => There (There (There (There (There (There Here)))))
      BufferRead => There (There (There (There (There (There (There Here))))))
      BufferWrite => There (There (There (There (There (There (There (There Here)))))))
  , describe = \case
      Consumption => MkCase (ident "Consumes") (word "consumes" ::: []) (line "takes over a value that owns its count")
      FreshIdentity => MkCase (ident "NewIdentity") (word "new_identity" ::: []) (line "a result whose identity something reads is fresh")
      Acquisition => MkCase (ident "Acquires") (word "acquires" ::: []) (line "a result that owns its count takes new memory")
      MemoRead => MkCase (ident "ReadsMemo") (word "reads_memo" ::: []) (line "reads a memo cell's state")
      SharedCount => MkCase (ident "CountsIfShared") (word "counts_if_shared" ::: []) (line "reads and writes a count the type does not prove unshared")
      Recycling => MkCase (ident "Recycles") (word "recycles" ::: []) (line "a token's cell, or new memory from a token that may be null")
      ForeignRelease => MkCase (ident "ReleasesForeign") (word "releases_foreign" ::: []) (line "releasing what may reach a foreign cell writes the outside")
      BufferRead => MkCase (ident "ReadsBuffers") (word "reads_buffers" ::: []) (line "reads a buffer operand's memory")
      BufferWrite => MkCase (ident "WritesBuffers") (word "writes_buffers" ::: []) (line "writes a buffer operand's memory")
  , doc = brief (line "a rule by which an effect follows from one value's type")
  }

||| The side whose values a rule reads.
public export
side : RuleName -> Side
side Consumption = OperandSide
side FreshIdentity = ResultSide
side Acquisition = ResultSide
side MemoRead = OperandSide
side SharedCount = EitherSide
side Recycling = OperandSide
side ForeignRelease = OperandSide
side BufferRead = OperandSide
side BufferWrite = OperandSide

||| What each rule means.
public export
consequence : (r : RuleName) -> Consequence (side r)
consequence Consumption = MkConsequence OwnsCount (GivenOn (Free ::: []) Count OnTheValues) NothingGiven
consequence FreshIdentity = MkConsequence HasIdentity (GivenOn (Allocate ::: []) Identity OnTheValues) NothingGiven
consequence Acquisition = MkConsequence OwnsCount (GivenOn (Allocate ::: []) Heap OnTheValues) NothingGiven
consequence MemoRead = MkConsequence MemoCell (GivenOn (Read ::: []) MemoState OnTheValues) NothingGiven
consequence SharedCount = MkConsequence MayBeShared (GivenOn (Read ::: [Write]) Count OnTheValues) NothingGiven
consequence Recycling =
  MkConsequence HoldsItsCell (GivenOn (Allocate ::: []) Identity OnEachResult) (GivenOn (Allocate ::: []) Heap OnEachResult)
consequence ForeignRelease = MkConsequence ReachesForeign (GivenOn (Write ::: []) IO OnTheState) NothingGiven
consequence BufferRead = MkConsequence Buffer (GivenOn (Read ::: []) Contents OnTheValues) NothingGiven
consequence BufferWrite = MkConsequence Buffer (GivenOn (Write ::: []) Contents OnTheValues) NothingGiven

||| Evidence that a value group is of the side a rule reads.
public export
data Reads : {0 i, o : Nat} -> Side -> Values i o -> Type where
  ReadsOperand : Reads OperandSide (Operands g)
  ReadsResult : Reads ResultSide (Results g)
  ReadsEither : Reads EitherSide values

||| A typed rule of an op: a rule reading the type of each value of one of
||| its groups; or, for a call, the row it carries, each ordering atom's
||| call effects and a write on each operand its callee writes through.
public export
data TypedRule : (i, o : Nat) -> Type where
  ByType : (rule : RuleName) -> (values : Values i o) -> {auto 0 fits : Reads (side rule) values} -> TypedRule i o
  Summarized : TypedRule i o

||| Takes over each value of an operand group that owns its count.
public export
Consumes : Fin i -> TypedRule i o
Consumes g = ByType Consumption (Operands g)

||| A fresh identity for each value of a result group whose identity
||| something reads.
public export
NewIdentity : Fin o -> TypedRule i o
NewIdentity g = ByType FreshIdentity (Results g)

||| New memory for each value of a result group that owns its count.
public export
Acquires : Fin o -> TypedRule i o
Acquires g = ByType Acquisition (Results g)

||| Reads the memo state of each value of an operand group that is a memo
||| cell's.
public export
ReadsMemo : Fin i -> TypedRule i o
ReadsMemo g = ByType MemoRead (Operands g)

||| Reads and writes the count of each value of a group whose type does not
||| prove it unshared.
public export
CountsIfShared : Values i o -> TypedRule i o
CountsIfShared values = ByType SharedCount values

||| The op's results take the cell the token operand holds, or new memory
||| where the token may be null.
public export
Recycles : Fin i -> TypedRule i o
Recycles token = ByType Recycling (Operands token)

||| Releasing a value of an operand group that may reach a foreign cell
||| writes the outside.
public export
ReleasesForeign : Fin i -> TypedRule i o
ReleasesForeign g = ByType ForeignRelease (Operands g)

||| Reads the memory of each value of an operand group that is a buffer.
public export
ReadsBuffers : Fin i -> TypedRule i o
ReadsBuffers g = ByType BufferRead (Operands g)

||| Writes the memory of each value of an operand group that is a buffer.
public export
WritesBuffers : Fin i -> TypedRule i o
WritesBuffers g = ByType BufferWrite (Operands g)

------------------------------------------------------------------------------
-- Bodies and runtime memory
------------------------------------------------------------------------------

||| Whether an op's regions add their effects to its own.
public export
data Bodies : Type where
  ||| Its own effects cover whatever its regions do, or it has none.
  Covered : Bodies
  ||| Its regions' effects are its own besides what it declares.
  Recursive : Bodies

||| Memory the runtime function an op calls may acquire or give back that
||| no value of the program names: a big number's temporaries, a text
||| buffer, the handle table's growth, a walk's stack, the C library's
||| buffers. It is no MLIR effect, since no value names it; a function's row
||| reports it as `alloc` and `free`.
public export
data RuntimeMemory = Untouched | Touched

public export
runtimeMemoryClosed : Closed RuntimeMemory
runtimeMemoryClosed = MkClosed
  { name = ident "RuntimeMemory"
  , shape = OneOf
  , every = Untouched ::: [Touched]
  , complete = \case
      Untouched => Here
      Touched => There Here
  , describe = \case
      Untouched => MkCase (ident "Untouched") (word "untouched" ::: []) (line "it acquires and gives back no memory no value names")
      Touched => MkCase (ident "Touched") (word "touched" ::: []) (line "it may acquire or give back memory no value names")
  , doc = brief (line "memory a runtime function holds that no value names")
  }

||| What runtime memory reports in a function's row.
public export
runtimeMemoryAtoms : RuntimeMemory -> List Atom
runtimeMemoryAtoms Untouched = []
runtimeMemoryAtoms Touched = [Alloc, Free]

------------------------------------------------------------------------------
-- The law over a declaration's own effects
------------------------------------------------------------------------------

||| Whether some effect of a list is of a sort: a sum, so a law can be a
||| type over it.
public export
data Occurs = Nowhere | Somewhere

public export
anyOf : (Effect i o -> Occurs) -> List (Effect i o) -> Occurs
anyOf found [] = Nowhere
anyOf found (e :: es) = case found e of
  Somewhere => Somewhere
  Nowhere => anyOf found es

||| An effect that ends the run normally.
public export
endsNormally : Effect i o -> Occurs
endsNormally (OnState Write Exit) = Somewhere
endsNormally _ = Nowhere

||| An effect that writes the outside.
public export
writesOutside : Effect i o -> Occurs
writesOutside (OnState Write IO) = Somewhere
writesOutside _ = Nowhere

||| An effect that crashes.
public export
crashes : Effect i o -> Occurs
crashes (OnState Write Crash) = Somewhere
crashes _ = Nowhere

||| Ending the run normally is an IO action: whatever writes the run's end
||| writes the outside, its ancestor, so it is ordered with output and with
||| a crash, its sibling, with no chain between them.
public export
data ExitsInIO : (exits, outside : Occurs) -> Type where
  NoExit : ExitsInIO Nowhere outside
  ExitWithIO : ExitsInIO Somewhere Somewhere

||| Evidence that some effect is of the sort.
public export
data Found : Occurs -> Type where
  IsFound : Found Somewhere

------------------------------------------------------------------------------
-- The declaration
------------------------------------------------------------------------------

||| An op's declaration of its effects.
public export
data Declaration : (i, o : Nat) -> Type where
  ||| Never executed where it stands, as a function's or the program's
  ||| definition: it declares nothing to MLIR, which then reads it as
  ||| unknown, so no pass deletes it as an op with no effect.
  Definition : Declaration i o
  ||| An op that runs where it stands: its own static effects and typed
  ||| rules, its regions', and whether its runtime function holds memory no
  ||| value names.
  Executes : (effects : List (Effect i o)) -> (rules : List (TypedRule i o))
          -> (bodies : Bodies) -> (memory : RuntimeMemory)
          -> {auto 0 exitsInIO : ExitsInIO (anyOf endsNormally effects) (anyOf writesOutside effects)}
          -> Declaration i o

||| An op's static effects.
public export
effectsOf : Declaration i o -> List (Effect i o)
effectsOf Definition = []
effectsOf (Executes effects _ _ _) = effects

||| How an op with no successor ends the run: it writes the run's normal
||| end or a crash, so nothing after it runs and every caller's row says
||| so. What an op that leaves its block with no successor must declare.
public export
data Stops : Declaration i o -> Type where
  StopsByExit : {auto 0 exits : Found (anyOf endsNormally (effectsOf d))} -> Stops d
  StopsByCrash : {auto 0 crash : Found (anyOf crashes (effectsOf d))} -> Stops d

||| An op that runs where it stands and does nothing besides computing its
||| results.
public export
noEffects : Declaration i o
noEffects = Executes [] [] Covered Untouched

------------------------------------------------------------------------------
-- What a call declares for its row
------------------------------------------------------------------------------

||| The effects a call holding an atom declares: each kind the atom
||| summarizes, on its state, naming no value; nothing for an atom that
||| only reports, since nothing is ordered with it.
public export
callEffectsOf : Atom -> List (Effect i o)
callEffectsOf IO = [OnState Read IO, OnState Write IO]
callEffectsOf RuntimeState = [OnState Read RuntimeState]
callEffectsOf Exit = [OnState Write Exit]
callEffectsOf Crash = [OnState Write Crash]
callEffectsOf Divergence = [OnState Write Divergence]
callEffectsOf Count = [OnState Read Count, OnState Write Count]
callEffectsOf MemoState = [OnState Read MemoState, OnState Write MemoState]
callEffectsOf Read = [OnState Read Contents]
callEffectsOf Write = [OnState Write Contents]
callEffectsOf Alloc = []
callEffectsOf Free = []

||| What an effect summarizes as in its function's row.
public export
projectEffect : Effect i o -> List Atom
projectEffect (OnState k r) = project k r WholeState
projectEffect (OnValues k r _) = project k r ThroughValue

||| A call's declared effects summarize back as the atom they stand for, and
||| nothing more: the row a call carries is the row its effects say, so a
||| caller's derivation through a call loses nothing and adds nothing.
export
0 roundTrip : (a : Atom) -> All (\e => projectEffect e = [a]) (callEffectsOf {i} {o} a)
roundTrip IO = [Refl, Refl]
roundTrip RuntimeState = [Refl]
roundTrip Exit = [Refl]
roundTrip Crash = [Refl]
roundTrip Divergence = [Refl]
roundTrip Count = [Refl, Refl]
roundTrip MemoState = [Refl, Refl]
roundTrip Read = [Refl]
roundTrip Write = [Refl]
roundTrip Alloc = []
roundTrip Free = []

||| What an op that runs code no declaration bounds declares (a label's run
||| before defunctionalization, a force): every ordering atom's call
||| effects, and memory no value names. A static row, so the op is never
||| deleted, merged or moved.
public export
unknownCode : Declaration i o
unknownCode = Executes (concatMap callEffectsOf (forget (every atomClosed))) [] Covered Touched

------------------------------------------------------------------------------
-- As ODS and the generated C++ hold it
------------------------------------------------------------------------------

||| A state of ours as the generator prints its class, its parent's
||| definition in it. The recursion goes up the tree, each step to a state
||| declared earlier, so it ends within as many steps as the state's place
||| in the order.
public export
defWithin : (bound : Nat) -> (r : Resource.Resource) -> (0 within : LT (treeRank r) bound) -> ResourceDef
defWithin Z _ LTEZero impossible
defWithin Z _ (LTESucc _) impossible
defWithin (S k) r within = MkResourceDef (describe resourceClosed r).name (printedName r) (parentDef (parent r))
  where
    parentDef : Parent r -> ResourceParent
    parentDef IsRoot = ResourceAtRoot
    parentDef (Under p {earlier}) = case origin p of
      Upstream => ResourceAtRoot
      Ours => ResourceUnder (defWithin k p (transitive earlier (fromLteSucc within)))

||| A state of ours as ODS and the generator name it.
public export
resourceDef : Resource.Resource -> ResourceDef
resourceDef r = defWithin (S (treeRank r)) r reflexive

||| Every state of ours, in the tree's order, each after its parent: the
||| classes the C++ names in `::idr::effects`.
public export
resources : List ResourceDef
resources = concatMap ours (forget (every resourceClosed))
  where
    ours : Resource.Resource -> List ResourceDef
    ours r = case origin r of
      Upstream => []
      Ours => [resourceDef r]

public export
odsState : Resource.Resource -> OdsResource
odsState Root = UpstreamRoot
odsState Frame = UpstreamFrame
odsState r = OurResource (resourceDef r)

public export
odsKind : Kind -> EffectKind
odsKind Read = MemRead
odsKind Write = MemWrite
odsKind Allocate = MemAlloc
odsKind Free = MemFree

public export
odsSubject : Values i o -> Subject i o
odsSubject (Operands g) = OfOperand g
odsSubject (Results g) = OfResult g

public export
odsEffect : Effect i o -> OdsEffect i o
odsEffect (OnState k r) = MkOdsEffect (odsKind k) (odsState r) OfOp
odsEffect (OnValues k r values) = MkOdsEffect (odsKind k) (odsState r) (odsSubject values)

||| A typed rule as the generated table names it: the C++ class of the rule
||| and the values it reads. A call's row is read off the call.
public export
odsRule : TypedRule i o -> OdsRule i o
odsRule (ByType rule values) = MkOdsRule (describe ruleClosed rule).name (odsSubject values)
odsRule Summarized = MkOdsRule (ident "Summarized") OfOp

||| Runtime memory as the generated table names it: a class that reports
||| `alloc` and `free` and gives MLIR no effect.
public export
runtimeMemoryRules : RuntimeMemory -> List (OdsRule i o)
runtimeMemoryRules Untouched = []
runtimeMemoryRules Touched = [MkOdsRule (ident "HoldsRuntimeMemory") OfOp]

||| An op's declaration as ODS and the generated C++ hold it.
public export
ods : Declaration i o -> OdsEffects i o
ods Definition = EveryEffect
ods (Executes effects rules bodies memory) =
  Declares (map odsEffect effects) (map odsRule rules ++ runtimeMemoryRules memory) (odsBodies bodies)
  where
    odsBodies : Bodies -> OdsBodies
    odsBodies Covered = OwnOnly
    odsBodies Recursive = WithBodies

------------------------------------------------------------------------------
-- The tables the C++ reads
------------------------------------------------------------------------------

||| The kinds a rule gives, as a set the C++ reads.
public export
givenKinds : Given side -> List Kind
givenKinds NothingGiven = []
givenKinds (GivenOn kinds _ _) = forget kinds

||| The state a rule gives its effects on, and where they land; the root
||| and the values it reads where it gives none, places the C++ never
||| reads since the kinds are empty.
public export
givenState : Given side -> Resource.Resource
givenState NothingGiven = Root
givenState (GivenOn _ state _) = state

public export
givenLanding : Given side -> Landing
givenLanding NothingGiven = OnTheValues
givenLanding (GivenOn _ _ landing) = landing

||| Each rule's meaning, one array per fact, indexed by the rule.
public export
ruleTable : Table
ruleTable = table ruleClosed
  [ MkColumn (ident "ruleCondition") (EnumColumn (enumDef conditionClosed))
      (\r => CaseCell (caseRef conditionClosed (condition (consequence r)))) (line "what the rule reads off a value's type")
  , MkColumn (ident "ruleHolds") (SetColumn (enumDef kindClosed))
      (\r => setCell kindClosed (givenKinds (holds (consequence r)))) (line "the kinds it gives where the condition holds")
  , MkColumn (ident "ruleHoldsOn") (EnumColumn (enumDef resourceClosed))
      (\r => CaseCell (caseRef resourceClosed (givenState (holds (consequence r))))) (line "the state it gives them on")
  , MkColumn (ident "ruleHoldsLanding") (EnumColumn (enumDef landingClosed))
      (\r => CaseCell (caseRef landingClosed (givenLanding (holds (consequence r))))) (line "where they land")
  , MkColumn (ident "ruleFails") (SetColumn (enumDef kindClosed))
      (\r => setCell kindClosed (givenKinds (fails (consequence r)))) (line "the kinds it gives where the condition fails")
  , MkColumn (ident "ruleFailsOn") (EnumColumn (enumDef resourceClosed))
      (\r => CaseCell (caseRef resourceClosed (givenState (fails (consequence r))))) (line "the state it gives them on")
  , MkColumn (ident "ruleFailsLanding") (EnumColumn (enumDef landingClosed))
      (\r => CaseCell (caseRef landingClosed (givenLanding (fails (consequence r))))) (line "where they land")
  ]

||| What a call holding each atom declares, as the C++ reads it: the kinds
||| on the atom's state.
public export
callKindsTable : Table
callKindsTable = table atomClosed
  [ MkColumn (ident "atomCallKinds") (SetColumn (enumDef kindClosed))
      (\a => setCell kindClosed (map kindOf (callEffectsOf {i = 0} {o = 0} a)))
      (line "the kinds a call holding the atom declares on its state")
  ]
  where
    kindOf : Effect 0 0 -> Kind
    kindOf (OnState k _) = k
    kindOf (OnValues k _ _) = k

public export
runtimeMemoryTable : Table
runtimeMemoryTable = table runtimeMemoryClosed
  [ MkColumn (ident "runtimeMemoryAtoms") (SetColumn (enumDef atomClosed))
      (\m => setCell atomClosed (runtimeMemoryAtoms m)) (line "what runtime memory reports in a function's row")
  ]
