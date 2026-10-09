// idr-meter: lowered code counts the ticks of compile-time evaluation's
// meter, as idr.lower's meterModule does it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRMETER
#include "idr/Passes.h.inc"
} // namespace idr

import idr.lower;

namespace {

struct Meter : idr::impl::IdrMeterBase<Meter> {
  using IdrMeterBase::IdrMeterBase;

  void runOnOperation() override { idr::lower::meterModule(getOperation()); }
};

} // namespace
