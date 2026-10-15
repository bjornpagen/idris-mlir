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
//
// An anchor, a point and an edge are each a sum: one alternative per kind,
// holding what that kind has and nothing else, so no reader meets a field
// that is not its kind's. A reader takes one apart with std::visit over
// llvm::makeVisitor, one function per alternative, so the compiler holds
// it to every kind.
#ifndef IDR_IR_FLOWEDGES_H
#define IDR_IR_FLOWEDGES_H

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMapInfo.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <variant>

namespace idr {

// A constructor's tag, which the dialect's header defines before it
// includes this one.
enum class Tag : std::uint32_t;

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
// a kind. The label solve keeps one set of labels per anchor, so what one
// value of the kind holds there, every value of the kind may.
struct FlowAnchor {
  // A field of a constructor of a data type, the type ungraded and unboxed.
  struct Field {
    mlir::Type data;
    Tag ctor;
    unsigned index;
    bool operator==(const Field &) const = default;
  };
  // The elements of every shaped value of an element type.
  struct Elements {
    mlir::Type element;
    bool operator==(const Elements &) const = default;
  };
  // The forced state of every suspension of a lazy type, ungraded, or after
  // idr-defunctionalize of the memo sum it became.
  struct Forced {
    mlir::Type lazy;
    bool operator==(const Forced &) const = default;
  };
  // A capture of every closure or suspension of a type, ungraded.
  struct Capture {
    mlir::Type carrier;
    unsigned index;
    bool operator==(const Capture &) const = default;
  };
  // The hole every destination of a type writes, ungraded.
  struct Hole {
    mlir::Type dest;
    bool operator==(const Hole &) const = default;
  };

  std::variant<Field, Elements, Forced, Capture, Hole> place;

  static FlowAnchor fieldOf(mlir::Type data, Tag ctor, unsigned index) {
    return {Field{data, ctor, index}};
  }
  static FlowAnchor elementsOf(mlir::Type element) { return {Elements{element}}; }
  static FlowAnchor forcedOf(mlir::Type lazy) { return {Forced{lazy}}; }
  static FlowAnchor captureOf(mlir::Type closure, unsigned index) {
    return {Capture{closure, index}};
  }
  static FlowAnchor holeOf(mlir::Type dest) { return {Hole{dest}}; }

  bool operator==(const FlowAnchor &) const = default;
};

inline llvm::hash_code hash_value(const FlowAnchor &anchor) {
  size_t kind = anchor.place.index();
  return std::visit(
      llvm::makeVisitor(
          [&](const FlowAnchor::Field &field) {
            return llvm::hash_combine(kind, field.data, static_cast<std::uint32_t>(field.ctor),
                                      field.index);
          },
          [&](const FlowAnchor::Elements &elements) {
            return llvm::hash_combine(kind, elements.element);
          },
          [&](const FlowAnchor::Forced &forced) { return llvm::hash_combine(kind, forced.lazy); },
          [&](const FlowAnchor::Capture &capture) {
            return llvm::hash_combine(kind, capture.carrier, capture.index);
          },
          [&](const FlowAnchor::Hole &hole) { return llvm::hash_combine(kind, hole.dest); }),
      anchor.place);
}

// One end of an edge.
struct FlowPoint {
  // A use whose value the op takes over, with the reference it holds: only
  // ever a `from`. Never null: of() makes it from a use.
  struct Taken {
    mlir::OpOperand *use;
    bool operator==(const Taken &) const = default;
  };
  // As a `from`, a value the op reads and does not take over (an operand's
  // value: the use keeps its reference); as a `to`, a result of the op or
  // an argument of a block of its regions.
  struct Whole {
    mlir::Value value;
    bool operator==(const Whole &) const = default;
  };
  // What `anchor` holds of a value. As a `from`, the part of an operand's
  // value, the op taking the whole over (Taken) or only reading it
  // (Whole); as a `to`, the part of a result or region argument the op
  // builds, or of an operand's value the op writes in place (Whole).
  struct Part {
    std::variant<Taken, Whole> of;
    FlowAnchor anchor;
    bool operator==(const Part &) const = default;
  };
  // A parameter of a function, by its name.
  struct Parameter {
    mlir::FlatSymbolRefAttr function;
    unsigned index;
    bool operator==(const Parameter &) const = default;
  };
  // A result of a function, by its name.
  struct Result {
    mlir::FlatSymbolRefAttr function;
    unsigned index;
    bool operator==(const Result &) const = default;
  };

  std::variant<Taken, Whole, Part, Parameter, Result> at;

  static FlowPoint of(mlir::OpOperand &use) { return {Taken{&use}}; }
  static FlowPoint of(mlir::Value value) { return {Whole{value}}; }
  static FlowPoint partOf(mlir::OpOperand &use, FlowAnchor anchor) {
    return {Part{Taken{&use}, anchor}};
  }
  static FlowPoint partOf(mlir::Value value, FlowAnchor anchor) {
    return {Part{Whole{value}, anchor}};
  }
  static FlowPoint parameter(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {Parameter{function, index}};
  }
  static FlowPoint result(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {Result{function, index}};
  }

