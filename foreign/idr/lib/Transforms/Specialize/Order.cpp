// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The run's arena of patterns and keys, the order keys of one owner are
// compared by, and lifting.
//
// The order ends specialization whatever else a program does: a key is
// refused when it grows a key its requester was given before, or one on
// its request chain, and a key that differs from earlier ones of its shape
// only in scalars is lifted to what it shares with all of them at once.
// The embedding is homeomorphic: a pattern embeds in another when it is
// the other with parts taken away, and what a pattern embeds in depends on
// its shape alone, so over finitely many tags and kinds it is a
// well-quasi-order, and every sequence of keys of one owner none of which
// grows an earlier one is finite.
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
// The arena
//===----------------------------------------------------------------------===//

namespace {

// The kinds of thing the arena interns, each in its own buckets.
enum class Interned : unsigned { Hole, Con, Const, PatternKey, RaiseKey, SignatureKey };

Interned kindOf(const Pattern::Node &node) {
  return idr::match(
      node, [](Hole) { return Interned::Hole; }, [](const Con &) { return Interned::Con; },
      [](const Const &) { return Interned::Const; });
}

llvm::hash_code hashOf(const Pattern::Node &node) {
  return idr::match(
      node, [](Hole) { return llvm::hash_value(0); },
      [](const Con &con) {
        return llvm::hash_combine(static_cast<unsigned>(con.tag),
                                  llvm::hash_combine_range(con.fields.begin(), con.fields.end()));
      },
      [](const Const &constant) { return llvm::hash_value(constant.value.getAsOpaquePointer()); });
}

// Whether two nodes are one: of one kind, a constructor of one tag over the
// same fields, a constant of the same attribute.
bool sameNode(const Pattern::Node &a, const Pattern::Node &b) {
  return idr::match(
      a,
      [&](Hole) {
        return idr::match(b, [](Hole) { return true; }, [](const auto &) { return false; });
      },
      [&](const Con &con) {
        return idr::match(
            b,
            [&](const Con &other) { return con.tag == other.tag && llvm::equal(con.fields, other.fields); },
            [](const auto &) { return false; });
      },
      [&](const Const &constant) {
        return idr::match(
            b, [&](const Const &other) { return constant.value == other.value; },
            [](const auto &) { return false; });
      });
}

} // namespace

llvm::ArrayRef<const Pattern *> Arena::copy(llvm::ArrayRef<const Pattern *> list) {
  auto *at = storage.Allocate<const Pattern *>(list.size());
  llvm::copy(list, at);
  return {at, list.size()};
}

const Pattern *Arena::intern(Pattern::Node node, unsigned holes) {
  std::lock_guard lock(mutex);
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(kindOf(node)), hashOf(node)}];
  for (const void *met : bucket)
    if (sameNode(static_cast<const Pattern *>(met)->get(), node))
      return static_cast<const Pattern *>(met);
  // A constructor's fields are the caller's until copied into the arena.
  Pattern::Node owned = idr::match(
      node, [](Hole hole) -> Pattern::Node { return hole; },
      [&](const Con &con) -> Pattern::Node { return Con{con.tag, copy(con.fields)}; },
      [](const Const &constant) -> Pattern::Node { return constant; });
  auto *made = new (storage.Allocate<Pattern>()) Pattern(owned);
  made->holeCount = holes;
  bucket.push_back(made);
  return made;
}

const Pattern *Arena::hole() { return intern(Hole{}, 1); }

const Pattern *Arena::con(Tag tag, llvm::ArrayRef<const Pattern *> fields) {
  unsigned holes = 0;
  for (const Pattern *field : fields)
    holes += field->holes();
  return intern(Con{tag, fields}, holes);
}

const Pattern *Arena::constant(Attribute value) { return intern(Const{value}, 0); }

const PatternKey *Arena::key(FunctionId owner, llvm::ArrayRef<const Pattern *> params) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash =
      llvm::hash_combine(owner.index(), llvm::hash_combine_range(params.begin(), params.end()));
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::PatternKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const PatternKey *>(met);
    if (key->owner == owner && llvm::equal(key->params, params))
      return key;
  }
  auto *made = new (storage.Allocate<PatternKey>()) PatternKey{owner, copy(params)};
  bucket.push_back(made);
  return made;
}

const RaiseKey *Arena::key(FunctionId callee, FormId form) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash = llvm::hash_combine(callee.index(), static_cast<unsigned>(form));
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::RaiseKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const RaiseKey *>(met);
    if (key->callee == callee && key->form == form)
      return key;
  }
  auto *made = new (storage.Allocate<RaiseKey>()) RaiseKey{callee, form};
  bucket.push_back(made);
  return made;
}

