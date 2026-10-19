// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of a call: a node is keyed by its owner (the function it is
// cloned from) and the patterns of the owner's parameters, so that keys
// made at calls of the owner and of its nodes compare.
//
// A call specializes on an argument only where the parameter's binding
// time, as the call sees it, is fixed (offline partial evaluation). A call
// that stays within the recursion of the component its requester stands
// for sees the callee's binding times: only a parameter every recursive
// call passes on unchanged keys a node, so the recursion keeps one key, and
// a counter, a list's tail or any other part that varies along it is
// passed as a value. A call that enters the component from outside sees
// every parameter fixed, as for a callee on no cycle: any static argument
// keys, one node per entry, inside which the first rule holds again. Every
// other argument is a runtime leaf, however static. A lone scalar is never
// a key position, and a world carries no value to specialize around.
//
// Inside a chain of nodes, a node's parameter specializes again only on a
// closure, a constructor of a sum defunctionalization made: a closure
// static at a later call is new knowledge, where data would re-abstract
// what the key already fixed.
//
// The key is composed from the call alone, the binding times it sees and,
// for a node, its key: the callee's parameters are the call's operands,
// whose types the callee's are. A pattern's type is its position's, so the
// key holds none, and a hole is its position: the walks below go through a
// key's holes in pre-order with a cursor.
//
// The binding times keep each recursion to the keys of its entries. What
// ends specialization whatever else a program does is the table's rule
// (request), over the order keys are compared by and lifting (Order.cpp):
// a key that grows an earlier one is refused, and one that differs from an
// earlier one of its shape only in scalars is lifted to the key that keeps
// what the two share.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// Whether a value of `type` is a closure: a constructor of a sum
// defunctionalization made.
bool isClosureValue(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.isClosures();
}

// Whether a call specializes on a static argument of a parameter it sees
// at binding time `time`: a fixed one, and inside a chain of nodes only on
// a closure.
bool specializesOn(BindingTime time, bool intoNode, Type type) {
  return time == BindingTime::Fixed && (!intoNode || isClosureValue(type));
}

// One argument of a call: its pattern and its runtime leaves, in the
// pattern's pre-order.
struct Shaped {
  Attribute shape;
  SmallVector<Value> leaves;
};

// `part` of a node's key with each hole filled with the shape of the
// argument at its position: the i-th hole of a node's key, met in
// pre-order, is its parameter i, whose argument's leaves follow in
// `values`.
Attribute fill(Attribute part, ArrayRef<Shaped> args, unsigned &next,
               SmallVectorImpl<Value> &values) {
  MLIRContext *ctx = part.getContext();
  if (isa<KeyHoleAttr>(part)) {
    const Shaped &arg = args[next++];
    llvm::append_range(values, arg.leaves);
    return arg.shape;
  }
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getTag(),
                           ArrayAttr::get(ctx, llvm::map_to_vector(con.getFields(),
                                                                   [&](Attribute inner) {
                                                                     return fill(inner, args, next,
                                                                                 values);
                                                                   })));
  return part;
}

