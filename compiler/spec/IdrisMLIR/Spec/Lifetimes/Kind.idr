-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A lifetime is an SSA value, of type `!idr.lifetime<kind>`. Two facts
||| about it live in two places: what the value is at run time is its type's
||| kind, read in zero steps by every allocation into it, every callee given
||| it, every frame holding it and the lowering; where its memory comes from
||| is the op that opens it, one op per source. The kind is no identity: two
||| lifetimes of one kind have one type, and the identity is the value.
module IdrisMLIR.Spec.Lifetimes.Kind

import Decidable.Decidable

%default total

--------------------------------------------------------------------------------
-- The kind: what the value is at run time
--------------------------------------------------------------------------------

||| What a lifetime value is at run time: nothing, for a lifetime nothing
||| allocates into; a pointer in, to a block of static size whose every cell
||| is at a constant offset; a cursor in and out, an unbounded bump; or
||| nothing, for the per-shard home of a site, which the decide step numbers
||| densely (a number, never a symbol: symbol walks do not see types).
public export
data LifetimeKind = View | Room | Cursor | Home Nat

||| A lifetime something may allocate into. A view has no memory, so an
||| allocation into one has no proof and cannot be written.
public export
data Puts : LifetimeKind -> Type where
  RoomPuts : Puts Room
  CursorPuts : Puts Cursor
  HomePuts : Puts (Home k)

export
Uninhabited (Puts View) where
  uninhabited RoomPuts impossible

public export
puts : (k : LifetimeKind) -> Dec (Puts k)
puts View = No absurd
puts Room = Yes RoomPuts
puts Cursor = Yes CursorPuts
puts (Home k) = Yes HomePuts

||| An argument of kind `a` passed where a parameter of kind `p` is asked:
||| any kind where a view is asked, since nothing happens to a view at run
||| time, so a function that only reads a lifetime has one body; any other
||| kind only to itself, so the call's type check is the mode check and a
||| callee is never given a kind it was not compiled for.
public export
data PassesAs : (arg, param : LifetimeKind) -> Type where
  AsView : PassesAs a View
  AsItself : PassesAs k k

export
passesAsReflexive : (k : LifetimeKind) -> PassesAs k k
passesAsReflexive k = AsItself

export
passesAsTransitive : PassesAs a b -> PassesAs b c -> PassesAs a c
passesAsTransitive _ AsView = AsView
passesAsTransitive x AsItself = x

||| A view asked of nothing but a view: the generic kind is the top.
export
viewPassesOnlyAsView : PassesAs View p -> p = View
viewPassesOnlyAsView AsView = Refl
viewPassesOnlyAsView AsItself = Refl

||| What a lifetime value lowers to. A view and a home are no value, so the
||| lowering drops them from every signature, call and frame by its type,
||| with no context; a room is a pointer in; a cursor a pointer in and out.
public export
data Lowered = NoValue | PointerIn | PointerInOut

public export
lowered : LifetimeKind -> Lowered
lowered View = NoValue
lowered Room = PointerIn
lowered Cursor = PointerInOut
lowered (Home _) = NoValue

--------------------------------------------------------------------------------
-- The opener: where the memory comes from
--------------------------------------------------------------------------------

||| Where a lifetime's memory comes from, one op per source: none
||| (`idr.lifetime`); the per-shard home of its site (`idr.lifetime.home`);
||| a block in the opener's frame, sized by its extent
||| (`idr.lifetime.block`); the stack of its base cursor, whose top it marks
||| and resets (`idr.lifetime.stack`); its own chain of chunks
||| (`idr.lifetime.chain`).
public export
data Opener = NoMemory | AtHome | InBlock | OnStack | InChain

||| A kind's case, without a home's site.
public export
data KindCase = ViewCase | RoomCase | CursorCase | HomeCase

public export
caseOf : LifetimeKind -> KindCase
caseOf View = ViewCase
caseOf Room = RoomCase
caseOf Cursor = CursorCase
caseOf (Home _) = HomeCase

||| A kind of the case, a home at site 0: the facts of a case hold of every
||| site.
public export
kindOfCase : KindCase -> LifetimeKind
kindOfCase ViewCase = View
kindOfCase RoomCase = Room
kindOfCase CursorCase = Cursor
kindOfCase HomeCase = Home 0

||| The kind an opener binds: each fixes its binder's, so a binder of the
||| wrong kind cannot be built. The stack and the chain both bind a cursor:
||| a callee bumps what it is given either way, so the difference stays in
||| the opener.
public export
bound : Opener -> KindCase
bound NoMemory = ViewCase
bound AtHome = HomeCase
bound InBlock = RoomCase
bound OnStack = CursorCase
bound InChain = CursorCase

||| Every opener with memory binds a kind that may be allocated into, and
||| the one without binds a view.
export
boundPuts : (o : Opener) -> Not (o = NoMemory) -> Puts (kindOfCase (bound o))
boundPuts NoMemory n = absurd (n Refl)
boundPuts AtHome _ = HomePuts
boundPuts InBlock _ = RoomPuts
boundPuts OnStack _ = CursorPuts
boundPuts InChain _ = CursorPuts

--------------------------------------------------------------------------------
-- A lifetime per recursion level
--------------------------------------------------------------------------------

||| The openers a lifetime spanning a framed call may have, one instance per
||| recursion level: before the push its region ends by packing it, the
||| frame holds the package, and the resume opens a fresh lifetime from it.
||| Its cells stay where they are while the frame waits, which a block in
||| the opener's native frame cannot do, so a block is never per level.
public export
data PerLevel : Opener -> Type where
  StackLevel : PerLevel OnStack
  ChainLevel : PerLevel InChain

export
Uninhabited (PerLevel InBlock) where
  uninhabited StackLevel impossible

export
Uninhabited (PerLevel NoMemory) where
  uninhabited StackLevel impossible

export
Uninhabited (PerLevel AtHome) where
  uninhabited StackLevel impossible

||| What a package holds, and so how the lifetime it reopens closes: the
||| mark of a stack lifetime (one word), or the chain of a chained one.
public export
data Packed = FromStack | FromChain

public export
packedOpener : Packed -> Opener
packedOpener FromStack = OnStack
packedOpener FromChain = InChain

||| Every package comes from an opener that may be per level.
export
packedPerLevel : (p : Packed) -> PerLevel (packedOpener p)
packedPerLevel FromStack = StackLevel
packedPerLevel FromChain = ChainLevel

||| Whether an opener may be per level.
public export
perLevel : (o : Opener) -> Dec (PerLevel o)
perLevel NoMemory = No absurd
perLevel AtHome = No absurd
perLevel InBlock = No absurd
perLevel OnStack = Yes StackLevel
perLevel InChain = Yes ChainLevel

||| What the package of a per-level opener's lifetime holds: its stack's
||| mark, or its chain.
public export
levelPacked : PerLevel o -> Packed
levelPacked StackLevel = FromStack
levelPacked ChainLevel = FromChain

||| A per-level opener's package reopens a lifetime of that opener.
export
levelPackedOpener : (l : PerLevel o) -> packedOpener (levelPacked l) = o
levelPackedOpener StackLevel = Refl
levelPackedOpener ChainLevel = Refl

||| A package reopens a cursor, as its opener bound.
export
packedBindsCursor : (p : Packed) -> bound (packedOpener p) = CursorCase
packedBindsCursor FromStack = Refl
packedBindsCursor FromChain = Refl
