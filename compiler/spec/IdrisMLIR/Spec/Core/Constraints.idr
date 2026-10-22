-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What an operand, a result or an attribute may be, as data: an upstream
||| constraint, one of the dialect's types or attributes by its
||| declaration, a choice among constraints, or a hand predicate where data
||| cannot say it. The generator prints each into ODS; mlir-tblgen
||| generates the check.
module IdrisMLIR.Spec.Core.Constraints

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Types
import IdrisMLIR.Spec.Core.Upstream

import Data.List1

%default total

||| A type constraint.
public export
data TypeC
  = UpstreamType UpType
  | OurType AnyTypeDef
  | AnyOfTypes (List1 TypeC) Line
  | AllOfTypes (List1 TypeC) Line
  | SatisfiesType Predicate

||| An attribute constraint.
public export
data AttrC
  = UpstreamAttr UpAttr
  | OurAttr AnyAttrDef
  | EnumAttrOf EnumDef
  | TypeAttrOf TypeC
  | Confined AttrC (List1 UpConfinement)
  | SatisfiesAttr Predicate

||| An op's configuration held as a property rather than an attribute: a
||| case of an enum of the dialect's, or a set of its cases, with the case
||| or cases it is when the op is built without it.
public export
data PropertyC
  = EnumProperty EnumDef
  | DefaultedEnumProperty EnumDef Code
