-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops area of the dialect: the runtime's values and the ops on
||| integers, Doubles, Integers, naturals and strings, the crashes and the
||| guards, IO and the platform; the types and attributes they name, the
||| interfaces and traits their C++ reads, the runtime's writers of a
||| number's text the lowering calls for an output of a show, the upstream
||| ops the frontend writes beside them, the rules of the e-graph on them,
||| the header of constants the inline arithmetic includes, and the fields
||| of a file's times the runtime's entries read.
module IdrisMLIR.Spec.Ops.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Spec.Ops.Scalars
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Platform
import IdrisMLIR.Spec.Ops.Rewrites

%default total

export
declarations : Declarations
declarations =
  { ops := [SomeOp constantOp, SomeOp platformOsOp]
           ++ scalarOps ++ bigOps ++ stringOps ++ checkOps ++ ioOps ++ platformOps
  , types := [SomeType strType, SomeType bigType, SomeType natType]
  , attributes := [SomeAttr siteAttr, SomeAttr bigAttr]
  , enums := [enumDef comparisonClosed, enumDef fileTimeFieldClosed]
  , interfaces := [literalType, guardInterface, bigOfIntegerInterface]
  , traits := [neverEmpty, noRuntimeForm]
  , predicates := opPredicates
  , helpers := [putSigned, putUnsigned, putDouble, putBig]
  , admitted := opAdmitted
  , rewrites := opRewrites
  , skeleton := skeletonRules
  , headers := [numericHeader, fileTimesHeader]
  } nothing
