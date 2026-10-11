// Whether a type may hold a world or a closure, remembered while a pass
// that does not change a data declaration is running. mayHoldWorld and
// mayHoldClosure answer from the innermost memo open on the context.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The memos open on a context are a chain its idr dialect holds. A memo
// opens and closes outside every nested pipeline, so the chain changes in
// order, on one thread, and never while another thread reads it. An
// exchange that finds another head than the one this thread left is a memo
// opened against that contract, and it dies here rather than racing.
std::atomic<HoldMemo *> &chain(MLIRContext *context) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already.
  auto *idr = context->getLoadedDialect<IdrDialect>();
  if (!idr)
    llvm::reportFatalInternalError("HoldMemo opened on a context without the idr dialect");
  return idr->holdMemos();
}

} // namespace

HoldMemo::HoldMemo(MLIRContext *context)
    : context(context), outer(chain(context).load(std::memory_order_relaxed)) {
  HoldMemo *expected = outer;
  if (!chain(context).compare_exchange_strong(expected, this, std::memory_order_release))
    llvm::reportFatalInternalError("HoldMemo opened while another thread opened or closed one");
}

HoldMemo::~HoldMemo() {
  HoldMemo *expected = this;
  if (!chain(context).compare_exchange_strong(expected, outer, std::memory_order_release))
    llvm::reportFatalInternalError("HoldMemo closed out of order");
}

HoldMemo *HoldMemo::of(MLIRContext *context) {
  auto *idr = context->getLoadedDialect<IdrDialect>();
  return idr ? idr->holdMemos().load(std::memory_order_acquire) : nullptr;
}
