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

// Whether `a` and `b` are one shape: holes where holes are, one constructor
// where one is over fields of one shape, one run of one length, and a
// scalar of one kind where one is, whatever its value.
bool oneShape(Attribute a, Attribute b) {
  if (a == b)
    return true;
  if (auto x = dyn_cast<KeyHoleAttr>(a)) {
    auto y = dyn_cast<KeyHoleAttr>(b);
    return y && x.getIndex() == y.getIndex();
  }
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
    if (!y || x.getData() != y.getData() || x.getTag() != y.getTag() ||
        x.getSpine() != y.getSpine() || x.getRunLength() != y.getRunLength() ||
        x.isRun() != y.isRun())
      return false;
    if (x.isRun() && !oneShape(x.getTail(), y.getTail()))
      return false;
    return llvm::all_of_zip(x.getCells(), y.getCells(),
                            [&](ArrayAttr xs, ArrayAttr ys) { return fields(xs, ys); });
  }
  return isScalar(b) && kindOf(a) == kindOf(b);
}

// `part` of a key with each scalar where it differs from `earlier`, of its
// shape, lifted out into a hole; the holes are numbered anew from the size
// of `sources`, each with where its operand comes from. A constant
// constructor that differs is taken apart into its constructor over its
// fields; a run is one constant, lifted whole, so that a key never unrolls
// a run.
Attribute liftPart(Attribute earlier, Attribute part, SmallVectorImpl<Source> &sources) {
  MLIRContext *ctx = part.getContext();
  auto hole = [&](Source source) {
    sources.push_back(source);
    return KeyHoleAttr::get(ctx, static_cast<unsigned>(sources.size() - 1));
  };
  auto fields = [&](ArrayAttr before, ArrayAttr after) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(llvm::zip_equal(before, after), [&](auto pair) {
                            return liftPart(std::get<0>(pair), std::get<1>(pair), sources);
                          }));
  };
  if (auto at = dyn_cast<KeyHoleAttr>(part))
    return hole(Kept{at.getIndex()});
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getTag(),
                           fields(cast<KeyConAttr>(earlier).getFields(), con.getFields()));
  if (part == earlier)
    return part;
  if (auto con = dyn_cast<ConAttr>(part)) {
    if (con.isRun())
      return hole(Lifted{con});
    return KeyConAttr::get(ctx, con.getTag(),
                           fields(cast<ConAttr>(earlier).getFields(), con.getFields()));
  }
  return hole(Lifted{part});
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
      llvm::makeVisitor(
          [&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
          [](const Constant &c) { return c.value; },
          [&](const Con &con) -> Attribute {
            SmallVector<Attribute> fields =
                llvm::map_to_vector(con.fields, [](const Pattern &part) { return keyOf(part); });
            return KeyConAttr::get(ctx, con.tag, ArrayAttr::get(ctx, fields));
          },
          [](const Linear &linear) { return keyOf(linear.value.front()); }),
      pattern.node);
}

std::optional<Composed> composeKey(idr::CallOp call, std::optional<SpecKeyAttr> own,
                                   ArrayRef<BindingTime> seen) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), [](Value v) { return isWorld(v.getType()) || isClosed(v); }))
    return std::nullopt;
  assert(seen.size() == call.getArgs().size() &&
         "a final callee has one binding time per parameter");

  Composed composed;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getArgs())) {
    BindingTime time = seen[i];
    Argument &arg = composed.args.emplace_back(Argument{leafOf(operand, 0), {operand}, time});
    if (!specializesOn(time, own.has_value(), operand.getType()))
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
    for (Attribute part : own->getPatterns())
      patterns.push_back(fill(part, composed));
  } else {
    for (unsigned p = 0; p < composed.args.size(); ++p)
      patterns.push_back(append(composed.args[p], composed.held[p], composed));
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
// earlier key with more structure, which the table refuses. A raise key
// grows nothing: its form is a function's that is no node, or its
// requesting raise node's own, and its callee one of the finitely many
// below a final function.
bool Order::grows(const Key &ancestor, const Key &key) {
  const auto *beforeKey = std::get_if<SpecKeyAttr>(&ancestor);
  const auto *afterKey = std::get_if<SpecKeyAttr>(&key);
  if (!beforeKey || !afterKey)
    return false;
  SpecKeyAttr before = *beforeKey, after = *afterKey;
  if (before == after || before.getOrigin() != after.getOrigin())
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

// Whether the constant `small` is of the kind of `big` and, for a constant
// constructor, no larger.
bool Order::atMost(Attribute small, Attribute big) {
  if (kindOf(small) != kindOf(big))
    return false;
  return !isa<ConAttr>(small) || unsignedAtMost(size(small), size(big));
}

// The size of a constant: one for a scalar, and for a constructor its
// cells, each one more than its fields, then its tail. Each part is
// measured once however often it is shared, from its last part back, with
// no recursion, however deep the constant.
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
    parts([&](Attribute part) { total = plus(total, sizes.at(part)); });
    sizes[at] = total;
    work.pop_back();
  }
  return sizes.at(constant);
}

bool sameShape(SpecKeyAttr a, SpecKeyAttr b) {
  return a.getOrigin() == b.getOrigin() &&
         llvm::all_of_zip(a.getPatterns(), b.getPatterns(), oneShape);
}

SpecKeyAttr lift(SpecKeyAttr earlier, SpecKeyAttr key, SmallVectorImpl<Source> &sources) {
  MLIRContext *ctx = key.getContext();
  SmallVector<Attribute> patterns;
  for (auto [before, after] : llvm::zip_equal(earlier.getPatterns(), key.getPatterns()))
    patterns.push_back(liftPart(before, after, sources));
  return SpecKeyAttr::get(ctx, key.getOrigin(), ArrayAttr::get(ctx, patterns));
}

} // namespace idr::specialize::detail
