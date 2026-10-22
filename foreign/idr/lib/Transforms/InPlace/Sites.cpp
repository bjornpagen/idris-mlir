// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-place rule's rebuild sites of one body (Rule.h), and the rewrite of
// each into a take of the cell and a rebuild in it.
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Flow.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::inplace {

llvm::SmallVector<RebuildSite> rebuildSites(FuncOp fn, const BodyValues &values) {
  SmallVector<RebuildSite> sites;
  // The constructions already paired, outer cells first, by their results.
  BitSet<BodyValue> paired(values.size());
  fn->walk<WalkOrder::PreOrder>([&](DataMatchOp match) {
    // The argument each case binds the scrutinee refined to.
    SmallVector<BlockArgument> bound(match->getNumRegions(), BlockArgument());
    forwardedValues(match, [&](OpOperand &operand, Value input) {
      auto arg = dyn_cast<BlockArgument>(input);
      if (arg && operand.get() == match.getScrutinee() && arg.getOwner()->getParentOp() == match)
        bound[arg.getOwner()->getParent()->getRegionNumber()] = arg;
    });
    for (auto [index, region] : llvm::enumerate(match->getRegions())) {
      BlockArgument taken = bound[index];
      if (!taken)
        continue;
      Type type = taken.getType();
      DataType family = ownership::familyOf(type);
      std::optional<Tag> tag = ownership::refinedTag(type);
      std::optional<Asks> promised = ownership::promisedAsks(family);
      // A cell of an in-place family, bound at quantity 1: a parameter's,
      // or a field's a linear match binds.
      if (!tag || !ownership::isCell(type) || !promised || usesOf(type) != Uses::Once)
        continue;
      DataConOp found;
      region.walk<WalkOrder::PreOrder>([&](Operation *op) {
        // A region that may run again would rebuild the one cell twice.
        if (ownership::repeats(op))
          return WalkResult::skip();
        auto con = dyn_cast<DataConOp>(op);
        if (!con || paired.test(values.at(con.getResult())))
          return WalkResult::advance();
        Type built = con.getResult().getType();
        if (ownership::sameFamily(ownership::familyOf(built), family) &&
            ownership::refinedTag(built) == tag && ownership::isCell(built)) {
          found = con;
          return WalkResult::interrupt();
        }
        return WalkResult::advance();
      });
      if (!found)
        continue;
      BodyValue made = values.at(found.getResult());
      (void)paired.raise(made);
      sites.push_back({match, static_cast<unsigned>(index), found, taken, *promised,
                       SiteAt{values.at(taken).index(), made.index()}});
    }
  });
  return sites;
}

void rebuild(DataMatchOp match, unsigned caseIndex, unsigned taken, DataConOp construction) {
  Block &entry = match->getRegion(caseIndex).front();
  BlockArgument cell = entry.getArgument(taken);
  OpBuilder builder = OpBuilder::atBlockBegin(&entry);
  auto take = CountTakeOp::create(builder, match.getLoc(), cell);
  for (OpOperand &use : llvm::make_early_inc_range(cell.getUses()))
    if (auto field = dyn_cast<DataFieldOp>(use.getOwner())) {
      field.getResult().replaceAllUsesWith(
          take.getFields()[static_cast<unsigned>(field.getIndex())]);
      field.erase();
    }
  builder.setInsertionPoint(construction);
  auto rebuilt = TokenRebuildOp::create(builder, construction.getLoc(),
                                        construction.getResult().getType(), take.getToken(),
                                        construction.getFields());
  construction.getResult().replaceAllUsesWith(rebuilt.getResult());
  construction.erase();
}

} // namespace idr::inplace
