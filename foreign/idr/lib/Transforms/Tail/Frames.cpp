// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Frames.cpp - idr-frames --------------------------------------------===//
//
// A call within a cycle of calls that runs a closure, whose
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
// For a component of the call graph with such calls (its frames, each a
// call of a member some closure sum names as a label, or a dispatch whose
// cases give such calls, in a tail block, with the rest of its block after
// it), one stack type of an
// empty stack and a frame per call, and for each member f:
//  - f.run, f's body taking the stack: a frame's call of g is a tail call
//    of g.run on the call's arguments and the stack with the frame pushed;
//    a tail call of a member m is m.run's on the same stack; any other tail
//    gives its value to the resume of f's result type with the stack.
//  - the resume of f's result type, resume(v, stack): an empty stack
//    gives v as the answer; a frame popped runs the rest of its block on
//    v and the values the frame holds, its tails going on as its
//    function's run's do, with the stack under the frame. The frame on
//    top was pushed by a call of f or of a member that went on in f by
//    tail calls, which keep the type: a frame whose value is of another
//    type than f's result is never on top when f returns, so one resume
//    per result type runs each rest exactly once.
//  - f calls f.run with the empty stack and takes its own result out of
//    the answer.
// Every run and resume is a tail of the call that started on the empty
// stack, so all give what that call gives. The members may differ in
// result type (an IO action of one type whose left action gives another),
// so what they give is the answer: the one result type itself when they
// agree, and otherwise a sum of one constructor per result type. The
// answer is data, made where a value meets the empty stack and taken
// apart where the member that started returns, so each body and each rest
// exists once however many types the members give.
// The runs and resumes call each other in tail position only, which
// idr-tail-loops and idr-tail-calls make loops and guaranteed tail calls.
// Only a run of a closure is a frame: a recursion over data (a
// fold, a tree) keeps its calls, whose depth its data's shape bounds.
//
// The pass stays at the program: the clones and the stack's data type are
// new symbols and types, named from the functions' and the kind.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Transforms/Expect.h"

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
#include "llvm/ADT/SmallVectorExtras.h"

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

// The tail matches from `block` on give `answer`: in a run or a resume,
// every tail is a call that gives it.
void answerTails(Block &block, Type answer) {
  Operation *match = tailMatch(block.getTerminator());
  if (!match)
    return;
  match->getResult(0).setType(answer);
  for (Region &region : match->getRegions())
    if (!region.empty())
      answerTails(region.front(), answer);
}

// The tails of `block`, of a body of `owner` or a rest of its, on `stack`:
// a call of a member right before the tail ends goes on with the stack in
// the member's run; any other value goes to the resume of owner's result
// type with it. The blocks of `skip` pushed their frames already.
void continueTails(RewriterBase &rewriter, Block &block, FuncOp owner, const FramesPlan &plan,
                   const FramesMade &made, Value stack,
                   const llvm::SmallPtrSetImpl<Block *> &skip) {
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
    auto given = CallOp::create(rewriter, terminator->getLoc(),
                                made.resume.at(owner.getResultTypes()[0]),
                                ValueRange{value, stack});
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, given.getResult(0)); });
  }
}

