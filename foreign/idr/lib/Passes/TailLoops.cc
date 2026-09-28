// idr-tail-loops: self tail calls become loops (LOW-TAIL-5, LOW-TAIL-4).
//
// A self tail call is a `func.call` of the enclosing function whose results
// are returned unchanged: it is the last op before the function's
// `func.return`, or before the `idr.yield` of a match region whose match is
// itself in tail position, and that terminator passes on exactly its results.
//
// A function with such a call becomes one `scf.while` over its arguments A.
// Its before region is the old body. Every tail position of the body now
// yields a payload (continue : i1, A, R):
//   - a self tail call yields (true, its arguments, poison R);
//   - any other result yields (false, poison A, the results R);
// the matches on the way yield the payload of their regions, and the region
// ends in `scf.condition(continue) A, R`. The after region passes A back to
// the before region, and the function returns the R of the loop's results.
//
// A function without `idr.total` may not terminate, so its loop gets
// `idr.may_loop`: a loop without effects whose results are unused would
// otherwise be trivially dead upstream (SEM-EVAL-5). Nothing here adds a
// progress guarantee.

#include "idr/Idr.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

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
  auto call = dyn_cast<func::CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

bool isTailMatch(Operation *op) { return isa<idr::MatchOp, idr::MatchLitOp>(op); }

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

struct TailLoops : idr::impl::IdrTailLoopsBase<TailLoops> {
  void runOnOperation() override {
    OpBuilder b(&getContext());
    for (auto fn : getOperation().getOps<func::FuncOp>()) {
      if (fn.isExternal() || !reachesTailCall(fn.getBody().front(), fn))
        continue;
      Loop{fn, fn.getArgumentTypes(), fn.getResultTypes(), b}.build();
    }
  }
};

} // namespace
