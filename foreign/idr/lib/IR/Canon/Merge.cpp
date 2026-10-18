// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Identical regions of a match merge. Upstream's region patterns merge
// results, not regions, and a match region is one block, which the block
// merging of region simplification never sees two of.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// Whether two regions do the same thing without reading their arguments.
bool sameBody(Region &a, Region &b) {
  Block &x = a.front(), &y = b.front();
  auto unused = [](Block &block) {
    return llvm::all_of(block.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
  };
  // Length is part of the comparison below. The list's size walks every
  // operation, and the comparison walks them again.
  if (!unused(x) || !unused(y))
    return false;
  DenseMap<Value, Value> same;
  return llvm::all_of_zip(x, y, [&](Operation &l, Operation &r) {
    return OperationEquivalence::isEquivalentTo(
        &l, &r,
        [&](Value lv, Value rv) { return success(lv == rv || same.lookup(lv) == rv); },
        [&](Value lv, Value rv) { same[lv] = rv; }, OperationEquivalence::IgnoreLocations);
  });
}

// The operations a case holds, hashed as the comparison below compares
// them but for their regions, so two cases that differ there are not
// compared body to body. Equal shapes still are: the hash can collide.
llvm::hash_code shape(Block &block) {
  return llvm::hash_combine(
      block.getNumArguments(), llvm::hash_combine_range(llvm::map_range(block, [](Operation &op) {
        return OperationEquivalence::computeHash(&op, OperationEquivalence::ignoreHashValue,
                                                 OperationEquivalence::ignoreHashValue,
                                                 OperationEquivalence::IgnoreLocations);
      })));
}

// The first case of `op` whose body another case repeats: compared only
// with the cases of its shape, since a match with many cases would compare
// each body with every other, and cases whose operations differ cannot be
// that pair.
std::optional<unsigned> firstRepeated(MatchOpInterface op) {
  llvm::DenseMap<llvm::hash_code, SmallVector<unsigned, 2>> buckets;
  for (unsigned i = 0, count = op.getNumCases(); i < count; ++i)
    buckets[shape(op.getCaseRegion(i).front())].push_back(i);
  std::optional<unsigned> first;
  for (auto &bucket : buckets) {
    ArrayRef<unsigned> ids = bucket.second;
    for (unsigned a = 0; a < ids.size() && (!first || ids[a] < *first); ++a)
      if (llvm::any_of(ids.drop_front(a + 1), [&](unsigned b) {
            return sameBody(op.getCaseRegion(ids[a]), op.getCaseRegion(b));
          })) {
        first = ids[a];
        break;
      }
  }
  return first;
}

// A case that does what the default does is left to the default, and
// without a default that runs, cases that do the same become it: the
// first of them, whose arguments are unused, binds the scrutinee instead,
// as a default does.
struct MergeIdenticalRegions : RewritePattern {
  MergeIdenticalRegions(StringRef root, MLIRContext *context)
      : RewritePattern(root, PatternBenefit(1), context) {
    setDebugName("idr-merge-identical-regions");
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    auto op = cast<MatchOpInterface>(root);
    Region *fallback = &op.getDefaultRegion();
    if (fallback->empty()) {
      std::optional<unsigned> first = firstRepeated(op);
      if (!first)
        return failure();
      // The case leaves the cases, so the match changes: its region binds
      // the scrutinee from here on, its own arguments unused.
      fallback = &op.getCaseRegion(*first);
      Block &block = fallback->front();
      rewriter.modifyOpInPlace(root, [&] {
        block.eraseArguments(0, block.getNumArguments());
        block.addArgument(op.getScrutinee().getType(), root->getLoc());
      });
    }
    SmallVector<unsigned> kept;
    for (unsigned i = 0, count = op.getNumCases(); i < count; ++i)
      if (&op.getCaseRegion(i) != fallback && !sameBody(op.getCaseRegion(i), *fallback))
        kept.push_back(i);
    if (kept.size() == op.getNumCases())
      return failure();
    rewriter.replaceOp(root, op.rebuild(rewriter, root->getResultTypes(), kept, fallback));
    return success();
  }
};

} // namespace

namespace idr::canon {

void addMerge(RewritePatternSet &results, MLIRContext *context, StringRef root) {
  results.add<MergeIdenticalRegions>(root, context);
}

} // namespace idr::canon
