-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops area of the dialect: the runtime's values and the ops on
||| integers, Doubles, Integers, naturals and strings, the crashes and the
||| guards, IO and the platform; the types and attributes they name, the
||| interfaces and traits their C++ reads, the rules of the e-graph on them,
||| and the header of constants the inline arithmetic includes.
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
  , attributes := [SomeAttr siteAttr]
  , enums := [enumDef comparisonClosed]
  , tables := [scalarFacts]
  , interfaces := [literalType, guardInterface]
  , traits := [neverEmpty, noRuntimeForm]
  , predicates := opPredicates
  , admitted := [subI, andI]
  , rewrites := opRewrites
  , skeleton := skeletonRules
  , headers := [numericHeader]
  } nothing
