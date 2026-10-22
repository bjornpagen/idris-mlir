// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lifting: a key that differs from earlier keys of its shape only in
// scalars is lifted to what it shares with all of them at once, so a
// recursion that walks a scalar keeps one copy. A pattern is as deep as the
// constructors a call's arguments nest, so the lift's walk keeps its own
// stack.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

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
  size_t arity;
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
        [](const OneOf<Hole, Con> auto &) { return false; });
  });
}

// The field `i` of a peer that is a constant constructor of one cell, or
// of a peer that is a constructor.
const Pattern *fieldOf(Arena &arena, const Pattern *peer, size_t i) {
  return idr::match(
      peer->get(), [&](const Con &con) { return con.fields[i]; },
      [&](const Const &constant) {
        return arena.constant(cast<ConAttr>(constant.value).getFields().getValue()[i]);
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
    size_t position = key.params.size() - 1 - i;
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
          auto expand = [&](Tag tag, size_t arity, auto &&fieldAt) {
            work.push_back(Build{tag, arity});
            for (size_t k = arity; k-- > 0;) {
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
                       [&](const Pattern *p, size_t k) { return fieldOf(arena, p, k); });
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
                expand(con.getTag(), con.getFields().size(),
                       [&](const Pattern *p, size_t k) { return fieldOf(arena, p, k); });
              });
        });
  }
  return arena.key(key.owner, built);
}

} // namespace idr::specialize
