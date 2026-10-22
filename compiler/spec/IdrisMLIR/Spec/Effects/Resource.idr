-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The states a compiled program's ops act on, as one tree, and the four
||| kinds of effect MLIR has on them. Two effects conflict only when one's
||| state is the other's or above it, so the tree is the whole of what is
||| ordered with what: the outside is one ordered state with the ways a run
||| ends beneath it; the heap is a sibling of a crash, so heap reads and
||| writes move across a crash or a guard while crashes, exits and output
||| stay ordered among themselves; a fresh identity is no memory at all.
||| Immutable memory, static data and what is fixed for the run are no
||| state: nothing that observes them can tell when they were read.
|||
||| The tree's laws are its types: every parent is declared before its
||| child, so it has one root and no cycle; no state a value reaches sits
||| under one no value reaches; each state takes only its kinds. A tree
||| that breaks one does not check, in every build, where upstream checks
||| the second only in a build with expensive checks and aborts on the
||| third at run time.
module IdrisMLIR.Spec.Effects.Resource

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums

import Data.List
import Data.List.Elem
import Data.List1
import Data.Nat

%default total

------------------------------------------------------------------------------
-- Reach
------------------------------------------------------------------------------

||| Whether an effect on a state may name the value whose state it is: memory
||| a value points to, its count, its memo state, its identity. The outside
||| and the ways a run ends are reached by no value, so an effect on them
||| names none.
public export
data Reach = Addressable | Opaque

||| A child's reach under its parent's. No constructor puts a state a value
||| reaches under one no value reaches.
public export
data ReachFits : (child, parent : Reach) -> Type where
  OpaqueUnderAny : ReachFits Opaque r
  AddressableUnderAddressable : ReachFits Addressable Addressable

||| Evidence that a state is one a value reaches: what an effect naming a
||| value needs of its state.
public export
data Addressed : Reach -> Type where
  IsAddressed : Addressed Addressable

public export
reachClosed : Closed Reach
reachClosed = MkClosed
  { name = ident "ResourceReach"
  , shape = OneOf
  , every = Addressable ::: [Opaque]
  , complete = \case
      Addressable => Here
      Opaque => There Here
  , describe = \case
      Addressable => MkCase (ident "Addressable") (word "addressable" ::: []) (line "an effect on it may name the value whose state it is")
      Opaque => MkCase (ident "Opaque") (word "opaque" ::: []) (line "no value reaches it: an effect on it names none")
  , doc = brief (line "whether an effect on a state may name a value")
  }

------------------------------------------------------------------------------
-- The states
------------------------------------------------------------------------------

||| The states a compiled program's ops act on: upstream's root and frame,
||| and ours. Named for the state each is, never for a reader's question or
||| a mechanism.
public export
data Resource : Type where
  ||| Upstream's root, any memory: the state an op of another dialect acts
  ||| on when it declares no other. No op of ours names it.
  Root : Resource
  ||| Upstream's frame: a function's stack cells.
  Frame : Resource
  ||| The memory any cell lives in, where it comes from and where it goes:
  ||| only acquiring and freeing are on it, everything a live cell holds is
  ||| beneath it, so giving memory back is ordered after every use of it.
  Heap : Resource
  ||| Memory written in place: array elements, buffer bytes, a cell's
  ||| fields while it is filled.
  Contents : Resource
  ||| Reference counts, which counting reads and writes and consuming a
  ||| reference frees.
  Count : Resource
  ||| A memo cell's state, the one cell that changes while references to it
  ||| live.
  MemoState : Resource
  ||| A fresh value's identity, which no memory holds: a value used once, of
  ||| an in-place family, or an unforced memo cell, which two equal builds
  ||| must never share. An allocation on it is no memory acquired.
  Identity : Resource
  ||| The outside, one ordered state: output, input, files, the
  ||| environment, clocks. Never split, so no reading of a clock moves past
  ||| output.
  IO : Resource
  ||| The runtime's own tables, read without IO: the handle table, the saved
  ||| error number. Only read: whatever changes them does IO, which is above
  ||| them, so a read stays after the change and moves across everything
  ||| else.
  RuntimeState : Resource
  ||| The run ending normally. Beneath the outside, so it is ordered with
  ||| output; whatever writes it writes the outside too, so it is ordered
  ||| with a crash.
  Exit : Resource
  ||| The run ending by a crash. Beneath the outside, beside the heap: the
  ||| runtime flushes output before a crash's message, and nothing reads the
  ||| heap after it.
  Crash : Resource
  ||| The run never ending. Beneath a crash, so a loop that may not end
  ||| stays before the crash after it, as eager evaluation runs them.
  Divergence : Resource

