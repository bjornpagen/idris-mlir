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
//
// Every function made takes the component's lifetimes after its values, as
// every function of the component does, and states where each scoped value
// it takes or gives lives among them as it is made, before any call of it
// is built; so no function made names a position it does not have, and
// each call of one passes the lifetimes as operands. A region op made again
// with other results states its new results' lifetimes and keeps those of
// what its regions bind.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
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

bool isScoped(Value value) { return freedBy(value.getType(), Release::Scoped); }

} // namespace

llvm::SmallVector<BlockArgument> lifetimesOf(FuncOp fn) {
  llvm::SmallVector<BlockArgument> lifetimes;
  for (BlockArgument param : fn.getBody().front().getArguments())
    if (isa<LifetimeType>(param.getType()))
      lifetimes.push_back(param);
  return lifetimes;
}

std::optional<unsigned> placeOf(Value lifetime, FuncOp fn) {
  auto param = dyn_cast<BlockArgument>(lifetimes::extentOf(lifetime));
  Block &entry = fn.getBody().front();
  if (!param || param.getOwner() != &entry || !isa<LifetimeType>(param.getType()))
    return std::nullopt;
  return static_cast<unsigned>(
      llvm::count_if(entry.getArguments().take_front(param.getArgNumber()),
                     [](BlockArgument before) { return isa<LifetimeType>(before.getType()); }));
}

// A function's signature names a lifetime parameter for each scoped result,
// which its verifier holds, so each has its place.
Row givenRow(FuncOp fn) {
  Row row;
  llvm::append_range(row.types, fn.getResultTypes());
  if (LivesInAttr lives = fn.getLivesInAttr())
    for (const LivesIn &result : lives.getResults())
      row.livesIn.push_back(*placeOf(fn.getBody().front().getArgument(result.lifetime), fn));
  return row;
}

Value givenIn(Operation *terminator, unsigned index) {
  if (isa<ReturnOp>(terminator)) {
    auto fn = terminator->getParentOfType<FuncOp>();
    LivesInAttr lives = fn.getLivesInAttr();
    std::optional<std::uint32_t> in = lives ? lives.lifetimeOfResult(index) : std::nullopt;
    return in ? Value(fn.getBody().front().getArgument(*in)) : Value();
  }
  return lifetimes::statedLifetime(terminator->getParentOp()->getResult(index));
}

Operation *remakeGiving(RewriterBase &rewriter, Operation *op, TypeRange results,
                        ValueRange resultOuters) {
  auto states = dyn_cast<StatesOutersOpInterface>(op);
  llvm::SmallVector<Value> outers(resultOuters);
  if (states) {
    OperandRange stated = states.getOutersMutable();
    auto scoped = static_cast<unsigned>(llvm::count_if(op->getResults(), isScoped));
    llvm::append_range(outers, stated.drop_front(scoped));
  }
  Operation *made = remakeOp(rewriter, op, op->getOperands(), results);
  if (states)
    rewriter.modifyOpInPlace(made, [&] {
      lifetimes::restateOuters(cast<StatesOutersOpInterface>(made), outers);
    });
  return made;
}

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

llvm::SmallVector<Value> withoutLifetimes(llvm::ArrayRef<Value> values) {
  return llvm::to_vector(llvm::make_filter_range(
      values, [](Value value) { return !isa<LifetimeType>(value.getType()); }));
}

