// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a value moves, as data: the vocabulary an op declares its edges in
// through the flow interface, which is generated with the dialect's other
// interfaces. It is a part of the dialect's header, which includes it after
// the types, which its anchors hold, and before the interfaces, whose flow
// interface names it; include idr/IR/IdrDialect.h, never this one.
// What a region branch forwards is upstream's to declare, and
// idr::forwardedValues (Flow.h) reads it.
//
// One account serves every reader: an edge says which carriers move along
// it, and each reader keeps the edges of the carrier it asks about. The
// label solve follows closures and suspensions; ownership (which uses take
// a reference over, which cells may leave their frame, which values hold
// the only reference to their cells) follows counted references.
//
// An anchor, a source, a place and an edge are each a sum: one alternative
// per kind, holding what that kind has and nothing else, so no reader
// meets a field that is not its kind's, and no place is a use taken over.
// A reader takes one apart with idr::match, one case per alternative, so
// the compiler holds it to every kind.
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
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <variant>

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
  // accounts for (idr::holdsReferences) that reference. A cell carries what
  // the box its init makes of it carries: it is that box before it is one,
  // so whether a box is new to anyone is whether its cell was.
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
// value of the kind holds there, every value of the kind may. Each anchor
// holds what it means, a declaration or a type, so no reader casts one.
struct FlowAnchor {
  // A field of a constructor of a member of a family, by the declaration
  // alone: every value of the member names it, at whatever index terms and
  // refinement the program meets the member, as the field's slot is the
  // declaration's.
  struct Field {
    FamilyAttr group;
    std::uint32_t member;
    Tag ctor;
    unsigned index;
    bool operator==(const Field &) const = default;
  };
  // The elements of every shaped value of an element type.
  struct Elements {
    mlir::Type element;
    bool operator==(const Elements &) const = default;
  };
  // The forced state of every suspension of a lazy type, ungraded.
  struct Forced {
    LazyType lazy;
    bool operator==(const Forced &) const = default;
  };
  // The forced state of every cell of a memo sum, what idr-defunctionalize
  // made of a lazy type: its forced constructor's one field.
  struct MemoState {
    DataType memo;
    bool operator==(const MemoState &) const = default;
  };
  // A capture of every closure or suspension of a type, ungraded.
  struct Capture {
    mlir::Type carrier;
    unsigned index;
    bool operator==(const Capture &) const = default;
  };
  // The hole every destination of a type writes.
  struct Hole {
    DestType dest;
    bool operator==(const Hole &) const = default;
  };

  std::variant<Field, Elements, Forced, MemoState, Capture, Hole> place;

  static FlowAnchor fieldOf(DataType data, Tag ctor, unsigned index) {
    return {Field{data.getGroup(), data.getMember(), ctor, index}};
  }
  static FlowAnchor elementsOf(mlir::Type element) { return {Elements{element}}; }
  static FlowAnchor forcedOf(LazyType lazy) { return {Forced{lazy}}; }
  static FlowAnchor memoStateOf(DataType memo) { return {MemoState{memo}}; }
  static FlowAnchor captureOf(mlir::Type carrier, unsigned index) {
    return {Capture{carrier, index}};
  }
  static FlowAnchor holeOf(DestType dest) { return {Hole{dest}}; }

  // The type of what every value of the kind holds here, ungraded: a
  // field's, the element type, a suspension's value, a memo sum's forced
  // field, the value a hole is written with. None at a capture, which is
  // its label's parameter, which only the label says.
  std::optional<mlir::Type> slot() const;

  bool operator==(const FlowAnchor &) const = default;
};

// An anchor's hash: its kind, and what it holds.
llvm::hash_code hash_value(const FlowAnchor &anchor);

// The source of an edge: where what moves comes from. A whole value, a
// parameter and a result are places too (FlowPlace); a use taken over is a
// source's alone.
struct FlowSource {
  // A use whose value the op takes over, with the reference it holds.
  // Never null: of() makes it from a use.
  struct Taken {
    mlir::OpOperand *use;
    bool operator==(const Taken &) const = default;
  };
  // As a source, a value the op reads and does not take over (an operand's
  // value: the use keeps its reference); as a place, a result of the op or
  // an argument of a block of its regions.
  struct Whole {
    mlir::Value value;
    bool operator==(const Whole &) const = default;
  };
  // What `anchor` holds of a value: of an operand's value, the op taking
  // the whole over (Taken) or only reading it (Whole), or of a result or a
  // region argument of its own, which it reads back (Whole).
  struct Part {
    std::variant<Taken, Whole> of;
    FlowAnchor anchor;

    // The value the part is of, taken or only read: a part always has one.
    mlir::Value value() const;
    // The use the op takes over where it takes the whole the part is of.
    std::optional<mlir::OpOperand *> taken() const;

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

  static FlowSource of(mlir::OpOperand &use) { return {Taken{&use}}; }
  static FlowSource of(mlir::Value value) { return {Whole{value}}; }
  static FlowSource partOf(mlir::OpOperand &use, FlowAnchor anchor) {
    return {Part{Taken{&use}, anchor}};
  }
  static FlowSource partOf(mlir::Value value, FlowAnchor anchor) {
    return {Part{Whole{value}, anchor}};
  }
  static FlowSource parameter(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {Parameter{function, index}};
  }
  static FlowSource result(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {Result{function, index}};
  }