public export
resourceClosed : Closed Resource
resourceClosed = MkClosed
  { name = ident "ResourceId"
  , shape = OneOf
  , every = Root ::: [Frame, Heap, Contents, Count, MemoState, Identity, IO, RuntimeState, Exit, Crash, Divergence]
  , complete = \case
      Root => Here
      Frame => There Here
      Heap => There (There Here)
      Contents => There (There (There Here))
      Count => There (There (There (There Here)))
      MemoState => There (There (There (There (There Here))))
      Identity => There (There (There (There (There (There Here)))))
      IO => There (There (There (There (There (There (There Here))))))
      RuntimeState => There (There (There (There (There (There (There (There Here)))))))
      Exit => There (There (There (There (There (There (There (There (There Here))))))))
      Crash => There (There (There (There (There (There (There (There (There (There Here)))))))))
      Divergence => There (There (There (There (There (There (There (There (There (There (There Here))))))))))
  , describe = \case
      Root => MkCase (ident "Root") (word "root" ::: []) (line "upstream's root: any memory")
      Frame => MkCase (ident "Frame") (word "frame" ::: []) (line "upstream's frame: a function's stack cells")
      Heap => MkCase (ident "Heap") (word "heap" ::: []) (line "the memory any cell lives in: acquired and given back")
      Contents => MkCase (ident "Contents") (word "contents" ::: []) (line "memory written in place")
      Count => MkCase (ident "Count") (word "count" ::: []) (line "reference counts")
      MemoState => MkCase (ident "MemoState") (word "memo_state" ::: []) (line "a memo cell's state")
      Identity => MkCase (ident "Identity") (word "identity" ::: []) (line "a fresh value's identity, which no memory holds")
      IO => MkCase (ident "IO") (word "io" ::: []) (line "the outside, one ordered state")
      RuntimeState => MkCase (ident "RuntimeState") (word "runtime_state" ::: []) (line "the runtime's handle table and saved error number")
      Exit => MkCase (ident "Exit") (word "exit" ::: []) (line "the run ending normally")
      Crash => MkCase (ident "Crash") (word "crash" ::: []) (line "the run ending by a crash")
      Divergence => MkCase (ident "Divergence") (word "divergence" ::: []) (line "the run never ending")
  , doc = brief (line "a state of the effect tree")
  }

||| A state's place in the order the tree is declared in, each parent before
||| its children: the measure that makes the tree well founded.
public export
treeRank : Resource -> Nat
treeRank Root = 0
treeRank Frame = 1
treeRank Heap = 2
treeRank Contents = 3
treeRank Count = 4
treeRank MemoState = 5
treeRank Identity = 6
treeRank IO = 7
treeRank RuntimeState = 8
treeRank Exit = 9
treeRank Crash = 10
treeRank Divergence = 11

||| Whether a value reaches the state. The outside's subtree is opaque;
||| memory, counts, memo state, identity and the frame are addressable.
public export
reach : Resource -> Reach
reach Root = Addressable
reach Frame = Addressable
reach Heap = Addressable
reach Contents = Addressable
reach Count = Addressable
reach MemoState = Addressable
reach Identity = Addressable
reach IO = Opaque
reach RuntimeState = Opaque
reach Exit = Opaque
reach Crash = Opaque
reach Divergence = Opaque

||| A state's parent: none for the root; for any other, a state declared
||| before it whose reach admits its own. A cycle, a later parent and a
||| state a value reaches under one no value reaches do not check.
public export
data Parent : Resource -> Type where
  IsRoot : Parent Root
  Under : (p : Resource)
       -> {auto 0 earlier : LT (treeRank p) (treeRank r)}
       -> {auto 0 fits : ReachFits (reach r) (reach p)}
       -> Parent r

public export
parent : (r : Resource) -> Parent r
parent Root = IsRoot
parent Frame = Under Root
parent Heap = Under Root
parent Contents = Under Heap
parent Count = Under Heap
parent MemoState = Under Heap
parent Identity = Under Root
parent IO = Under Root
parent RuntimeState = Under IO
parent Exit = Under IO
parent Crash = Under IO
parent Divergence = Under Crash

||| The state above, the root standing for itself: the sentinel the C++
||| walks up to, so no walk tests for a missing parent.
public export
above : Resource -> Resource
above r = case parent r of
  IsRoot => Root
  Under p => p

------------------------------------------------------------------------------
-- The kinds
------------------------------------------------------------------------------

||| Upstream's four kinds of effect, and no other: a consumption is a free of
||| a count, an acquisition an allocation on the heap, an ending a write of
||| a state a run ends in.
public export
data Kind = Read | Write | Allocate | Free

