-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a value that holds references holds: who frees it, what is known of
||| its sharing, and the hold, the pairs of the two that mean something. Two
||| axes, never one enum: who frees a value decides whether a count is
||| touched, what is known of its sharing decides whether a cell may be
||| rebuilt in place, and every pair of them is meaningful but one, a claim
||| of uniqueness on static data, which is shared by definition and has no
||| constructor here.
|||
||| The hold is its module's own type, so the frontend's generated encoder,
||| which names a closed set's type by its module, names it, and `Hold.Hold`
||| is its one spelling. Who frees a value shares its cases' names with the
||| hold's, so it keeps a namespace of its own.
module IdrisMLIR.Spec.Grades.Hold

%default total

||| Who frees what a value holds: its count, when it reaches zero; the end
||| of the lifetime the op that made it names; or nothing, for static data,
||| which lives for the whole run.
namespace Release
  public export
  data Release = Counted | Scoped | Static

||| What is known of a value's sharing: nothing; that its own family's cells
||| are reached through it alone (through every recursive field of its
||| family); or that nothing it reaches is shared.
public export
data Unique = None | Self | Deep

||| What a value that holds references holds: who frees it and, where
||| something frees it, what is known of its sharing. Static data is shared
||| by every reader of it, so its case takes no claim: `static unique deep`
||| has no constructor.
public export
data Hold = Counted Unique | Scoped Unique | Static

||| Who frees a value at a hold.
public export
release : Hold -> Release
release (Counted _) = Counted
release (Scoped _) = Scoped
release Static = Static

||| What a hold claims of sharing: static data claims nothing.
public export
claim : Hold -> Unique
claim (Counted u) = u
claim (Scoped u) = u
claim Static = None
