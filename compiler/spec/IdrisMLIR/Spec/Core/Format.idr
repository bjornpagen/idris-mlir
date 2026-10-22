-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| An op's declarative assembly format as data over the op's own groups:
||| every reference is a position (`Fin i` among `i` operand groups, and so
||| on), so a format cannot name a group the op lacks, and no name is looked
||| up. The generator prints it with the groups' names; mlir-tblgen reads
||| it as ODS's format.
module IdrisMLIR.Spec.Core.Format

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks

import Data.Fin

%default total

||| A group of an op with `i` operand, `o` result, `a` attribute and `r`
||| region groups.
public export
data Ref : (i, o, a, r : Nat) -> Type where
  OperandRef : Fin i -> Ref i o a r
  ResultRef : Fin o -> Ref i o a r
  AttrRef : Fin a -> Ref i o a r
  RegionRef : Fin r -> Ref i o a r

||| What a type directive or a functional type reads: one group, or every
||| operand or every result together.
public export
data TypeSource : (i, o, a, r : Nat) -> Type where
  OfGroup : Ref i o a r -> TypeSource i o a r
  OfOperands : TypeSource i o a r
  OfResults : TypeSource i o a r

||| One argument of a custom directive: a group, its type, or either read
||| again (`ref`).
public export
data DirectiveIn : (i, o, a, r : Nat) -> Type where
  Group : Ref i o a r -> DirectiveIn i o a r
  TypeOfGroup : Ref i o a r -> DirectiveIn i o a r
  Again : Ref i o a r -> DirectiveIn i o a r
  TypeAgain : Ref i o a r -> DirectiveIn i o a r

||| One element of a format.
public export
data Item : (i, o, a, r : Nat) -> Type where
  ||| A literal: a keyword or punctuation ODS prints between backquotes.
  Lit : Line -> Item i o a r
  ||| A group's value: an operand, an attribute, a region.
  ValueOf : Ref i o a r -> Item i o a r
  ||| A group's type, qualified when the printer must name its dialect.
  TypeOf : TypeSource i o a r -> Item i o a r
  QualifiedTypeOf : TypeSource i o a r -> Item i o a r
  ||| `functional-type(from, to)`.
  FunctionalType : TypeSource i o a r -> TypeSource i o a r -> Item i o a r
  ||| The op's attribute dictionary, with or without its keyword.
  AttrDict : Item i o a r
  AttrDictWithKeyword : Item i o a r
  ||| The op's properties as a dictionary.
  PropDict : Item i o a r
  ||| Every region of the op.
  Regions : Item i o a r
  ||| A custom directive over groups.
  Custom : Directive -> List (DirectiveIn i o a r) -> Item i o a r
  ||| A group printed only when its anchor is present: the items before
  ||| it, the anchor, the items after, so a group has its anchor by
  ||| construction.
  OptionalGroup : List (Item i o a r) -> Item i o a r -> List (Item i o a r) -> Item i o a r

||| An op's syntax: declarative, or written by hand (its parser and
||| printer).
public export
data Format : (i, o, a, r : Nat) -> Type where
  Declared : List (Item i o a r) -> Format i o a r
  HandFormat : Format i o a r
