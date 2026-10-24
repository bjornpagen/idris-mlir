-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Control flow, as regions from the frontend to the lowering: the matches,
||| a region per case; the yield that ends a region; the join points, one
||| family of two members by where their tokens are; the jump to one of
||| them; the divergence of a loop Idris did not prove to end; the flow
||| interface, which reads what a region branch forwards from upstream's
||| interface; the upstream ops a condition is chosen with,
||| `scf.if` and its `scf.yield`, which the frontend writes, and
||| `scf.index_switch`, which only the lowering writes; and the skeleton
||| rules of the e-graph pass over these ops. Blocks appear only at the
||| lowering, in one conversion with upstream's scf patterns.
module IdrisMLIR.Spec.Control.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Control.Matches
import IdrisMLIR.Spec.Control.Joins
import IdrisMLIR.Spec.Control.Rules

%default total

public export
declarations : Declarations
declarations =
  { ops := [SomeOp matchOp, SomeOp matchLitOp, SomeOp yieldOp] ++ joinPointOps ++ [SomeOp jumpOp, SomeOp mayLoopOp]
  , enums := [enumDef tokenScopeClosed]
  , interfaces := [flowInterface, matchInterface, joinPointsInterface, valueSourceInterface]
  , admitted := controlAdmitted
  , skeleton := skeletonRules
  } nothing
