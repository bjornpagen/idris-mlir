// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of a call: a node is keyed by its owner (the function it is
// cloned from) and the patterns of the owner's parameters, so that keys
// made at calls of the owner and of its nodes compare.
//
// A call specializes on an argument only when the parameter's binding time
// allows it: anything static when the callee is on no cycle, and otherwise
// only for a fixed parameter, or a decreasing or bounded one whose static
// value is small. Every other argument is a runtime leaf, however static. A
// world carries no value to specialize around.
//
// Inside a chain of nodes, a node's parameter specializes again only on a
// closure, a constructor of a sum defunctionalization made: a closure
// static at a later call is new knowledge, where data would re-abstract
// what the key already fixed.
//
// The key is composed from the call alone, its callee's binding times and,
// for a node, its key: the callee's parameters are the call's operands,
// whose types the callee's are. A pattern's type is its position's, so the
// key holds none.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// The largest static value (unrollSize) a decreasing or bounded parameter
// is unrolled on. Unrolling exists to take small, partially static data off
// the heap (`Vect 3 Double`); a larger value stays data.
constexpr uint64_t kUnrollLimit = 32;

using ConstantKeys = llvm::DenseMap<std::pair<Attribute, Type>, Attribute>;

// The index in its constructor of field `i` of a run's cell, which holds
// every field but the spine.
unsigned fieldOfCell(unsigned i, unsigned spine) { return i < spine ? i : i + 1; }

// A constant at a position of `type`, as a key: a constructor as the node
// it folds from, over its fields at their declared types. Each shared part
// is keyed once per type, in `keys`. A run is keyed as the constructors it
// stands for, from its tail back to its first cell, so that each cell is
// read once.
Attribute keyOfConstant(Attribute value, Type type, ConstantKeys &keys) {
  type = unrestricted(type);
  if (Attribute known = keys.lookup({value, type}))
    return known;
  Attribute key = value;
  auto con = dyn_cast<ConAttr>(value);
  DataType data = con ? dataTypeOf(type) : DataType();
  std::optional<unsigned> tag =
      data ? data.getTag(con.getCtor().getValue()) : std::optional<unsigned>();
  if (tag) {
    MLIRContext *ctx = value.getContext();
    ArrayRef<Type> types = data.getCtor(*tag).fields;
    StringAttr name = StringAttr::get(ctx, data.getName());
    StringAttr ctor = con.getCtor().getAttr();
    if (!con.isRun()) {
      SmallVector<Attribute> fields;
      for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), types))
        fields.push_back(keyOfConstant(field, fieldType, keys));
      key = KeyConAttr::get(ctx, name, ctor, ArrayAttr::get(ctx, fields));
    } else {
      unsigned spine = con.getSpine();
      key = keyOfConstant(con.getTail(), type, keys);
      for (ArrayAttr cell : llvm::reverse(con.getRunCells())) {
        SmallVector<Attribute> fields;
        for (auto [i, field] : llvm::enumerate(cell))
          fields.push_back(
              keyOfConstant(field, types[fieldOfCell(static_cast<unsigned>(i), spine)], keys));
        fields.insert(fields.begin() + spine, key);
        key = KeyConAttr::get(ctx, name, ctor, ArrayAttr::get(ctx, fields));
      }
    }
  }
  return keys[{value, type}] = key;
}

Attribute keyOfConstant(Attribute value, Type type) {
  ConstantKeys keys;
  return keyOfConstant(value, type, keys);
}

// Whether a value of `type` is a closure: a constructor of a sum
// defunctionalization made.
bool isClosureValue(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.isClosures();
}

// Whether a call specializes on a static argument of a parameter of
// binding time `time`: inside a chain of nodes only on a closure.
bool specializesOn(BindingTime time, bool intoNode, Type type) {
  return time != BindingTime::Other && (!intoNode || isClosureValue(type));
}

// Appends argument `arg` to `out` as the key's next holes, and returns its
// pattern as a key.
Attribute append(Argument &arg, SmallVector<unsigned> &held, Composed &out) {
  unsigned next = static_cast<unsigned>(out.values.size());
  unsigned first = next;
  renumber(arg.pattern, next);
  for (unsigned hole = first; hole < next; ++hole)
    held.push_back(hole);
  llvm::append_range(out.values, arg.leaves);
  return keyOf(arg.pattern);
}

