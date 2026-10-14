// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reuse rewrite at the sites Reuses decided: idr.take where the box
// dies, idr.reuse for each constructor that gets its cell.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::ownership {

// The sites are taken in the order they were decided, each on the function
// the ones before it left: a site may take apart a field an earlier take
// gave, and may name, as its box or its point, a constructor an earlier
// site rebuilt as a reuse, which stands where the constructor stood. What
// was rebuilt is looked up by the old value and op, which are gone and so
// are never asked anything.
void reuseAt(RewriterBase &rewriter, ArrayRef<Reuses::Site> sites, Counted &counted) {
  SmallVector<TakeOp> takes;
  DenseMap<Value, Value> rebuiltValues;
  DenseMap<Operation *, Operation *> rebuiltOps;
  for (const Reuses::Site &site : sites) {
    Value box = site.box ? site.box : takes[site.from].getFields()[site.field];
    if (Value reuse = rebuiltValues.lookup(box))
      box = reuse;
    Operation *after = site.after;
    if (Operation *reuse = rebuiltOps.lookup(after))
      after = reuse;
    Block::iterator at = after ? std::next(after->getIterator()) : site.block->begin();
    TakeOp take = takeAt(rewriter, box, site.ctor, *site.block, at, site.fields, counted);
    takes.push_back(take);
    Value cell = take.getToken();
    for (ConOp con : site.cons) {
      rewriter.setInsertionPoint(con);
      auto reuse = ReuseOp::create(rewriter, con.getLoc(), con.getType(), cell, con.getCtor(),
                                   con.getFields());
      reuse->setDiscardableAttrs(con->getDiscardableAttrDictionary());
      rebuiltValues[con.getResult()] = reuse.getResult();
      rebuiltOps[con] = reuse;
      rewriter.replaceOp(con, reuse.getResult());
    }
  }
}

} // namespace idr::ownership
