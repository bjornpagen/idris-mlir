// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow interface: how an op that holds, takes or gives a closure or a
// suspension says where it moves. Its vocabulary is idr/IR/Flow.h, which
// includes what this file generates; every op holds it as an external
// model, whose edges are in lib/IR/Flow.cpp.

#ifndef IDR_FLOW
#define IDR_FLOW

include "mlir/IR/OpBase.td"

def Idr_FlowOpInterface : OpInterface<"FlowOpInterface"> {
  let cppNamespace = "::idr";
  let description = [{
    An op that holds, takes or gives a closure or a suspension declares
    how each one moves: into its results or region arguments, into an
    anchor, into a function's parameters or results, or through a
    dispatch. It declares only edges no upstream interface declares: a
    branch's and a region branch's forwarded values are read from
    BranchOpInterface and RegionBranchOpInterface.
  }];
  let methods = [
    InterfaceMethod<[{
        Adds to `edges` every edge along which a closure or a suspension
        this op holds, takes or gives moves. An op with no value of a
        closure or lazy carrier adds nothing.
      }],
      "void", "getFlowEdges", (ins "::idr::FlowEdges &":$edges)>,
  ];
}

#endif // IDR_FLOW