// `part` of a node's key with each hole filled with the pattern of the
// argument at its position: hole i of a node's key is its parameter i.
Attribute fill(Attribute part, Composed &out) {
  MLIRContext *ctx = part.getContext();
  if (auto hole = dyn_cast<KeyHoleAttr>(part)) {
    unsigned p = hole.getIndex();
    return append(out.args[p], out.held[p], out);
  }
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getData(), con.getCtor(),
                           ArrayAttr::get(ctx, llvm::map_to_vector(con.getFields(),
                                                                   [&](Attribute inner) {
                                                                     return fill(inner, out);
                                                                   })));
  return part;
}

} // namespace

// The pattern as a key: a dialect attribute, whose constructors are names
// and not symbol uses, so that a key keeps no function alive. A constructor
// constant is keyed as the node it folds from, so that both key the same
// node. A value entered into a linear type is keyed as the value: the type
// of its position says it is linear.
Attribute keyOf(const Pattern &pattern) {
  MLIRContext *ctx = pattern.type.getContext();
  return std::visit(
      Match{[&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
            [&](const Constant &c) { return keyOfConstant(c.value, pattern.type); },
            [&](const Con &con) -> Attribute {
              DataType data = dataTypeOf(pattern.type);
              SmallVector<Attribute> fields =
                  llvm::map_to_vector(con.fields, [](const Pattern &part) { return keyOf(part); });
              return KeyConAttr::get(ctx, StringAttr::get(ctx, data.getName()),
                                     con.ctor.getAttr(), ArrayAttr::get(ctx, fields));
            },
            [](const Linear &linear) { return keyOf(linear.value.front()); }},
      pattern.node);
}

std::optional<Composed> composeKey(idr::CallOp call, SpecKeyAttr own, const BindingTimes &times) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), [](Value v) { return isWorld(v.getType()) || isClosed(v); }))
    return std::nullopt;
  StringAttr callee = call.getCalleeAttr().getAttr();
  SmallVector<BindingTime> given = times.of(callee);
  // A final callee has its binding times; one without them is no final one.
  if (given.size() != call.getArgs().size())
    return std::nullopt;

  Composed composed;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getArgs())) {
    BindingTime time = given[i];
    Argument &arg = composed.args.emplace_back(Argument{leafOf(operand, 0), {operand}, time});
    if (!specializesOn(time, static_cast<bool>(own), operand.getType()))
      continue;
    SmallVector<Value> leaves;
    Pattern shape = shapeOf(operand, leaves);
    // An unrolling parameter counts down scalars too (a Nat), but only as
    // far as the value is small.
    bool unrolls = time == BindingTime::Decreasing || time == BindingTime::Bounded;
    if (shape.isHole() || (unrolls ? unrollSize(shape) > kUnrollLimit : !hasStructure(shape)))
      continue;
    // A linear leaf moves into the node's call, so the shape that held it
    // must die with the call it feeds: else the leaf is used twice.
    if (llvm::any_of(leaves, [](Value leaf) { return isLinear(leaf.getType()); }) &&
        !usedOnce(operand))
      continue;
    arg.pattern = std::move(shape);
    arg.leaves = std::move(leaves);
    any = true;
  }
  if (!any)
    return std::nullopt;

  MLIRContext *ctx = call.getContext();
  composed.held.resize(composed.args.size());
  SmallVector<Attribute> patterns;
  if (own) {
    for (Attribute part : own.getPatterns())
      patterns.push_back(fill(part, composed));
  } else {
    for (unsigned p = 0; p < composed.args.size(); ++p)
      patterns.push_back(append(composed.args[p], composed.held[p], composed));
  }
  StringAttr owner = own ? own.getOrigin() : callee;
  composed.key = SpecKeyAttr::get(ctx, owner, ArrayAttr::get(ctx, patterns));
  return composed;
}

} // namespace idr::specialize::detail
