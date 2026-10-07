// idr-accumulate: a self call whose result a tail position adds becomes a
// tail call that carries the sum, as idr.tail accumulates.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRACCUMULATE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.tail;

namespace {

struct Accumulate : idr::impl::IdrAccumulateBase<Accumulate> {
  void runOnOperation() override {
    idr::tail::Accumulated accumulated = idr::tail::accumulate(getOperation());
    numFunctions += accumulated.functions;
    numTails += accumulated.tails;
  }
};

} // namespace
