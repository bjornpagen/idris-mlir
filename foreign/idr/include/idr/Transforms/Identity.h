// idr-identity: every call of a function that gives back one of its
// arguments, made that argument.
#ifndef IDR_TRANSFORMS_IDENTITY_H
#define IDR_TRANSFORMS_IDENTITY_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRIDENTITY
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_IDENTITY_H