// A function the pass makes beside `owner`: owner's facts (its row, what
// Idris proved of its loops), the index binders of the scope its code comes
// from, and a signature of its own: the values `takes`, none a lifetime,
// then owner's lifetimes, the component's, giving `results`. Where each
// scoped parameter and result lives is stated as it is made, before any
// call of it is built, at the place among its own lifetimes of the one
// owner's statement names: a value taken, where the op that made it says;
// a result, `resultsIn`'s lifetime at its position. Owner's bounds between
// its lifetimes hold between the same lifetimes here. Its row and
// per-parameter record are the writer's to make exact; what owner gave back
// names owner's positions and goes.
FailureOr<Made> Component::makeFunction(FuncOp owner, llvm::StringRef kind,
                                        llvm::ArrayRef<Value> takes, TypeRange results,
                                        llvm::ArrayRef<Value> resultsIn,
                                        llvm::ArrayRef<families::Sort> binders) {
  MLIRContext *ctx = owner.getContext();
  llvm::SmallVector<BlockArgument> ownLifetimes = lifetimesOf(owner);
  auto first = static_cast<std::uint32_t>(takes.size());
  auto parameterFor = [&](Value lifetime) -> std::optional<std::uint32_t> {
    std::optional<unsigned> place = lifetime ? placeOf(lifetime, owner) : std::nullopt;
    return place ? std::optional<std::uint32_t>(first + *place) : std::nullopt;
  };
  llvm::SmallVector<LivesIn> parameters, scopedResults;
  llvm::SmallVector<Outlives> bounds;
  for (auto [index, value] : llvm::enumerate(takes)) {
    if (!isScoped(value))
      continue;
    std::optional<std::uint32_t> in = parameterFor(lifetimes::statedLifetime(value));
    if (!in)
      return owner.emitOpError("internal error: idr-frames: code moved out of it reads a value "
                               "of a lifetime that ends with its call");
    parameters.push_back({static_cast<std::uint32_t>(index), *in});
  }
  for (auto [index, type] : llvm::enumerate(results)) {
    if (!freedBy(type, Release::Scoped))
      continue;
    std::optional<std::uint32_t> in = parameterFor(resultsIn[index]);
    if (!in)
      return owner.emitOpError("internal error: idr-frames: code moved out of it gives a value "
                               "of a lifetime that ends with its call");
    scopedResults.push_back({static_cast<std::uint32_t>(index), *in});
  }
  Block &ownEntry = owner.getBody().front();
  if (LivesInAttr lives = owner.getLivesInAttr())
    for (const Outlives &bound : lives.getBounds())
      bounds.push_back({*parameterFor(ownEntry.getArgument(bound.longer)),
                        *parameterFor(ownEntry.getArgument(bound.shorter))});

  llvm::SmallVector<Type> inputs =
      llvm::map_to_vector(takes, [](Value value) { return value.getType(); });
  for (BlockArgument lifetime : ownLifetimes)
    inputs.push_back(lifetime.getType());
  auto fn = cast<FuncOp>(owner->cloneWithoutRegions());
  fn.setSymNameAttr(StringAttr::get(ctx, owner.getSymName() + "." + kind));
  fn.setFunctionTypeAttr(TypeAttr::get(FunctionType::get(ctx, inputs, results)));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setLivesInAttr(parameters.empty() && scopedResults.empty() && bounds.empty()
                        ? LivesInAttr()
                        : LivesInAttr::get(ctx, parameters, scopedResults, bounds));
  fn.setGivenBackAttr(nullptr);
  fn.setBindersAttr(binders.empty() ? IndexBindersAttr() : IndexBindersAttr::get(ctx, binders));
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : inputs)
    entry->addArgument(input, owner.getLoc());
  symbols.insert(fn, std::next(owner->getIterator()));

  Made out{fn, llvm::to_vector(takes)};
  llvm::append_range(out.args, ownLifetimes);
  return out;
}

// Every use inside `fn` of a lifetime of owner's scope, read from fn's own:
// each of owner's lifetimes is fn's at the same place, and a view of one
// that its moved code reads, `reads`, is taken again of fn's at its entry.
// Any other lifetime ends with owner's call, which nothing moved out of it
// may read: a room carved before it is memory of that call.
LogicalResult Component::adoptLifetimes(FuncOp owner, FuncOp fn, llvm::ArrayRef<Value> reads) {
  llvm::SmallVector<BlockArgument> own = lifetimesOf(fn);
  auto within = [&](OpOperand &use) { return fn->isProperAncestor(use.getOwner()); };
  for (auto [mine, theirs] : llvm::zip_equal(own, lifetimesOf(owner)))
    rewriter.replaceUsesWithIf(theirs, mine, within);
  for (Value lifetime : reads) {
    if (lifetime.getParentBlock() == &owner.getBody().front() && isa<BlockArgument>(lifetime))
      continue;
    auto forget = lifetime.getDefiningOp<LifetimeForgetOp>();
    std::optional<unsigned> place = placeOf(lifetime, owner);
    if (!forget || !place)
      return owner.emitOpError("internal error: idr-frames: code moved out of it reads a "
                               "lifetime that ends with its call");
    rewriter.setInsertionPointToStart(&fn.getBody().front());
    IRMapping view;
    view.map(forget->getOperand(0), own[*place]);
    Operation *again = rewriter.clone(*forget, view);
    rewriter.replaceUsesWithIf(lifetime, again->getResult(0), within);
  }
  return success();
}

