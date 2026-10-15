// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a value moves, as data: the vocabulary an op declares its edges in
// through the flow interface (IdrFlow.td), and that interface itself, which
// this header ends with, so that the dialect's header includes this one
// before its ops. What a branch or a region branch forwards is upstream's
// to declare, and idr::forwardedValues (Flow.h) reads it.
//
// One account serves every reader: an edge says which carriers move along
// it, and each reader keeps the edges of the carrier it asks about. The
// label solve follows closures and suspensions; ownership (which uses take
// a reference over, which cells may leave their frame, which values hold
// the only reference to their cells) follows counted references.
#ifndef IDR_IR_FLOWEDGES_H
#define IDR_IR_FLOWEDGES_H

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr {

// What a reader follows where a value moves: the labels of a closure or of
// a suspension, and a reference a count accounts for. A closure or a
// suspension is a counted cell too, so a value of one carries both.
enum class Carrier : std::uint8_t { Closure = 1, Suspension = 2, Reference = 4 };

// A set of carriers.
class Carriers {
public:
  constexpr Carriers() = default;
  constexpr Carriers(Carrier carrier) : bits(static_cast<std::uint8_t>(carrier)) {}

  // What a value of `type` carries, at any grade: a closure its labels, a
  // suspension its labels, and anything that holds a reference a count
  // accounts for (idr::holdsReferences) that reference.
  static Carriers of(mlir::Type type);

  // The carriers whose values hold labels, and every carrier.
  static constexpr Carriers labels() { return Carriers(Carrier::Closure) | Carrier::Suspension; }
  static constexpr Carriers all() { return labels() | Carrier::Reference; }

  constexpr Carriers operator|(Carriers other) const { return bitsOf(bits | other.bits); }
  constexpr Carriers operator&(Carriers other) const { return bitsOf(bits & other.bits); }
  constexpr bool contains(Carrier carrier) const {
    return (bits & static_cast<std::uint8_t>(carrier)) != 0;
  }
  constexpr bool empty() const { return bits == 0; }
  constexpr bool operator==(const Carriers &) const = default;

private:
  static constexpr Carriers bitsOf(unsigned value) {
    Carriers out;
    out.bits = static_cast<std::uint8_t>(value);
    return out;
  }
  std::uint8_t bits = 0;
};

// Where a value holds part of what it is, the same place in every value of
// a kind: a field of a constructor of a data type; the elements of every
// shaped value of an element type; the forced state of every suspension of
// a type; a capture of every closure or suspension of a type; the hole
// every destination of a type writes. The label solve keeps one set of
// labels per anchor, so what one value of the kind holds there, every value
// of the kind may.
struct FlowAnchor {
  enum class Kind : std::uint8_t { Field, Elements, Forced, Capture, Hole };
  Kind kind = Kind::Field;
  // Field: the data type, ungraded and unboxed. Elements: the element type.
  // Forced: the lazy type, ungraded, or after idr-defunctionalize the memo
  // sum it became. Capture: the closure or lazy type, ungraded. Hole: the
  // destination type, ungraded.
  mlir::Type type;
  // Field: the constructor's tag. Every other kind: 0.
  unsigned ctor = 0;
  // Field: the field's index. Capture: the capture's index. Every other
  // kind: 0.
  unsigned field = 0;

  static FlowAnchor fieldOf(mlir::Type data, unsigned ctor, unsigned field) {
    return {Kind::Field, data, ctor, field};
  }
  static FlowAnchor elementsOf(mlir::Type element) { return {Kind::Elements, element, 0, 0}; }
  static FlowAnchor forcedOf(mlir::Type lazy) { return {Kind::Forced, lazy, 0, 0}; }
  static FlowAnchor captureOf(mlir::Type closure, unsigned index) {
    return {Kind::Capture, closure, 0, index};
  }
  static FlowAnchor holeOf(mlir::Type dest) { return {Kind::Hole, dest, 0, 0}; }

  bool operator==(const FlowAnchor &) const = default;
};

// One end of an edge.
//   Operand: a use whose value the op takes over, with the reference it
//     holds: only ever a `from`.
//   Value: as a `from`, a value the op reads and does not take over (an
//     operand's value: the use keeps its reference); as a `to`, a result of
//     the op or an argument of a block of its regions.
//   Part: what `anchor` holds of a value. As a `from`, the part of an
//     operand's value, the op taking the whole over (`operand` set) or only
//     reading it (`value` set); as a `to`, the part of a result or region
//     argument the op builds, or of an operand's value the op writes in
//     place (`value` set).
//   Parameter, Result: a parameter or a result of a function, by its name.
struct FlowPoint {
  enum class Kind : std::uint8_t { Operand, Value, Part, Parameter, Result };
  Kind kind = Kind::Value;
  mlir::OpOperand *operand = nullptr;
  mlir::Value value;
  FlowAnchor anchor;
  mlir::FlatSymbolRefAttr function;
  unsigned index = 0;

  static FlowPoint of(mlir::OpOperand &use) {
    FlowPoint point;
    point.kind = Kind::Operand;
    point.operand = &use;
    return point;
  }
  static FlowPoint of(mlir::Value value) {
    FlowPoint point;
    point.kind = Kind::Value;
    point.value = value;
    return point;
  }
  static FlowPoint partOf(mlir::OpOperand &use, FlowAnchor anchor) {
    FlowPoint point;
    point.kind = Kind::Part;
    point.operand = &use;
    point.anchor = anchor;
    return point;
  }
  static FlowPoint partOf(mlir::Value value, FlowAnchor anchor) {
    FlowPoint point;
    point.kind = Kind::Part;
    point.value = value;
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

  // The SSA value at an Operand, Value or Part point: the use's value, or
  // the value; null at a parameter or a result.
  mlir::Value getValue() const { return operand ? operand->get() : value; }
  // Whether the op takes the value at this point over: an Operand, or the
  // Part of a value a use gives up.
  bool takes() const { return operand != nullptr; }
};

// The edges ops declare, as data, in the order they were added. Each edge
// holds the carriers that move along it, those of the value that moves; a
// helper that would add an edge carrying nothing adds none, so an edge of
// a word or of a world is never declared.
class FlowEdges {
public:
  struct Edge {
    enum class Kind : std::uint8_t {
      // What `from` carries, `to` carries.
      Flow,
      // `from` and `to` hold one set of labels: a cell both share.
      Unify,
      // `to` holds `label`.
      Source,
      // `to` is a value the op makes, a new cell or a sum of what it moves
      // into it, to which no other value holds a reference.
      Fresh,
      // The use at `from` gives its reference up at the op, which ends it
      // there: a drop frees it, a reuse builds in its cell, a store hands it
      // to memory no edge follows.
      Release,
      // `to` holds the constant `constant`, each part where its carrier
      // says: a closure is its label there, a constructor holds its fields
      // at their anchors, and static data is held by every copy of it.
      Constant,
      // `call`, a CallOpInterface whose callee is a value, runs each label
      // its callee holds, and its arguments move into the parameters of
      // whatever runs.
      Dispatch,
    };
    Kind kind;
    Carriers carriers;
    FlowPoint from;
    FlowPoint to;
    mlir::FlatSymbolRefAttr label;
    mlir::Attribute constant;
    mlir::Operation *call = nullptr;

    bool carries(Carrier carrier) const { return carriers.contains(carrier); }
    bool carriesAny(Carriers some) const { return !(carriers & some).empty(); }
  };

  // What the value at `from` holds moves to `to`, carrying what that value
  // carries: the value of an Operand or Value point, the anchor's slot of a
  // Part, and at a parameter or a result what `to` holds. `only` keeps
  // those of some carriers: a capture's labels go to its label's
  // parameter, and its reference into its closure's cell.
  void flow(FlowPoint from, FlowPoint to, Carriers only = Carriers::all());
  // The labels `a` and `b` hold are one set.
  void unify(FlowPoint a, FlowPoint b);
  // `to`, a closure or a suspension, holds `label`.
  void source(mlir::FlatSymbolRefAttr label, mlir::Value to);
  // `to` is new: no other value holds a reference to it.
  void fresh(mlir::Value to);
  // The use gives its reference up at the op.
  void release(mlir::OpOperand &use);
  // `to` holds the constant `part`.
  void constant(mlir::Attribute part, mlir::Value to);
  // `call` runs the labels its callee holds.
  void dispatch(mlir::CallOpInterface call);

  llvm::ArrayRef<Edge> edges() const { return list; }
  void clear() { list.clear(); }

private:
  void add(Edge::Kind kind, Carriers carriers, FlowPoint from, FlowPoint to);

  llvm::SmallVector<Edge, 4> list;
};

} // namespace idr

#include "idr/IR/IdrFlow.h.inc"

#endif // IDR_IR_FLOWEDGES_H
