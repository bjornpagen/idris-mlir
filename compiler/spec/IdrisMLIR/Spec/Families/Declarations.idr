-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the families declare in the dialect, as one value the
||| specification's root unions with the other areas'.
module IdrisMLIR.Spec.Families.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Ops
import IdrisMLIR.Spec.Families.Types

%default total

export
declarations : Declarations
declarations = MkDeclarations
  { ops =
      [ SomeOp conOp, SomeOp fieldOp, SomeOp tagOp, SomeOp dataReindexOp, SomeOp assumeOp
      , SomeOp numeralToNatOp, SomeOp numeralOfNatOp ]
  , types = [SomeType dataType, SomeType selfType]
  , attributes =
      [ SomeAttr familyAttr, SomeAttr indexBindersAttr, SomeAttr indexArgsAttr, SomeAttr equationAttr
      , SomeAttr conAttr ]
  , enums = []
  , tables = []
  , interfaces = [erasedBinderInterface]
  , traits = []
  , directives =
      [ termsParam, sortsParam, membersParam, refinementParam, familyParam, dataParam
      , fieldsDirective, fieldsWithHolesDirective, countedResultDirective ]
  , predicates = [dataValue, refinedValue, cellValue, numeralValue, naturalValue]
  , resources = []
  , helpers = []
  , admitted = []
  , rewrites = []
  , skeleton = familySkeleton
  , headers = [familiesHeader]
  }
