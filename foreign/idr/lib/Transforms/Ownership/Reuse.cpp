// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reuse rewrite at the sites Reuses decided: an idr.take where the box
// dies, and an idr.cell.recycle of its token for each idr.cell.new that
// gets its cell.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::ownership {

namespace {

// idr-rc reuses the cell of a box that dies for new cells; the unit is the
// first cell that would take it. Skipped, every cell stays new and the box
// dies as counting places it.
struct ReuseAction : support::TaggedAction<ReuseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-reuse-site";
};

} // namespace

// The sites are taken in the order they were decided, each on the function
// the ones before it left: a site may take apart a field an earlier take
// gave, and is skipped with it. A recycle replaces one source of a cell by
// another, so the idr.cell.init that names the cell, the point a later
// site names and the box it takes apart are never replaced.
void reuseAt(RewriterBase &rewriter, Positions &positions, ArrayRef<Reuses::Site> sites) {
  SmallVector<TakeOp> takes;
  for (const Reuses::Site &site : sites) {
    // The box: a value of the function, or a field an earlier site's take
    // gave, none when that site was skipped.
    Value box = std::visit(llvm::makeVisitor([](Value value) { return value; },
                                             [&](Reuses::TakenField field) -> Value {
                                               TakeOp taken = takes[field.site];
                                               return taken ? taken.getFields()[field.field]
                                                            : Value();
                                             }),
                           site.box);
    TakeOp take;
    auto rewrite = [&] {
      take = takeAt(rewriter, positions, box, site.tag, blockOf(site.point), firstAt(site.point),
                    site.bound);
      // Each recycle where its cell was made, not where the take left the
      // rewriter.
      for (CellNewOp cell : site.cells) {
        rewriter.setInsertionPoint(cell);
        positions.forget(cell);
        rewriter.replaceOpWithNewOp<CellRecycleOp>(cell, cell.getCell().getType(),
                                                   take.getToken());
      }
    };
    if (box && site.cells.empty())
      rewrite();
    else if (box)
      support::perform<ReuseAction>(site.cells.front(), rewrite);
    takes.push_back(take);
  }
}

} // namespace idr::ownership