public export
kindClosed : Closed Kind
kindClosed = MkClosed
  { name = ident "EffectKind"
  , shape = OneOf
  , every = Read ::: [Write, Allocate, Free]
  , complete = \case
      Read => Here
      Write => There Here
      Allocate => There (There Here)
      Free => There (There (There Here))
  , describe = \case
      Read => MkCase (ident "Read") (word "read" ::: []) (line "reads a state")
      Write => MkCase (ident "Write") (word "write" ::: []) (line "writes a state")
      Allocate => MkCase (ident "Allocate") (word "allocate" ::: []) (line "makes a fresh value of a state")
      Free => MkCase (ident "Free") (word "free" ::: []) (line "gives a value of a state up")
  , doc = brief (line "one of MLIR's four kinds of memory effect")
  }

||| Two kinds are the same exactly when their places in the one order are.
public export
DecEq Kind where
  decEq Read Read = Yes Refl
  decEq Write Write = Yes Refl
  decEq Allocate Allocate = Yes Refl
  decEq Free Free = Yes Refl
  decEq Read Write = No (\case Refl impossible)
  decEq Read Allocate = No (\case Refl impossible)
  decEq Read Free = No (\case Refl impossible)
  decEq Write Read = No (\case Refl impossible)
  decEq Write Allocate = No (\case Refl impossible)
  decEq Write Free = No (\case Refl impossible)
  decEq Allocate Read = No (\case Refl impossible)
  decEq Allocate Write = No (\case Refl impossible)
  decEq Allocate Free = No (\case Refl impossible)
  decEq Free Read = No (\case Refl impossible)
  decEq Free Write = No (\case Refl impossible)
  decEq Free Allocate = No (\case Refl impossible)

||| The kinds an op of ours may declare on each state. The root takes none:
||| no op of ours acts on "any memory". Runtime state is only read, so a
||| change of it is IO. A run's ends are only written. The heap is only
||| acquired and given back; what live memory holds is beneath it.
public export
admittedKinds : Resource -> List Kind
admittedKinds Root = []
admittedKinds Frame = [Allocate]
admittedKinds Heap = [Allocate, Free]
admittedKinds Contents = [Read, Write]
admittedKinds Count = [Read, Write, Free]
admittedKinds MemoState = [Read, Write]
admittedKinds Identity = [Allocate]
admittedKinds IO = [Read, Write]
admittedKinds RuntimeState = [Read]
admittedKinds Exit = [Write]
admittedKinds Crash = [Write]
admittedKinds Divergence = [Write]

||| Evidence that the state takes the kind.
public export
0 AdmitsKind : Resource -> Kind -> Type
AdmitsKind r k = Elem k (admittedKinds r)

------------------------------------------------------------------------------
-- Printed names
------------------------------------------------------------------------------

||| How MLIR prints a state: upstream's two as upstream prints them; each of
||| ours as the dialect's name and the state's, flat, the parent left to
||| the tree.
public export
printedName : Resource -> Line
printedName Root = line "<Default>"
printedName Frame = line "AutomaticAllocationScope"
printedName Heap = line "idr.heap"
printedName Contents = line "idr.contents"
printedName Count = line "idr.count"
printedName MemoState = line "idr.memo_state"
printedName Identity = line "idr.identity"
printedName IO = line "idr.io"
printedName RuntimeState = line "idr.runtime_state"
printedName Exit = line "idr.exit"
printedName Crash = line "idr.crash"
printedName Divergence = line "idr.divergence"

||| Whose class a state is: upstream's own, for its root and frame, or ours,
||| generated in `::idr::effects` under its case's name.
public export
data Origin = Upstream | Ours

public export
origin : Resource -> Origin
origin Root = Upstream
origin Frame = Upstream
origin Heap = Ours
origin Contents = Ours
origin Count = Ours
origin MemoState = Ours
origin Identity = Ours
origin IO = Ours
origin RuntimeState = Ours
origin Exit = Ours
origin Crash = Ours
origin Divergence = Ours

------------------------------------------------------------------------------
-- The table the C++ reads
------------------------------------------------------------------------------

||| The tree as the C++ reads it, one array per fact indexed by the state's
||| place: its parent (the root its own, the sentinel a walk up stops at),
||| its reach, the kinds an op of ours may declare on it.
public export
resourceTable : Table
resourceTable = table resourceClosed
  [ MkColumn (ident "resourceParent") (EnumColumn (enumDef resourceClosed))
      (\r => CaseCell (caseRef resourceClosed (above r))) (line "the state above; the root's is itself")
  , MkColumn (ident "resourceReach") (EnumColumn (enumDef reachClosed))
      (\r => CaseCell (caseRef reachClosed (reach r))) (line "whether an effect on it may name a value")
  , MkColumn (ident "resourceKinds") (SetColumn (enumDef kindClosed))
      (\r => setCell kindClosed (admittedKinds r)) (line "the kinds an op of ours may declare on it")
  , MkColumn (ident "resourcePrinted") TextColumn
      (\r => TextCell (lineText (printedName r))) (line "how MLIR prints the state")
  ]
