// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a closure or a suspension moves, as data: what an op declares through
// FlowOpInterface (IdrFlow.td), what flowEdgesOf reads of every op, and the
// flow rule the verifier holds every function to. The label solve and the
// key decision of idr-defunctionalize read these edges and nothing else.
//
// Every op of ours and the upstream ops that move one closure hold the
// interface as an external model (lib/IR/Flow.cpp), attached by
// registerFlowInterfaceExternalModels, so the dialect's own header needs
// none of this.
#ifndef IDR_IR_FLOW_H
#define IDR_IR_FLOW_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr {

// Whether a value of `type` is a closure or a suspension, at any grade:
// the values that carry labels. A value of any other type carries none,
// whatever it holds: an anchor holds the labels of its parts.
inline bool isKeyed(mlir::Type type) { return isClosureType(type) || isLazyType(type); }

// Where closures or suspensions are held for every value of a kind, not
// for one value: a field of a constructor of a data type, the elements of
// every shaped value of an element type, the forced state of every cell
// of a lazy type. Each holds values of one carrier.
struct FlowAnchor {
  enum class Kind : std::uint8_t { Field, Elements, Forced };
  Kind kind = Kind::Field;
  // Field: the identified data type, ungraded and unboxed. Elements: the
  // element type. Forced: the lazy type, ungraded.
  mlir::Type type;
  // Field: the constructor's tag and the field's index.
  unsigned ctor = 0;
  unsigned field = 0;

  static FlowAnchor fieldOf(mlir::Type data, unsigned ctor, unsigned field) {
    return {Kind::Field, data, ctor, field};
  }
  static FlowAnchor elementsOf(mlir::Type element) { return {Kind::Elements, element, 0, 0}; }
  static FlowAnchor forcedOf(mlir::Type lazy) { return {Kind::Forced, lazy, 0, 0}; }
  bool operator==(const FlowAnchor &other) const {
    return kind == other.kind && type == other.type && ctor == other.ctor &&
           field == other.field;
  }
};

// One end of an edge: a use that moves its value (only ever a `from`), a
// result or block argument (only ever a `to`), an anchor, or a parameter
// or result of a function, by its name.
struct FlowPoint {
  enum class Kind : std::uint8_t { Operand, Value, Anchor, Parameter, Result };
  Kind kind = Kind::Value;
  mlir::OpOperand *operand = nullptr;
  mlir::Value value;
  FlowAnchor anchor;
  mlir::FlatSymbolRefAttr function;
  unsigned index = 0;

  static FlowPoint of(mlir::OpOperand &operand) {
    FlowPoint point;
    point.kind = Kind::Operand;
    point.operand = &operand;
    return point;
  }
  static FlowPoint of(mlir::Value value) {
    FlowPoint point;
    point.kind = Kind::Value;
    point.value = value;
    return point;
  }
  static FlowPoint of(FlowAnchor anchor) {
    FlowPoint point;
    point.kind = Kind::Anchor;
    point.anchor = anchor;
    return point;
  }
  static FlowPoint parameter(mlir::FlatSymbolRefAttr function, unsigned index) {
    FlowPoint point;
    point.kind = Kind::Parameter;
    point.function = function;
    point.index = index;
    return point;
  }
  static FlowPoint result(mlir::FlatSymbolRefAttr function, unsigned index) {
    FlowPoint point = parameter(function, index);
    point.kind = Kind::Result;
    return point;
  }
};

// The edges ops declare, as data, in the order they were added.
class FlowEdges {
public:
  struct Edge {
    enum class Kind : std::uint8_t {
      // Every label `from` holds, `to` holds.
      Flow,
      // `from` and `to` hold one set: a cell both share.
      Unify,
      // `to` holds `label`.
      Source,
      // The constant part `constant` is held at `to`.
      Constant,
      // `call`, a CallOpInterface whose callee is a value, runs each label
      // its callee holds.
      Dispatch,
    };
    Kind kind;
    FlowPoint from;
    FlowPoint to;
    mlir::FlatSymbolRefAttr label;
    mlir::Attribute constant;
    mlir::Operation *call = nullptr;
  };

  void flow(FlowPoint from, FlowPoint to) {
    list.push_back({Edge::Kind::Flow, from, to, {}, {}, nullptr});
  }
  void unify(FlowPoint a, FlowPoint b) {
    list.push_back({Edge::Kind::Unify, a, b, {}, {}, nullptr});
  }
  void source(mlir::FlatSymbolRefAttr label, FlowPoint to) {
    list.push_back({Edge::Kind::Source, {}, to, label, {}, nullptr});
  }
  void constant(mlir::Attribute part, FlowPoint at) {
    list.push_back({Edge::Kind::Constant, {}, at, {}, part, nullptr});
  }
  void dispatch(mlir::CallOpInterface call) {
    list.push_back({Edge::Kind::Dispatch, {}, {}, {}, {}, call.getOperation()});
  }

  llvm::ArrayRef<Edge> edges() const { return list; }
  void clear() { list.clear(); }

private:
  llvm::SmallVector<Edge, 4> list;
};

// Adds to `edges` every edge `op` declares: its FlowOpInterface edges, and
// the forwarded values of BranchOpInterface, of
// RegionBranchTerminatorOpInterface and of RegionBranchOpInterface's
// entry, each a Flow from the operand to the successor input, for values
// of a closure or lazy carrier only. The one reader of closure flow.
void flowEdgesOf(mlir::Operation *op, FlowEdges &edges);

// The flow rule, which idr.func's verifier runs on every op of its body.
// An op with FlowOpInterface: each edge it declares joins two ends of one
// carrier (the type without its outermost grade), from an operand of its
// own, an anchor, a parameter or a result, to a result or region argument
// of its own, an anchor, a parameter or a result. Any other op: every
// operand, result and block argument whose type isKeyed is a forwarded
// operand or a successor input of a branch or a region branch, or an
// argument of a non-entry block. Fails with an error at `op` naming the
// edge or the value otherwise.
mlir::LogicalResult verifyFlow(mlir::Operation *op);

// Attaches FlowOpInterface to every op of ours that holds, takes or gives
// a closure or a suspension, and to the upstream ops that move one or make
// one from nothing: tensor.insert, tensor.extract, tensor.from_elements,
// tensor.splat, tensor.yield, ub.poison. Every registry a module is read
// with takes it.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

} // namespace idr

#include "idr/IR/IdrFlow.h.inc"

#endif // IDR_IR_FLOW_H
