// Calling a clone: the one way a call becomes a call of a clone, for the
// module pass that made the clone and for the function pass that finds it
// in the table. It reads the clone's record, never the clone.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Effects.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

std::optional<idr::CallOp> redirect(RewriterBase &rewriter, idr::CallOp call, const Clone &clone,
                                    ArrayRef<Value> operands, std::optional<Consumer> consumer) {
  // Raising replaces what the consumer returns; specialization the call.
  Operation *replaced = consumer ? consumer->apply.getOperation() : call.getOperation();
  // A clone whose parameters or results have changed since its key was
  // made takes no call of that key.
  if (operands.size() != clone.type.getNumInputs() ||
      !llvm::all_of(llvm::zip(operands, clone.type.getInputs()),
                    [](auto pair) { return std::get<0>(pair).getType() == std::get<1>(pair); }) ||
      replaced->getResultTypes() != TypeRange(clone.type.getResults()))
    return std::nullopt;

  // The call's effects hold its callee's; they stay true of the clone's
  // call only when they hold the clone's too.
  idr::EffectAttr effects = call.getEffectsAttr();
  if (effects && !bitEnumContainsAll(effects.getValue(), clone.effects.value_or(anyEffect)))
    effects = {};
  rewriter.setInsertionPoint(replaced);
  auto fresh = idr::CallOp::create(rewriter, call.getLoc(), clone.type.getResults(), clone.name,
                                   operands, /*arg_attrs=*/ArrayAttr(),
                                   /*res_attrs=*/ArrayAttr(), effects);
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(replaced, fresh.getResults());
  if (consumer) {
    // The steps from the call's result to the apply, each the one use of
    // the one before: erased from the apply back.
    if (consumer->use)
      rewriter.eraseOp(consumer->use);
    if (consumer->field)
      rewriter.eraseOp(consumer->field);
    if (consumer->exit) {
      rewriter.eraseOp(consumer->exit);
      rewriter.eraseOp(consumer->enter);
    }
    rewriter.eraseOp(call);
  }
  eraseUnused(rewriter, old);
  return fresh;
}

} // namespace idr::specialize
