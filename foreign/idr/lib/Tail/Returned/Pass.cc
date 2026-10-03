// idr-returned-arguments: a result that a function always returns as one
// of its arguments is dropped, as idr.tail finds them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRRETURNEDARGUMENTS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.tail;

namespace {

struct ReturnedArgumentsPass : idr::impl::IdrReturnedArgumentsBase<ReturnedArgumentsPass> {
  using IdrReturnedArgumentsBase::IdrReturnedArgumentsBase;

  void runOnOperation() override { numDropped += idr::tail::dropReturnedArguments(getOperation()); }
};

} // namespace
