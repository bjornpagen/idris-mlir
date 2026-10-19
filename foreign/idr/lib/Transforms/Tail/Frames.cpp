// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Frames.cpp - idr-frames --------------------------------------------===//
//
// A call within a cycle of calls that runs a part of a closure, whose
// result the rest of its tail then consumes, becomes a tail call that
// carries the rest as data: a frame of the values the rest reads, pushed on
// a stack the cycle's functions take, and popped where a value would have
// been returned. The run of an IO action is the case: io_bind's closure
// runs its left action, then applies its continuation to what that gave;
// when the left action is a bind itself, the run is a call of a bind
// closure's function (its own, or another type's) whose result the
// continuation needs, and a chain of binds nested to the left (foldlM's)
// runs as deep as it is long. With the continuation on the stack, running
// a bind is a tail call whatever its left action is, and the nesting the
// program built is on the heap, as the program built it: the left-nested
// bind is no longer special.
//
// For a component of the call graph with such calls (its frames, each in a
// case of a match on a closure, in tail position, with the rest of its
// block after it, calling a member of the component), one stack type of an
// empty stack and a frame per call, and for each member f:
//  - f.run, f's body taking the stack: a frame's call of g is a tail call
//    of g.run on the call's arguments and the stack with the frame pushed;
//    a tail call of a member m is m.run's on the same stack; any other tail
//    gives its value to f.resume with the stack.
//  - f.resume(v, stack): an empty stack returns v; a frame popped, pushed by
//    a call of f, runs the rest of its block on v and the values the frame
//    holds, its tails going on as its function's run's do, with the stack
//    under the frame. A frame of a call of another member is never on top
//    when f returns.
//  - f calls f.run with the empty stack.
// The runs and resumes call each other in tail position only, which
// idr-tail-loops and idr-tail-calls make loops and guaranteed tail calls.
// Only a run of a closure's part is a frame: a recursion over data (a
// fold, a tree) keeps its calls, whose depth its data's shape bounds.
//
// The pass stays at the program: the clones and the stack's data type are
// new symbols and types, named from the functions' and the kind.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/CallCycles.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SetVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRFRAMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-frames gives one component its runs and resumes; the unit is the
// component's first function.
struct FramesAction : support::TaggedAction<FramesAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-frames";
};

// A component's functions, by name.
using Members = llvm::DenseMap<StringAttr, FuncOp>;

// The member `op` calls, when it is a call of one.
FuncOp memberCalled(Operation *op, const Members &members) {
  auto call = dyn_cast_or_null<CallOp>(op);
  return call ? members.lookup(call.getCalleeAttr().getAttr()) : FuncOp();
}

// A call of a member that runs a part of a closure, in a tail block of its
// function, and what the rest of the block reads that the call does not
// make: the values its frame holds. A constant the rest reads is made
// again where it resumes.
struct Frame {
  CallOp call;
  FuncOp owner, callee;
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

// What becomes of one component: its members, its frames, the stack's data
// type, each member's run and resume.
struct Plan {
  SmallVector<FuncOp> members;
  Members byName;
  SmallVector<Frame> frames;
  StringAttr stack;
  llvm::DenseMap<Operation *, std::pair<StringAttr, StringAttr>> names;
};

// The stack's data type: `empty`, then each frame, holding what its rest
// reads and the stack under it.
FailureOr<DataType> stackType(MLIRContext *ctx, Plan &plan) {
  SmallVector<SmallVector<Type>> fields;
  fields.reserve(plan.frames.size());
  return DataType::define(ctx, plan.stack.getValue(), [&](DataType self) {
    Type below = BoxType::get(ctx, self);
    DataType::Body body;
    body.ctors.push_back({StringAttr::get(ctx, "empty"), {}, role::Plain{}});
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

// Each member's run and resume.
struct Made {
  llvm::DenseMap<Operation *, FuncOp> run, resume;
};

// The tails of `block`, of a body of `owner` or a rest of its, on `stack`:
// a call of a member right before the tail ends goes on with the stack in
// the member's run; any other value goes to owner's resume with it. The
// blocks of `skip` pushed their frames already.
void continueTails(RewriterBase &rewriter, Block &block, FuncOp owner, const Plan &plan,
                   const Made &made, Value stack, const llvm::SmallPtrSetImpl<Block *> &skip) {
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
    Operation *def = value.getDefiningOp();
    if (FuncOp member = memberCalled(def, plan.byName);
        member && def->getNextNode() == terminator) {
      auto call = cast<CallOp>(def);
      SmallVector<Value> args(call.getArgs());
      args.push_back(stack);
      auto again = CallOp::create(rewriter, call.getLoc(), made.run.at(member), args);
      rewriter.replaceOp(call, again.getResults());
      continue;
    }
    auto given = CallOp::create(rewriter, terminator->getLoc(), made.resume.at(owner),
                                ValueRange{value, stack});
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, given.getResult(0)); });
  }
}

