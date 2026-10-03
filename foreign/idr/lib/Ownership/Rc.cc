// idr-rc: every reference made explicit, as idr.ownership's pipeline does
// it (Rc.cppm). The base, its options and statistics are TableGen's.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRRC
#include "idr/Passes.h.inc"
} // namespace idr

import idr.ownership;

namespace {

struct Rc : idr::impl::IdrRcBase<Rc> {
  using IdrRcBase::IdrRcBase;

  void runOnOperation() override {
    namespace own = idr::ownership;
    own::RcCounts counts;
    mlir::LogicalResult ran = own::rc(getOperation(), {reuse, borrow, sink}, counts);
    numTakes += counts.takes;
    numReuses += counts.reuses;
    numBorrowed += counts.borrowed;
    numDups += counts.dups;
    numDrops += counts.drops;
    numExclusive += counts.exclusive;
    if (mlir::failed(ran))
      signalPassFailure();
  }
};

} // namespace
