// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reuse rewrite at the sites Reuses decided: idr.take where the box
// dies, idr.reuse for each constructor that gets its cell.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"

#include <variant>

using namespace mlir;

namespace idr::ownership {

// The sites are taken in the order they were decided, each on the function
// the ones before it left: a site may take apart a field an earlier take
// gave, and may name, as its box or its point, a constructor an earlier
// site rebuilt as a reuse, which stands where the constructor stood. What
// was rebuilt is looked up by the old value and op, which are gone and so
// are never asked anything.
namespace {

// The rewrite at the sites in order, with what the earlier ones rebuilt.
class Rewrite {
public:
  explicit Rewrite(RewriterBase &rewriter) : rewriter(rewriter) {}

  void at(const Reuses::Site &site) {
    Value box = std::visit([&](const auto &held) { return boxOf(held); }, site.box);
    Point point = std::visit([&](auto where) { return pointOf(where); }, site.point);
    TakeOp take = takeAt(rewriter, box, site.data, site.tag, blockOf(point), firstAt(point),
                         site.bound);
    takes.push_back(take);
    Value cell = take.getToken();
    for (ConOp con : site.cons) {
      rewriter.setInsertionPoint(con);
      auto reuse = ReuseOp::create(rewriter, con.getLoc(), con.getResult().getType(), cell,
                                   con.getTag(), con.getFields(), con.getHoles());
      rebuiltValues[con.getResult()] = reuse.getResult();
      rebuiltOps[con] = reuse;
      rewriter.replaceOp(con, reuse);
    }
  }

private:
  // `old` as it stands now: what rebuilt it, or itself.
  template <typename T> static T now(const DenseMap<T, T> &rebuilt, T old) {
    auto it = rebuilt.find(old);
    return it == rebuilt.end() ? old : it->second;
  }

  // The box a site takes apart, as it stands now: a value of the function,
  // or a field an earlier site's take gave.
  Value boxOf(Value value) const { return now(rebuiltValues, value); }
  Value boxOf(Reuses::TakenField field) const {
    TakeOp take = takes[field.site];
    return now(rebuiltValues, Value(take.getFields()[field.field]));
  }

  // Where a site's take goes, as it stands now.
  Point pointOf(BlockStart start) const { return start; }
  Point pointOf(After after) const { return After{now(rebuiltOps, after.op)}; }

  RewriterBase &rewriter;
  SmallVector<TakeOp> takes;
  DenseMap<Value, Value> rebuiltValues;
  DenseMap<Operation *, Operation *> rebuiltOps;
};

} // namespace

void reuseAt(RewriterBase &rewriter, ArrayRef<Reuses::Site> sites) {
  Rewrite rewrite(rewriter);
  for (const Reuses::Site &site : sites)
    rewrite.at(site);
}

} // namespace idr::ownership
