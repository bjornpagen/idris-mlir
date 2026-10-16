// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values that flow around loops and out of merges made words where
// every value that may flow there fits: the webs' joints.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/EquivalenceClasses.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::narrow {

using ranges::Bounds;

namespace {

// idr-narrow makes one joint's carried bigs words; the unit is the joint op.
struct NarrowJointAction : support::TaggedAction<NarrowJointAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-narrow-joint";
};

// Retypes the big block argument `arg` to i64: its uses get the big of it.
// The argument belongs to the joint being rewritten, or to an op inside it.
void narrowArgument(RewriterBase &rewriter, Facts &facts, BlockArgument arg) {
  Bounds bounds = facts.of(arg);
  Type type = arg.getType();
  rewriter.modifyOpInPlace(arg.getOwner()->getParentOp(),
                           [&] { arg.setType(rewriter.getI64Type()); });
  rewriter.setInsertionPointToStart(arg.getOwner());
  Value big = facts.big(rewriter, arg.getLoc(), type, arg, bounds);
  rewriter.replaceAllUsesExcept(arg, big, big.getDefiningOp());
}

// Retypes the big result `result` to i64: its uses get the big of it.
void narrowResult(RewriterBase &rewriter, Facts &facts, OpResult result) {
  Bounds bounds = facts.of(result);
  Type type = result.getType();
  rewriter.modifyOpInPlace(result.getOwner(), [&] { result.setType(rewriter.getI64Type()); });
  rewriter.setInsertionPointAfter(result.getOwner());
  Value big = facts.big(rewriter, result.getLoc(), type, result, bounds);
  rewriter.replaceAllUsesExcept(result, big, big.getDefiningOp());
}

// Passes the word of operand `index` of `op` instead of the big. The
// operands narrowed here are consumed where they are passed (a loop's
// start, a yield), so a big that held a reference drops it there: counting
// ran before, and the word takes nothing.
void passWord(RewriterBase &rewriter, Facts &facts, Operation *op, unsigned index) {
  rewriter.setInsertionPoint(op);
  Value big = op->getOperand(index);
  Value word = facts.word(rewriter, op->getLoc(), big);
  rewriter.modifyOpInPlace(op, [&] { op->setOperand(index, word); });
  if (facts.owned(big))
    DropOp::create(rewriter, op->getLoc(), big);
}

// The values that flow around `op`, a loop, or out of it, a merge, made
// words where every value that may flow there fits; how many. What flows
// is what `op` and the terminators of its regions forward: each forwarded
// operand moves into the values it becomes, and the values one operand
// becomes, with every operand that moves into any of them, are one joint,
// as a loop's argument and its result are one with its start and what
// each iteration yields. A region that ends the program forwards nothing.
unsigned narrowCarried(RewriterBase &rewriter, Facts &facts, Operation *op) {
  SmallVector<std::pair<OpOperand *, Value>> edges;
  auto add = [&](Operation *from) {
    forwardedValues(from, [&](OpOperand &operand, Value input) {
      if (isBig(input.getType()))
        edges.emplace_back(&operand, input);
    });
  };
  add(op);
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (!block.empty() && block.back().hasTrait<OpTrait::IsTerminator>())
        add(&block.back());
  // The joints, each the class of its values under the operands they
  // share, in the order their first value is met.
  llvm::EquivalenceClasses<void *> joints;
  for (auto [operand, input] : edges)
    joints.unionSets(input.getAsOpaquePointer(), operand);
  llvm::MapVector<void *, std::pair<SmallVector<OpOperand *>, SetVector<Value>>> members;
  for (auto [operand, input] : edges) {
    auto &[operands, inputs] = members[joints.getLeaderValue(operand)];
    if (!llvm::is_contained(operands, operand))
      operands.push_back(operand);
    inputs.insert(input);
  }
  unsigned count = 0;
  for (auto &[leader, joint] : members) {
    auto &[operands, inputs] = joint;
    if (!llvm::all_of(inputs, [&](Value input) { return facts.fits(input); }) ||
        !llvm::all_of(operands, [&](OpOperand *operand) { return facts.fits(operand->get()); }))
      continue;
    count += support::perform<NarrowJointAction>(op, [&] {
      for (OpOperand *operand : operands)
        passWord(rewriter, facts, operand->getOwner(), operand->getOperandNumber());
      for (Value input : inputs) {
        if (auto arg = dyn_cast<BlockArgument>(input))
          narrowArgument(rewriter, facts, arg);
        else
          narrowResult(rewriter, facts, cast<OpResult>(input));
      }
    });
  }
  return count;
}

// A joint whose carried bigs all fit: the walk reaches it after everything
// inside it, while every value it carries is still the one analysed.
struct NarrowJoint : OpInterfaceRewritePattern<RegionBranchOpInterface> {
  NarrowJoint(MLIRContext *ctx, Facts &facts, uint64_t &carried)
      : OpInterfaceRewritePattern(ctx), facts(facts), carried(carried) {}

  LogicalResult matchAndRewrite(RegionBranchOpInterface op,
                                PatternRewriter &rewriter) const override {
    unsigned count = narrowCarried(rewriter, facts, op);
    if (count == 0)
      return failure();
    carried += count;
    return success();
  }

  Facts &facts;
  uint64_t &carried;
};

} // namespace

void populateJointPatterns(RewritePatternSet &patterns, Facts &facts, uint64_t &carried) {
  patterns.add<NarrowJoint>(patterns.getContext(), facts, carried);
}

} // namespace idr::narrow
