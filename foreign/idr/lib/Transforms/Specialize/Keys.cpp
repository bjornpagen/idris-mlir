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
// (request), over the order keys are compared by (Order) and lifting: a
// key that grows an earlier one is refused, and one that differs from an
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

// An unsigned sum wide enough for both: a shared part counts once per use,
// so a size has no bound.
APInt plus(const APInt &lhs, const APInt &rhs) {
  unsigned width = std::max(lhs.getActiveBits(), rhs.getActiveBits()) + 1;
  return lhs.zextOrTrunc(width) + rhs.zextOrTrunc(width);
}

bool unsignedAtMost(const APInt &lhs, const APInt &rhs) {
  unsigned width = std::max(lhs.getBitWidth(), rhs.getBitWidth());
  return lhs.zext(width).ule(rhs.zext(width));
}

// What a constant is compared by besides its shape: a scalar by its kind
// and, when typed, its type; a big and a string by their kind; a constant
// constructor by its data type.
std::pair<TypeID, const void *> kindOf(Attribute value) {
  if (isa<BigAttr, StringAttr>(value))
    return {value.getTypeID(), nullptr};
  if (auto con = dyn_cast<ConAttr>(value))
    return {value.getTypeID(), con.getData().getAsOpaquePointer()};
  if (auto typed = dyn_cast<TypedAttr>(value))
    return {value.getTypeID(), typed.getType().getAsOpaquePointer()};
  return {value.getTypeID(), nullptr};
}

// A scalar of a key: a constant that is neither a constructor nor a part of
// a key's own.
bool isScalar(Attribute pattern) {
  return !isa<ConAttr, KeyHoleAttr, KeyConAttr>(pattern);
}

// Whether `a` and `b` are one shape: holes where holes are (a hole is one
// attribute), one constructor where one is over fields of one shape, one
// constant constructor of one data type, tag and spine over cells of one
// shape, and a scalar of one kind where one is, whatever its value.
bool oneShape(Attribute a, Attribute b) {
  if (a == b)
    return true;
  auto fields = [](ArrayAttr xs, ArrayAttr ys) {
    return xs.size() == ys.size() && llvm::all_of_zip(xs, ys, [](Attribute x, Attribute y) {
             return oneShape(x, y);
           });
  };
  if (auto x = dyn_cast<KeyConAttr>(a)) {
    auto y = dyn_cast<KeyConAttr>(b);
    return y && x.getTag() == y.getTag() && fields(x.getFields(), y.getFields());
  }
  if (auto x = dyn_cast<ConAttr>(a)) {
    auto y = dyn_cast<ConAttr>(b);
    // all_of_zip is false for cells of two lengths.
    return y && x.getData() == y.getData() && x.getTag() == y.getTag() &&
           x.getSpine() == y.getSpine() && llvm::all_of_zip(x.getCells(), y.getCells(), fields);
  }
  return isScalar(a) && isScalar(b) && kindOf(a) == kindOf(b);
}

// `part` of a key with each scalar where it differs from `earlier`, of its
// shape, lifted out into a hole, each new hole's source appended to
// `sources`; `next` counts the holes of the key `part` is of, in pre-order,
// so a kept hole names the one it was. A constant constructor of one cell
// that differs is taken apart into its constructor over its fields; a run
// of more than one cell is one constant, lifted whole, so that a key never
// unrolls a run: its cells are the run's length, not a shape.
Attribute liftPart(Attribute earlier, Attribute part, unsigned &next,
                   SmallVectorImpl<Source> &sources) {
  MLIRContext *ctx = part.getContext();
  auto hole = [&](Source source) {
    sources.push_back(source);
    return KeyHoleAttr::get(ctx);
  };
  auto fields = [&](ArrayAttr before, ArrayAttr after) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(llvm::zip_equal(before, after), [&](auto pair) {
                            return liftPart(std::get<0>(pair), std::get<1>(pair), next, sources);
                          }));
  };
  if (isa<KeyHoleAttr>(part))
    return hole(Kept{next++});
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getTag(),
                           fields(cast<KeyConAttr>(earlier).getFields(), con.getFields()));
  if (part == earlier)
    return part;
  if (auto con = dyn_cast<ConAttr>(part)) {
    if (con.getRunLength() > 1)
      return hole(Lifted{con});
    return KeyConAttr::get(ctx, con.getTag(),
                           fields(cast<ConAttr>(earlier).getFields(), con.getFields()));
  }
  return hole(Lifted{part});
}

} // namespace

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

// A homeomorphic embedding of keys, the well-quasi-order that stops
// supercompilation, over the patterns of one owner's parameters, position
// by position. A pattern embeds in another when it is the other with parts
// taken away: a constructor in a constructor of its tag, field by field,
// or in any field of a larger one; a hole in a hole; a scalar in any
// scalar of its kind, its value an equality domain that lifting answers
// and the order does not measure; a constant constructor, one constant, in
// one of its data type no smaller, measured by its cells and scalars, so
// that a run stays a run here too and is measured once. What a pattern
// embeds in is a function of its shape alone. A key grows an earlier one of
// its owner that embeds in it when it does not embed back: it is the
// earlier key with more structure, which the table refuses; a key does not
// grow itself. A raise key is never compared: its form is a function's that
// is no node, or its requesting raise node's own, and its callee one of the
// finitely many below a final function.
bool Order::grows(SpecKeyAttr ancestor, SpecKeyAttr key) {
  Embeddings known;
  auto all = [&](ArrayAttr small, ArrayAttr big) {
    return llvm::all_of_zip(small, big,
                            [&](Attribute s, Attribute b) { return embeds(s, b, known); });
  };
  return all(ancestor.getPatterns(), key.getPatterns()) &&
         !all(key.getPatterns(), ancestor.getPatterns());
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

// Whether the constant `small` is of the kind of `big` and, for a constant
// constructor, no larger.
bool Order::atMost(Attribute small, Attribute big) {
  if (kindOf(small) != kindOf(big))
    return false;
  return !isa<ConAttr>(small) || unsignedAtMost(size(small), size(big));
}

// The size of a constant: one for a scalar, and for a constructor its
// cells, each one more than its fields, the last cell's spine field among
// them. Each part is measured once however often it is shared, from its
// last part back, with no recursion, however deep the constant.
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
      sizes[at] = APInt(1, 1);
      work.pop_back();
      continue;
    }
    auto parts = [&](auto &&each) {
      for (ArrayAttr cell : con.getCells())
        for (Attribute field : cell)
          each(field);
    };
    if (!expanded) {
      work.back().second = true;
      parts([&](Attribute part) {
        if (!sizes.contains(part))
          work.push_back({part, false});
      });
      continue;
    }
    APInt total(64, con.getRunLength());
    parts([&](Attribute part) { total = plus(total, sizes.at(part)); });
    sizes[at] = total;
    work.pop_back();
  }
  return sizes.at(constant);
}

bool sameShape(SpecKeyAttr a, SpecKeyAttr b) {
  return llvm::all_of_zip(a.getPatterns(), b.getPatterns(), oneShape);
}

SpecKeyAttr lift(SpecKeyAttr earlier, SpecKeyAttr key, SmallVectorImpl<Source> &sources) {
  MLIRContext *ctx = key.getContext();
  SmallVector<Attribute> patterns;
  unsigned next = 0;
  for (auto [before, after] : llvm::zip_equal(earlier.getPatterns(), key.getPatterns()))
    patterns.push_back(liftPart(before, after, next, sources));
  return SpecKeyAttr::get(ctx, key.getOrigin(), ArrayAttr::get(ctx, patterns));
}

} // namespace idr::specialize::detail
