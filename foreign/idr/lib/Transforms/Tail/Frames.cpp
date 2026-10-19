// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Frames.cpp - idr-frames --------------------------------------------===//
//
// A self call that runs a part of a closure, whose result the rest of its
// tail then consumes, becomes a tail call that carries the rest as data: a
// frame of the values the rest reads, pushed on a stack the function takes,
// and popped where a value would have been returned. The run of an IO
// action is the case: io_bind's closure runs its left action, then applies
// its continuation to what that gave; when the left action is a bind
// itself, the run is a call of the closure's own function whose result the
// continuation needs, and a chain of binds nested to the left (foldlM's)
// runs as deep as it is long. With the continuation on the stack, running
// a bind is a tail call whatever its left action is, and the nesting the
// program built is on the heap, as the program built it: the left-nested
// bind is no longer special.
//
// For f, a function with such calls (its frames, each in a case of a match
// on a closure, in tail position, with the rest of its block after it):
//  - f.run, f's body taking the stack: a frame's call is a tail call of
//    f.run on the call's arguments and the stack with the frame pushed;
//    f's own tail calls are tail calls of f.run on the same stack; any
//    other tail gives its value to f.resume with the stack.
//  - f.resume(v, stack): an empty stack returns v; a frame popped runs the
//    rest of its block on v and the values the frame holds, its tails
//    going on as f.run's do with the stack under the frame.
//  - f calls f.run with the empty stack.
// f.run and f.resume call each other and themselves in tail position only,
// which idr-tail-loops and idr-tail-calls make loops and guaranteed tail
// calls. Only a run of a closure's part is a frame: a recursion over data
// (a fold, a tree) keeps its calls, whose depth its data's shape bounds.
//
// The pass stays at the program: the clones and the stack's data type are
// new symbols and types, named from the function's and the kind.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SetVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRFRAMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-frames gives one function its run and resume; the unit is the
// function.
struct FramesAction : support::TaggedAction<FramesAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-frames";
};

// A self call that runs a part of a closure, in a tail block, and what the
// rest of the block reads that the call does not make: the values its
// frame holds. A constant the rest reads is made again where it resumes.
struct Frame {
  CallOp call;
  llvm::SetVector<Value> held;
};

// The ops of `block` after `call`, its terminator among them.
auto restOf(CallOp call) {
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

// The frame of `block`, a tail block of `fn`: a case of a match on a
// closure, and in it a self call not in tail position whose rest calls f
// again only in tail position, which goes on with the stack.
std::optional<Frame> frameAt(Block &block, FuncOp fn) {
  auto match = dyn_cast_or_null<MatchOp>(block.getParentOp());
  if (!match || !match.knownTag(*block.getParent()) || !match.getDataType() ||
      !match.getDataType().isClosures())
    return std::nullopt;
  for (Operation &op : block) {
    auto call = dyn_cast<CallOp>(op);
    if (!call || !isSelfCall(call, fn) || call->getNumResults() != 1 || inTailPosition(call))
      continue;
    Frame frame{call, {}};
    bool selfAgain = false;
    for (Operation &later : restOf(call))
      later.walk([&](Operation *inner) {
        if (isSelfCall(inner, fn) && !inTailPosition(inner))
          selfAgain = true;
        for (Value operand : inner->getOperands())
          if (operand != call.getResult(0) && !madeInRest(call, operand) &&
              !isConstant(operand))
            frame.held.insert(operand);
      });
    // A self call the rest makes elsewhere would need a frame of its own.
    if (selfAgain)
      return std::nullopt;
    return frame;
  }
  return std::nullopt;
}

// The frames of the blocks that end in a tail position from `block` on:
// its own, the rest of which holds every tail after it, or those of the
// regions of the match in tail position it ends with.
void framesFrom(Block &block, FuncOp fn, SmallVectorImpl<Frame> &frames) {
  if (std::optional<Frame> frame = frameAt(block, fn)) {
    frames.push_back(std::move(*frame));
    return;
  }
  if (Operation *match = tailMatch(block.getTerminator()))
    for (Region &region : match->getRegions())
      if (!region.empty())
        framesFrom(region.front(), fn, frames);
}

// What becomes of one function: its frames, the stack's data type (empty,
// then a frame per call), and the names of its run and resume.
struct Plan {
  FuncOp fn;
  SmallVector<Frame> frames;
  StringAttr run, resume, stack;
};

// The stack's data type: `empty`, then each frame, holding what its rest
// reads and the stack under it.
FailureOr<DataType> stackType(MLIRContext *ctx, Plan &plan) {
  SmallVector<SmallVector<Type>> fields;
  return DataType::define(ctx, plan.stack.getValue(), [&](DataType self) {
    Type below = BoxType::get(ctx, self);
    DataType::Body body;
    body.ctors.push_back({StringAttr::get(ctx, "empty"), {}, role::Plain{}});
    fields.reserve(plan.frames.size());
    for (auto [index, frame] : llvm::enumerate(plan.frames)) {
      SmallVector<Type> &each = fields.emplace_back();
      for (Value held : frame.held)
        each.push_back(held.getType());
      each.push_back(below);
      body.ctors.push_back(
          {StringAttr::get(ctx, "frame" + std::to_string(index)), each, role::Plain{}});
    }
    return FailureOr<DataType::Body>(std::move(body));
  });
}

// The tails of `block` in run or resume, on `stack`: a self call of the
// function becomes run's on the stack, any other value goes to resume
// with it. `skip` are the blocks whose frames were pushed already.
void continueTails(RewriterBase &rewriter, Block &block, FuncOp fn, FuncOp run, FuncOp resume,
                   Value stack, const llvm::SmallPtrSetImpl<Block *> &skip) {
  SmallVector<Block *> tails;
  forTails(block, [&](Block &tail) { tails.push_back(&tail); });
  for (Block *tail : tails) {
    if (skip.contains(tail))
      continue;
    Operation *terminator = tail->getTerminator();
    if (!isa<ReturnOp, YieldOp>(terminator) || terminator->getNumOperands() != 1)
      continue;
    Value value = terminator->getOperand(0);
    rewriter.setInsertionPoint(terminator);
    // A self call right before the tail ends goes on with the stack; the
    // value of one anywhere else is a value, given to resume.
    if (auto call = value.getDefiningOp<CallOp>();
        call && isSelfCall(call, fn) && call->getNextNode() == terminator) {
      SmallVector<Value> args(call.getArgs());
      args.push_back(stack);
      auto again = CallOp::create(rewriter, call.getLoc(), run, args);
      rewriter.replaceOp(call, again.getResults());
      continue;
    }
    auto given = CallOp::create(rewriter, terminator->getLoc(), resume, ValueRange{value, stack});
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, given.getResult(0)); });
  }
}

