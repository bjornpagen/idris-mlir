// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of a call: a clone is keyed by its owner (the function it was
// first cloned from) and the patterns of the owner's parameters, so that
// keys made at calls of the owner and of its clones compare.
//
// A call specializes on an argument only when the parameter's binding time
// allows it: anything static when the callee is on no cycle, and otherwise
// only for a fixed parameter, or a decreasing or bounded one whose static
// value is small. Every other argument is a runtime leaf, however static. A
// world carries no value to specialize around.
//
// Inside a chain of clones, a clone's parameter specializes again only when
// it is a closure: a closure static at a later call is new knowledge, where
// data would re-abstract what the key already fixed.
//
// The key is composed from the call alone: the callee's name, and its
// parameters as the call's operands, whose types verifySymbolUses makes
// the callee's. So a function pass composes it without resolving the
// callee.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/IR/Grades.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

namespace {

// The largest static value (unrollSize) a decreasing or bounded parameter
// is unrolled on. Unrolling exists to take small, partially static data off
// the heap (`Vect 3 Double`); a larger value stays data.
constexpr uint64_t kUnrollLimit = 32;

// A constant as a key: constructors and closures as the nodes they fold
// from. Each shared part is keyed once, in `keys`. A run is keyed as the
// constructors it stands for, from its tail back to its first cell, so that
// each cell is read once.
Attribute keyOfConstant(Attribute value, llvm::DenseMap<Attribute, Attribute> &keys) {
  if (Attribute known = keys.lookup(value))
    return known;
  MLIRContext *ctx = value.getContext();
  auto keysOf = [&](ArrayAttr parts) {
    return llvm::map_to_vector(parts, [&](Attribute part) { return keyOfConstant(part, keys); });
  };
  Attribute key = value;
  if (auto con = dyn_cast<ConAttr>(value)) {
    StringAttr data = con.getCtor().getRootReference();
    StringAttr ctor = con.getCtor().getLeafReference();
    if (!con.isRun()) {
      key = KeyConAttr::get(ctx, data, ctor, ArrayAttr::get(ctx, keysOf(con.getFields())));
    } else {
      key = keyOfConstant(con.getTail(), keys);
      for (ArrayAttr cell : llvm::reverse(con.getRunCells())) {
        auto fields = keysOf(cell);
        fields.insert(fields.begin() + con.getSpine(), key);
        key = KeyConAttr::get(ctx, data, ctor, ArrayAttr::get(ctx, fields));
      }
    }
  } else if (auto closure = dyn_cast<ClosureAttr>(value)) {
    key = KeyClosureAttr::get(ctx, closure.getCallee().getAttr(),
                              ArrayAttr::get(ctx, keysOf(closure.getCaptures())));
  }
  return keys[value] = key;
}

Attribute keyOfConstant(Attribute value) {
  llvm::DenseMap<Attribute, Attribute> keys;
  return keyOfConstant(value, keys);
}

// Whether a call specializes on a static argument of a parameter of
// binding time `time`: inside a chain of clones only on a closure, which is
// new knowledge where data would re-abstract what the key already fixed.
bool specializesOn(BindingTime time, bool intoClone, Type type) {
  return time != BindingTime::Other && (!intoClone || isClosureType(type));
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

// `part` of a clone's key with each hole filled with the pattern of the
// argument at its position: hole i of a clone's key is its parameter i.
Attribute fill(Attribute part, Composed &out) {
  MLIRContext *ctx = part.getContext();
  if (auto hole = dyn_cast<KeyHoleAttr>(part)) {
    unsigned p = hole.getIndex();
    return append(out.args[p], out.held[p], out);
  }
  auto parts = [&](ArrayAttr from) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(from, [&](Attribute inner) {
                            return fill(inner, out);
                          }));
  };
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getData(), con.getCtor(), parts(con.getFields()));
  if (auto closure = dyn_cast<KeyClosureAttr>(part))
    return KeyClosureAttr::get(ctx, closure.getCallee(), parts(closure.getCaptures()));
  return part;
}

} // namespace

// The pattern as a key: a typed attribute, whose labels are names and not
// symbol uses, so that a key keeps no function alive. A constructor or
// closure constant is keyed as the node it folds from, so that both key the
// same clone.
Attribute keyOf(const Pattern &pattern) {
  MLIRContext *ctx = pattern.type.getContext();
  auto keysOf = [&](const std::vector<Pattern> &parts) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(parts, [](const Pattern &part) {
                            return keyOf(part);
                          }));
  };
  return std::visit(
      Match{[&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
            [](const Constant &c) { return keyOfConstant(c.value); },
            [&](const Con &con) -> Attribute {
              return KeyConAttr::get(ctx, con.ctor.getRootReference(),
                                     con.ctor.getLeafReference(), keysOf(con.fields));
            },
            [&](const Closure &closure) -> Attribute {
              return KeyClosureAttr::get(ctx, closure.callee.getAttr(), keysOf(closure.captures));
            },
            // The type of the position says the value is linear.
            [](const Linear &linear) { return keyOf(linear.value.front()); }},
      pattern.node);
}

std::optional<Composed> composeKey(idr::CallOp call, const CloneTable &clones,
                                   const BindingTimes &times) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), [](Value v) { return isWorld(v.getType()) || isClosed(v); }))
    return std::nullopt;
  StringAttr callee = call.getCalleeAttr().getAttr();
  const Clone *own = clones.specialization(callee);

  Composed composed;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getArgs())) {
    std::optional<BindingTime> time = times.of(callee, static_cast<unsigned>(i));
    // A function made since the binding times were found has none until
    // they are found again.
    if (!time)
      return std::nullopt;
    Argument &arg = composed.args.emplace_back(Argument{leafOf(operand, 0), {operand}, *time});
    if (!specializesOn(*time, own, operand.getType()))
      continue;
    SmallVector<Value> leaves;
    Pattern shape = shapeOf(operand, leaves);
    // An unrolling parameter counts down scalars too (a Nat), but only as
    // far as the value is small.
    bool unrolls = *time == BindingTime::Decreasing || *time == BindingTime::Bounded;
    if (shape.isHole() || (unrolls ? unrollSize(shape) > kUnrollLimit : !hasStructure(shape)))
      continue;
    // A linear leaf moves into the clone's call, so the shape that held it
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
    for (Attribute part : cast<SpecKeyAttr>(own->key).getPatterns())
      patterns.push_back(fill(part, composed));
  } else {
    for (unsigned p = 0; p < composed.args.size(); ++p)
      patterns.push_back(append(composed.args[p], composed.held[p], composed));
  }
  composed.key =
      SpecKeyAttr::get(ctx, clones.ownerOf(callee), ArrayAttr::get(ctx, patterns));
  return composed;
}

} // namespace idr::specialize
