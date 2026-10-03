// idr-loop-breakers: every cycle of references among the functions that
// may be inlined keeps a loop breaker, as idr.simplify marks them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRLOOPBREAKERS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;

namespace {

struct LoopBreakers : idr::impl::IdrLoopBreakersBase<LoopBreakers> {
  void runOnOperation() override {
    unsigned marked = idr::simplify::markLoopBreakers(getOperation());
    numBreakers += marked;
    if (!marked)
      markAllAnalysesPreserved();
  }
};

} // namespace
