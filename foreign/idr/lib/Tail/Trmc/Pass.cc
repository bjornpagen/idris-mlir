// idr-trmc: a self call whose result is a field of the boxed constructor a
// tail position returns becomes a tail call that writes the field, as
// idr.tail passes destinations.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRTRMC
#include "idr/Passes.h.inc"
} // namespace idr

import idr.tail;

namespace {

struct Trmc : idr::impl::IdrTrmcBase<Trmc> {
  void runOnOperation() override {
    idr::tail::Destinations passed = idr::tail::passDestinations(getOperation());
    numFunctions += passed.functions;
    numTails += passed.tails;
  }
};

} // namespace
