// idr-tail-loops: self tail calls become loops.
//
// A self tail call is a `func.call` of the enclosing function whose results
// are returned unchanged: it is the last op before the function's
// `func.return`, or before the `idr.yield` of a match region whose match is
// itself in tail position, and that terminator passes on exactly its results.
//
// Most such functions decide once per call whether to go round again: their
// body ends in a match whose results it returns, one region of which ends in
// the self tail call and the other reaches none. That function becomes the
// loop MLIR expects, in while-do form:
//   - the before region is the body up to the decision, and ends in
//     `scf.condition(continue)` over the arguments that change;
//   - the after region is the region that calls, its call's arguments
//     yielded as the next ones;
//   - the region that exits follows the loop, on the loop's results.
// Arguments the call passes unchanged are not carried at all, and code that
// depends on nothing the loop changes runs once, before it. A loop that
// counts up to a bound is then exactly what upstream's uplift recognizes,
// and becomes an scf.for with a trip count.
//
// Any other function with a self tail call becomes one `scf.while` over its
// arguments A whose before region is the old body. Every tail position of
// the body then yields a payload (continue : i1, A, R):
//   - a self tail call yields (true, its arguments, poison R);
//   - any other result yields (false, poison A, the results R);
// the matches on the way yield the payload of their regions, and the region
// ends in `scf.condition(continue) A, R`. The after region passes A back to
// the before region, and the function returns the R of the loop's results.
//
// A function without `idr.total` may not terminate, so its loop gets
// `idr.may_loop`: a loop without effects whose results are unused would
// otherwise be trivially dead upstream. Nothing here adds a
// progress guarantee.

#include "Ownership/Ownership.h"
#include "idr/Idr.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/LoopInvariantCodeMotionUtils.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTAILLOOPS
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// Whether `op` passes on exactly the results of the op just before it.
bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return prev && llvm::equal(prev->getResults(), terminator->getOperands());
}