// f.run: f's body on the stack, each frame's call pushing its frame.
void fillRun(RewriterBase &rewriter, Plan &plan, FuncOp run, FuncOp resume,
             const IRMapping &mapping) {
  Value top = run.getArguments().back();
  Type stackBox = top.getType();
  llvm::SmallPtrSet<Block *, 4> pushed;
  for (auto [index, frame] : llvm::enumerate(plan.frames)) {
    auto call = cast<CallOp>(mapping.lookup(frame.call.getOperation()));
    Block *block = call->getBlock();
    Operation *terminator = block->getTerminator();
    // The rest is resume's now: its ops go, users first, once the call that
    // pushes the frame takes its place.
    SmallVector<Operation *> rest;
    for (Operation &op : llvm::make_range(std::next(call->getIterator()), block->end()))
      if (&op != terminator)
        rest.push_back(&op);
    rewriter.setInsertionPoint(call);
    SmallVector<Value> fields;
    for (Value held : frame.held)
      fields.push_back(mapping.lookup(held));
    fields.push_back(top);
    Value pushedStack = ConOp::create(rewriter, call.getLoc(), stackBox,
                                      Tag{static_cast<uint32_t>(index + 1)}, fields);
    SmallVector<Value> args(call.getArgs());
    args.push_back(pushedStack);
    auto tailCall = CallOp::create(rewriter, call.getLoc(), run, args);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(tailCall.getResults()); });
    for (Operation *op : llvm::reverse(rest))
      rewriter.eraseOp(op);
    rewriter.eraseOp(call);
    rewriter.moveOpBefore(tailCall, terminator);
    pushed.insert(block);
  }
  continueTails(rewriter, run.getBody().front(), plan.fn, run, resume, top, pushed);
}

