-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The flow interface: how an op says where what it holds, takes or gives
||| moves (into its results or region arguments, into or out of a part of a
||| value, into a function's parameters or results, through a dispatch),
||| which uses it takes over, which results are new. It declares only what
||| no upstream interface declares: what a region branch forwards, a match's
||| refined scrutinee and a jump's arguments among it, is read from
||| RegionBranchOpInterface (`idr::forwardedValues`), so neither the matches
||| nor the join points hold it. Its vocabulary is the hand header
||| `idr/IR/FlowEdges.h`; its verifier holds each op's edges to their rule
||| at every stage, after the op's own verifier, whose facts the edges read.
module IdrisMLIR.Spec.Control.Flow

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Interfaces

%default total

export
flowInterface : InterfaceDef
flowInterface = MkInterfaceDef
  { name = ident "FlowOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject (code "void") (ident "getFlowEdges")
          [param (code "::idr::FlowEdges &") (ident "edges")] EveryImplementer
          (line "adds to `edges` every edge along which something this op holds, takes or gives moves") ]
  , verifier = Verifies (ident "verifyFlowEdges") AfterRegions
  , doc = MkDoc (line "an op that moves a value holding labels or a counted reference declares each move")
      """
      Each edge names only ends the op may name, and one that carries labels
      joins two places of one carrier type. An op without the interface is
      unknown to the readers that follow references, unless upstream's
      interfaces say every move it makes (a region branch, its terminators, a
      select).
      """
  }
