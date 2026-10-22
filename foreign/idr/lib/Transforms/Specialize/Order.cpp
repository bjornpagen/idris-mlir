// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The order keys of one owner are compared by.
//
// The order ends specialization whatever else a program does: a key is
// refused when it grows a key its requester was given before, or one on
// its request chain, and a key that differs from earlier ones of its shape
// only in scalars is lifted (Lift.cpp). The embedding is homeomorphic: a
// pattern embeds in another when it is the other with parts taken away,
// and what a pattern embeds in depends on its shape alone, so over finitely
// many tags and kinds it is a well-quasi-order, and every sequence of keys
// of one owner none of which grows an earlier one is finite.
//
// A pattern is as deep as the constructors a call's arguments nest, which
// the program's size bounds, so every walk here keeps its own stack.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

//===----------------------------------------------------------------------===//
// The order
//===----------------------------------------------------------------------===//

namespace {

// What a constant is compared by besides its shape: its attribute's kind
// and, when typed, its type. A constant constructor is one constant of its
// data type.
std::pair<TypeID, Type> constantKind(Attribute value) {
  if (auto typed = dyn_cast<TypedAttr>(value))
    return {value.getTypeID(), typed.getType()};
  return {value.getTypeID(), Type()};
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

// The size of a constant: one for a scalar, and for a constructor its
// cells, each one more than its fields. Each part measured once however
// often it is shared.
APInt sizeOf(Attribute constant, llvm::DenseMap<Attribute, APInt> &sizes) {
  llvm::SmallVector<std::pair<Attribute, bool>> work{{constant, false}};
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
    if (!expanded) {
      work.back().second = true;
      con.walkFields([&](Attribute part, unsigned) {
        if (!sizes.contains(part))
          work.push_back({part, false});
      });
      continue;
    }
    APInt total(64, con.getRunLength());
    con.walkFields([&](Attribute part, unsigned) { total = plus(total, sizes.at(part)); });
    sizes[at] = total;
    work.pop_back();
  }
  return sizes.at(constant);
}

using Pair = std::pair<const Pattern *, const Pattern *>;

// The embedding questions of one comparison of two keys, each pair
// answered once, from the leaves up.
class Embeds {
public:
  bool operator()(const Pattern *small, const Pattern *big) {
    llvm::SmallVector<Pair> work{{small, big}};
    while (!work.empty()) {
      Pair at = work.back();
      if (known.contains(at)) {
        work.pop_back();
        continue;
      }
      bool ready = true;
      for (Pair need : needs(at))
        if (!known.contains(need)) {
          work.push_back(need);
          ready = false;
        }
      if (!ready)
        continue;
      known[at] = answer(at);
      work.pop_back();
    }
    return known.at({small, big});
  }

private:
  // The pairs whose answers `s` in `b` reads: `s` in each field of a
  // larger constructor, and, under one tag, field in field.
  llvm::SmallVector<Pair> needs(Pair at) {
    auto [s, b] = at;
    llvm::SmallVector<Pair> out;
    if (s == b)
      return out;
    idr::match(
        b->get(),
        [&](const Con &big) {
          for (const Pattern *field : big.fields)
            out.push_back({s, field});
          idr::match(
              s->get(),
              [&](const Con &smallCon) {
                if (smallCon.tag == big.tag)
                  for (auto [sf, bf] : llvm::zip_equal(smallCon.fields, big.fields))
                    out.push_back({sf, bf});
              },
              [](const auto &) {});
        },
        [](const auto &) {});
    return out;
  }

  // A constructor in one of its tag, field by field, or in any field of a
  // larger one; a hole in a hole; a scalar in any scalar of its kind; a
  // constant constructor in one of its data type no smaller.
  bool answer(Pair at) {
    auto [s, b] = at;
    if (s == b)
      return true;
    bool inField = idr::match(
        b->get(),
        [&](const Con &big) {
          return llvm::any_of(big.fields, [&](const Pattern *field) { return known.at({s, field}); });
        },
        [](const auto &) { return false; });
    if (inField)
      return true;
    return idr::match(
        s->get(),
        [&](Hole) {
          return idr::match(b->get(), [](Hole) { return true; }, [](const auto &) { return false; });
        },
        [&](const Con &smallCon) {
          return idr::match(
              b->get(),
              [&](const Con &big) {
                return smallCon.tag == big.tag &&
                       llvm::all_of_zip(smallCon.fields, big.fields,
                                        [&](const Pattern *sf, const Pattern *bf) {
                                          return known.at({sf, bf});
                                        });
              },
              [](const auto &) { return false; });
        },
        [&](const Const &smallConst) {
          return idr::match(
              b->get(),
              [&](const Const &bigConst) {
                if (constantKind(smallConst.value) != constantKind(bigConst.value))
                  return false;
                if (!isa<ConAttr>(smallConst.value))
                  return true;
                return unsignedAtMost(sizeOf(smallConst.value, sizes),
                                      sizeOf(bigConst.value, sizes));
              },
              [](const auto &) { return false; });
        });
  }

  llvm::DenseMap<Pair, bool> known;
  llvm::DenseMap<Attribute, APInt> sizes;
};

// Whether `a` and `b` are one shape: holes where holes are, one
// constructor over fields of one shape, a scalar of one kind, whatever its
// value.
bool oneShape(const Pattern *a, const Pattern *b) {
  llvm::SmallVector<Pair> work{{a, b}};
  while (!work.empty()) {
    auto [x, y] = work.pop_back_val();
    if (x == y)
      continue;
    bool same = idr::match(
        x->get(),
        [&](Hole) {
          return idr::match(y->get(), [](Hole) { return true; }, [](const auto &) { return false; });
        },
        [&](const Con &con) {
          return idr::match(
              y->get(),
              [&](const Con &other) {
                if (con.tag != other.tag || con.fields.size() != other.fields.size())
                  return false;
                for (auto [xf, yf] : llvm::zip_equal(con.fields, other.fields))
                  work.push_back({xf, yf});
                return true;
              },
              [](const auto &) { return false; });
        },
        [&](const Const &constant) {
          return idr::match(
              y->get(),
              [&](const Const &other) {
                return constantKind(constant.value) == constantKind(other.value);
              },
              [](const auto &) { return false; });
        });
    if (!same)
      return false;
  }
  return true;
}

} // namespace

bool grows(const PatternKey &earlier, const PatternKey &key) {
  Embeds embeds;
  auto all = [&](llvm::ArrayRef<const Pattern *> small, llvm::ArrayRef<const Pattern *> big) {
    return llvm::all_of_zip(small, big,
                            [&](const Pattern *s, const Pattern *b) { return embeds(s, b); });
  };
  return all(earlier.params, key.params) && !all(key.params, earlier.params);
}

bool sameShape(const PatternKey &a, const PatternKey &b) {
  return a.owner == b.owner && llvm::all_of_zip(a.params, b.params, oneShape);
}

} // namespace idr::specialize
