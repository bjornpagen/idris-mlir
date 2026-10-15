// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of a call: a node is keyed by its owner (the function it is
// cloned from) and the patterns of the owner's parameters, so that keys
// made at calls of the owner and of its nodes compare.
//
// A call specializes on an argument only where the parameter's binding
// time, as the call sees it, is free or fixed (offline partial evaluation).
// A call that stays within the recursion of the component its requester
// stands for sees the callee's binding times: only a parameter every
// recursive call passes on unchanged keys a node, so the recursion keeps
// one key, and a counter, a list's tail or any other part that varies
// along it is passed as a value. A call that enters the component from
// outside sees the callee as on no cycle, every parameter free: any static
// argument keys, one node per entry, inside which the first rule holds
// again. Every other argument is a runtime leaf, however static. A lone
// scalar is never a key position, and a world carries no value to
// specialize around.
//
// Inside a chain of nodes, a node's parameter specializes again only on a
// closure, a constructor of a sum defunctionalization made: a closure
// static at a later call is new knowledge, where data would re-abstract
// what the key already fixed.
//
// The key is composed from the call alone, the binding times it sees and,
// for a node, its key: the callee's parameters are the call's operands,
// whose types the callee's are. A pattern's type is its position's, so the
// key holds none.
//
// The binding times keep each recursion to the keys of its entries. What
// ends specialization whatever else a program does is the order keys are
// compared by on a request chain (Order): a key that grows one on its
// chain is not made.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

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
// at binding time `time`: one free or fixed, and inside a chain of nodes
// only on a closure.
bool specializesOn(BindingTime time, bool intoNode, Type type) {
  return (time == BindingTime::Free || time == BindingTime::Fixed) &&
         (!intoNode || isClosureValue(type));
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
    return KeyConAttr::get(ctx, con.getTag(),
                           ArrayAttr::get(ctx, llvm::map_to_vector(con.getFields(),
                                                                   [&](Attribute inner) {
                                                                     return fill(inner, out);
                                                                   })));
  return part;
}

// An unsigned sum wide enough for both: a magnitude has no bound.
APInt plus(const APInt &lhs, const APInt &rhs) {
  unsigned width = std::max(lhs.getActiveBits(), rhs.getActiveBits()) + 1;
  return lhs.zextOrTrunc(width) + rhs.zextOrTrunc(width);
}

bool unsignedAtMost(const APInt &lhs, const APInt &rhs) {
  unsigned width = std::max(lhs.getBitWidth(), rhs.getBitWidth());
  return lhs.zext(width).ule(rhs.zext(width));
}

// What a constant other than a constructor is compared by besides its
// magnitude: an integer or a float by its kind and type, a big and a
// string by their kind, any other constant as itself.
std::pair<TypeID, const void *> kindOf(Attribute value) {
  if (auto integer = dyn_cast<IntegerAttr>(value))
    return {value.getTypeID(), integer.getType().getAsOpaquePointer()};
  if (auto real = dyn_cast<FloatAttr>(value))
    return {value.getTypeID(), real.getType().getAsOpaquePointer()};
  if (isa<BigAttr, StringAttr>(value))
    return {value.getTypeID(), nullptr};
  if (auto con = dyn_cast<ConAttr>(value))
    return {value.getTypeID(), con.getData().getAsOpaquePointer()};
  return {value.getTypeID(), value.getAsOpaquePointer()};
}

// The magnitude of a scalar constant: an integer of any kind and a big by
// their absolute value (an unsigned one by its value), a string by its
// length. Finitely many constants of one kind share one, so a chain of
// distinct keys whose constants never grow is finite. A float, finitely
// many of each type, and a constant compared as itself measure nothing.
APInt magnitudeOf(Attribute value) {
  if (auto integer = dyn_cast<IntegerAttr>(value)) {
    const APInt &n = integer.getValue();
    return integer.getType().isUnsignedInteger() ? n : n.abs();
  }
  if (auto big = dyn_cast<BigAttr>(value))
    return big.getValue().abs();
  if (auto text = dyn_cast<StringAttr>(value))
    return APInt(64, text.size());
  return APInt(1, 0);
}

} // namespace

// The pattern as a key: a dialect attribute, whose constructors are tags
// and not symbol uses, so that a key keeps no function alive. A constant
// is keyed as itself, a run as the run it is, so a key is as large as the
// code and the constants that make it. A value entered into a linear type
// is keyed as the value: the type of its position says it is linear.
Attribute keyOf(const Pattern &pattern) {
  MLIRContext *ctx = pattern.type.getContext();
  return std::visit(
      Match{[&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
            [](const Constant &c) { return c.value; },
            [&](const Con &con) -> Attribute {
              SmallVector<Attribute> fields =
                  llvm::map_to_vector(con.fields, [](const Pattern &part) { return keyOf(part); });
              return KeyConAttr::get(ctx, con.tag, ArrayAttr::get(ctx, fields));
            },
            [](const Linear &linear) { return keyOf(linear.value.front()); }},
      pattern.node);
}

std::optional<Composed> composeKey(idr::CallOp call, SpecKeyAttr own, ArrayRef<BindingTime> seen) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), [](Value v) { return isWorld(v.getType()) || isClosed(v); }))
    return std::nullopt;
  // A final callee has its binding times; one without them is no final one.
  if (seen.size() != call.getArgs().size())
    return std::nullopt;

  Composed composed;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getArgs())) {
    BindingTime time = seen[i];
    Argument &arg = composed.args.emplace_back(Argument{leafOf(operand, 0), {operand}, time});
    if (!specializesOn(time, static_cast<bool>(own), operand.getType()))
      continue;
    SmallVector<Value> leaves;
    Pattern shape = shapeOf(operand, leaves);
    if (!hasStructure(shape))
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
  StringAttr owner = own ? own.getOrigin() : call.getCalleeAttr().getAttr();
  composed.key = SpecKeyAttr::get(ctx, owner, ArrayAttr::get(ctx, patterns));
  return composed;
}

