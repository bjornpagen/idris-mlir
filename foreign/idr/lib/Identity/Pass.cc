// idr-identity: every call of a function that gives back one of its
// arguments becomes that argument, as idr.identity finds them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRIDENTITY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.identity;

namespace {

struct Identity : idr::impl::IdrIdentityBase<Identity> {
  void runOnOperation() override {
    idr::identity::Elided elided = idr::identity::elide(getOperation());
    numFunctions += elided.functions;
    numCalls += elided.calls;
    if (elided.calls == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace
