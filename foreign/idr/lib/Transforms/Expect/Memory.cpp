// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// aligned-access, reads-nothing and writes-nothing: what a lowered
// function does to memory, stated by the effects and the alignments its
// ops declare. LLVM takes an access without an alignment at its type's
// ABI alignment, which a cell's layout does not promise; a value a
// function has in its registers (an array's size) is one no op of it
// loads; and a cell a function only reads is one no op of it writes.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;

namespace idr::expect {

// Anywhere or in @f, every LLVM load and store states its alignment.
LogicalResult alignedAccess(const Request<Roots> &request) {
  bool held = true;
  auto check = [&](Operation *op, std::optional<uint64_t> alignment) {
    if (alignment && *alignment != 0)
      return;
    fail(op->getLoc(), request.property) << op->getName() << " in " << where(op)
                                         << " states no alignment";
    held = false;
  };
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](Operation *op) {
      if (auto load = dyn_cast<LLVM::LoadOp>(op))
        check(op, load.getAlignment());
      else if (auto store = dyn_cast<LLVM::StoreOp>(op))
        check(op, store.getAlignment());
    });
  return success(held);
}

namespace {

// No op of any copy of the functions `function` names but a call has an
// effect of kind `Effect` on memory outside its own frame.
template <typename Effect>
LogicalResult touchesNothing(const Request<Functions> &request, StringRef doing) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](MemoryEffectOpInterface effects) {
      if (isa<CallOpInterface>(effects.getOperation()))
        return;
      SmallVector<MemoryEffects::EffectInstance> all;
      effects.getEffects(all);
      if (llvm::none_of(all, [](const MemoryEffects::EffectInstance &effect) {
            return isa<Effect>(effect.getEffect()) &&
                   !isa<SideEffects::AutomaticAllocationScopeResource>(effect.getResource());
          }))
        return;
      fail(effects->getLoc(), request.property) << effects->getName() << " " << doing
                                                << " memory in " << where(effects);
      held = false;
    });
  return success(held);
}

} // namespace

LogicalResult readsNothing(const Request<Functions> &request) {
  return touchesNothing<MemoryEffects::Read>(request, "reads");
}

LogicalResult writesNothing(const Request<Functions> &request) {
  return touchesNothing<MemoryEffects::Write>(request, "writes");
}

} // namespace idr::expect
