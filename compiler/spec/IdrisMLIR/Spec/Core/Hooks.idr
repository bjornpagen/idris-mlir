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

import Data.List1

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

||| A type parameter of a member function template: the concept that
||| constrains it, `::std::invocable<::mlir::OpOperand &>`, and its name. A
||| callback is a template parameter a concept constrains, never a
||| type-erased `function_ref`, so its call is inlined where it is made.
public export
record TypeParam where
  constructor MkTypeParam
  concept : Code
  name : Ident

||| A member a class declares and a hand unit defines: a method MLIR finds
||| by its name on the class (an attribute's sub-element walk), or one the
||| C++ calls on it, by its result's spelling, its name and its parameters;
||| or a function template of at least one type parameter, whose definition
||| a hand header gives, since a template is instantiated where it is used.
public export
data Member : Type where
  MkMember : (binding : Binding) -> (result : Code) -> (name : Ident) -> (params : List Param) -> Member
  MkTemplateMember : (typeParams : List1 TypeParam) -> (binding : Binding) -> (result : Code)
                  -> (name : Ident) -> (params : List Param) -> Member

||| A fold of constants made of constants (a constructor's or a closure's
||| construction, a constant constructor's tag and fields, a constant at
||| another type, the platform), its condition written once over where its
||| operands' constants live (`fold::Composite`): what the op gives where
||| they make one, or nothing. Its own folder asks it of the constants ops
||| hold, and the e-graph of its own values, which makes no attribute until
||| the write-back places one. `opClass` is the op's class, whose own facts
||| (its data type, its index) the condition reads; its definition is a hand
||| header's, since a template is instantiated where it is used.
public export
compositeMeaning : (opClass : Code) -> Member
compositeMeaning opClass =
  MkTemplateMember (MkTypeParam "::idr::fold::Composite" "W" ::: []) OnClass
    "::std::optional<typename W::Result>" "meaning"
    [ param "W &" "where", param opClass "op"
    , param "::llvm::ArrayRef<typename W::Operand>" "constants" ]

||| A fold that may give a value of the program instead of a constant (a
||| field of a constructor an op built, a cast of a cast, a force of an
||| evaluated suspension), its condition written once over where values and
||| constants live, as `compositeMeaning`'s: what it gives is a constant, or
||| an operand's value, of its own op or of the op that built one
||| (`fold::Folded`).
public export
structuralMeaning : (opClass : Code) -> Member
structuralMeaning opClass =
  MkTemplateMember (MkTypeParam "::idr::fold::Composite" "W" ::: []) OnClass
    "::std::optional<::idr::fold::Folded<W>>" "meaning"
    [ param "W &" "where", param opClass "op"
    , param "::llvm::ArrayRef<typename W::Operand>" "constants" ]

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
