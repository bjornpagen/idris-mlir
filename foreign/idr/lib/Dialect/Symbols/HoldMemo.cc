// Whether a type may hold a world or a closure, remembered while a pass
// that does not change a data declaration is running. mayHoldWorld and
// mayHoldClosure answer from the innermost memo this thread has open.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The memos this thread has open, innermost first. A memo opened on the
// calling thread before a nested pipeline runs is not on a worker's chain,
// and a memo a worker opens is not on this one.
HoldMemo *&head() {
  static thread_local HoldMemo *top = nullptr;
  return top;
}

HoldMemo *&chain(MLIRContext *context) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already.
  if (!context->getLoadedDialect<IdrDialect>())
    llvm::reportFatalInternalError("HoldMemo opened on a context without the idr dialect");
  return head();
}

} // namespace

HoldMemo::HoldMemo(MLIRContext *context) : context(context), outer(chain(context)) {
  chain(context) = this;
}

HoldMemo::~HoldMemo() {
  HoldMemo *&top = chain(context);
  if (top != this)
    llvm::reportFatalInternalError("HoldMemo closed out of order");
  top = outer;
}

HoldMemo *HoldMemo::of(MLIRContext *context) {
  if (!context->getLoadedDialect<IdrDialect>())
    return nullptr;
  for (HoldMemo *memo = head(); memo; memo = memo->outer)
    if (memo->context == context)
      return memo;
  return nullptr;
}
