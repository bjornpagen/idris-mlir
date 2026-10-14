// idr-deduplicate: one of each group of private idr.funcs whose type,
// facts and body are the same stays, and every use of the others names it.
#ifndef IDR_TRANSFORMS_DEDUPLICATE_H
#define IDR_TRANSFORMS_DEDUPLICATE_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_DEDUPLICATE_H
