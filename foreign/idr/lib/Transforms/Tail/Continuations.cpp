// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' first step: continuations become functions. Each call to
// frame must end its block in a tail of its function, so every region op
// around it whose results something after it reads gives its continuation
// to a function of its own (a lifted continuation), which each region of
// the op tail-calls; a join point around it becomes functions too
// (Dissolve.cpp); a lifetime's region around it splits (Split.cpp); and
// the rest of the call's block becomes a function its call runs into,
// tail-calling it with what the rest reads. Each step moves code, never
// copies it, and makes a function of the component, read in turn, so it
// ends: the code it moves only shrinks.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Remake.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

namespace {

// Whether `value` is made by one of the ops of its block from `first` on,
// or bound inside one of them.
bool madeFrom(Value value, Operation *first) {
  Block *block = first->getBlock();
  Operation *anchor = value.getDefiningOp();
  if (!anchor) {
    Block *owner = cast<BlockArgument>(value).getOwner();
    if (owner == block)
      return false;
    anchor = owner->getParentOp();
  }
  Operation *top = block->findAncestorOpInBlock(*anchor);
  return top && !top->isBeforeInBlock(first);
}

} // namespace

IndexArgsAttr concatArgs(MLIRContext *ctx, IndexArgsAttr a, IndexArgsAttr b) {
  llvm::SmallVector<families::TermNode> nodes(a.getTerms());
  llvm::append_range(nodes, b.getTerms());
  return IndexArgsAttr::get(ctx, nodes, a.getCount() + b.getCount());
}

llvm::SmallVector<families::Sort> scopeSorts(Region *region) {
  llvm::SmallVector<Region *> path;
  for (; region; region = region->getParentRegion())
    path.push_back(region);
  llvm::SmallVector<families::Sort> sorts;
  for (Region *at : llvm::reverse(path))
    if (auto binder = dyn_cast<ErasedBinderOpInterface>(at->getParentOp()))
      llvm::append_range(sorts, binder.getBoundSorts(*at));
  return sorts;
}

llvm::SetVector<Value> liveIns(Operation *first) {
  llvm::SetVector<Value> in;
  for (Operation *op = first; op; op = op->getNextNode())
    op->walk([&](Operation *inner) {
      for (Value operand : inner->getOperands())
        if (!madeFrom(operand, first))
          in.insert(operand);
    });
  return in;
}

// A function the pass makes beside `owner`: owner's facts (its row, what
// Idris proved of its loops), a signature of its own, the index binders of
// the scope its code comes from, and an entry block taking its parameters.
// Its row and per-parameter record are the writer's to make exact; what
// owner's signature stated of lifetimes and of what it gives back names
// owner's positions, not its own, and goes.
FuncOp Component::makeFunction(FuncOp owner, llvm::StringRef kind, FunctionType type,
                               llvm::ArrayRef<families::Sort> binders) {
  MLIRContext *ctx = owner.getContext();
  auto fn = cast<FuncOp>(owner->cloneWithoutRegions());
  fn.setSymNameAttr(StringAttr::get(ctx, owner.getSymName() + "." + kind));
  fn.setFunctionTypeAttr(TypeAttr::get(type));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setLivesInAttr(nullptr);
  fn.setGivenBackAttr(nullptr);
  fn.setBindersAttr(binders.empty() ? IndexBindersAttr() : IndexBindersAttr::get(ctx, binders));
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : type.getInputs())
    entry->addArgument(input, owner.getLoc());
  symbols.insert(fn, std::next(owner->getIterator()));
  return fn;
}

// The ops of `first`'s block from `first` on moved into a function of
// their own, which takes `params` (values `first`'s code receives) and
// then what the code reads, and gives what the block's terminator gives;
// in their place a tail call of it, whose results the terminator gives.
CallOp Component::outline(FuncOp owner, unsigned row, Operation *first, ValueRange params,
                          llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  Block *block = first->getBlock();
  Operation *terminator = block->getTerminator();
  llvm::SetVector<Value> in = liveIns(first);
  llvm::SmallVector<Value> passed(params);
  for (Value value : in)
    if (!llvm::is_contained(params, value))
      passed.push_back(value);
  llvm::SmallVector<Type> inputs = llvm::map_to_vector(passed, [](Value v) { return v.getType(); });
  auto type = FunctionType::get(ctx, inputs, terminator->getOperandTypes());
  llvm::SmallVector<families::Sort> binders = scopeSorts(block->getParent());
  FuncOp fn = makeFunction(owner, kind, type, binders);
  Block *entry = &fn.getBody().front();

  // The code moves, so the ops the pass recorded stay the ops they are.
  entry->getOperations().splice(entry->end(), block->getOperations(), first->getIterator(),
                                terminator->getIterator());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, terminator->getLoc(), terminator->getOperands());
  for (auto [value, arg] : llvm::zip_equal(passed, entry->getArguments()))
    rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
      return fn->isProperAncestor(use.getOwner());
    });

  rewriter.setInsertionPoint(terminator);
  auto call = CallOp::create(rewriter, terminator->getLoc(), fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             passed, TailKind::tail);
  rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(call.getResults()); });
  made.push_back(call);
  functions.push_back({fn, row});
  return call;
}