// The ops of `first`'s block from `first` on moved into a function of
// their own, which takes `params` (values `first`'s code receives) and
// then what the code reads, and gives what the block's terminator gives,
// each scoped value where it goes; in their place a tail call of it, whose
// results the terminator gives.
FailureOr<CallOp> Component::outline(FuncOp owner, unsigned row, Operation *first,
                                     ValueRange params, llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  Block *block = first->getBlock();
  Operation *terminator = block->getTerminator();
  llvm::SmallVector<Value> read(params);
  for (Value value : liveIns(first))
    if (!llvm::is_contained(params, value))
      read.push_back(value);
  llvm::SmallVector<Value> takes = withoutLifetimes(read);
  llvm::SmallVector<Value> resultsIn;
  for (unsigned at = 0, given = terminator->getNumOperands(); at < given; ++at)
    resultsIn.push_back(givenIn(terminator, at));
  llvm::SmallVector<families::Sort> binders = scopeSorts(block->getParent());
  FailureOr<Made> moved =
      makeFunction(owner, kind, takes, terminator->getOperandTypes(), resultsIn, binders);
  if (failed(moved))
    return failure();
  FuncOp fn = moved->fn;
  Block *entry = &fn.getBody().front();

  // The code moves, so the ops the pass recorded stay the ops they are.
  entry->getOperations().splice(entry->end(), block->getOperations(), first->getIterator(),
                                terminator->getIterator());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, terminator->getLoc(), terminator->getOperands());
  for (auto [value, arg] : llvm::zip(takes, entry->getArguments()))
    rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
      return fn->isProperAncestor(use.getOwner());
    });
  llvm::SmallVector<Value> lifetimesRead = llvm::to_vector(llvm::make_filter_range(
      read, [](Value value) { return isa<LifetimeType>(value.getType()); }));
  if (failed(adoptLifetimes(owner, fn, lifetimesRead)))
    return failure();

  rewriter.setInsertionPoint(terminator);
  auto call = CallOp::create(rewriter, terminator->getLoc(), fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             moved->args, TailKind::tail);
  rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(call.getResults()); });
  made.push_back(call);
  functions.push_back({fn, row});
  return call;
}

// `call`, right after `rejoin` and taking its results, moved into each of
// its regions that rejoins it: each tail-calls the continuation with what
// it gives, and the op gives the continuation's results, each scoped one
// where the call says it lives, so it is in tail position once its block
// gives them.
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
  llvm::SmallVector<Value> outers;
  for (OpResult result : call->getResults())
    if (isScoped(result))
      outers.push_back(call.getStatedLifetime(result));
  Operation *remade = remakeGiving(rewriter, rejoin, call.getResultTypes(), outers);
  rewriter.replaceAllUsesWith(call.getResults(), remade->getResults());
  llvm::erase(made, call);
  rewriter.eraseOp(call);
  rewriter.eraseOp(rejoin);
}

// The changes of grade after each region op of the tail spine from `root`
// moved into the op's regions, before each region's end: every region op
// a tail runs through then gives what its function gives, type for type,
// each scoped result where the change of grade stated it, so a
// continuation made of the code after one gives it too.
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
    llvm::SmallVector<Value> livesIn = llvm::map_to_vector(
        source->getResults(), [](Value result) { return lifetimes::statedLifetime(result); });
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
      livesIn[at] = lifetimes::statedLifetime(regrade->getResult(0));
      rewriter.replaceAllUsesWith(regrade->getResult(0), source->getResult(at));
      rewriter.eraseOp(regrade);
    }
    if (!regrades.empty()) {
      llvm::SmallVector<Value> outers;
      for (auto [type, lifetime] : llvm::zip_equal(types, livesIn))
        if (freedBy(type, Release::Scoped))
          outers.push_back(lifetime);
      Operation *remade = remakeGiving(rewriter, source, types, outers);
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
      FailureOr<CallOp> continuation =
          outline(fn, row, join->getNextNode(), join->getResults(), "k");
      if (failed(continuation))
        return failure();
      sinkInto(join, *continuation);
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
      FailureOr<CallOp> continuation =
          outline(fn, row, lift->getNextNode(), lift->getResults(), "k");
      if (failed(continuation))
        return failure();
      sinkInto(lift, *continuation);
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
    FailureOr<CallOp> rest = outline(fn, row, site->getNextNode(), site->getResults(), "rest");
    if (failed(rest))
      return failure();
    framed.push_back({site, *rest});
  }
  return success();
}

} // namespace idr::tail::frames