  // The SSA value at this point: a use's value, a value, or the value a
  // part is of; none at a parameter or a result.
  std::optional<mlir::Value> value() const {
    auto ofEnd = [](const std::variant<Taken, Whole> &end) {
      return std::visit(llvm::makeVisitor([](Taken taken) { return taken.use->get(); },
                                          [](Whole whole) { return whole.value; }),
                        end);
    };
    using Found = std::optional<mlir::Value>;
    return std::visit(llvm::makeVisitor([](Taken taken) -> Found { return taken.use->get(); },
                                        [](Whole whole) -> Found { return whole.value; },
                                        [&](const Part &part) -> Found { return ofEnd(part.of); },
                                        [](Parameter) -> Found { return std::nullopt; },
                                        [](Result) -> Found { return std::nullopt; }),
                      at);
  }

  // The type of what is held at this point, where the op alone says it: a
  // use's or a value's, unrestricted, or a part's slot as its anchor says
  // it; none at a capture or a memo sum's forced state, which only the label
  // and the body say, and none at a parameter or a result, the function's,
  // which the symbol user checks (lib/IR/FlowEdges.cpp).
  std::optional<mlir::Type> type() const;

  // The use the op takes over at this point: a use taken, or the use whose
  // value a part is of when the op takes it; none where the op only reads,
  // makes or writes in place, or at a parameter or a result.
  std::optional<mlir::OpOperand *> taken() const {
    auto ofEnd = [](const std::variant<Taken, Whole> &end) {
      return std::visit(
          llvm::makeVisitor(
              [](Taken taken) -> std::optional<mlir::OpOperand *> { return taken.use; },
              [](Whole) -> std::optional<mlir::OpOperand *> { return std::nullopt; }),
          end);
    };
    return std::visit(
        llvm::makeVisitor(
            [](Taken taken) -> std::optional<mlir::OpOperand *> { return taken.use; },
            [](Whole) -> std::optional<mlir::OpOperand *> { return std::nullopt; },
            [&](const Part &part) { return ofEnd(part.of); },
            [](Parameter) -> std::optional<mlir::OpOperand *> { return std::nullopt; },
            [](Result) -> std::optional<mlir::OpOperand *> { return std::nullopt; }),
        at);
  }

  bool operator==(const FlowPoint &) const = default;
};

// The edges ops declare, as data, in the order they were added. Each edge
// holds the carriers that move along it, those of the value that moves; a
// helper that would add an edge carrying nothing adds none, so an edge of
// a word or of a world is never declared.
class FlowEdges {
public:
  // What `from` holds moves to `to`.
  struct Flow {
    FlowPoint from;
    FlowPoint to;
  };
  // The labels `a` and `b` hold are one set: a cell both share.
  struct Unify {
    FlowPoint a;
    FlowPoint b;
  };
  // `to`, a closure or a suspension the op makes, holds `label`.
  struct Source {
    mlir::FlatSymbolRefAttr label;
    mlir::Value to;
  };
  // `to` is a value the op makes, a new cell or a sum of what it moves into
  // it, to which no other value holds a reference.
  struct Fresh {
    mlir::Value to;
  };
  // `use` gives its reference up at the op, which ends it there: a drop
  // frees it, a reuse builds in its cell, a store hands it to memory no edge
  // follows. Never null: release() makes it from a use.
  struct Release {
    mlir::OpOperand *use;
  };
  // `to` holds the constant `part`, each part where its carrier says: a
  // closure is its label there, a constructor holds its fields at their
  // anchors, and static data is held by every copy of it.
  struct Constant {
    mlir::Attribute part;
    mlir::Value to;
  };
  // `call`, a call whose callee is a value, runs each label its callee
  // holds, and its arguments move into the parameters of whatever runs.
  struct Dispatch {
    mlir::CallOpInterface call;
  };

  struct Edge {
    std::variant<Flow, Unify, Source, Fresh, Release, Constant, Dispatch> move;
    Carriers carriers;

    bool carries(Carrier carrier) const { return carriers.contains(carrier); }
    bool carriesAny(Carriers some) const { return !(carriers & some).empty(); }
  };

  // What the value at `from` holds moves to `to`, carrying what that value
  // carries: the value of a Taken or Whole point, the anchor's slot of a
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
  // `edge`, unless it carries nothing.
  void add(Edge edge);

  llvm::SmallVector<Edge, 4> list;
};

} // namespace idr

// An anchor is a key of the label solve's tables.
template <>
struct llvm::DenseMapInfo<idr::FlowAnchor> {
  static unsigned getHashValue(const idr::FlowAnchor &anchor) {
    return static_cast<unsigned>(hash_value(anchor));
  }
  static bool isEqual(const idr::FlowAnchor &a, const idr::FlowAnchor &b) { return a == b; }
};

#include "idr/IR/IdrFlow.h.inc"

#endif // IDR_IR_FLOWEDGES_H
