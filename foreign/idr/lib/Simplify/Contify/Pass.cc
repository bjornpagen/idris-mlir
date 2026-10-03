// idr-contify: the continuations of a function inlined into it, as
// idr.simplify contifies them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;

namespace {

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnOperation() override { numContified += idr::simplify::contify(getOperation()); }
};

} // namespace