// A member's run: its body on the stack, each frame of its own pushed by
// the call that takes its site's place. A site that is a dispatch keeps its
// match, each case going on with the frame pushed: a call of a member in
// that member's run, any other value in a resume, which pops the frame
// again at once.
void fillRun(RewriterBase &rewriter, const FramesPlan &plan, const FramesMade &made, FuncOp member,
             const IRMapping &mapping) {
  FuncOp run = made.run.at(member);
  Value top = run.getArguments().back();
  llvm::SmallPtrSet<Block *, 4> pushed;
  for (auto [index, frame] : llvm::enumerate(plan.frames)) {
    if (frame.owner != member)
      continue;
    Operation *site = mapping.lookup(frame.site);
    Block *block = site->getBlock();
    Operation *terminator = block->getTerminator();
    // The rest is a resume's now: its ops go, users first.
    SmallVector<Operation *> rest;
    for (Operation &op : llvm::make_range(std::next(site->getIterator()), block->end()))
      if (&op != terminator)
        rest.push_back(&op);
    rewriter.setInsertionPoint(site);
    SmallVector<Value> fields;
    for (Value held : frame.held)
      fields.push_back(mapping.lookup(held));
    fields.push_back(top);
    Value pushedStack = ConOp::create(rewriter, site->getLoc(), top.getType(),
                                      Tag{static_cast<uint32_t>(index + 1)}, fields);
    auto runOn = [&](CallOp call, FuncOp callee) {
      SmallVector<Value> args(call.getArgs());
      args.push_back(pushedStack);
      return CallOp::create(rewriter, call.getLoc(), made.run.at(callee), args);
    };
    if (auto call = dyn_cast<CallOp>(site)) {
      CallOp tailCall = runOn(call, frame.callees.front());
      rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(tailCall.getResults()); });
      for (Operation *op : llvm::reverse(rest))
        rewriter.eraseOp(op);
      rewriter.eraseOp(call);
      rewriter.moveOpBefore(tailCall, terminator);
      pushed.insert(block);
      continue;
    }
    for (Region &region : site->getRegions()) {
      if (region.empty())
        continue;
      Block &each = region.front();
      Operation *yield = each.getTerminator();
      if (!isa<YieldOp>(yield) || yield->getNumOperands() != 1)
        continue;
      rewriter.setInsertionPoint(yield);
      if (FuncOp callee = caseCallee(region, plan.byName); llvm::is_contained(frame.callees, callee)) {
        auto call = cast<CallOp>(yield->getOperand(0).getDefiningOp());
        rewriter.replaceOp(call, runOn(call, callee).getResults());
      } else {
        auto given = CallOp::create(rewriter, yield->getLoc(),
                                    made.resume.at(yield->getOperand(0).getType()),
                                    ValueRange{yield->getOperand(0), pushedStack});
        rewriter.modifyOpInPlace(yield, [&] { yield->setOperand(0, given.getResult(0)); });
      }
      pushed.insert(&each);
    }
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(site->getResults()); });
    for (Operation *op : llvm::reverse(rest))
      rewriter.eraseOp(op);
  }
  answerTails(run.getBody().front(), made.answer);
  continueTails(rewriter, run.getBody().front(), member, plan, made, top, pushed);
}

// A result type's resume: the empty stack gives the value back as the
// answer; a frame whose value is of this result type runs its rest; any
// other frame is never on top when a member giving this type returns.
void fillResume(RewriterBase &rewriter, const FramesPlan &plan, const FramesMade &made, Type result,
                DataType stack) {
  FuncOp resume = made.resume.at(result);
  Location loc = resume.getLoc();
  Type stackBox = BoxType::get(stack.getContext(), stack);
  Block *entry = rewriter.createBlock(&resume.getBody(), {}, {result, stackBox},
                                     {passBinder(loc, "value"), passBinder(loc, "stack")});
  Value value = entry->getArgument(0);
  Value top = entry->getArgument(1);
  auto tags = llvm::to_vector(stack.getTags());
  auto match = MatchOp::create(rewriter, loc, TypeRange(made.answer), top, ArrayRef<Tag>(tags));
  {
    Region &empty = match.getCaseRegion(0);
    rewriter.createBlock(&empty, empty.end());
    YieldOp::create(rewriter, loc, made.asAnswer(rewriter, loc, plan, value));
  }
  for (auto [index, frame] : llvm::enumerate(plan.frames)) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(index + 1));
    const Ctor &ctor = stack.getCtor(Tag{static_cast<uint32_t>(index + 1)});
    SmallVector<Type> bound;
    for (Type field : ctor.fields)
      bound.push_back(fieldType(stackBox, field));
    Block *block = rewriter.createBlock(&region, region.end(), bound,
                                        SmallVector<Location>(bound.size(), passBinder(loc, "held")));
    if (frame.site->getResult(0).getType() != result) {
      ub::UnreachableOp::create(rewriter, loc);
      continue;
    }
    IRMapping map;
    map.map(frame.site->getResult(0), value);
    for (auto [held, arg] : llvm::zip_first(frame.held, block->getArguments()))
      map.map(held, heldAs(rewriter, loc, arg, held.getType()));
    // The constants the rest reads, made again here.
    for (Operation &later : restOf(frame.site))
      later.walk([&](Operation *inner) {
        for (Value operand : inner->getOperands())
          if (isConstant(operand) && !map.contains(operand) &&
              !madeInRest(frame.site, operand))
            map.map(operand, rewriter.clone(*operand.getDefiningOp())->getResult(0));
      });
    // The rest ends the case: a return of the owner's body yields here.
    for (Operation &later : restOf(frame.site)) {
      if (auto done = dyn_cast<ReturnOp>(later)) {
        YieldOp::create(rewriter, done.getLoc(), llvm::map_to_vector(done.getOperands(), [&](Value v) {
                          return map.lookupOrDefault(v);
                        }));
        continue;
      }
      rewriter.clone(later, map);
    }
    answerTails(*block, made.answer);
    continueTails(rewriter, *block, frame.owner, plan, made, block->getArguments().back(),
                  llvm::SmallPtrSet<Block *, 1>());
  }
  rewriter.setInsertionPointAfter(match);
  ReturnOp::create(rewriter, loc, match->getResults());
}

