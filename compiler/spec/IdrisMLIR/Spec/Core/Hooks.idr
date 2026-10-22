-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The hand C++ the specification names and never holds: a declaration is
||| printed, its definition is written by hand, and a missing definition is
||| a link error. Semantics stays C++ (a verifier's rule, a folder, a custom
||| directive's parse and print); the specification says only that it
||| exists and what it takes, so no C++ text of a body ever sits in a
||| generated file.
module IdrisMLIR.Spec.Core.Hooks

import IdrisMLIR.Spec.Core.Text

%default total

||| A parameter of a declared C++ function: its type's spelling and its
||| name.
public export
record Param where
  constructor MkParam
  type : Code
  name : Ident

public export
param : Code -> Ident -> Param
param = MkParam

||| Whether a member reads its object, or is the class's.
public export
data Binding = OnObject | OnObjectConst | OnClass

||| A member a class declares and a hand unit defines: a method MLIR finds
||| by its name on the class (an attribute's sub-element walk), or one the
||| C++ calls on it. Its result's spelling, its name, its parameters.
public export
record Member where
  constructor MkMember
  binding : Binding
  result : Code
  name : Ident
  params : List Param

||| What one argument of a custom directive is, which decides the C++ type
||| its parse and print take: an operand, an operand group, its type, its
||| type list, an attribute, a region, a group of regions, or any of these
||| read again by `ref`.
public export
data DirectiveArg
  = OperandArg
  | VariadicOperandArg
  | OptionalOperandArg
  | TypeArg
  | VariadicTypeArg
  | AttrArg Code
  | RegionArg
  | VariadicRegionArg
  | RefTypeArg
  | RefAttrArg Code
  | RefVariadicTypeArg

||| A custom directive of an assembly format: `custom<Read>(...)` calls the
||| hand `parseRead` and `printRead`. A value of its own, defined once and
||| named by the formats that use it, so a format cannot name a directive no
||| one declared; its declarations are printed from the argument kinds.
public export
record Directive where
  constructor MkDirective
  name : Ident
  args : List DirectiveArg
  doc : Doc

||| A predicate over a type or an attribute that data cannot say (whether a
||| type is a field's), a C++ function the generated constraint calls and a
||| hand unit defines: `bool isFieldType(::mlir::Type)`.
public export
data PredicateSubject = OnType | OnAttribute

public export
record Predicate where
  constructor MkPredicate
  name : Ident
  subject : PredicateSubject
  doc : Doc