// A homeomorphic embedding of keys, the well-quasi-order that stops
// supercompilation, over the patterns of one owner's parameters, position
// by position. A pattern embeds in another when it is the other with parts
// taken away: a constructor in a constructor of its tag, field by field,
// or in any field of a larger one; a hole in a hole; a constant in a
// constant of its kind no smaller. A constant constructor is one constant,
// measured by its size (each cell one, each scalar one more than its
// magnitude), so that a run stays a run here too and is measured once.
//
// On one request chain the keys of one owner are distinct, and finitely
// many keys of one owner embed both ways in one key. By Kruskal's tree
// theorem any infinite sequence of them has an earlier key embedded in a
// later one, and then one that does not embed back: there the chain grows,
// and the key is not made. So every chain is finite. A raise key grows
// nothing: its form is a function's that is no node, or its requesting
// raise node's own, and its callee one of the finitely many below a final
// function.
bool Order::grows(Attribute ancestor, Attribute key) {
  auto before = dyn_cast<SpecKeyAttr>(ancestor);
  auto after = dyn_cast<SpecKeyAttr>(key);
  if (!before || !after || before == after || before.getOrigin() != after.getOrigin())
    return false;
  Embeddings known;
  auto all = [&](ArrayAttr small, ArrayAttr big) {
    return llvm::all_of_zip(small, big,
                            [&](Attribute s, Attribute b) { return embeds(s, b, known); });
  };
  return all(before.getPatterns(), after.getPatterns()) &&
         !all(after.getPatterns(), before.getPatterns());
}

bool Order::embeds(Attribute small, Attribute big, Embeddings &known) {
  if (small == big)
    return true;
  if (auto found = known.find({small, big}); found != known.end())
    return found->second;
  bool out = false;
  auto bigCon = dyn_cast<KeyConAttr>(big);
  if (bigCon)
    out = llvm::any_of(bigCon.getFields(),
                       [&](Attribute field) { return embeds(small, field, known); });
  if (!out) {
    if (isa<KeyHoleAttr>(small)) {
      out = isa<KeyHoleAttr>(big);
    } else if (auto smallCon = dyn_cast<KeyConAttr>(small)) {
      out = bigCon && smallCon.getTag() == bigCon.getTag() &&
            llvm::all_of_zip(smallCon.getFields(), bigCon.getFields(),
                             [&](Attribute s, Attribute b) { return embeds(s, b, known); });
    } else {
      out = !bigCon && !isa<KeyHoleAttr>(big) && atMost(small, big);
    }
  }
  known[{small, big}] = out;
  return out;
}

// Whether the constant `small` is of the kind of `big` and no larger.
bool Order::atMost(Attribute small, Attribute big) {
  if (kindOf(small) != kindOf(big))
    return false;
  if (isa<ConAttr>(small))
    return unsignedAtMost(size(small), size(big));
  return unsignedAtMost(magnitudeOf(small), magnitudeOf(big));
}

// The size of a constant: one more than its magnitude for a scalar, and for
// a constructor its cells, each one more than its fields, then its tail.
// Each part is measured once however often it is shared, from its last
// part back, with no recursion, however deep the constant.
APInt Order::size(Attribute constant) {
  SmallVector<std::pair<Attribute, bool>> work{{constant, false}};
  while (!work.empty()) {
    auto [at, expanded] = work.back();
    if (sizes.contains(at)) {
      work.pop_back();
      continue;
    }
    auto con = dyn_cast<ConAttr>(at);
    if (!con) {
      sizes[at] = plus(APInt(1, 1), magnitudeOf(at));
      work.pop_back();
      continue;
    }
    auto parts = [&](auto &&each) {
      for (ArrayAttr cell : con.getCells())
        for (Attribute field : cell)
          each(field);
      if (Attribute tail = con.getTail())
        each(tail);
    };
    if (!expanded) {
      work.back().second = true;
      parts([&](Attribute part) {
        if (!sizes.contains(part))
          work.push_back({part, false});
      });
      continue;
    }
    APInt total(64, con.getCells().size());
    parts([&](Attribute part) { total = plus(total, sizes.lookup(part)); });
    sizes[at] = total;
    work.pop_back();
  }
  return sizes.lookup(constant);
}

} // namespace idr::specialize::detail
