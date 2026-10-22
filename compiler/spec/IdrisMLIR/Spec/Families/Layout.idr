-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Inline or in a cell is layout, one function of a data type computed when
||| the type is made: never a type of its own, never the frontend's choice.
|||
||| An application's class is `Closed` when every index term is closed and
||| its unfolding stays within the shape budget, `Unknown` otherwise; all
||| `Unknown` applications of one member share its layout. A memo member is
||| a cell, since a force writes the one cell every reference sees. A member
||| of numeral shape (`Fin`, `Elem`, `LNat`, a user's Peano type) is a
||| number: a fixed width where its bound is closed and fits one, a natural
||| otherwise. Any other member at `Unknown` is a cell when its group is
||| recursive and in place over its constructors when it is not; at `Closed`
||| it is in place over the constructors its indices leave possible, unless
||| the unfolding meets an application again or passes the budget, when it
||| takes its member's layout at `Unknown`. The lifetime chooses where a
||| cell lives, never whether a value is one.
module IdrisMLIR.Spec.Families.Layout

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1

%default total

||| Whether an application's indices fix its shape.
public export
data Class = Closed | Unknown

||| What a value of a data type is at run time: a number of a fixed width,
||| a natural (a big's word), its constructors' fields in place (a tag
||| first where two or more are possible, nothing where none is), one
||| pointer to a cell, or the top of a frame stack: linear by its type,
||| uncounted, contiguous, its frame below implicit by position. One enum,
||| so no width can stand beside a layout that has none.
public export
data Layout = Word8 | Word16 | Word32 | Word64 | Natural | InPlace | Cell | FrameStack

||| Whether a value's type bounds everything it reaches: no member that
||| holds itself at an unknown index, and no cell sized at run time (a
||| string, a big number, an array, a natural), none whose contents a run
||| changes (a memo cell) and no frame stack, all of which grow with the
||| input. A value borrowed past its last use holds a fixed number of bytes
||| only where its type bounds what it reaches.
public export
data Reach = Bounded | Unbounded

||| Whether the cells a member's `unique self` claim covers (its own, and
||| those of every member a field of its group or of an `in_place` family
||| names) hold a buffer, read off the declaration. The promise asks the
||| same of every type rebuilt in place, its own cells unshared, which
||| covers a held buffer's storage; what a buffer changes is where it binds: a
||| buffer is written in place wherever its value is, not only where a cell
||| is rebuilt, so a value whose own cells hold one carries the promise by
||| construction, and a parameter of quantity 1 is owed it at the boundary.
public export
data Buffers = NoBuffer | HoldsBuffer

||| Whether a value of a family can reach a closure or a suspension, through
||| its members' fields and the families they name, read off the
||| declaration when the family is made: each exists only before
||| idr-defunctionalize makes it a constructor of a sum, so past it no value
||| reaches one, which a value's type answers with no walk of the program.
public export
data ClosureReach = NoClosure | ReachesClosure

||| Whether values of two applications of one member are the same words at
||| run time. A closed application held in place is its own unfolding, over
||| the fields its indices determine; every other value of a member (a
||| cell, a frame stack, a value in place at an unknown class) is laid out
||| as its member at an unknown index, which all such applications share;
||| a number is its layout's word. Where they are not the same words, a
||| reindex between them re-packs.
public export
data LayoutMatch = SameLayout | OtherLayout

||| The most runtime components a closed application unfolds to before it
||| takes its member's layout at an unknown index. It bounds the classes,
||| and so the copies specialization by class makes; a spent budget leaves
||| a value in its cells and never refuses a program. Each application
||| unfolded spends one besides its components, so an unfolding whose
||| applications keep nothing in place stops too. Measured on the
||| stage-1 module (copies per function against the components a value
||| keeps in place) before it is fixed.
public export
shapeBudget : Nat
shapeBudget = 16

------------------------------------------------------------------------------
-- The closed sets the C++ storage reads
------------------------------------------------------------------------------

export
layoutClosed : Closed Layout
layoutClosed = MkClosed
  { name = "Layout"
  , shape = OneOf
  , every = Word8 ::: [Word16, Word32, Word64, Natural, InPlace, Cell, FrameStack]
  , complete = \case
      Word8 => Here
      Word16 => There Here
      Word32 => There (There Here)
      Word64 => There (There (There Here))
      Natural => There (There (There (There Here)))
      InPlace => There (There (There (There (There Here))))
      Cell => There (There (There (There (There (There Here)))))
      FrameStack => There (There (There (There (There (There (There Here))))))
  , describe = \case
      Word8 => MkCase "Word8" ("word8" ::: []) "a number below 2^8"
      Word16 => MkCase "Word16" ("word16" ::: []) "a number below 2^16"
      Word32 => MkCase "Word32" ("word32" ::: []) "a number below 2^32"
      Word64 => MkCase "Word64" ("word64" ::: []) "a number below 2^64"
      Natural => MkCase "Natural" ("natural" ::: []) "a natural, a big's word"
      InPlace => MkCase "InPlace" ("in_place" ::: []) "its constructors' fields in place, a tag where two are possible"
      Cell => MkCase "Cell" ("cell" ::: []) "one pointer to a cell"
      FrameStack => MkCase "FrameStack" ("frame_stack" ::: []) "the top of a frame stack, linear and uncounted"
  , doc = brief "what a value of a data type is at run time"
  }

export
classClosed : Closed Class
classClosed = MkClosed
  { name = "Class"
  , shape = OneOf
  , every = Closed ::: [Unknown]
  , complete = \case
      Closed => Here
      Unknown => There Here
  , describe = \case
      Closed => MkCase "Closed" ("closed" ::: []) "every index closed and its unfolding within the shape budget"
      Unknown => MkCase "Unknown" ("unknown" ::: []) "an index names a level, holds an opaque term, or unfolds past the budget"
  , doc = brief "whether an application's indices fix its shape"
  }

export
reachClosed : Closed Reach
reachClosed = MkClosed
  { name = "Reach"
  , shape = OneOf
  , every = Bounded ::: [Unbounded]
  , complete = \case
      Bounded => Here
      Unbounded => There Here
  , describe = \case
      Bounded => MkCase "Bounded" ("bounded" ::: []) "everything a value reaches is bounded by its type"
      Unbounded => MkCase "Unbounded" ("unbounded" ::: []) "a value may reach a self-holding member or a cell sized at run time"
  , doc = brief "whether a value's type bounds everything it reaches"
  }

export
buffersClosed : Closed Buffers
buffersClosed = MkClosed
  { name = "Buffers"
  , shape = OneOf
  , every = NoBuffer ::: [HoldsBuffer]
  , complete = \case
      NoBuffer => Here
      HoldsBuffer => There Here
  , describe = \case
      NoBuffer => MkCase "NoBuffer" ("no_buffer" ::: []) "no cell the claim on its own cells covers holds a buffer"
      HoldsBuffer => MkCase "HoldsBuffer" ("holds_buffer" ::: []) "a cell the claim on its own cells covers holds a buffer"
  , doc = brief "whether a member's own cells hold a buffer"
  }

export
closureReachClosed : Closed ClosureReach
closureReachClosed = MkClosed
  { name = "ClosureReach"
  , shape = OneOf
  , every = NoClosure ::: [ReachesClosure]
  , complete = \case
      NoClosure => Here
      ReachesClosure => There Here
  , describe = \case
      NoClosure => MkCase "NoClosure" ("no_closure" ::: []) "no value of the family reaches a closure or a suspension"
      ReachesClosure => MkCase "ReachesClosure" ("reaches_closure" ::: []) "a value of the family can reach a closure or a suspension"
  , doc = brief "whether a family's values can reach a closure or a suspension"
  }

export
layoutMatchClosed : Closed LayoutMatch
layoutMatchClosed = MkClosed
  { name = "LayoutMatch"
  , shape = OneOf
  , every = SameLayout ::: [OtherLayout]
  , complete = \case
      SameLayout => Here
      OtherLayout => There Here
  , describe = \case
      SameLayout => MkCase "SameLayout" ("same_layout" ::: []) "the two are the same words at run time"
      OtherLayout => MkCase "OtherLayout" ("other_layout" ::: []) "a value of one is re-packed to be a value of the other"
  , doc = brief "whether two data types are the same words at run time"
  }