LogicalResult perform(RewriterBase &rewriter, SymbolTable &symbols, Declarations &declarations,
                      FramesPlan &plan) {
  MLIRContext *ctx = plan.members.front().getContext();
  FailureOr<DataType> stack = stackTypeOf(declarations, plan);
  if (failed(stack))
    return failure();
  Type stackBox = BoxType::get(ctx, *stack);

  FramesMade made;
  if (plan.answer) {
    FailureOr<DataType> sum = answerTypeOf(declarations, plan);
    if (failed(sum))
      return failure();
    made.sum = *sum;
    made.answer = BoxType::get(ctx, *sum);
  } else {
    made.answer = plan.results.front();
  }

  // Every run and resume first, so that each body can call any of them.
  llvm::DenseMap<Operation *, IRMapping> mappings;
  for (FuncOp fn : plan.members) {
    IRMapping &mapping = mappings[fn];
    auto run = cast<FuncOp>(fn->clone(mapping));
    run.setSymNameAttr(plan.runs.at(fn));
    run.setTotalAttr(plan.total ? UnitAttr::get(ctx) : UnitAttr());
    SmallVector<Type> inputs(fn.getArgumentTypes());
    inputs.push_back(stackBox);
    (void)run.insertArgument(run.getNumArguments(), stackBox, DictionaryAttr(),
                            passBinder(fn.getLoc(), "stack"));
    run.setFunctionTypeAttr(TypeAttr::get(FunctionType::get(ctx, inputs, {made.answer})));
    symbols.insert(run, std::next(fn->getIterator()));
    made.run[fn] = run;
  }
  for (Type result : plan.results) {
    // The members share their effects, so the first speaks for the type.
    FuncOp fn = *llvm::find_if(plan.members, [&](FuncOp each) {
      return each.getResultTypes()[0] == result;
    });
    OpBuilder b(ctx);
    FuncOp::Properties properties;
    properties.setSymName(plan.resumes.at(result));
    properties.setFunctionType(
        TypeAttr::get(FunctionType::get(ctx, {result, stackBox}, {made.answer})));
    // What it runs is what the component ran after a call: its effects,
    // and the members' proof that they end, since each turn pops a frame
    // a run pushed.
    properties.setTotal(plan.total ? UnitAttr::get(ctx) : UnitAttr());
    auto resume = FuncOp::create(b, fn.getLoc(), TypeRange(), ValueRange(), properties);
    resume.setEffects(fn.getEffects());
    symbols.insert(resume, std::next(fn->getIterator()));
    made.resume[result] = resume;
  }
  for (Type result : plan.results)
    fillResume(rewriter, plan, made, result, *stack);
  for (FuncOp fn : plan.members) {
    fillRun(rewriter, plan, made, fn, mappings.at(fn));
    mappings.erase(fn);
  }

  // Each member runs on the empty stack.
  for (FuncOp fn : plan.members) {
    Block &entry = fn.getBody().front();
    clearBlock(rewriter, entry);
    rewriter.setInsertionPointToStart(&entry);
    Value empty = ConOp::create(rewriter, fn.getLoc(), stackBox, Tag{0}, ValueRange());
    SmallVector<Value> args(entry.getArguments());
    args.push_back(empty);
    auto call = CallOp::create(rewriter, fn.getLoc(), made.run.at(fn), args);
    Value given = fromAnswer(rewriter, plan, made, fn, call.getResult(0));
    ReturnOp::create(rewriter, fn.getLoc(), ValueRange{given});
  }
  return success();
}

struct Frames : impl::IdrFramesBase<Frames> {
  void runOnProgram(ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const CallCycles &cycles = getAnalysis<CallCycles>();
    Labels labels = closureLabels(program);
    std::vector<FramesPlan> plans;
    for (const CallCycles::Component &component : cycles.components()) {
      FailureOr<std::optional<FramesPlan>> plan = framesPlanOf(component, labels, symbols);
      if (failed(plan))
        return signalPassFailure();
      if (*plan)
        plans.push_back(std::move(**plan));
    }
    IRRewriter rewriter(program.getContext());
    Declarations declarations(program);
    unsigned performed = 0;
    bool failedOne = false;
    for (FramesPlan &plan : plans)
      performed += support::perform<FramesAction>(plan.members.front(), [&] {
        numFunctions += plan.members.size();
        numFrames += plan.frames.size();
        failedOne |= failed(perform(rewriter, symbols, declarations, plan));
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
