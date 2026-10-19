// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' plan: the frames of a call cycle's functions, each a call of
// a member that runs a part of a closure, and the values the rest of its
// block reads (Frames.cpp rewrites them).

#include "idr/Transforms/Tail.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"

using namespace mlir;

namespace idr::tail {

// The member `op` calls, when it is a call of one.
FuncOp memberCalled(Operation *op, const Members &members) {
  auto call = dyn_cast_or_null<CallOp>(op);
  return call ? members.lookup(call.getCalleeAttr().getAttr()) : FuncOp();
}

// The ops of `block` after `call`, its terminator among them.
llvm::iterator_range<Block::iterator> restOf(CallOp call) {
  return llvm::make_range(std::next(call->getIterator()), call->getBlock()->end());
}

// Whether `value` is made by an op of the rest after `call`, or bound by a
// region of one.
bool madeInRest(CallOp call, Value value) {
  Operation *def = value.getDefiningOp();
  Operation *anchor = def ? def : cast<BlockArgument>(value).getOwner()->getParentOp();
  return llvm::any_of(restOf(call), [&](Operation &op) { return op.isAncestor(anchor); });
}

bool isConstant(Value value) {
  Operation *def = value.getDefiningOp();
  return def && def->hasTrait<OpTrait::ConstantLike>();
}

namespace {

// The frame of `block`, a tail block of `owner`: a case of a match on a
// closure, and in it a call of a member not in tail position, whose rest
// calls members again only in tail position, which goes on with the stack.
std::optional<Frame> frameAt(Block &block, FuncOp owner, const Members &members) {
  auto match = dyn_cast_or_null<MatchOp>(block.getParentOp());
  if (!match || !match.knownTag(*block.getParent()) || !match.getDataType() ||
      !match.getDataType().isClosures())
    return std::nullopt;
  for (Operation &op : block) {
    FuncOp callee = memberCalled(&op, members);
    auto call = dyn_cast<CallOp>(op);
    if (!callee || call->getNumResults() != 1 || inTailPosition(call))
      continue;
    Frame frame{call, owner, callee, {}};
    bool callsAgain = false;
    for (Operation &later : restOf(call))
      later.walk([&](Operation *inner) {
        if (memberCalled(inner, members) && !inTailPosition(inner))
          callsAgain = true;
        for (Value operand : inner->getOperands())
          if (operand != call.getResult(0) && !madeInRest(call, operand) &&
              !isConstant(operand))
            frame.held.insert(operand);
      });
    // A call of a member the rest makes elsewhere would need a frame of its
    // own.
    if (callsAgain)
      return std::nullopt;
    return frame;
  }
  return std::nullopt;
}

// The frames of the blocks that end in a tail position from `block` on:
// its own, the rest of which holds every tail after it, or those of the
// regions of the match in tail position it ends with.
void framesFrom(Block &block, FuncOp owner, const Members &members,
                SmallVectorImpl<Frame> &frames) {
  if (std::optional<Frame> frame = frameAt(block, owner, members)) {
    frames.push_back(std::move(*frame));
    return;
  }
  if (Operation *match = tailMatch(block.getTerminator()))
    for (Region &region : match->getRegions())
      if (!region.empty())
        framesFrom(region.front(), owner, members, frames);
}

} // namespace

// The plan of a component; none when no member has a frame, or when the
// members differ in what they may do or in their proof that they end,
// which their runs and resumes, each running the others' rests, share.
FailureOr<std::optional<FramesPlan>> framesPlanOf(ArrayRef<Operation *> component, SymbolTable &symbols) {
  FramesPlan plan;
  for (Operation *op : component) {
    auto fn = dyn_cast<FuncOp>(op);
    if (!fn || fn.getBody().empty() || fn.getNumResults() != 1)
      return std::optional<FramesPlan>();
    plan.members.push_back(fn);
    plan.byName[fn.getSymNameAttr()] = fn;
  }
  FuncOp first = plan.members.front();
  if (llvm::any_of(plan.members, [&](FuncOp fn) {
        return fn.getEffects() != first.getEffects() || fn.getTotal() != first.getTotal();
      }))
    return std::optional<FramesPlan>();
  for (FuncOp fn : plan.members)
    framesFrom(fn.getBody().front(), fn, plan.byName, plan.frames);
  if (plan.frames.empty())
    return std::optional<FramesPlan>();
  for (FuncOp fn : plan.members) {
    FailureOr<StringAttr> run = copyName(fn, "run", symbols);
    FailureOr<StringAttr> resume = copyName(fn, "resume", symbols);
    if (failed(run) || failed(resume))
      return failure();
    plan.names[fn] = {*run, *resume};
  }
  plan.stack = StringAttr::get(first.getContext(), contentName(first.getSymName(), "frames", ""));
  return std::optional<FramesPlan>(std::move(plan));
}

} // namespace idr::tail
