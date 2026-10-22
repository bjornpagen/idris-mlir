-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The atoms of a function's row: one fact each of what a run of the
||| function may do besides computing its results, each on one state of the
||| tree. A row is a set of them, held on the function's op and on every
||| call of it, never in a value's type, since none changes a calling
||| convention. One name per concept: an atom on a state with one atom is
||| that state's name; a state with two names its atoms by kind, LLVM's own
||| words for the heap's.
|||
||| What an op's effect summarizes as is `project`, total over every kind
||| and state, the root's case included, so a row never loses an effect an
||| op declares (`kept`). The row has no error case: it never refuses a
||| program.
module IdrisMLIR.Spec.Effects.Atom

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Effects.Resource

import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Decidable.Equality

%default total

||| What a run of a function may do, one fact each. A caller orders a call
||| with the first nine; the last two only report, since nothing is ordered
||| for the sake of memory.
public export
data Atom : Type where
  ||| It may read and write the outside.
  IO : Atom
  ||| It may read the runtime's tables.
  RuntimeState : Atom
  ||| It may end the run normally.
  Exit : Atom
  ||| It may end the run by a crash.
  Crash : Atom
  ||| It may never end.
  Divergence : Atom
  ||| It may read or write reference counts.
  Count : Atom
  ||| It may read or write a memo cell's state.
  MemoState : Atom
  ||| It may read memory written in place.
  Read : Atom
  ||| It may write memory in place.
  Write : Atom
  ||| It may acquire memory: reported, never ordered.
  Alloc : Atom
  ||| It may give memory back: reported, never ordered.
  Free : Atom

||| The atoms in the one order the row is printed in: `effects<io, crash,
||| alloc>`. Dense, so every table over them is a load at an atom's place;
||| a row is a set of them, `::idr::EnumSet<::idr::Atom>`.
public export
atomClosed : Closed Atom
atomClosed = MkClosed
  { name = ident "Atom"
  , shape = OneOf
  , every = IO ::: [RuntimeState, Exit, Crash, Divergence, Count, MemoState, Read, Write, Alloc, Free]
  , complete = \case
      IO => Here
      RuntimeState => There Here
      Exit => There (There Here)
      Crash => There (There (There Here))
      Divergence => There (There (There (There Here)))
      Count => There (There (There (There (There Here))))
      MemoState => There (There (There (There (There (There Here)))))
      Read => There (There (There (There (There (There (There Here))))))
      Write => There (There (There (There (There (There (There (There Here)))))))
      Alloc => There (There (There (There (There (There (There (There (There Here))))))))
      Free => There (There (There (There (There (There (There (There (There (There Here)))))))))
  , describe = \case
      IO => MkCase (ident "io") (word "io" ::: []) (line "it may read and write the outside")
      RuntimeState => MkCase (ident "runtime_state") (word "runtime_state" ::: []) (line "it may read the runtime's tables")
      Exit => MkCase (ident "exit") (word "exit" ::: []) (line "it may end the run normally")
      Crash => MkCase (ident "crash") (word "crash" ::: []) (line "it may end the run by a crash")
      Divergence => MkCase (ident "divergence") (word "divergence" ::: []) (line "it may never end")
      Count => MkCase (ident "count") (word "count" ::: []) (line "it may read or write reference counts")
      MemoState => MkCase (ident "memo_state") (word "memo_state" ::: []) (line "it may read or write a memo cell's state")
      Read => MkCase (ident "read") (word "read" ::: []) (line "it may read memory written in place")
      Write => MkCase (ident "write") (word "write" ::: []) (line "it may write memory in place")
      Alloc => MkCase (ident "alloc") (word "alloc" ::: []) (line "it may acquire memory")
      Free => MkCase (ident "free") (word "free" ::: []) (line "it may give memory back")
  , doc = brief (line "what a run of a function may do besides computing its results")
  }

||| The state an atom stands for.
public export
atomState : Atom -> Resource
atomState IO = IO
atomState RuntimeState = RuntimeState
atomState Exit = Exit
atomState Crash = Crash
atomState Divergence = Divergence
atomState Count = Count
atomState MemoState = MemoState
atomState Read = Contents
atomState Write = Contents
atomState Alloc = Heap
atomState Free = Heap

------------------------------------------------------------------------------
-- Projection
------------------------------------------------------------------------------

||| Whether an effect names a value or the state as a whole. It matters only
||| on the root: an op of another dialect acting on "any memory" through a
||| value acts on array elements, and with none it may act on anything.
public export
data Target = ThroughValue | WholeState

||| What an effect on one of the tree's states summarizes as, whatever it
||| names. Consumption (a free of a count) and a fresh identity or frame
||| cell are the function's own business: a call declares its consumption
||| on its own operands, and no caller sees the others. A kind a state does
||| not take summarizes as nothing, since no op can declare it.
public export
stateAtoms : Kind -> Resource -> List Atom
stateAtoms Allocate Heap = [Alloc]
stateAtoms Free Heap = [Free]
stateAtoms Read Contents = [Read]
stateAtoms Write Contents = [Write]
stateAtoms Read Count = [Count]
stateAtoms Write Count = [Count]
stateAtoms Read MemoState = [MemoState]
stateAtoms Write MemoState = [MemoState]
stateAtoms Read IO = [IO]
stateAtoms Write IO = [IO]
stateAtoms Read RuntimeState = [RuntimeState]
stateAtoms Write Exit = [Exit]
stateAtoms Write Crash = [Crash]
stateAtoms Write Divergence = [Divergence]
stateAtoms _ _ = []

