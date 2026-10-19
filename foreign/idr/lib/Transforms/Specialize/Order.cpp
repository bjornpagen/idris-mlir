// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How keys of one owner are compared, which ends specialization whatever
// else a program does: the order a key is checked by against the keys on
// its request chain and those its requester was given (a homeomorphic
// embedding), and lifting, which takes a key that differs from an earlier
// one of its shape only in scalars to the key that keeps what the two
// share. The keys themselves are composed in Keys.cpp.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize::detail {

namespace {

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
