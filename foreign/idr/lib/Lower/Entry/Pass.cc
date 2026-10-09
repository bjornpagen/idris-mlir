// idr-entry: the lowered root becomes the program's entry, @__idr_main and
// @main, as idr.lower's makeEntry does it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRENTRY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.lower;

namespace {

struct Entry : idr::impl::IdrEntryBase<Entry> {
  using IdrEntryBase::IdrEntryBase;

  void runOnOperation() override {
    if (mlir::failed(idr::lower::makeEntry(getOperation())))
      signalPassFailure();
  }
};

} // namespace
