// idr-isolate: every idr.lambda and every idr.delay but an evaluated one,
// outlined into a function of its own.
#ifndef IDR_TRANSFORMS_ISOLATE_H
#define IDR_TRANSFORMS_ISOLATE_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRISOLATE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_ISOLATE_H
