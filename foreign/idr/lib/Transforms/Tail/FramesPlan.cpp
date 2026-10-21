// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' plan: the frames of a call cycle's functions, each a call of
// a member that runs a part of a closure, and the values the rest of its
// block reads (Frames.cpp rewrites them).

#include "idr/Transforms/Tail.h"

#include "idr/IR/Grades.h"
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

// The ops of `site`'s block after it, its terminator among them.
llvm::iterator_range<Block::iterator> restOf(Operation *site) {
  return llvm::make_range(std::next(site->getIterator()), site->getBlock()->end());
}

// Whether `value` is made by an op of the rest after `site`, or bound by a
// region of one.
bool madeInRest(Operation *site, Value value) {
  Operation *def = value.getDefiningOp();
  Operation *anchor = def ? def : cast<BlockArgument>(value).getOwner()->getParentOp();
  return llvm::any_of(restOf(site), [&](Operation &op) { return op.isAncestor(anchor); });
}

// The member whose call a case of a match gives as its value, if any.
FuncOp caseCallee(Region &region, const Members &members) {
  if (region.empty())
    return FuncOp();
  Operation *terminator = region.front().getTerminator();
  if (!isa<YieldOp>(terminator) || terminator->getNumOperands() != 1)
    return FuncOp();
  Operation *def = terminator->getOperand(0).getDefiningOp();
  return def && def->getNextNode() == terminator ? memberCalled(def, members) : FuncOp();
}

bool isConstant(Value value) {
  Operation *def = value.getDefiningOp();
  return def && def->hasTrait<OpTrait::ConstantLike>();
}

namespace {

// The members whose closures `op` runs for its one value, which the rest
// of its block then needs: `op`, not in tail position, is a call of one,
// or a match (the dispatch of an action) a case of which gives a call of
// one as its value.
SmallVector<FuncOp, 2> closuresRun(Operation &op, const Members &members, const Labels &labels) {
  SmallVector<FuncOp, 2> callees;
  if (op.getNumResults() != 1 || inTailPosition(&op))
    return callees;
  auto add = [&](FuncOp callee) {
    if (callee && labels.contains(callee.getSymNameAttr()) && !llvm::is_contained(callees, callee))
      callees.push_back(callee);
  };
  if (isa<CallOp>(op))
    add(memberCalled(&op, members));
  else if (isa<MatchOpInterface>(op))
    for (Region &region : op.getRegions())
      add(caseCallee(region, members));
  return callees;
}

// The frame of `block`, a tail block of `owner`: an op that runs the
// closure of a member (a function a closure sum names as a label), not in
// tail position, whose rest calls members again only in tail position,
// which goes on with the stack. A recursion over data, which calls no
// closure's function, keeps its calls.
std::optional<Frame> frameAt(Block &block, FuncOp owner, const Members &members,
                             const Labels &labels) {
  for (Operation &op : block) {
    SmallVector<FuncOp, 2> callees = closuresRun(op, members, labels);
    if (callees.empty())
      continue;
    Frame frame{&op, owner, std::move(callees), {}};
    bool callsAgain = false;
    for (Operation &later : restOf(&op))
      later.walk([&](Operation *inner) {
        if (memberCalled(inner, members) && !inTailPosition(inner))
          callsAgain = true;
        for (Value operand : inner->getOperands())
          if (operand != op.getResult(0) && !madeInRest(&op, operand) && !isConstant(operand))
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
void framesFrom(Block &block, FuncOp owner, const Members &members, const Labels &labels,
                SmallVectorImpl<Frame> &frames) {
  if (std::optional<Frame> frame = frameAt(block, owner, members, labels)) {
    frames.push_back(std::move(*frame));
    return;
  }
  if (Operation *match = tailMatch(block.getTerminator()))
    for (Region &region : match->getRegions())
      if (!region.empty())
        framesFrom(region.front(), owner, members, labels, frames);
}

} // namespace

// Every function a closure sum of the program names as a label.
Labels closureLabels(ProgramOp program) {
  Labels labels;
  auto add = [&](Type type) {
    if (DataType data = dataTypeOf(type); data && data.isClosures())
      for (const Ctor &ctor : data.getCtors())
        if (const auto *label = std::get_if<role::Label>(&ctor.role))
          labels.insert(label->fn.getAttr());
  };
  program.walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      add(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          add(type);
  });
  return labels;
}

// The plan of a component; none when no member has a frame, or when the
// members differ in what they may do, which their runs and resumes, each
// running the others' rests, share (the effects solve gives a cycle one
// set). Those end when every member does.
FailureOr<std::optional<FramesPlan>> framesPlanOf(ArrayRef<Operation *> component,
                                                  const Labels &labels, SymbolTable &symbols) {
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
        return fn.getEffects() != first.getEffects();
      }))
    return std::optional<FramesPlan>();
  plan.total = llvm::all_of(plan.members, [](FuncOp fn) { return fn.getTotal(); });
  for (FuncOp fn : plan.members)
    framesFrom(fn.getBody().front(), fn, plan.byName, labels, plan.frames);
  if (plan.frames.empty())
    return std::optional<FramesPlan>();
  for (FuncOp fn : plan.members) {
    Type result = fn.getResultTypes()[0];
    // The answer holds a member's result as one of its fields, so a
    // result no constructor may hold keeps the component's plain calls.
    if (!isFieldType(result))
      return std::optional<FramesPlan>();
    if (!llvm::is_contained(plan.results, result))
      plan.results.push_back(result);
  }
  for (FuncOp fn : plan.members) {
    StringAttr run =
        StringAttr::get(fn.getContext(), contentName(fn.getSymName(), "run", ""));
    if (symbols.lookup(run))
      return fn.emitError() << "internal error: the name " << run.getValue() << " of a run of @"
                            << fn.getSymName() << " is taken";
    plan.runs[fn] = run;
  }
  for (Type result : plan.results) {
    StringAttr resume = StringAttr::get(
        first.getContext(), contentName(first.getSymName(), "resume", canonicalHash(result)));
    if (symbols.lookup(resume))
      return first.emitError() << "internal error: the name " << resume.getValue()
                               << " of a resume of @" << first.getSymName() << " is taken";
    plan.resumes[result] = resume;
  }
  if (plan.results.size() > 1)
    plan.answer =
        StringAttr::get(first.getContext(), contentName(first.getSymName(), "answer", ""));
  plan.stack = StringAttr::get(first.getContext(), contentName(first.getSymName(), "frames", ""));
  return std::optional<FramesPlan>(std::move(plan));
}

} // namespace idr::tail
