// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow interface: how an op says where what it holds, takes or gives
// moves. Its vocabulary is idr/IR/FlowEdges.h, which also includes what
// this file generates; each op of ours that has an edge to declare holds
// the interface in its ODS, and upstream's ops hold it as external models
// (idr::registerFlowInterfaceExternalModels). The interface verifies the
// edges each op of ours declares, at every stage.

#ifndef IDR_FLOW
#define IDR_FLOW

include "mlir/IR/OpBase.td"

def Idr_FlowOpInterface : OpInterface<"FlowOpInterface"> {
  let cppNamespace = "::idr";
  let description = [{
    An op that moves a value holding a carrier (the labels of a closure or
    of a suspension, or a counted reference) declares each move: into its
    results or region arguments, into or out of a part of a value (a
    field, the elements, the forced state, a capture, a hole), into a
    function's parameters or results, or through a dispatch; which uses
    it takes over and which it ends; which results are new; which labels
    and constants it makes. A use it declares no edge for is only read
    while the op runs. It declares only what no upstream interface
    declares: what a region branch forwards is read from
    RegionBranchOpInterface (idr::forwardedValues), so a terminator that
    only forwards holds no flow interface.

    Every op of ours with an edge to declare holds it, and so does an op
    that reads a box or a sum in place without moving it (idr.tag), so
    that readers know the read is all it does. An op
    without it is unknown to the readers that follow references: what it
    takes may go anywhere, and what it gives may be shared.

    Each edge names only ends the op may name, and one that carries labels
    joins two places of one carrier type (idr::detail::verifyFlowEdges),
    checked whenever the op is verified, at every stage: `consumes` and the
    effects of the uses an op takes over are read from these edges, so a
    wrong one would be a wrong effect.
  }];
  let methods = [
    InterfaceMethod<[{
        Adds to `edges` every edge along which something this op holds,
        takes or gives moves.
      }],
      "void", "getFlowEdges", (ins "::idr::FlowEdges &":$edges)>,
  ];
  let verify = [{ return ::idr::detail::verifyFlowEdges($_op); }];
  // After the op's own verifier: its edges read the facts that verifier
  // holds (a tag in range, a field's index, a constraint's type).
  let verifyWithRegions = 1;
}

#endif // IDR_FLOW
