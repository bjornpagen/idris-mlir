// idr-stack: the cells of boxes that never leave their frame, built on the
// stack.
#ifndef IDR_TRANSFORMS_STACK_H
#define IDR_TRANSFORMS_STACK_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRSTACK
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_STACK_H