  // The SSA value of this source: a use's value, a value, or the value a
  // part is of; none at a parameter or a result.
  std::optional<mlir::Value> value() const;

  // The type of what is held at this source, where the op alone says it: a
  // use's or a value's, unrestricted, or a part's slot (FlowAnchor::slot);
  // none at a capture, which only the label says, and none at a parameter
  // or a result, the function's, which the symbol user checks.
  std::optional<mlir::Type> type() const;

  // The use the op takes over at this source: a use taken, or the use whose
  // value a part is of when the op takes it; none where the op only reads,
  // or at a parameter or a result.
  std::optional<mlir::OpOperand *> taken() const;

  bool operator==(const FlowSource &) const = default;
};

// A place: where what moves goes, what a unification joins, what an
// overwrite writes. A value the op makes, a part of one or of a value it or
// its parent holds, a parameter or a result; never a use, which only a
// source takes over.
struct FlowPlace {
  // What `anchor` holds of `of`: a part of a result or a region argument
  // the op builds, of an operand's value it writes in place, or of what its
  // parent makes or writes.
  struct Part {
    mlir::Value of;
    FlowAnchor anchor;
  };

  std::variant<FlowSource::Whole, Part, FlowSource::Parameter, FlowSource::Result> at;

  static FlowPlace of(mlir::Value value) { return {FlowSource::Whole{value}}; }
  static FlowPlace partOf(mlir::Value value, FlowAnchor anchor) { return {Part{value, anchor}}; }
  static FlowPlace parameter(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {FlowSource::Parameter{function, index}};
  }
  static FlowPlace result(mlir::FlatSymbolRefAttr function, unsigned index) {
    return {FlowSource::Result{function, index}};
  }

  // The SSA value at this place: a value, or the value a part is of; none
  // at a parameter or a result.
  std::optional<mlir::Value> value() const;
  // The type of what is held here, as at a source (FlowSource::type).
  std::optional<mlir::Type> type() const;
};

// The edges ops declare, as data, in the order they were added. Each edge
// holds the carriers that move along it, those of the value that moves; a
// helper that would add an edge carrying nothing adds none, so an edge of
// a word or of a world is never declared.
class FlowEdges {
public:
  // What `from` holds moves to `to`.
  struct Flow {
    FlowSource from;
    FlowPlace to;
  };
  // The labels `a` and `b` hold are one set: a cell both share.
  struct Unify {
    FlowPlace a;
    FlowPlace b;
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
  // frees it, a recycle makes a new cell of its cell, an unpack of an atom
  // takes it apart into nothing, a store hands it to memory no edge
  // follows. Never null: release() makes it from a use.
  struct Release {
    mlir::OpOperand *use;
  };
  // What `place`, a part of a value that exists before the op, held is
  // released as the op writes the place: a write of an element over the
  // one it replaces (idr.array.set, memref.store), which the lowering
  // releases. An op that writes memory that exists before it declares
  // this, or a fill where the place held nothing, or is the exchange of
  // that memory (an update, a memo cell's force), or writes a hole.
  struct Overwrite {
    FlowPlace::Part place;
  };
  // `place`, a part of a value that exists before the op, held nothing, and
  // the op's write fills it: slots a take left (idr.array.place,
  // idr.array.put_back), or a buffer no write reached yet. Nothing is
  // released.
  struct Fill {
    FlowPlace::Part place;
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
    std::variant<Flow, Unify, Source, Fresh, Release, Overwrite, Fill, Constant, Dispatch> move;
    Carriers carriers;

    bool carries(Carrier carrier) const { return carriers.contains(carrier); }
    bool carriesAny(Carriers some) const { return !(carriers & some).empty(); }
  };

  // What the value at `from` holds moves to `to`, carrying what that value
  // carries: the value of a Taken or Whole source, the anchor's slot of a
  // Part, and at a parameter or a result what `to` holds. `only` keeps
  // those of some carriers: a capture's labels go to its label's
  // parameter, and its reference into its closure's cell.
  void flow(FlowSource from, FlowPlace to, Carriers only = Carriers::all());
  // The labels `a` and `b` hold are one set.
  void unify(FlowPlace a, FlowPlace b);
  // `to`, a closure or a suspension, holds `label`.
  void source(mlir::FlatSymbolRefAttr label, mlir::Value to);
  // `to` is new: no other value holds a reference to it.
  void fresh(mlir::Value to);
  // The use gives its reference up at the op.
  void release(mlir::OpOperand &use);
  // What `anchor` holds of `of` is released as the op writes it.
  void overwrite(mlir::Value of, FlowAnchor anchor);
  // What `anchor` holds of `of` is nothing until the op writes it.
  void fill(mlir::Value of, FlowAnchor anchor);
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

namespace idr {

// The rule every op that holds the flow interface keeps, which the
// interface's verifier holds it to at every stage: each edge its model
// declares names only ends the op may name, a `from` a use of its own, an
// operand's value or a part of either, or a part of a result or a region
// argument of its own (what a region reads back from an earlier step, what
// the op reads out of a place its region wrote), a `to` a value it makes,
// a part of one or of a value it or its parent holds, and either a
// parameter or a result; and an edge that carries labels joins two places of one carrier
// type. Fails with an error at the op otherwise (lib/IR/Flow.cpp).
// Declared before the interface, whose verifier calls it.
mlir::LogicalResult verifyFlowEdges(mlir::Operation *op);

} // namespace idr

#endif // IDR_IR_FLOWEDGES_H