bool isSelfCall(Operation *op, func::FuncOp fn) {
  auto call = dyn_cast_or_null<func::CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

bool isTailMatch(Operation *op) { return isa_and_nonnull<idr::MatchOp, idr::MatchLitOp>(op); }

// Whether the block, which ends in a tail position, reaches a self tail call.
bool reachesTailCall(Block &block, func::FuncOp fn) {
  Operation *terminator = block.getTerminator();
  if (!isa<func::ReturnOp, idr::YieldOp>(terminator) || !passesOnPrevious(terminator))
    return false;
  Operation *prev = terminator->getPrevNode();
  if (isSelfCall(prev, fn))
    return true;
  if (!isTailMatch(prev))
    return false;
  return llvm::any_of(prev->getRegions(), [&](Region &region) {
    return !region.empty() && reachesTailCall(region.front(), fn);
  });
}

// The general loop: the whole body in the before region, with a payload at
// every tail position.
struct Loop {
  func::FuncOp fn;
  TypeRange args;
  TypeRange results;
  OpBuilder &b;

  SmallVector<Value> poison(Location loc, TypeRange types) {
    return llvm::map_to_vector(types, [&](Type type) -> Value {
      return ub::PoisonOp::create(b, loc, type);
    });
  }

  Value flag(Location loc, bool value) {
    return arith::ConstantOp::create(b, loc, b.getBoolAttr(value));
  }

  // Rewrites the tail of `block`, which ends in a tail position, to compute
  // the payload (continue, A, R), and returns it. The block's terminator,
  // whose operands may be dropped, is left for the caller to replace.
  SmallVector<Value> payload(Block &block) {
    Operation *terminator = block.getTerminator();
    Location loc = terminator->getLoc();
    Operation *prev = passesOnPrevious(terminator) ? terminator->getPrevNode() : nullptr;
    SmallVector<Value> out;
    if (prev && isSelfCall(prev, fn)) {
      b.setInsertionPoint(prev);
      out.push_back(flag(loc, true));
      llvm::append_range(out, prev->getOperands());
      llvm::append_range(out, poison(loc, results));
      prev->dropAllUses();
      prev->erase();
      return out;
    }
    if (prev && isTailMatch(prev) && reachesTailCall(block, fn))
      return SmallVector<Value>(rebuildMatch(prev)->getResults());
    b.setInsertionPoint(terminator);
    out.push_back(flag(loc, false));
    llvm::append_range(out, poison(loc, args));
    llvm::append_range(out, terminator->getOperands());
    return out;
  }

  // The match `op`, with results (continue, A, R) and each region yielding
  // its payload. Regions that end in `ub.unreachable` are left alone.
  Operation *rebuildMatch(Operation *op) {
    SmallVector<Type> types{b.getI1Type()};
    llvm::append_range(types, args);
    llvm::append_range(types, results);
    OperationState state(op->getLoc(), op->getName());
    state.addOperands(op->getOperands());
    state.addTypes(types);
    state.addAttributes(llvm::to_vector(op->getDiscardableAttrs()));
    state.propertiesAttr = op->getPropertiesAsAttribute();
    for (Region &region : op->getRegions())
      state.addRegion()->takeBody(region);
    b.setInsertionPoint(op);
    Operation *match = b.create(state);
    op->dropAllUses();
    op->erase();
    for (Region &region : match->getRegions()) {
      if (region.empty())
        continue;
      auto yield = dyn_cast<idr::YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      SmallVector<Value> values = payload(region.front());
      b.setInsertionPoint(yield);
      idr::YieldOp::create(b, yield.getLoc(), values);
      yield.erase();
    }
    return match;
  }

  void build() {
    Block &entry = fn.getBody().front();
    Location loc = fn.getLoc();
    auto before = std::make_unique<Block>();
    for (BlockArgument arg : entry.getArguments())
      before->addArgument(arg.getType(), arg.getLoc());
    before->getOperations().splice(before->end(), entry.getOperations());
    for (auto [old, now] : llvm::zip(entry.getArguments(), before->getArguments()))
      old.replaceAllUsesWith(now);

    auto ret = cast<func::ReturnOp>(before->getTerminator());
    SmallVector<Value> values = payload(*before);
    b.setInsertionPoint(ret);
    scf::ConditionOp::create(b, ret.getLoc(), values.front(), ArrayRef(values).drop_front());
    ret.erase();
    if (!fn->hasAttr("idr.total")) {
      b.setInsertionPointToStart(before.get());
      idr::MayLoopOp::create(b, loc);
    }

    SmallVector<Type> carried(args);
    llvm::append_range(carried, results);
    b.setInsertionPointToEnd(&entry);
    auto loop = scf::WhileOp::create(b, loc, carried, entry.getArguments());
    loop.getBefore().push_back(before.release());
    Block *after = b.createBlock(&loop.getAfter(), loop.getAfter().end(), carried,
                                 SmallVector<Location>(carried.size(), loc));
    scf::YieldOp::create(b, loc, after->getArguments().take_front(args.size()));
    b.setInsertionPointToEnd(&entry);
    func::ReturnOp::create(b, loc, loop.getResults().drop_front(args.size()));
  }
};

// The body of a function that decides once per call whether to go round
// again: the match whose results it returns, the region of it that ends in
// the self tail call, and the one that reaches none.
struct Decision {
  Operation *match;
  Region *loops;
  Region *exits;
};

std::optional<Decision> decisionOf(func::FuncOp fn) {
  Operation *ret = fn.getBody().front().getTerminator();
  if (!passesOnPrevious(ret) || !isTailMatch(ret->getPrevNode()))
    return std::nullopt;
  Operation *match = ret->getPrevNode();
  if (match->getNumRegions() != 2)
    return std::nullopt;
  Decision decision{match, nullptr, nullptr};
  for (Region &region : match->getRegions()) {
    if (region.empty())
      return std::nullopt;
    Operation *end = region.front().getTerminator();
    if (isa<idr::YieldOp>(end) && passesOnPrevious(end) && isSelfCall(end->getPrevNode(), fn))
      decision.loops = &region;
    else if (!reachesTailCall(region.front(), fn))
      decision.exits = &region;
  }
  if (!decision.loops || !decision.exits)
    return std::nullopt;
  // The loop tests an integer against the one key of its case, or the
  // constructor of a value.
  if (auto lit = dyn_cast<idr::MatchLitOp>(match))
    if (!isa<IntegerType>(lit.getScrutinee().getType()) || lit.getCases().size() != 1)
      return std::nullopt;
  return decision;
}

// The loop of a function whose body is a decision (decisionOf).
class WhileDo {
public:
  WhileDo(func::FuncOp fn, Decision decision, idr::ownership::Counting &counting, OpBuilder &b)
      : fn(fn), decision(decision), counting(counting), b(b) {}

  // Builds the loop, or leaves the function as it was and fails when what
  // the regions need from the body cannot pass from one iteration to the
  // next as plain values: values that hold no reference.
  FailureOr<scf::WhileOp> build();

private:
  // The value `scope` sees for `value` of the body: the before region's
  // argument, the after region's, or the loop's result.
  enum class Scope { Before, After, Exit };
  Value in(Value value, Scope scope);
  // Where `scope`'s code begins: the before or after block, or the
  // function's block after the loop.
  Block *blockOf(Scope scope);
  // The `i1` that holds when the decision takes the region that loops,
  // built at the end of the before block.
  Value continues();
  // Moves the ops of `region` to the end of `scope`'s block, its arguments
  // (a case's fields) read from the scrutinee, and returns its terminator.
  Operation *inlineRegion(Region &region, Scope scope);

  func::FuncOp fn;
  Decision decision;
  idr::ownership::Counting &counting;
  OpBuilder &b;
  scf::WhileOp loop;
  // The arguments that change from one call to the next, by position.
  SmallVector<unsigned> carried;
  // What the body computes before the decision and the regions use: carried
  // by the loop after the arguments.
  SmallVector<Value> passed;
};

Block *WhileDo::blockOf(Scope scope) {
  switch (scope) {
  case Scope::Before:
    return loop.getBeforeBody();
  case Scope::After:
    return loop.getAfterBody();
  case Scope::Exit:
    return loop->getBlock();
  }
  llvm_unreachable("a scope");
}

Value WhileDo::in(Value value, Scope scope) {
  Block &entry = fn.getBody().front();
  auto arg = dyn_cast<BlockArgument>(value);
  unsigned slot;
  if (arg && arg.getOwner() == &entry) {
    const auto *it = llvm::find(carried, arg.getArgNumber());
    if (it == carried.end())
      return value;
    slot = static_cast<unsigned>(it - carried.begin());
  } else {
    const auto *it = llvm::find(passed, value);
    if (it == passed.end())
      return value;
    if (scope == Scope::Before)
      return value;
    slot = static_cast<unsigned>(carried.size()) + static_cast<unsigned>(it - passed.begin());
  }
  switch (scope) {
  case Scope::Before:
    return loop.getBeforeArguments()[slot];
  case Scope::After:
    return loop.getAfterArguments()[slot];
  case Scope::Exit:
    return loop.getResult(slot);
  }
  llvm_unreachable("a scope");
}

Value WhileDo::continues() {
  Operation *match = decision.match;
  bool loopsFirst = decision.loops->getRegionNumber() == 0;
  Location loc = match->getLoc();
  b.setInsertionPointToEnd(loop.getBeforeBody());
  // `(x == k) == loopsFirst`: region 0 is the case k, region 1 the default.
  auto test = [&](Value x, IntegerAttr k) -> Value {
    auto predicate = loopsFirst ? arith::CmpIPredicate::eq : arith::CmpIPredicate::ne;
    // A test of a flag is the flag, or the comparison it holds, turned
    // around.
    if (auto extended = x.getDefiningOp<arith::ExtUIOp>();
        extended && extended.getIn().getType().isInteger(1) && k.getValue().ule(1)) {
      x = extended.getIn();
      k = b.getIntegerAttr(x.getType(), k.getValue().trunc(1));
    }
    if (x.getType().isInteger(1)) {
      bool whenSet = (predicate == arith::CmpIPredicate::eq) == k.getValue().isOne();
      if (whenSet)
        return x;
      if (auto compare = x.getDefiningOp<arith::CmpIOp>())
        return arith::CmpIOp::create(b, loc, arith::invertPredicate(compare.getPredicate()),
                                     compare.getLhs(), compare.getRhs());
    }
    Value key = arith::ConstantOp::create(b, loc, k);
    return arith::CmpIOp::create(b, loc, predicate, x, key);
  };
  if (auto lit = dyn_cast<idr::MatchLitOp>(match))
    return test(in(lit.getScrutinee(), Scope::Before), cast<IntegerAttr>(lit.getCases()[0]));
  // Region 0 is the case of a constructor; region 1 is the default, or the
  // last case, which idr-lower also takes for any constructor Idris proved
  // impossible.
  auto sum = cast<idr::MatchOp>(match);
  Value scrutinee = in(sum.getScrutinee(), Scope::Before);
  auto name = cast<FlatSymbolRefAttr>(sum.getCases()[0]).getAttr();
  auto ctors = idr::lookupData(sum, scrutinee.getType()).getCtors();
  auto ctor = llvm::find_if(ctors, [&](idr::CtorOp c) { return c.getSymNameAttr() == name; });
  Value tag = idr::TagOp::create(b, loc, scrutinee);
  return test(tag, b.getI64IntegerAttr(ctor - ctors.begin()));
}

Operation *WhileDo::inlineRegion(Region &region, Scope scope) {
  Block &from = region.front();
  Block *to = blockOf(scope);
  // Uses of the body's values in the region see this scope's.
  region.walk([&](Operation *op) {
    for (OpOperand &operand : op->getOpOperands())
      operand.set(in(operand.get(), scope));
  });
  if (auto sum = dyn_cast<idr::MatchOp>(decision.match); sum && from.getNumArguments() != 0) {
    auto ctor = cast<FlatSymbolRefAttr>(sum.getCases()[region.getRegionNumber()]);
    Value scrutinee = in(sum.getScrutinee(), scope);
    idr::CtorOp decl = idr::lookupCtor(idr::lookupData(sum, scrutinee.getType()), ctor.getValue());
    b.setInsertionPointToEnd(to);
    for (BlockArgument field : from.getArguments()) {
      if (field.use_empty())
        continue;
      Type type = decl.getFieldType(field.getArgNumber());
      Value value = idr::FieldOp::create(b, field.getLoc(), type, scrutinee, ctor,
                                         b.getI64IntegerAttr(field.getArgNumber()));
      if (type != field.getType())
        value = idr::LinEnterOp::create(b, field.getLoc(), field.getType(), value);
      field.replaceAllUsesWith(value);
    }
  }
  to->getOperations().splice(to->end(), from.getOperations());
  return to->getTerminator();
}

FailureOr<scf::WhileOp> WhileDo::build() {
  Block &entry = fn.getBody().front();
  Operation *match = decision.match;
  auto call = cast<func::CallOp>(decision.loops->front().getTerminator()->getPrevNode());
  for (BlockArgument arg : entry.getArguments())
    if (call.getOperand(arg.getArgNumber()) != arg)
      carried.push_back(arg.getArgNumber());

  // The body before the decision: what depends only on arguments that do
  // not change, and holds no reference, runs once before the loop; the rest
  // runs in every iteration.
  SmallVector<Operation *> hoisted, repeated;
  llvm::SmallPtrSet<Operation *, 16> outside;
  auto invariant = [&](Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value))
      return arg.getOwner() == &entry && !llvm::is_contained(carried, arg.getArgNumber());
    return outside.contains(value.getDefiningOp());
  };
  for (Operation &op : llvm::make_range(entry.begin(), match->getIterator())) {
    bool once = op.getNumRegions() == 0 && isMemoryEffectFree(&op) &&
                llvm::all_of(op.getOperands(), invariant) &&
                llvm::none_of(op.getResults(), [&](Value r) { return counting.tracked(r); });
    if (once)
      outside.insert(&op);
    (once ? hoisted : repeated).push_back(&op);
  }
  // What the regions use of the repeated part passes from the before
  // region to the rest as a plain value, one that holds no reference; the
  // scrutinee of a match on a constructor too, whose fields the regions
  // read.
  llvm::SetVector<Value> needed;
  for (Region *region : {decision.loops, decision.exits})
    region->walk([&](Operation *op) {
      for (Value operand : op->getOperands())
        if (Operation *def = operand.getDefiningOp();
            def && def->getBlock() == &entry && !outside.contains(def))
          needed.insert(operand);
    });
  if (auto sum = dyn_cast<idr::MatchOp>(match))
    if (Operation *def = sum.getScrutinee().getDefiningOp(); def && !outside.contains(def))
      needed.insert(sum.getScrutinee());
  if (llvm::any_of(needed, [&](Value value) { return counting.tracked(value); }))
    return failure();
  // The before region passes every argument it has on to the rest, as the
  // uplift expects. A world or linear argument that the decision's code
  // already takes would then be taken twice.
  auto takenBefore = [&](unsigned index) {
    BlockArgument arg = entry.getArgument(index);
    return idr::quantityOf(arg.getType()) == idr::Quantity::One &&
           llvm::any_of(arg.getUsers(), [&](Operation *user) {
             Operation *top = entry.findAncestorOpInBlock(*user);
             return top && top->isBeforeInBlock(match);
           });
  };
  if (llvm::any_of(carried, takenBefore))
    return failure();
  passed = needed.takeVector();

  Location loc = fn.getLoc();
  SmallVector<Type> types;
  SmallVector<Value> initValues;
  for (unsigned index : carried) {
    types.push_back(entry.getArgument(index).getType());
    initValues.push_back(entry.getArgument(index));
  }
  SmallVector<Type> through(types);
  for (Value value : passed)
    through.push_back(value.getType());
  b.setInsertionPoint(match);
  loop = scf::WhileOp::create(b, loc, through, initValues);
  SmallVector<Location> locs(through.size(), loc);
  Block *before = b.createBlock(&loop.getBefore(), {}, types, ArrayRef(locs).take_front(types.size()));
  b.createBlock(&loop.getAfter(), {}, through, locs);
  for (Operation *op : repeated) {
    op->moveBefore(before, before->end());
    op->walk([&](Operation *inner) {
      for (OpOperand &operand : inner->getOpOperands())
        operand.set(in(operand.get(), Scope::Before));
    });
  }
  Value go = continues();
  SmallVector<Value> forwarded(loop.getBeforeArguments());
  llvm::append_range(forwarded, passed);
  scf::ConditionOp::create(b, match->getLoc(), go, forwarded);

  // The region that loops: its call's arguments are the next iteration's.
  Operation *yield = inlineRegion(*decision.loops, Scope::After);
  auto next = cast<func::CallOp>(yield->getPrevNode());
  b.setInsertionPoint(yield);
  SmallVector<Value> values;
  for (unsigned index : carried)
    values.push_back(next.getOperand(index));
  scf::YieldOp::create(b, yield->getLoc(), values);
  yield->erase();
  next.erase();
  if (!fn->hasAttr("idr.total")) {
    b.setInsertionPointToStart(loop.getAfterBody());
    idr::MayLoopOp::create(b, loc);
  }

  // The region that exits runs after the loop; the function returns what
  // it yields.
  // The region's ops go after the return, which then makes way for them.
  Operation *ret = entry.getTerminator();
  Operation *exit = inlineRegion(*decision.exits, Scope::Exit);
  ret->erase();
  b.setInsertionPoint(exit);
  if (auto result = dyn_cast<idr::YieldOp>(exit)) {
    func::ReturnOp::create(b, result.getLoc(), result.getResults());
  } else {
    // A region that crashes: no function body ends in ub.unreachable
    // (PINS.md: inline-unreachable), so the function returns poison, which
    // is never reached.
    SmallVector<Value> none = llvm::map_to_vector(fn.getResultTypes(), [&](Type type) -> Value {
      return ub::PoisonOp::create(b, exit->getLoc(), type);
    });
    func::ReturnOp::create(b, exit->getLoc(), none);
  }
  exit->erase();
  match->erase();
  // What only the decision read (a flag widened for it, a comparison
  // turned around) is left over. The ops are listed first: a reverse
  // iterator refers to the op after the one it yields, which may go too.
  SmallVector<Operation *> body =
      llvm::map_to_vector(before->without_terminator(), [](Operation &op) { return &op; });
  for (Operation *op : llvm::reverse(body))
    if (isOpTriviallyDead(op))
      op->erase();
  return loop;
}

