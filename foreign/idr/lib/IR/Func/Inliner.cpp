// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inliner's rules for the dialect, as func's are for its own: every
// call may be inlined, and every op and region may move into another
// function. Which calls are worth it is the inlining pass's decision. A
// callee's body is one block: it ends in idr.return, whose operands become
// the call's results; or in an op with no successor (a crash, an exit),
// after which nothing of the caller's runs, so the caller's rest goes into
// a block nothing reaches, which each site that inlines erases.
//
// A lifetime of any kind may be passed where a view is asked, which upstream
// meets as a type that differs at the call: the parameter becomes the
// view of the lifetime given, `idr.lifetime.forget`, the one op whose result
// is its operand's view, defined where the argument is in scope.
//
// Each call the body holds moves to a new place, so its tail fact is
// decided again there, by the one definition of tail position, as every
// call's is from the first-order program on.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

struct IdrInlinerInterface : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;

  bool isLegalToInline(Operation *, Operation *, bool) const final { return true; }
  bool isLegalToInline(Region *, Region *, bool, IRMapping &) const final { return true; }
  bool isLegalToInline(Operation *, Region *, bool, IRMapping &) const final { return true; }

  // The body goes in as its block where it returns; where it ends in an op
  // with no successor, upstream's own path splits the caller's block, so
  // that op stays the last of its block.
  bool allowSingleBlockOptimization(iterator_range<Region::iterator> inlined) const final {
    return llvm::hasSingleElement(inlined) && isa<ReturnOp>(inlined.begin()->getTerminator());
  }

  // The callee's return: the call's results are what it gives back, and
  // the inliner erases it.
  void handleTerminator(Operation *op, ValueRange valuesToRepl) const final {
    auto ret = cast<ReturnOp>(op);
    for (auto [replaced, value] : llvm::zip_equal(valuesToRepl, ret.getOperands()))
      replaced.replaceAllUsesWith(value);
  }

  // A body that ends with no successor goes on to nothing, so it branches to
  // none of the caller's blocks.
  void handleTerminator(Operation *, Block *) const final {}

  // A call the body holds gives its results where the call it replaced gave
  // its own, so it is in tail position, or a self call of the caller modulo
  // a context, exactly where it was so in the body and the call it replaced
  // was in tail position; anywhere else it is an ordinary call. Upstream
  // calls this while the body still ends in the callee's return, so the one
  // decider reads each held call's place in the body, and the replaced
  // call's own fact, the decider's answer at its place, says the rest.
  void processInlinedCallBlocks(Operation *call,
                                iterator_range<Region::iterator> inlined) const final {
    TailKind replaced = cast<CallOp>(call).getTailKind();
    for (Block &block : inlined)
      block.walk([&](CallOp held) {
        held.setTailKind(replaced == TailKind::tail ? tail::decide(held) : TailKind::nontail);
      });
  }

  // A lifetime passed where a view is asked: the view of it.
  Operation *materializeCallConversion(OpBuilder &builder, Value input, Type resultType,
                                       Location conversionLoc) const final {
    if (!lifetimes::passesAs(input.getType(), resultType))
      return nullptr;
    return LifetimeForgetOp::create(builder, conversionLoc, resultType, input);
  }
};

} // namespace

void idr::addInlinerInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrInlinerInterface>();
}
