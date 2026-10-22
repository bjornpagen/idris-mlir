-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The index language of a family: what an erased index of a data type may
||| be, in the one form a type holds. A natural is a number, never a chain
||| of successors; a variable is a de Bruijn level of the scope that binds
||| it, so a type prints and is uniqued with no context and a value keeps
||| one type as it flows inward; anything the language has no term for is
||| opaque, which is sound and refines nothing.
|||
||| The terms are well-scoped by construction (a level is a `Fin s`), and
||| in normal form by construction: a successor applies only to a level, so
||| `nat 3 + 1` and `(v + 1) + 1` cannot be written, only `nat 4` and
||| `v + 2`. The C++ holds the same terms as a preorder array of nodes whose
||| kinds are `TermKind`'s, printed from here.
module IdrisMLIR.Spec.Families.Terms

import Data.Fin
-- `TSucc`'s automatic proof is searched where it is written.
import public Data.Nat
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Sorts
------------------------------------------------------------------------------

||| The scalar types an index may range over: a literal of one of them is a
||| term of that sort. `Char` is a code point, an `i32`.
public export
data Scalar = I8 | I16 | I32 | I64 | F64 | Str | Big

||| The sort of an index position or a constructor's binder: what its terms
||| may be. `family` is how the holder names a member of a family: by
||| position in the group being declared, or a member of an earlier group.
||| A lifetime is never a sort: a lifetime is a value, not an index.
public export
data Sort : (family : Type) -> Type where
  ||| A natural, or a member of numeral shape (`Fin`, `Elem`), whose values
  ||| are numbers.
  SNat : Sort family
  ||| An Idris type, known by the MLIR type the frontend gives it.
  SType : Sort family
  ||| Anything else: its terms are levels and `opaque` alone.
  SOpaque : Sort family
  SScalar : Scalar -> Sort family
  SFamily : family -> Sort family

||| The kinds of sort, the closed set the C++ storage and the bytecode name.
public export
data SortKind = NatSort | TypeSort | OpaqueSort | ScalarSort | FamilySort

public export
sortKind : Sort family -> SortKind
sortKind SNat = NatSort
sortKind SType = TypeSort
sortKind SOpaque = OpaqueSort
sortKind (SScalar _) = ScalarSort
sortKind (SFamily _) = FamilySort

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| An index term over `s` binders, in normal form.
|||
||| `literal` is the holder's constant (an integer, a character, a string,
||| a type), compared by value; `family` names a constructor's family.
public export
data Term : (family, literal : Type) -> (s : Nat) -> Type where
  ||| A natural.
  TNat : Nat -> Term family literal s
  ||| The binder at this level of the scope.
  TVar : Fin s -> Term family literal s
  ||| A level plus a positive count: the one successor form, so a natural
  ||| is never a chain of successors and two successors never nest.
  TSucc : Fin s -> (k : Nat) -> {auto 0 positive : IsSucc k} -> Term family literal s
  ||| A constant of a scalar sort, or a type.
  TLit : literal -> Term family literal s
  ||| Constructor `tag` of a family member, applied to its binders, then
  ||| its fields, in declaration order.
  TCon : family -> (tag : Nat) -> List (Term family literal s) -> Term family literal s
  ||| An index outside the language: equal to every other opaque term, so
  ||| a decision that reads one learns nothing.
  TOpaque : Term family literal s

||| The kinds of term, the closed set the C++ storage and the bytecode name.
public export
data TermKind = Natural | Level | Successor | Literal | Constructor | Opaque

public export
termKind : Term family literal s -> TermKind
termKind (TNat _) = Natural
termKind (TVar _) = Level
termKind (TSucc _ _) = Successor
termKind (TLit _) = Literal
termKind (TCon _ _ _) = Constructor
termKind TOpaque = Opaque

||| A term plus `k`, in normal form: what Idris's `S` applied `k` times is.
||| Only a term of a natural's sort has a successor; any other term plus a
||| positive count has no term of the language, so it is opaque, which is
||| sound.
public export
plus : Term family literal s -> Nat -> Term family literal s
plus t Z = t
plus (TNat n) (S k) = TNat (n + S k)
plus (TVar v) (S k) = TSucc v (S k)
plus (TSucc v j) (S k) = TSucc v (j + S k) {positive = plusSucc j k}
  where
    plusSucc : (a, b : Nat) -> IsSucc (a + S b)
    plusSucc Z b = ItIsSucc
    plusSucc (S a) b = ItIsSucc
plus (TLit _) (S _) = TOpaque
plus (TCon _ _ _) (S _) = TOpaque
plus TOpaque (S _) = TOpaque

||| A term over `s` binders seen under `n` more: levels count from the
||| outside in, so a term keeps its meaning, and its form, unchanged.
public export
weaken : (n : Nat) -> Term family literal s -> Term family literal (s + n)
weaken n (TNat k) = TNat k
weaken n (TVar v) = TVar (weakenN n v)
weaken n (TSucc v k {positive}) = TSucc (weakenN n v) k {positive}
weaken n (TLit c) = TLit c
weaken n (TCon f tag args) = TCon f tag (weakenAll args)
  where
    weakenAll : List (Term family literal s) -> List (Term family literal (s + n))
    weakenAll [] = []
    weakenAll (a :: as) = weaken n a :: weakenAll as
weaken n TOpaque = TOpaque

mutual
  ||| Whether a term names no binder: a closed term is a value the class
  ||| rule may unfold, an open one stands for every value.
  public export
  data Closed : Term family literal s -> Type where
    ClosedNat : Closed (TNat n)
    ClosedLit : Closed (TLit c)
    ClosedCon : AllClosed args -> Closed (TCon f tag args)

  ||| Every term of a list is closed.
  public export
  data AllClosed : List (Term family literal s) -> Type where
    NoneLeft : AllClosed []
    OneMore : Closed t -> AllClosed ts -> AllClosed (t :: ts)