// Whether the value a counted loop's counter ends with is used after it.
// Upstream's uplift gives that value as the counter of the last iteration,
// one step short of what the loop ends with (PINS.md:
// uplift-final-counter), so such a loop stays an scf.while.
bool counterUsedAfter(scf::WhileOp loop) {
  Block *before = loop.getBeforeBody();
  auto compare = dyn_cast<arith::CmpIOp>(before->front());
  if (!compare)
    return false;
  for (Value side : {compare.getLhs(), compare.getRhs()})
    if (auto arg = dyn_cast<BlockArgument>(side); arg && arg.getOwner() == before)
      if (!loop.getResult(arg.getArgNumber()).use_empty())
        return true;
  return false;
}

// Whether `op`, in a loop, may run once before it instead: it has no
// effect, cannot fail, and holds no reference, so no count changes
// whichever iteration's copy it is.
bool invariantCode(Operation *op, idr::ownership::Counting &counting) {
  return isMemoryEffectFree(op) && isSpeculatable(op) &&
         llvm::none_of(op->getResults(), [&](Value result) { return counting.tracked(result); });
}

struct TailLoops : idr::impl::IdrTailLoopsBase<TailLoops> {
  void runOnOperation() override {
    OpBuilder b(&getContext());
    idr::ownership::Counting counting(getOperation());
    SmallVector<scf::WhileOp> loops;
    for (auto fn : getOperation().getOps<func::FuncOp>()) {
      if (fn.isExternal() || !reachesTailCall(fn.getBody().front(), fn))
        continue;
      ++numLoops;
      if (std::optional<Decision> decision = decisionOf(fn)) {
        FailureOr<scf::WhileOp> loop = WhileDo(fn, *decision, counting, b).build();
        if (succeeded(loop)) {
          loops.push_back(*loop);
          continue;
        }
      }
      Loop{fn, fn.getArgumentTypes(), fn.getResultTypes(), b}.build();
    }
    // Code that the loop does not change moves out of it, and a loop that
    // counts to a bound becomes an scf.for.
    for (scf::WhileOp loop : loops)
      moveLoopInvariantCode(
          loop.getLoopRegions(),
          [&](Value value, Region *) { return loop.isDefinedOutsideOfLoop(value); },
          [&](Operation *op, Region *) { return invariantCode(op, counting); },
          [&](Operation *op, Region *) { loop.moveOutOfLoop(op); });
    RewritePatternSet uplift(&getContext());
    scf::populateUpliftWhileToForPatterns(uplift);
    FrozenRewritePatternSet frozen(std::move(uplift));
    for (scf::WhileOp loop : loops) {
      if (counterUsedAfter(loop))
        continue;
      bool erased = false;
      if (failed(applyOpPatternsGreedily({loop.getOperation()}, frozen,
                                         GreedyRewriteConfig().enableFolding(false).setStrictness(
                                             GreedyRewriteStrictness::ExistingOps),
                                         /*changed=*/nullptr, &erased)))
        return signalPassFailure();
      if (erased)
        ++numCounted;
    }
  }
};

} // namespace