const SignatureKey *Arena::key(FunctionId owner, FunctionType signature,
                               IndexArgsAttr indices) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash = llvm::hash_combine(owner.index(), signature, indices);
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::SignatureKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const SignatureKey *>(met);
    if (key->owner == owner && key->signature == signature && key->indices == indices)
      return key;
  }
  auto *made = new (storage.Allocate<SignatureKey>()) SignatureKey{owner, signature, indices};
  bucket.push_back(made);
  return made;
}

unsigned PatternKey::holes() const {
  unsigned total = 0;
  for (const Pattern *param : params)
    total += param->holes();
  return total;
}

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

//===----------------------------------------------------------------------===//
// Lifting
//===----------------------------------------------------------------------===//

namespace {

// What the lift knows at one position: the key's part there and every
// peer's, all of one shape.
struct Position {
  const Pattern *part;
  llvm::SmallVector<const Pattern *, 2> peers;
};

// One step of the lift's walk: a position to visit, or a constructor whose
// fields, the last `arity` results, are ready to be built over.
struct Visit {
  Position at;
};
struct Build {
  Tag tag;
  unsigned arity;
};
using Step = std::variant<Visit, Build>;

// Whether every peer is the constant constructor of one cell and of `tag`.
bool oneCellOf(Tag tag, llvm::ArrayRef<const Pattern *> peers) {
  return llvm::all_of(peers, [&](const Pattern *peer) {
    return idr::match(
        peer->get(),
        [&](const Const &theirs) {
          auto con = dyn_cast<ConAttr>(theirs.value);
          return con && con.getTag() == tag && con.getRunLength() == 1;
        },
        [](const auto &) { return false; });
  });
}

// The field `i` of a peer that is a constant constructor of one cell, or
// of a peer that is a constructor.
const Pattern *fieldOf(Arena &arena, const Pattern *peer, unsigned i) {
  return idr::match(
      peer->get(), [&](const Con &con) { return con.fields[i]; },
      [&](const Const &constant) {
        return arena.constant(llvm::to_vector(cast<ConAttr>(constant.value).getFields())[i]);
      },
      [&](Hole) { return peer; });
}

} // namespace

// Each position in pre-order: a hole kept is the hole it was, counted in
// pre-order; a scalar where any peer differs is lifted out into a hole; a
// constructor is its fields'; a constant constructor of one cell that
// differs is taken apart into its constructor over its fields, and a run
// of more than one cell is one constant, lifted whole, so a key never
// unrolls a run. The walk keeps its own stack, the built parts on another.
const PatternKey *liftOver(Arena &arena, const PatternKey &key,
                           llvm::ArrayRef<const PatternKey *> peers,
                           llvm::SmallVectorImpl<Source> &sources) {
  unsigned next = 0;
  llvm::SmallVector<const Pattern *> built;
  llvm::SmallVector<Step> work;
  for (auto [i, param] : llvm::enumerate(llvm::reverse(key.params))) {
    unsigned position = key.params.size() - 1 - i;
    Position at{param, {}};
    for (const PatternKey *peer : peers)
      at.peers.push_back(peer->params[position]);
    work.push_back(Visit{std::move(at)});
  }
  while (!work.empty()) {
    Step step = work.pop_back_val();
    idr::match(
        step,
        [&](const Build &make) {
          llvm::SmallVector<const Pattern *> fields(built.end() - make.arity, built.end());
          built.resize(built.size() - make.arity);
          built.push_back(arena.con(make.tag, fields));
        },
        [&](const Visit &visit) {
          const Position &at = visit.at;
          // A constructor's fields, pushed so that the first is visited
          // first and the constructor built once all are.
          auto expand = [&](Tag tag, unsigned arity, auto &&fieldAt) {
            work.push_back(Build{tag, arity});
            for (unsigned k = arity; k-- > 0;) {
              Position field{fieldAt(at.part, k), {}};
              for (const Pattern *peer : at.peers)
                field.peers.push_back(fieldAt(peer, k));
              work.push_back(Visit{std::move(field)});
            }
          };
          idr::match(
              at.part->get(),
              [&](Hole) {
                sources.push_back(Kept{next++});
                built.push_back(arena.hole());
              },
              [&](const Con &con) {
                expand(con.tag, con.fields.size(),
                       [&](const Pattern *p, unsigned k) { return fieldOf(arena, p, k); });
              },
              [&](const Const &constant) {
                if (llvm::all_of(at.peers, [&](const Pattern *peer) { return peer == at.part; })) {
                  built.push_back(at.part);
                  return;
                }
                auto con = dyn_cast<ConAttr>(constant.value);
                if (!con || con.getRunLength() > 1 || !oneCellOf(con.getTag(), at.peers)) {
                  sources.push_back(Lifted{constant.value});
                  built.push_back(arena.hole());
                  return;
                }
                expand(con.getTag(), llvm::size(con.getFields()),
                       [&](const Pattern *p, unsigned k) { return fieldOf(arena, p, k); });
              });
        });
  }
  return arena.key(key.owner, built);
}

} // namespace idr::specialize