// A member's run: its body on the stack, each frame of its own pushed by
// the call that takes its place.
void fillRun(RewriterBase &rewriter, const Plan &plan, const Made &made, FuncOp member,
             const IRMapping &mapping) {
  FuncOp run = made.run.at(member);
  Value top = run.getArguments().back();
  llvm::SmallPtrSet<Block *, 4> pushed;
  for (auto [index, frame] : llvm::enumerate(plan.frames)) {
    if (frame.owner != member)
      continue;
    auto call = cast<CallOp>(mapping.lookup(frame.call.getOperation()));
    Block *block = call->getBlock();
    Operation *terminator = block->getTerminator();
    // The rest is a resume's now: its ops go, users first, once the call
    // that pushes the frame takes its place.
    SmallVector<Operation *> rest;
    for (Operation &op : llvm::make_range(std::next(call->getIterator()), block->end()))
      if (&op != terminator)
        rest.push_back(&op);
    rewriter.setInsertionPoint(call);
    SmallVector<Value> fields;
    for (Value held : frame.held)
      fields.push_back(mapping.lookup(held));
    fields.push_back(top);
    Value pushedStack = ConOp::create(rewriter, call.getLoc(), top.getType(),
                                      Tag{static_cast<uint32_t>(index + 1)}, fields);
    SmallVector<Value> args(call.getArgs());
    args.push_back(pushedStack);
    auto tailCall = CallOp::create(rewriter, call.getLoc(), made.run.at(frame.callee), args);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(tailCall.getResults()); });
    for (Operation *op : llvm::reverse(rest))
      rewriter.eraseOp(op);
    rewriter.eraseOp(call);
    rewriter.moveOpBefore(tailCall, terminator);
    pushed.insert(block);
  }
  continueTails(rewriter, run.getBody().front(), member, plan, made, top, pushed);
}

// A member's resume: the empty stack gives the value back; a frame of a
// call of the member runs its rest; a frame of a call of another member is
// never on top when this one returns.
void fillResume(RewriterBase &rewriter, const Plan &plan, const Made &made, FuncOp member,
                DataType stack) {
  FuncOp resume = made.resume.at(member);
  Location loc = member.getLoc();
  Type result = member.getResultTypes()[0];
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
    if (frame.callee != member) {
      ub::UnreachableOp::create(rewriter, loc);
      continue;
    }
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
    continueTails(rewriter, *block, frame.owner, plan, made, block->getArguments().back(),
                  llvm::SmallPtrSet<Block *, 1>());
  }
  rewriter.setInsertionPointAfter(match);
  ReturnOp::create(rewriter, loc, match->getResults());
}

