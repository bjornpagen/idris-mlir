// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reuse rewrite at the sites Reuses decided: an idr.take where the box
// dies, and an idr.cell.recycle of its token for each idr.cell.new that
// gets its cell.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::ownership {

// The sites are taken in the order they were decided, each on the function
// the ones before it left: a site may take apart a field an earlier take
// gave. A recycle replaces one source of a cell by another, so the
// idr.cell.init that names the cell, the point a later site names and the
// box it takes apart are never replaced.
void reuseAt(RewriterBase &rewriter, ArrayRef<Reuses::Site> sites) {
  SmallVector<TakeOp> takes;
  for (const Reuses::Site &site : sites) {
    // The box: a value of the function, or a field an earlier site's take
    // gave.
    Value box = std::visit(llvm::makeVisitor([](Value value) { return value; },
                                             [&](Reuses::TakenField field) -> Value {
                                               return takes[field.site].getFields()[field.field];
                                             }),
                           site.box);
    TakeOp take = takeAt(rewriter, box, site.tag, blockOf(site.point), firstAt(site.point),
                         site.bound);
    takes.push_back(take);
    // Each recycle where its cell was made, not where the take left the
    // rewriter.
    for (CellNewOp cell : site.cells) {
      rewriter.setInsertionPoint(cell);
      rewriter.replaceOpWithNewOp<CellRecycleOp>(cell, cell.getCell().getType(), take.getToken());
    }
  }
}

} // namespace idr::ownership
