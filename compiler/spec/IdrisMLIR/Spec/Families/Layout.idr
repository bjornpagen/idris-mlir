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
