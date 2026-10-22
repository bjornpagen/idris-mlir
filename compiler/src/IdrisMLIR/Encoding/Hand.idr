-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The `idr` types and attributes whose parameters the dialect's C++ codes
||| by hand: the families' index terms, sorts and members
||| (`lib/IR/Families/Bytecode.cpp`), a natural's index term, a grade's hold
||| and a termination proof. The specification's generator gives each of
||| their encoders such a parameter as its parts already laid out, and an
||| entry's parts can only be laid out once the writer has numbered what it
||| holds; so the frontend holds these values typed, and lays out their
||| parts here, in the order and the form the hand C++ reads them. `ty` and
||| `at` are what the types and attributes they hold are: the frontend's own
||| while Emit makes them, their entries once the writer has numbered them.
module IdrisMLIR.Encoding.Hand

import IdrisMLIR.MLIR.Parts
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Functions.Termination
import IdrisMLIR.Spec.Grades.Declarations
import IdrisMLIR.Spec.Grades.Grade

%default total

------------------------------------------------------------------------------
-- Terms, sorts and members
------------------------------------------------------------------------------

||| One node of an index term, in preorder: a natural; a level of the scope
||| the term is written in; a successor, the count it adds (at least one),
||| followed by its level's node; a literal, a typed attribute or the type
||| attribute of a type; a constructor of a family's member, its group
||| absent for the group the term is declared in, followed by its `arity`
||| arguments (the constructor's binders, then its fields); or an index
||| outside the language.
public export
data TermNode : (ty, at : Type) -> Type where
  NatNode : Nat -> TermNode ty at
  LevelNode : Nat -> TermNode ty at
  SuccNode : (count : Nat) -> TermNode ty at
  LitNode : at -> TermNode ty at
  ConNode : (group : Maybe at) -> (member, tag, arity : Nat) -> TermNode ty at
  OpaqueNode : TermNode ty at

||| The sort of an index position or a constructor's binder: a natural, a
||| type, an index outside the language, a scalar of the type given, or a
||| member of a family, its group absent for the group the sort is declared
||| in.
public export
data SortOf : (ty, at : Type) -> Type where
  SortNat : SortOf ty at
  SortType : SortOf ty at
  SortOpaque : SortOf ty at
  SortScalar : ty -> SortOf ty at
  SortFamily : (group : Maybe at) -> (member : Nat) -> SortOf ty at

||| A constructor of a data member: its label, its binders' sorts, its
||| equation (one term per index of its family, in its own scope) and its
||| fields' types.
public export
data CtorDecl : (ty, at : Type) -> Type where
  MkCtorDecl : (label : String) -> (binders : List (SortOf ty at)) -> (equation : List (TermNode ty at)) ->
               (fields : List ty) -> CtorDecl ty at

||| A data member of a group: its label, what its library promises of its
||| values, its declaration's location, its index sorts and its
||| constructors. The frontend declares data members alone; the passes that
||| make closures, memo cells and frames add the other kinds.
public export
data DataMember : (ty, at : Type) -> Type where
  MkDataMember : (label : String) -> Promise -> (loc : at) -> (indices : List (SortOf ty at)) ->
                 (ctors : List (CtorDecl ty at)) -> DataMember ty at

------------------------------------------------------------------------------
-- The types and attributes
------------------------------------------------------------------------------

||| The hand-coded `idr` types: `!idr.data`, a member of a family's group
||| applied to one term per index, refined to the tags a dense array of
||| `i32` holds (none unrefined, empty uninhabited); `!idr.self`, a member
||| of the group being declared, in a field of that group; `!idr.nat`, a
||| natural, linked to the one index term it is; and `!idr.graded`, a
||| carrier's uses and, where it holds references, its hold.
public export
data HandType : (ty, at : Type) -> Type where
  DataOf : (group : at) -> (member : Nat) -> (indices : List (TermNode ty at)) -> (refinement : Maybe at) -> HandType ty at
  SelfOf : (member : Nat) -> (indices : List (TermNode ty at)) -> HandType ty at
  NatOf : (index : List (TermNode ty at)) -> HandType ty at
  GradedOf : Uses -> Maybe Hold -> (carrier : ty) -> HandType ty at

||| The hand-coded `idr` attributes: `#idr.family`, a group's data
||| members; `#idr.index_binders`, the sorts of a function's index
||| parameters or a region's binders; `#idr.index_args`, the terms a call or
||| a lifted function's maker gives them; and `#idr.terminates`, what Idris
||| proved of a function's loops.
public export
data HandAttr : (ty, at : Type) -> Type where
  FamilyOf : List (DataMember ty at) -> HandAttr ty at
  BindersOf : List (SortOf ty at) -> HandAttr ty at
  ArgsOf : List (TermNode ty at) -> HandAttr ty at
  TerminatesOf : Proof -> HandAttr ty at

------------------------------------------------------------------------------
-- The parts, as the hand C++ reads them
------------------------------------------------------------------------------

||| How many whole terms a run of nodes in preorder holds: a node with no
||| term above it still owed children begins a term, and owes its own (a
||| successor its level, a constructor its arguments).
export
countTerms : List (TermNode ty at) -> Nat
countTerms = go 0 0
  where
    children : TermNode ty at -> Nat
    children (SuccNode _) = 1
    children (ConNode _ _ _ arity) = arity
    children _ = 0
    go : (whole, owed : Nat) -> List (TermNode ty at) -> Nat
    go whole owed [] = whole
    go whole Z (n :: ns) = go (S whole) (children n) ns
    go whole (S owed) (n :: ns) = go whole (owed + children n) ns

||| A node: its kind's number in the specification's set of kinds, then a
||| natural's, a level's or a successor's value; a literal's attribute; a
||| constructor's optional group, member, tag and arity; an opaque term
||| nothing.
nodeParts : TermNode TypeRef AttrRef -> List Part
nodeParts (NatNode n) = [VarInt (position termKindClosed Natural), VarInt n]
nodeParts (LevelNode k) = [VarInt (position termKindClosed Level), VarInt k]
nodeParts (SuccNode k) = [VarInt (position termKindClosed Successor), VarInt k]
nodeParts (LitNode a) = [VarInt (position termKindClosed Literal), AttrAt a]
nodeParts (ConNode grp m t n) = [VarInt (position termKindClosed Constructor), OptionalAttrAt grp, VarInt m, VarInt t, VarInt n]
nodeParts OpaqueNode = [VarInt (position termKindClosed Opaque)]

||| Index terms: how many nodes, then each node.
export
termsParts : List (TermNode TypeRef AttrRef) -> List Part
termsParts ns = VarInt (length ns) :: concatMap nodeParts ns

||| A sort: its kind's number, then a scalar's type, or a member's optional
||| group and its member.
sortParts : SortOf TypeRef AttrRef -> List Part
sortParts SortNat = [VarInt (position sortKindClosed NatSort)]
sortParts SortType = [VarInt (position sortKindClosed TypeSort)]
sortParts SortOpaque = [VarInt (position sortKindClosed OpaqueSort)]
sortParts (SortScalar t) = [VarInt (position sortKindClosed ScalarSort), TypeAt t]
sortParts (SortFamily grp m) = [VarInt (position sortKindClosed FamilySort), OptionalAttrAt grp, VarInt m]

||| Sorts: how many, then each.
export
sortsParts : List (SortOf TypeRef AttrRef) -> List Part
sortsParts ss = VarInt (length ss) :: concatMap sortParts ss

||| A constructor: its label, its binders' sorts, its equation's terms, and
||| its fields' types, how many and then each.
ctorParts : CtorDecl TypeRef AttrRef -> List Part
ctorParts (MkCtorDecl l bs eq fs) =
  Str l :: sortsParts bs ++ termsParts eq ++ VarInt (length fs) :: map TypeAt fs

||| A data member: its kind among the members' kinds, its label, its
||| promise's number, its location, its index sorts, and its constructors,
||| how many and then each.
memberParts : DataMember TypeRef AttrRef -> List Part
memberParts (MkDataMember l p loc is cs) =
  [VarInt (position memberKindClosed Data), Str l, VarInt (position promiseClosed p), AttrAt loc]
  ++ sortsParts is ++ VarInt (length cs) :: concatMap ctorParts cs

||| A group's members: how many, then each.
export
membersParts : List (DataMember TypeRef AttrRef) -> List Part
membersParts ms = VarInt (length ms) :: concatMap memberParts ms

||| A data type's refinement: an optional attribute, the dense array of its
||| tags.
export
refinementParts : Maybe AttrRef -> List Part
refinementParts r = [OptionalAttrAt r]

||| A family's group, by its attribute's entry.
export
groupParts : AttrRef -> List Part
groupParts g = [AttrAt g]

||| A hold: zero where a carrier holds no reference, else one more than its
||| case's place among the holds.
export
holdParts : Maybe Hold -> List Part
holdParts Nothing = [VarInt 0]
holdParts (Just h) = [VarInt (S (position holdClosed h))]

||| A termination proof: zero for a made function's acyclicity, else one
||| more than the component Idris proved it in.
export
proofParts : Proof -> List Part
proofParts MadeAcyclic = [VarInt 0]
proofParts (ProvedIn c) = [VarInt (S c)]
