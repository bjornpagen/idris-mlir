// idr-entry: keeps the root alive through generic passes (LOW-ENTRY-1).

#include "idr/Idr.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRENTRY
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// The root is referenced only from the module's idr.entry attribute, which
// symbol-dce and the inliner do not count as a use. Making it public until
// idr-lower creates the C entry point keeps it alive.
struct Entry : idr::impl::IdrEntryBase<Entry> {
  void runOnOperation() override {
    auto entry = getOperation()->getAttrOfType<FlatSymbolRefAttr>("idr.entry");
    auto root = entry ? getOperation().lookupSymbol<func::FuncOp>(entry.getAttr())
                      : func::FuncOp();
    if (!root) {
      getOperation().emitError("internal error: idr.entry does not name a function");
      return signalPassFailure();
    }
    root.setPublic();
  }
};

} // namespace