// f.resume: the empty stack gives the value back; a frame runs its rest.
void fillResume(RewriterBase &rewriter, Plan &plan, FuncOp run, FuncOp resume,
                DataType stack) {
  Location loc = plan.fn.getLoc();
  Type result = plan.fn.getResultTypes()[0];
  Type stackBox = BoxType::get(stack.getContext(), stack);
  Block *entry = rewriter.createBlock(&resume.getBody(), {}, {result, stackBox}, {loc, loc});
  Value value = entry->getArgument(0);
  Value top = entry->getArgument(1);
  auto tags = llvm::to_vector(stack.getTags());
  auto match = MatchOp::create(rewriter, loc, TypeRange(result), top, ArrayRef<Tag>(tags));
  {
    Region &empty = match.getCaseRegion(0);
    rewriter.createBlock(&empty, empty.end());
    YieldOp::create(rewriter, loc, value);
  }
  for (auto [index, frame] : llvm::enumerate(plan.frames)) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(index + 1));
    const Ctor &ctor = stack.getCtor(Tag{static_cast<uint32_t>(index + 1)});
    SmallVector<Type> bound;
    for (Type field : ctor.fields)
      bound.push_back(fieldType(stackBox, field));
    Block *block = rewriter.createBlock(&region, region.end(), bound,
                                        SmallVector<Location>(bound.size(), loc));
    IRMapping map;
    map.map(frame.call.getResult(0), value);
    for (auto [held, arg] : llvm::zip_first(frame.held, block->getArguments()))
      map.map(held, heldAs(rewriter, loc, arg, held.getType()));
    // The constants the rest reads, made again here.
    for (Operation &later : restOf(frame.call))
      later.walk([&](Operation *inner) {
        for (Value operand : inner->getOperands())
          if (isConstant(operand) && !map.contains(operand) &&
              !madeInRest(frame.call, operand))
            map.map(operand, rewriter.clone(*operand.getDefiningOp())->getResult(0));
      });
    for (Operation &later : restOf(frame.call))
      rewriter.clone(later, map);
    continueTails(rewriter, *block, plan.fn, run, resume, block->getArguments().back(),
                  llvm::SmallPtrSet<Block *, 1>());
  }
  rewriter.setInsertionPointAfter(match);
  ReturnOp::create(rewriter, loc, match->getResults());
}

FailureOr<std::optional<Plan>> planOf(FuncOp fn, SymbolTable &symbols) {
  if (fn.getNumResults() != 1 || fn.getBody().empty())
    return std::optional<Plan>();
  SmallVector<Frame> frames;
  framesFrom(fn.getBody().front(), fn, frames);
  if (frames.empty())
    return std::optional<Plan>();
  FailureOr<StringAttr> run = copyName(fn, "run", symbols);
  FailureOr<StringAttr> resume = copyName(fn, "resume", symbols);
  if (failed(run) || failed(resume))
    return failure();
  auto stack = StringAttr::get(fn.getContext(), contentName(fn.getSymName(), "frames", ""));
  return std::optional<Plan>(Plan{fn, std::move(frames), *run, *resume, stack});
}

LogicalResult perform(RewriterBase &rewriter, SymbolTable &symbols, Plan &plan) {
  FuncOp fn = plan.fn;
  MLIRContext *ctx = fn.getContext();
  FailureOr<DataType> stack = stackType(ctx, plan);
  if (failed(stack))
    return failure();
  Type stackBox = BoxType::get(ctx, *stack);
  Type result = fn.getResultTypes()[0];

  IRMapping mapping;
  auto run = cast<FuncOp>(fn->clone(mapping));
  run.setSymNameAttr(plan.run);
  (void)run.insertArgument(run.getNumArguments(), stackBox, DictionaryAttr(), fn.getLoc());
  symbols.insert(run, std::next(fn->getIterator()));

  OpBuilder b(ctx);
  FuncOp::Properties properties;
  properties.setSymName(plan.resume);
  properties.setFunctionType(TypeAttr::get(FunctionType::get(ctx, {result, stackBox}, {result})));
  // What it runs is what f ran after its call: f's effects, and f's proof
  // that it ends, since each of its turns pops a frame f pushed.
  properties.setTotal(fn.getTotalAttr());
  auto resume = FuncOp::create(b, fn.getLoc(), TypeRange(), ValueRange(), properties);
  resume.setEffects(fn.getEffects());
  symbols.insert(resume, std::next(run->getIterator()));

  fillResume(rewriter, plan, run, resume, *stack);
  fillRun(rewriter, plan, run, resume, mapping);

  // f runs on the empty stack.
  Block &entry = fn.getBody().front();
  clearBlock(rewriter, entry);
  rewriter.setInsertionPointToStart(&entry);
  Value empty = ConOp::create(rewriter, fn.getLoc(), stackBox, Tag{0}, ValueRange());
  SmallVector<Value> args(entry.getArguments());
  args.push_back(empty);
  auto call = CallOp::create(rewriter, fn.getLoc(), run, args);
  ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
  return success();
}

struct Frames : impl::IdrFramesBase<Frames> {
  void runOnProgram(ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    SmallVector<Plan> plans;
    for (FuncOp fn : program.getOps<FuncOp>()) {
      FailureOr<std::optional<Plan>> plan = planOf(fn, symbols);
      if (failed(plan))
        return signalPassFailure();
      if (*plan)
        plans.push_back(std::move(**plan));
    }
    IRRewriter rewriter(program.getContext());
    unsigned performed = 0;
    bool failedOne = false;
    for (Plan &plan : plans)
      performed += support::perform<FramesAction>(plan.fn, [&] {
        ++numFunctions;
        numFrames += plan.frames.size();
        failedOne |= failed(perform(rewriter, symbols, plan));
      });
    if (failedOne)
      return signalPassFailure();
    if (performed == 0)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
} // namespace idr::tail