// Each label of the closures `pattern`, at a value of `type`, holds, when
// it holds closures alone: a constructor of a closure sum is its label,
// and its captures are read at their own types; a hole is a value of run
// time, and a scalar a closure captured is data it carries. False at a
// structure a recursion could walk: a constructor of another data type, or
// a closure that holds, among its captures at any depth, a closure of its
// own label (a chain of compositions, of continuations). `path` holds the
// labels of the closures `pattern` is a capture of.
bool closuresIn(Attribute pattern, Type type, SmallVectorImpl<StringAttr> &labels,
                SmallVectorImpl<StringAttr> &path) {
  if (isa<KeyHoleAttr>(pattern))
    return true;
  DataType data = dataTypeOf(type);
  if (!data || !data.isClosures())
    return false;
  auto capturesIn = [&](Attribute capture, Type captureType) {
    if (isa<KeyHoleAttr>(capture))
      return true;
    if (DataType held = dataTypeOf(captureType); held && held.isClosures())
      return closuresIn(capture, captureType, labels, path);
    return !isa<KeyConAttr, ConAttr>(capture);
  };
  // A closure sum's constructors are its labels.
  auto enter = [&](Tag tag) -> const Ctor * {
    const Ctor &found = data.getCtor(tag);
    StringAttr label = std::get_if<role::Label>(&found.role)->fn.getAttr();
    if (llvm::is_contained(path, label))
      return nullptr;
    labels.push_back(label);
    path.push_back(label);
    return &found;
  };
  bool alone = true;
  if (auto con = dyn_cast<KeyConAttr>(pattern)) {
    const Ctor *found = enter(con.getTag());
    if (!found)
      return false;
    for (auto [capture, captureType] : llvm::zip_equal(con.getFields(), found->fields))
      alone = alone && capturesIn(capture, captureType);
  } else {
    auto constant = dyn_cast<ConAttr>(pattern);
    if (!constant || constant.getRunLength() > 1)
      return false;
    const Ctor *found = enter(constant.getTag());
    if (!found)
      return false;
    constant.walkFields([&](Attribute capture, unsigned i) {
      alone = alone && capturesIn(capture, found->fields[i]);
    });
  }
  path.pop_back();
  return alone;
}

} // namespace

std::optional<SmallVector<StringAttr>> closuresFixed(SpecKeyAttr key, TypeRange params) {
  SmallVector<StringAttr> labels, path;
  for (auto [pattern, type] : llvm::zip_equal(key.getPatterns(), params))
    if (!closuresIn(pattern, type, labels, path))
      return std::nullopt;
  return labels;
}

namespace {

// Whether `value`, or a closure or suspension among the parts of a
// constructor that built it, is used by something else too: the parts a key
// fixes are read through the constructors that build them, and through the
// grades on the way.
bool sharedPart(Value value) {
  Value made = throughLinear(value);
  if (isClosureValue(value.getType()) && (!value.hasOneUse() || !made.hasOneUse()))
    return true;
  auto built = made.getDefiningOp<ConOp>();
  return built && llvm::any_of(built.getFields(), sharedPart);
}

} // namespace

bool sharesClosure(idr::CallOp call) {
  return llvm::any_of(call.getArgs(), sharedPart);
}

std::optional<Composed> composeKey(idr::CallOp call, std::optional<SpecKeyAttr> own,
                                   ArrayRef<BindingTime> seen) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), [](Value v) { return isWorld(v.getType()) || isClosed(v); }))
    return std::nullopt;
  assert(seen.size() == call.getArgs().size() &&
         "a final callee has one binding time per parameter");

  MLIRContext *ctx = call.getContext();
  // Each argument a hole over itself, or the shape it is specialized on.
  SmallVector<Shaped> args;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getArgs())) {
    Shaped &arg = args.emplace_back(Shaped{KeyHoleAttr::get(ctx), {operand}});
    if (!specializesOn(seen[i], own.has_value(), operand.getType()))
      continue;
    SmallVector<Value> leaves;
    Attribute shape = shapeOf(operand, leaves);
    if (!hasStructure(shape))
      continue;
    // A linear leaf moves into the node's call, so the shape that held it
    // must die with the call it feeds: else the leaf is used twice.
    if (llvm::any_of(leaves, [](Value leaf) { return isLinear(leaf.getType()); }) &&
        !usedOnce(operand))
      continue;
    arg = Shaped{shape, std::move(leaves)};
    any = true;
  }
  if (!any)
    return std::nullopt;

  Composed composed;
  SmallVector<Attribute> patterns;
  if (own) {
    unsigned next = 0;
    for (Attribute part : own->getPatterns())
      patterns.push_back(fill(part, args, next, composed.values));
  } else {
    for (Shaped &arg : args) {
      patterns.push_back(arg.shape);
      llvm::append_range(composed.values, arg.leaves);
    }
  }
  StringAttr owner = own ? own->getOrigin() : call.getCalleeAttr().getAttr();
  composed.key = SpecKeyAttr::get(ctx, owner, ArrayAttr::get(ctx, patterns));
  return composed;
}

} // namespace idr::specialize::detail
