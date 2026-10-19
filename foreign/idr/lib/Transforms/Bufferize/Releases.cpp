// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Releases, and what may touch a released buffer after one.
//
// A release hands a buffer to a place One-Shot does not see: a cell's field
// (idr.con, the yield of idr.memo.run), a linear thread (idr.lin.enter), or a callee,
// which may keep it in either. The analysis sees the release read and write
// the buffer, so a later read of it makes the release copy. It sees no read
// after a later write that does not read: such a write would overwrite a
// buffer something else now holds, and nothing would conflict. So before any
// analysis, the program is made such that no such write exists: each
// tensor.empty is one buffer with one use, where common subexpression
// elimination would have shared one between two writes, and a write-only use
// of a released buffer after its release writes a tensor.empty of its own.
// Its contents were never read, so only its shape is the program's.
//
// Which buffers may be one is every aliasing relation the models declare,
// followed both ways, before the analysis decides any of them; when one
// value may run after another is by position, through loops and branches,
// as One-Shot's own conflict check reads it.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "idr/Support/Worklist.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <optional>

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// Whether `region` runs again after each run of it, by its op's model.
bool isRepetitive(Region *region, const BufferizationOptions &options) {
  BufferizableOpInterface op = options.dynCastBufferizableOp(region->getParentOp());
  return op && op.isRepetitiveRegion(region->getRegionNumber());
}

// The uses of `value`, taken before any of them changes.
SmallVector<OpOperand *> usesOf(Value value) {
  return llvm::map_to_vector(value.getUses(), [](OpOperand &use) { return &use; });
}

// `use` writes a tensor.empty of its own, of the shape of the value it wrote.
void writeOwn(RewriterBase &rewriter, OpOperand &use) {
  Operation *writer = use.getOwner();
  Value old = use.get();
  auto type = cast<RankedTensorType>(old.getType());
  rewriter.setInsertionPoint(writer);
  SmallVector<OpFoldResult> sizes = tensor::getMixedSizes(rewriter, writer->getLoc(), old);
  Value own = tensor::EmptyOp::create(rewriter, writer->getLoc(), sizes, type.getElementType(),
                                      type.getEncoding());
  rewriter.modifyOpInPlace(writer, [&] { use.set(own); });
}

} // namespace

// Each value enters once, and the values of the program are finitely many.
llvm::SetVector<Value> idr::bufferize::sharers(Value value, const BufferizationOptions &options) {
  AnalysisState state(options);
  OnceWorklist<Value> found;
  found.push(value);
  while (std::optional<Value> sharer = found.pop()) {
    for (AliasingOpOperand alias : state.getAliasingOpOperands(*sharer))
      found.push(alias.opOperand->get());
    for (OpOperand &use : sharer->getUses())
      for (AliasingValue alias : state.getAliasingValues(use))
        found.push(alias.value);
  }
  ArrayRef<Value> entered = found.entered();
  return llvm::SetVector<Value>(entered.begin(), entered.end());
}

bool idr::bufferize::mayRunAfter(Operation *later, Operation *earlier, Value value,
                                 const BufferizationOptions &options) {
  // A loop around both, inside the region that defines `value`, runs `later`
  // again after `earlier` on the same instance. A loop that holds the
  // definition defines it anew on each run.
  Region *defining = value.getParentRegion();
  for (Region *region = later->getParentRegion(); region && !region->isAncestor(defining);
       region = region->getParentRegion())
    if (isRepetitive(region, options) && region->isAncestor(earlier->getParentRegion()))
      return true;

  // Otherwise by position, in the closest region that holds both: one of
  // the regions around `earlier`, which are finitely many, and the body of
  // the function that holds both is one of them.
  Region *common = nullptr;
  for (Region *region = earlier->getParentRegion(); region && !common;
       region = region->getParentRegion())
    if (region->findAncestorOpInRegion(*later))
      common = region;
  if (!common)
    llvm_unreachable("two ops of one function share no region");
  Operation *first = common->findAncestorOpInRegion(*earlier);
  Operation *second = common->findAncestorOpInRegion(*later);
  if (first == second) {
    // `later` holds `earlier`, and its operands are read before its regions
    // run; or the two are in two regions of one op, which run one after the
    // other unless they exclude each other.
    if (second == later)
      return false;
    return first == earlier || !insideMutuallyExclusiveRegions(earlier, later);
  }

  // In the region's one block: a function's body is one block, and so is
  // every region of the ops counting meets in it.
  return first->isBeforeInBlock(second);
}

bool idr::bufferize::isRelease(OpOperand &operand, const AnalysisState &state) {
  if (!isa<TensorLikeType>(operand.get().getType()))
    return false;
  if (isa<CallOpInterface>(operand.getOwner()))
    return true;
  return state.bufferizesToMemoryWrite(operand) &&
         state.getAliasingValues(operand).getNumAliases() == 0;
}

void idr::bufferize::prepare(Operation *program, const BufferizationOptions &options) {
  IRRewriter rewriter(program->getContext());

  program->walk([&](tensor::EmptyOp empty) {
    // The first use keeps the op; one nothing uses has no first.
    SmallVector<OpOperand *> uses = usesOf(empty.getResult());
    if (uses.empty())
      return;
    for (OpOperand *use : llvm::drop_begin(uses)) {
      rewriter.setInsertionPointAfter(empty);
      Operation *own = rewriter.clone(*empty);
      rewriter.modifyOpInPlace(use->getOwner(), [&] { use->set(own->getResult(0)); });
    }
  });

  AnalysisState state(options);
  SmallVector<OpOperand *> releases;
  program->walk([&](Operation *op) {
    for (OpOperand &operand : op->getOpOperands())
      if (isRelease(operand, state))
        releases.push_back(&operand);
  });
  for (OpOperand *release : releases) {
    Operation *releaser = release->getOwner();
    for (Value sharer : sharers(release->get(), options)) {
      if (!isa<RankedTensorType>(sharer.getType()))
        continue;
      for (OpOperand *use : usesOf(sharer))
        if (state.bufferizesToMemoryWrite(*use) && !state.bufferizesToMemoryRead(*use) &&
            mayRunAfter(use->getOwner(), releaser, sharer, options))
          writeOwn(rewriter, *use);
    }
  }
}