// The plan of a component; none when no member has a frame, or when the
// members differ in what they may do or in their proof that they end,
// which their runs and resumes, each running the others' rests, share.
FailureOr<std::optional<Plan>> planOf(ArrayRef<Operation *> component, SymbolTable &symbols) {
  Plan plan;
  for (Operation *op : component) {
    auto fn = dyn_cast<FuncOp>(op);
    if (!fn || fn.getBody().empty() || fn.getNumResults() != 1)
      return std::optional<Plan>();
    plan.members.push_back(fn);
    plan.byName[fn.getSymNameAttr()] = fn;
  }
  FuncOp first = plan.members.front();
  if (llvm::any_of(plan.members, [&](FuncOp fn) {
        return fn.getEffects() != first.getEffects() || fn.getTotal() != first.getTotal();
      }))
    return std::optional<Plan>();
  for (FuncOp fn : plan.members)
    framesFrom(fn.getBody().front(), fn, plan.byName, plan.frames);
  if (plan.frames.empty())
    return std::optional<Plan>();
  for (FuncOp fn : plan.members) {
    FailureOr<StringAttr> run = copyName(fn, "run", symbols);
    FailureOr<StringAttr> resume = copyName(fn, "resume", symbols);
    if (failed(run) || failed(resume))
      return failure();
    plan.names[fn] = {*run, *resume};
  }
  plan.stack = StringAttr::get(first.getContext(), contentName(first.getSymName(), "frames", ""));
  return std::optional<Plan>(std::move(plan));
}

LogicalResult perform(RewriterBase &rewriter, SymbolTable &symbols, Plan &plan) {
  MLIRContext *ctx = plan.members.front().getContext();
  FailureOr<DataType> stack = stackType(ctx, plan);
  if (failed(stack))
    return failure();
  Type stackBox = BoxType::get(ctx, *stack);

  // Every run and resume first, so that each body can call any of them.
  Made made;
  llvm::DenseMap<Operation *, IRMapping> mappings;
  for (FuncOp fn : plan.members) {
    auto [runName, resumeName] = plan.names.at(fn);
    IRMapping &mapping = mappings[fn];
    auto run = cast<FuncOp>(fn->clone(mapping));
    run.setSymNameAttr(runName);
    (void)run.insertArgument(run.getNumArguments(), stackBox, DictionaryAttr(), fn.getLoc());
    symbols.insert(run, std::next(fn->getIterator()));
    made.run[fn] = run;

    OpBuilder b(ctx);
    Type result = fn.getResultTypes()[0];
    FuncOp::Properties properties;
    properties.setSymName(resumeName);
    properties.setFunctionType(
        TypeAttr::get(FunctionType::get(ctx, {result, stackBox}, {result})));
    // What it runs is what the component ran after a call: its effects, and
    // its proof that it ends, since each turn pops a frame a run pushed.
    properties.setTotal(fn.getTotalAttr());
    auto resume = FuncOp::create(b, fn.getLoc(), TypeRange(), ValueRange(), properties);
    resume.setEffects(fn.getEffects());
    symbols.insert(resume, std::next(run->getIterator()));
    made.resume[fn] = resume;
  }
  for (FuncOp fn : plan.members)
    fillResume(rewriter, plan, made, fn, *stack);
  for (FuncOp fn : plan.members)
    fillRun(rewriter, plan, made, fn, mappings.at(fn));

  // Each member runs on the empty stack.
  for (FuncOp fn : plan.members) {
    Block &entry = fn.getBody().front();
    clearBlock(rewriter, entry);
    rewriter.setInsertionPointToStart(&entry);
    Value empty = ConOp::create(rewriter, fn.getLoc(), stackBox, Tag{0}, ValueRange());
    SmallVector<Value> args(entry.getArguments());
    args.push_back(empty);
    auto call = CallOp::create(rewriter, fn.getLoc(), made.run.at(fn), args);
    ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
  }
  return success();
}

struct Frames : impl::IdrFramesBase<Frames> {
  void runOnProgram(ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const CallCycles &cycles = getAnalysis<CallCycles>();
    SmallVector<Plan> plans;
    for (const CallCycles::Component &component : cycles.components()) {
      FailureOr<std::optional<Plan>> plan = planOf(component, symbols);
      if (failed(plan))
        return signalPassFailure();
      if (*plan)
        plans.push_back(std::move(**plan));
    }
    IRRewriter rewriter(program.getContext());
    unsigned performed = 0;
    bool failedOne = false;
    for (Plan &plan : plans)
      performed += support::perform<FramesAction>(plan.members.front(), [&] {
        numFunctions += plan.members.size();
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
