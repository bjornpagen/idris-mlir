// idr-tail-loops: every function with a self tail call becomes an scf.while
// loop (LOW-TAIL-1, LOW-TAIL-2, SEM-RES-2).

#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTAILLOOPS
#define GEN_PASS_DEF_IDRENTRY
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

bool isSelfCall(Value value, func::FuncOp fn) {
  auto call = value.getDefiningOp<func::CallOp>();
  return call && call.getCallee() == fn.getSymName() && value.hasOneUse();
}

// A region op whose single result is `value`, used only by one terminator.
Operation *tailRegionOp(Value value) {
  Operation *op = value.getDefiningOp();
  if (!op || !isa<scf::IfOp, scf::IndexSwitchOp>(op) || op->getNumResults() != 1 ||
      !value.hasOneUse())
    return nullptr;
  return op;
}

// LOW-TAIL-1: `value` reaches the function's result through tail positions
// only, and at least one of them is a self call.
bool hasSelfTailCall(Value value, func::FuncOp fn) {
  if (isSelfCall(value, fn))
    return true;
  Operation *op = tailRegionOp(value);
  if (!op)
    return false;
  for (Region &region : op->getRegions())
    if (!region.empty() &&
        hasSelfTailCall(region.front().getTerminator()->getOperand(0), fn))
      return true;
  return false;
}

struct Loop {
  func::FuncOp fn;
  TypeRange argTypes;
  Type resultType;
  IRRewriter &rewriter;
  SmallVector<Operation *> dead; // replaced, erased once no longer used

  Value poison(Location loc, Type type) {
    return ub::PoisonOp::create(rewriter, loc, type);
  }

  Value flag(Location loc, bool value) {
    return arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(value));
  }

  // Replaces the tail value `value`, used by `terminator`, by
  // (continue?, next arguments..., result).
  SmallVector<Value> tailify(Value value, Operation *terminator) {
    Location loc = value.getLoc();
    if (isSelfCall(value, fn)) {
      auto call = value.getDefiningOp<func::CallOp>();
      rewriter.setInsertionPoint(call);
      SmallVector<Value> out{flag(loc, true)};
      llvm::append_range(out, call.getOperands());
      out.push_back(poison(loc, resultType));
      dead.push_back(call);
      return out;
    }
    SmallVector<Type> types{rewriter.getI1Type()};
    types.append(argTypes.begin(), argTypes.end());
    types.push_back(resultType);
    if (Operation *op = tailRegionOp(value)) {
      rewriter.setInsertionPoint(op);
      Operation *replacement;
      if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
        auto next = scf::IfOp::create(rewriter, op->getLoc(), types,
                                      ifOp.getCondition(), false, false);
        next.getThenRegion().takeBody(ifOp.getThenRegion());
        next.getElseRegion().takeBody(ifOp.getElseRegion());
        replacement = next;
      } else {
        auto sw = cast<scf::IndexSwitchOp>(op);
        auto next = scf::IndexSwitchOp::create(rewriter, op->getLoc(), types,
                                               sw.getArg(), sw.getCases(),
                                               static_cast<unsigned>(sw.getCaseRegions().size()));
        next.getDefaultRegion().takeBody(sw.getDefaultRegion());
        for (auto [to, from] : llvm::zip(next.getCaseRegions(), sw.getCaseRegions()))
          to.takeBody(from);
        replacement = next;
      }
      for (Region &region : replacement->getRegions()) {
        Operation *yield = region.front().getTerminator();
        SmallVector<Value> values = tailify(yield->getOperand(0), yield);
        rewriter.setInsertionPoint(yield);
        rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, values);
      }
      SmallVector<Value> out(replacement->getResults());
      dead.push_back(op);
      return out;
    }
    // Not a tail call: stop with this result.
    rewriter.setInsertionPoint(terminator);
    SmallVector<Value> out{flag(loc, false)};
    for (Type type : argTypes)
      out.push_back(poison(loc, type));
    out.push_back(value);
    return out;
  }

  void run() {
    Block &body = fn.getBody().front();
    auto ret = cast<func::ReturnOp>(body.getTerminator());
    Location loc = fn.getLoc();
    size_t n = argTypes.size();

    // The old body becomes the loop's "before" region.
    Block *entry = rewriter.createBlock(&fn.getBody(), fn.getBody().begin(),
                                        argTypes,
                                        SmallVector<Location>(static_cast<unsigned>(n), loc));
    SmallVector<Type> forwarded(argTypes.begin(), argTypes.end());
    forwarded.push_back(resultType);
    rewriter.setInsertionPointToEnd(entry);
    auto loop = scf::WhileOp::create(rewriter, loc, forwarded,
                                     entry->getArguments());
    func::ReturnOp::create(rewriter, loc, loop.getResult(static_cast<unsigned>(n)));

    body.moveBefore(&loop.getBefore(), loop.getBefore().end());
    SmallVector<Value> values = tailify(ret.getOperand(0), ret);
    rewriter.setInsertionPoint(ret);
    rewriter.replaceOpWithNewOp<scf::ConditionOp>(
        ret, values.front(), ArrayRef<Value>(values).drop_front());

    Block *after = rewriter.createBlock(&loop.getAfter(), {}, forwarded,
                                        SmallVector<Location>(static_cast<unsigned>(n + 1), loc));
    rewriter.setInsertionPointToEnd(after);
    scf::YieldOp::create(rewriter, loc, after->getArguments().take_front(n));
    // Outer ops were recorded after the ops they contain; their uses are gone.
    for (Operation *op : llvm::reverse(dead))
      rewriter.eraseOp(op);
  }
};

// The root is referenced only from the module's idr.entry attribute, which
// symbol-dce and the inliner do not count as a use. Making it public until
// idr-lower creates the C entry point keeps it alive.
struct Entry : idr::impl::IdrEntryBase<Entry> {
  void runOnOperation() override {
    auto entry = getOperation()->getAttrOfType<FlatSymbolRefAttr>("idr.entry");
    auto root = entry ? getOperation().lookupSymbol<func::FuncOp>(entry.getAttr())
                      : func::FuncOp();
    if (!root) {
      getOperation().emitError("internal error: idr.entry does not name a function");
      return signalPassFailure();
    }
    root.setPublic();
  }
};

struct TailLoops : idr::impl::IdrTailLoopsBase<TailLoops> {
  void runOnOperation() override {
    IRRewriter rewriter(&getContext());
    for (auto fn : llvm::make_early_inc_range(getOperation().getOps<func::FuncOp>())) {
      if (fn.isExternal() || !fn.getBody().hasOneBlock() || fn.getNumResults() != 1)
        continue;
      auto ret = dyn_cast<func::ReturnOp>(fn.getBody().front().getTerminator());
      if (!ret || !hasSelfTailCall(ret.getOperand(0), fn))
        continue;
      Loop{fn, fn.getArgumentTypes(), fn.getResultTypes()[0], rewriter, {}}.run();
    }
    // LOW-TAIL-2: no self tail call remains.
    bool ok = true;
    getOperation().walk([&](func::ReturnOp ret) {
      auto fn = ret->getParentOfType<func::FuncOp>();
      if (ret->getParentOp() == fn && ret.getNumOperands() == 1 &&
          hasSelfTailCall(ret.getOperand(0), fn)) {
        ret.emitError("internal error: self tail call survived idr-tail-loops");
        ok = false;
      }
    });
    if (!ok)
      signalPassFailure();
  }
};

} // namespace
