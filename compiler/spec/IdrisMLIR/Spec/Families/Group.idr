-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A family's declaration, as Idris checked it: its erased indices; per
||| constructor the index variables it binds, the equation its result index
||| satisfies, and its fields with their quantities; a reference to a member
||| of the same group by position. A data type is a member applied to index
||| terms, and its identity is this content: no table holds it and nothing
||| looks a label up, so there is no name without a body.
|||
||| A group is a strongly connected component of the instances the frontend
||| registers (`Rose Int` and `List (Rose Int)` are one), its members in the
||| frontend's registration order. Four kinds of member, each with only
||| what it has: Idris's data, whose constructors are its declaration's; a
||| closure sum, whose labels name the function each runs; a memo sum, whose
||| labels also say how a force runs them and which holds its forced value;
||| a frame stack, whose constructors are the frames a recursion pushes.
||| A list and a numeral are shapes the C++ derives from a data member, not
||| kinds of their own.
|||
||| What is erased is absent: a field has a quantity of one or many, never
||| zero; an erased binder is an index variable, or, where it occurs nowhere,
||| a proof, and not declared at all.
module IdrisMLIR.Spec.Families.Group

import Data.Fin
import Data.Vect

import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Grades.Grade

%default total

------------------------------------------------------------------------------
-- What a member says of itself
------------------------------------------------------------------------------

||| Whether a data member's values are rebuilt in place with no run-time
||| test (the registry's `in_place` types): a fact counting reads, not a
||| change of structure, so it is a field of a data member and no kind of
||| its own. At the module's top level, where the frontend's encoder of a
||| member names it.
public export
data Promise = None | InPlace

||| How a force runs a memo label: once, its cell then holding the forced
||| value; or at every force, the cell never written, where the function
||| reaches an observable effect that each force must perform.
public export
data Mode = Memoized | ByName

||| How a declaration names a family member: by its position in the group
||| being declared, or a member of a group made before it.
public export
data Ref : (members : Nat) -> (earlier : Type) -> Type where
  Own : Fin members -> Ref members earlier
  Earlier : earlier -> Ref members earlier

------------------------------------------------------------------------------
-- Constructors and labels
------------------------------------------------------------------------------

||| A field of a constructor or a capture of a label: how often a value of
||| it uses the field, and the field's type over the constructor's binders,
||| in the holder's representation of types (`type binders`).
public export
record Field (type : Nat -> Type) (binders : Nat) where
  constructor MkField
  uses : Uses
  fieldType : type binders

||| A data constructor: its label, for readers; the sorts of the index
||| variables it binds, which are the levels of its own scope; the equation
||| its result satisfies, one term per index of its family, so an equation
||| of the wrong length cannot be written; and its fields, in order.
public export
record Ctor (sort, literal : Type) (type : Nat -> Type) (indices : Nat) where
  constructor MkCtor
  label : String
  arity : Nat
  binders : Vect arity (Sort sort)
  equation : Vect indices (Term sort literal arity)
  fields : List (Field type arity)

||| A label of a closure or memo sum: a constructor whose fields are the
||| captures of the function it runs. Its binders are the lifted function's
||| index parameters; the equation ties those the sum's indices determine,
||| and the others occur in no equation, bound afresh by the dispatch.
public export
record Label (sort, literal, symbol : Type) (type : Nat -> Type) (indices : Nat) where
  constructor MkLabel
  label : String
  function : symbol
  arity : Nat
  binders : Vect arity (Sort sort)
  equation : Vect indices (Term sort literal arity)
  captures : List (Field type arity)

||| A memo sum's label, with how a force runs it.
public export
record MemoLabel (sort, literal, symbol : Type) (type : Nat -> Type) (indices : Nat) where
  constructor MkMemoLabel
  mode : Mode
  label : Label sort literal symbol type indices

------------------------------------------------------------------------------
-- Members and groups
------------------------------------------------------------------------------

||| A member of a group: a label for readers and a list of index sorts, then
||| what its kind holds. A memo sum's states are no declared constructors:
||| `running` and `forced` follow its labels, `forced` holding the value of
||| type `forced` (over the member's indices), so a memo sum has them by
||| construction and no rule checks them.
public export
data Member : (sort, literal, symbol : Type) -> (type : Nat -> Type) -> Type where
  Data : (label : String) -> Promise -> (indices : Vect n (Sort sort))
      -> List (Ctor sort literal type n) -> Member sort literal symbol type
  Closures : (label : String) -> (indices : Vect n (Sort sort))
      -> List (Label sort literal symbol type n) -> Member sort literal symbol type
  Memo : (label : String) -> (indices : Vect n (Sort sort))
      -> List (MemoLabel sort literal symbol type n) -> (forced : type n)
      -> Member sort literal symbol type
  ||| A frame stack: the continuations a recursion on a call cycle pushes,
  ||| one stack per awaited result. Its one index is a natural, its
  ||| constructors' equations `nat j`; a constructor's field of its own
  ||| member is the frame below, and one with none is a base frame.
  Frames : (label : String) -> List (Ctor sort literal type 1)
      -> Member sort literal symbol type

||| The kinds of member, the closed set the C++ storage and the bytecode
||| name: a member's alternative in its sum.
namespace MemberKind
  public export
  data MemberKind = Data | Closures | Memo | Frames

public export
memberKind : Member sort literal symbol type -> MemberKind
memberKind (Data _ _ _ _) = Data
memberKind (Closures _ _ _) = Closures
memberKind (Memo _ _ _ _) = Memo
memberKind (Frames _ _) = Frames

||| A group: one member or more, each naming the group's members by
||| position (`Own`) and earlier groups' by the holder's reference. A field
||| type names the group's members too, so the holder's representation of
||| types is indexed by the group's size and the binders in scope.
public export
record Group (earlier, literal, symbol : Type) (type : Nat -> Nat -> Type) where
  constructor MkGroup
  size : Nat
  members : Vect (S size) (Member (Ref (S size) earlier) literal symbol (type (S size)))
