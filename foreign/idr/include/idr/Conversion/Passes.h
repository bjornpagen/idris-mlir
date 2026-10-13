// The lowering's passes: idr-lower, idr-entry and idr-tail-calls, which
// take a program out of the idr dialect.
#ifndef IDR_CONVERSION_PASSES_H
#define IDR_CONVERSION_PASSES_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRLOWER
#define GEN_PASS_DECL_IDRENTRY
#define GEN_PASS_DECL_IDRTAILCALLS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_CONVERSION_PASSES_H