||| The state an effect of another dialect on memory through a value acts
||| on: what live memory holds is contents; acquiring and giving it back
||| are the heap's. Counts and memo cells are ours alone, touched only by
||| ops of ours, so this is exact.
public export
valueMemory : Kind -> Resource
valueMemory Read = Contents
valueMemory Write = Contents
valueMemory Allocate = Heap
valueMemory Free = Heap

||| Every atom an effect of the kind on any state may summarize as: what an
||| effect on the root naming no value is, since it may act on anything.
public export
everyAtomOf : Kind -> List Atom
everyAtomOf k = concatMap taken (forget (every resourceClosed))
  where
    taken : Resource -> List Atom
    taken r = case isElem k (admittedKinds r) of
      Yes _ => stateAtoms k r
      No _ => []

||| What an op's effect summarizes as in its function's row.
public export
project : Kind -> Resource -> Target -> List Atom
project k Root n = rootAtoms n
  where
    rootAtoms : Target -> List Atom
    rootAtoms ThroughValue = stateAtoms k (valueMemory k)
    rootAtoms WholeState = everyAtomOf k
project k r _ = stateAtoms k r

------------------------------------------------------------------------------
-- No effect is lost
------------------------------------------------------------------------------

||| The effects a function keeps to itself: consumption, a fresh identity, a
||| frame cell.
public export
data Local : Kind -> Resource -> Type where
  CountTakenOver : Local Free Count
  IdentityMade : Local Allocate Identity
  FrameCellMade : Local Allocate Frame

||| What an effect an op may declare becomes in the row: atoms, at least
||| one, each on the effect's own state, so a call holding them conflicts
||| with everything the op does; or nothing, for an effect the function
||| keeps to itself.
public export
data Kept : Kind -> Resource -> List Atom -> Type where
  Projected : {0 atoms : List Atom}
            -> (0 nonEmpty : NonEmpty atoms)
            -> (0 onIt : All (\a => atomState a = r) atoms)
            -> Kept k r atoms
  KeptLocal : (0 local : Local k r) -> Kept k r []

||| What keeping says of one kind on one state, whatever the effect names.
0 KeptFor : Resource -> Kind -> Type
KeptFor r k = (n : Target) -> Kept k r (project k r n)

||| Each state's admitted kinds in the order `admittedKinds` lists them, each
||| kept. One clause per state, its entries checked at a known kind and
||| state, so each index reduces to a closed list and no case is a proof
||| taken apart: the root admits nothing, so its entry is empty.
0 keptOn : (r : Resource) -> All (KeptFor r) (admittedKinds r)
keptOn Root = []
keptOn Frame = [\_ => KeptLocal FrameCellMade]
keptOn Heap = [\_ => Projected IsNonEmpty [Refl], \_ => Projected IsNonEmpty [Refl]]
keptOn Contents = [\_ => Projected IsNonEmpty [Refl], \_ => Projected IsNonEmpty [Refl]]
keptOn Count = [\_ => Projected IsNonEmpty [Refl], \_ => Projected IsNonEmpty [Refl], \_ => KeptLocal CountTakenOver]
keptOn MemoState = [\_ => Projected IsNonEmpty [Refl], \_ => Projected IsNonEmpty [Refl]]
keptOn Identity = [\_ => KeptLocal IdentityMade]
keptOn IO = [\_ => Projected IsNonEmpty [Refl], \_ => Projected IsNonEmpty [Refl]]
keptOn RuntimeState = [\_ => Projected IsNonEmpty [Refl]]
keptOn Exit = [\_ => Projected IsNonEmpty [Refl]]
keptOn Crash = [\_ => Projected IsNonEmpty [Refl]]
keptOn Divergence = [\_ => Projected IsNonEmpty [Refl]]

||| Every effect an op of ours may declare is kept: the row never says less
||| than the ops it summarizes. The kind's admission is its place in its
||| state's list, which picks its entry.
export
0 kept : (k : Kind) -> (r : Resource) -> AdmitsKind r k -> (n : Target) -> Kept k r (project k r n)
kept _ r admitted = indexAll {p = KeptFor r} admitted (keptOn r)

------------------------------------------------------------------------------
-- The tables the C++ reads
------------------------------------------------------------------------------

||| The atoms as the C++ reads them: each one's state. The row's value is a
||| set of them.
public export
atomTable : Table
atomTable = table atomClosed
  [ MkColumn (ident "atomState") (EnumColumn (enumDef resourceClosed))
      (\a => CaseCell (caseRef resourceClosed (atomState a))) (line "the state the atom stands for")
  ]

||| What an op's effect on each state summarizes as, one column per kind,
||| indexed by the state: the root's column entry is what an effect naming
||| no value is, since the C++ folds an effect of another dialect naming a
||| value onto `valueMemory` first.
public export
projectionTable : Table
projectionTable = table resourceClosed
  [ column (ident "projectRead") Read
  , column (ident "projectWrite") Write
  , column (ident "projectAllocate") Allocate
  , column (ident "projectFree") Free
  ]
  where
    column : Ident -> Kind -> Column Resource
    column name k = MkColumn name (SetColumn (enumDef atomClosed))
      (\r => setCell atomClosed (project k r WholeState)) (line "what an effect of the kind on the state summarizes as")

||| Where an effect of another dialect on memory through a value lands,
||| per kind.
public export
valueMemoryTable : Table
valueMemoryTable = table kindClosed
  [ MkColumn (ident "valueMemory") (EnumColumn (enumDef resourceClosed))
      (\k => CaseCell (caseRef resourceClosed (valueMemory k))) (line "the state an effect on memory through a value acts on")
  ]
