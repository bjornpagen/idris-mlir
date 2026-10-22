// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rule of a match's identical regions: a case that does what
// the running default does, reading nothing it binds, is left to the
// default; with no default, cases of an exhaustive match that do the same
// become its default. Two regions are compared body to body, after their
// operations' shapes are hashed, so only regions of one shape are.

#include "idr/IR/Control/Control.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins/Rules.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Hashing.h"

#include <algorithm>

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

// Whether a region reads none of its arguments.
bool readsNothingBound(Region &region) {
  return llvm::all_of(region.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
}

// One region's body, ready to be compared with every region it may stand
// for: the values it makes, its ops' results and its nested blocks'
// arguments, are numbered once (a value carries no number MLIR gives it),
// so a body compared with several others is numbered once, not once per
// comparison; the value of the other body each matches, as a comparison
// meets them, is a table by that number. Both are scratch counted in the
// pass's footprint, sized by the body. A value made outside the body
// matches itself alone. Upstream's own comparison of regions is not used,
// since its block arguments must agree in type where a case's need not.
class Body {
public:
  explicit Body(Region &region) : block(region.front()) {
    block.walk([&](Operation *op) {
      for (Value result : op->getResults())
        number.try_emplace(result, static_cast<unsigned>(number.size()));
      for (Region &nested : op->getRegions())
        for (Block &inner : nested)
          for (Value arg : inner.getArguments())
            number.try_emplace(arg, static_cast<unsigned>(number.size()));
    });
    partner.resize(number.size());
  }

  // Whether `other`, a region that reads none of its arguments, does what
  // this body does, which reads none of its own.
  bool sameAs(Region &other) {
    Block &y = other.front();
    if (block.getOperations().size() != y.getOperations().size())
      return false;
    std::fill(partner.begin(), partner.end(), Value());
    return llvm::all_of_zip(block, y, [&](Operation &l, Operation &r) {
      return OperationEquivalence::isEquivalentTo(
          &l, &r,
          [&](Value lv, Value rv) {
            auto it = number.find(lv);
            return success(lv == rv || (it != number.end() && partner[it->second] == rv));
          },
          [&](Value lv, Value rv) { partner[number.find(lv)->second] = rv; },
          OperationEquivalence::IgnoreLocations);
    });
  }

private:
  Block &block;
  footprint::DenseMap<Value, unsigned> number;
  footprint::Vector<Value> partner;
};

// The operations a region holds, hashed as Body compares them but for
// their regions, so only regions of one shape are compared body to body;
// equal shapes still are, since the hash can collide.
llvm::hash_code shape(Region &region) {
  return llvm::hash_combine_range(llvm::map_range(region.front(), [](Operation &op) {
    return OperationEquivalence::computeHash(&op, OperationEquivalence::ignoreHashValue,
                                             OperationEquivalence::ignoreHashValue,
                                             OperationEquivalence::IgnoreLocations);
  }));
}

// What the rule keeps of `op`: the region that is the default afterwards,
// by its number, the default's own 0, so a case that takes the default's
// place is written as the default is; then the index of each case kept.
// None where no case goes.
//
// A case that does what a running default does, reading nothing it binds,
// is left to the default. With no default, the first case some other case
// repeats becomes it, the others like it going too, where it reads nothing
// it binds, binds no index variable and assumes no equation, so its body
// means the same in the scope around the match.
std::optional<SmallVector<unsigned>> identicalRegions(MatchOpInterface op) {
  Region &given = op.getDefaultRegion();
  auto binders = dyn_cast<ErasedBinderOpInterface>(op.getOperation());
  auto movable = [&](Region &region) {
    return readsNothingBound(region) &&
           (!binders || (binders.getBoundSorts(region).empty() && !binders.getRefinement(region)));
  };
  Region *fallback = nullptr;
  if (!given.empty()) {
    if (readsNothingBound(given))
      fallback = &given;
  } else {
    llvm::DenseMap<llvm::hash_code, SmallVector<unsigned, 2>> buckets;
    for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
      if (movable(op.getCaseRegion(i)))
        buckets[shape(op.getCaseRegion(i))].push_back(i);
    std::optional<unsigned> first;
    for (auto &bucket : buckets) {
      ArrayRef<unsigned> ids = bucket.second;
      for (unsigned a = 0; a < ids.size() && (!first || ids[a] < *first); ++a) {
        Body body(op.getCaseRegion(ids[a]));
        if (llvm::any_of(ids.drop_front(a + 1),
                         [&](unsigned b) { return body.sameAs(op.getCaseRegion(b)); })) {
          first = ids[a];
          break;
        }
      }
    }
    if (first)
      fallback = &op.getCaseRegion(*first);
  }
  if (!fallback)
    return std::nullopt;
  SmallVector<unsigned> kept{fallback->getRegionNumber()};
  Body body(*fallback);
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i) {
    Region &region = op.getCaseRegion(i);
    if (&region != fallback && !(movable(region) && body.sameAs(region)))
      kept.push_back(i);
  }
  if (kept.size() == op.getNumCases() + 1)
    return std::nullopt;
  return kept;
}

} // namespace

// Identical regions merge into the default.
std::optional<Edit> egraph::IdenticalRegions::decide(MatchOpInterface op, const OperandFacts &) {
  std::optional<SmallVector<unsigned>> kept = identicalRegions(op);
  if (!kept)
    return std::nullopt;
  return Edit(Rewrite{std::move(*kept)});
}

void egraph::IdenticalRegions::rewrite(MatchOpInterface op, const Rewrite &chosen,
                                       RewriterBase &rewriter) {
  // Recomputed on the root as it now is, since what it compares is the
  // regions' bodies, which an earlier rewrite may have changed.
  std::optional<SmallVector<unsigned>> kept = identicalRegions(op);
  if (!kept || *kept != chosen.chosen)
    return;
  unsigned fallback = kept->front();
  Region *region = fallback == 0 ? &op.getDefaultRegion() : &op.getCaseRegion(fallback - 1);
  (void)op.keepCases(rewriter, ArrayRef<unsigned>(*kept).drop_front(), region);
}

} // namespace idr