// `call`, right after `rejoin` and taking its results, moved into each of
// its regions that rejoins it: each tail-calls the continuation with what
// it gives, and the op gives the continuation's results, so it is in tail
// position once its block gives them.
void Component::sinkInto(Operation *rejoin, CallOp call) {
  llvm::SmallVector<Operation *> ends;
  for (Region &region : rejoin->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (isa<RegionBranchTerminatorOpInterface>(end) &&
        end->getNumOperands() == rejoin->getNumResults())
      ends.push_back(end);
  }
  for (Operation *end : ends) {
    rewriter.setInsertionPoint(end);
    IRMapping map;
    for (auto [result, given] : llvm::zip_equal(rejoin->getResults(), end->getOperands()))
      map.map(result, given);
    auto copy = cast<CallOp>(rewriter.clone(*call, map));
    rewriter.modifyOpInPlace(end, [&] { end->setOperands(copy.getResults()); });
    made.push_back(copy);
  }
  Operation *remade = remakeOp(rewriter, rejoin, rejoin->getOperands(), call.getResultTypes());
  rewriter.replaceAllUsesWith(call.getResults(), remade->getResults());
  llvm::erase(made, call);
  rewriter.eraseOp(call);
  rewriter.eraseOp(rejoin);
}

// The changes of grade after each region op of the tail spine from `root`
// moved into the op's regions, before each region's end: every region op
// a tail runs through then gives what its function gives, type for type,
// so a continuation made of the code after one gives it too.
void Component::normalize(Block *root) {
  llvm::SmallVector<Block *, 8> spine{root};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>())
      continue;
    llvm::SmallVector<Operation *> ends;
    for (Region &region : source->getRegions()) {
      if (region.empty())
        continue;
      Operation *end = region.front().getTerminator();
      if (isa<RegionBranchTerminatorOpInterface>(end) &&
          end->getNumOperands() == source->getNumResults())
        ends.push_back(end);
    }
    llvm::SmallVector<Type> types(source->getResultTypes());
    llvm::SmallVector<Operation *> regrades;
    for (Operation *op = source->getNextNode(); !op->hasTrait<OpTrait::IsTerminator>();
         op = op->getNextNode())
      regrades.push_back(op);
    for (Operation *regrade : regrades) {
      unsigned at = cast<OpResult>(regrade->getOperand(0)).getResultNumber();
      for (Operation *end : ends) {
        rewriter.setInsertionPoint(end);
        Operation *copy = rewriter.clone(*regrade);
        copy->setOperand(0, end->getOperand(at));
        rewriter.modifyOpInPlace(end, [&] { end->setOperand(at, copy->getResult(0)); });
      }
      types[at] = regrade->getResult(0).getType();
      rewriter.replaceAllUsesWith(regrade->getResult(0), source->getResult(at));
      rewriter.eraseOp(regrade);
    }
    if (!regrades.empty()) {
      Operation *remade = remakeOp(rewriter, source, source->getOperands(), types);
      rewriter.replaceAllUsesWith(source->getResults(), remade->getResults());
      rewriter.eraseOp(source);
      source = remade;
    }
    for (Operation *end : ends)
      spine.push_back(end->getBlock());
  }
}

LogicalResult Component::restructure(FuncOp fn, unsigned row) {
  for (;;) {
    // A join point op around a call to frame, outermost first.
    Operation *join = nullptr;
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (!op->hasTrait<OpTrait::TokenProducerTrait>())
        return WalkResult::advance();
      bool holds = op->walk([&](CallOp call) {
                         return frames(call) ? WalkResult::interrupt() : WalkResult::advance();
                       })
                       .wasInterrupted();
      if (!holds)
        return WalkResult::skip();
      join = op;
      return WalkResult::interrupt();
    });
    if (!join)
      break;
    normalize(&fn.getBody().front());
    if (!inTailPosition(join)) {
      CallOp continuation = outline(fn, row, join->getNextNode(), join->getResults(), "k");
      sinkInto(join, continuation);
      // The op was made again: it is found afresh.
      continue;
    }
    if (failed(dissolve(fn, row, join)))
      return failure();
  }
  normalize(&fn.getBody().front());

  // Each call to frame, in program order; one an earlier one's change moved
  // into a function of its own is that function's.
  llvm::SmallVector<CallOp> sites;
  fn.walk<WalkOrder::PreOrder>([&](CallOp call) {
    if (frames(call))
      sites.push_back(call);
  });
  for (CallOp site : sites) {
    if (site->getParentOfType<FuncOp>() != fn)
      continue;
    // The region ops around the call, outermost first: each a break may
    // cross whose results something after it reads gives its continuation
    // to a function, until the call's block ends a tail. Each such change
    // remakes the ops around, so they are read again after it.
    for (;;) {
      llvm::SmallVector<Operation *> around;
      for (Operation *op = site->getParentOp(); op != fn.getOperation(); op = op->getParentOp())
        around.push_back(op);
      Operation *lift = nullptr;
      for (Operation *op : llvm::reverse(around)) {
        if (op->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
          if (inTailPosition(op))
            continue;
          lift = op;
          break;
        }
        // Only a lifetime's region directly around the call may split.
        if (op != site->getParentOp())
          return site.emitOpError("internal error: idr-frames: a call on its function's cycle "
                                  "inside an op whose region frames cannot split: ")
                 << op->getName();
      }
      if (!lift)
        break;
      CallOp continuation = outline(fn, row, lift->getNextNode(), lift->getResults(), "k");
      sinkInto(lift, continuation);
      normalize(&fn.getBody().front());
    }
    // The rest of the call's block runs after it: in a lifetime's region,
    // which ends before the call, reopened by the rest.
    Operation *parent = site->getParentOp();
    if (parent != fn.getOperation() && !parent->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      if (failed(split(fn, row, site, parent)))
        return failure();
      continue;
    }
    CallOp rest = outline(fn, row, site->getNextNode(), site->getResults(), "rest");
    framed.push_back({site, rest});
  }
  return success();
}

} // namespace idr::tail::frames
