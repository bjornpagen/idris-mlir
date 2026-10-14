// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-demand: the promise a program can be asked to keep, checked on the
// grades idr-rc wrote, when it is asked to; it changes nothing.
//
// in-place: a function that takes a parameter of quantity 1 apart and
// builds in its cell rebuilds it in place with no runtime test only when it
// holds that cell alone. Linearity says the function uses the value once,
// not that its caller held it alone; that is each call's to keep, and the
// grade idr-rc proved at the call says whether it does.
#include "idr/Transforms/Demand.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEMAND
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The value `value` is, seen through the positions that hand it on as
// itself: a linear position (idr.lin.enter, idr.lin.use), a view of it
// (idr.borrow, which a match reads), and the default region of a match on
// it, which takes the scrutinee back at its type.
Value itself(Value value) {
  for (;;) {
    if (Operation *def = value.getDefiningOp()) {
      if (!isa<idr::LinEnterOp, idr::LinUseOp, idr::BorrowOp>(def))
        return value;
      value = def->getOperand(0);
      continue;
    }
    auto arg = cast<BlockArgument>(value);
    auto match = dyn_cast_or_null<idr::MatchOp>(arg.getOwner()->getParentOp());
    if (!match || arg.getParentRegion() != match.getDefaultRegion())
      return value;
    value = match.getScrutinee();
  }
}

// The parameters `fn` rebuilds in place: those of quantity 1 whose cell an
// idr.reuse builds in, with the token of an idr.take of the parameter.
SmallVector<unsigned> rebuilt(idr::FuncOp fn) {
  SmallVector<unsigned> params;
  Block *entry = &fn.getBody().front();
  fn.walk([&](idr::ReuseOp reuse) {
    auto take = reuse.getToken().getDefiningOp<idr::TakeOp>();
    auto param = take ? dyn_cast<BlockArgument>(itself(take.getValue())) : BlockArgument();
    if (!param || param.getOwner() != entry || !idr::isLinear(param.getType()))
      return;
    if (!llvm::is_contained(params, param.getArgNumber()))
      params.push_back(param.getArgNumber());
  });
  return params;
}

// A call that passes a value other than an exclusive one where a promise
// asks for one: the function it is in, the call, the argument, and the
// idr.dup that shared the value there, when one did.
struct Broken {
  idr::FuncOp caller;
  idr::CallOp call;
  unsigned index;
  idr::DupOp dup;
};

void report(Broken broken) {
  Value value = broken.call.getArgs()[broken.index];
  InFlightDiagnostic error = broken.call.emitError();
  error << "unsupported (uniqueness): @" << broken.caller.getSymName() << " passes a shared "
        << idr::getSumName(value.getType()).getValue() << " to @" << broken.call.getCallee()
        << ", which rebuilds it in place";
  if (broken.dup)
    error.attachNote(broken.dup.getLoc()) << "shared here";
}

// Every call of a function passes each parameter the function rebuilds in
// place exclusive (`!idr.excl<T>`): an error at each call that shares it
// (passes what an idr.dup made), with a note at the idr.dup, or, when none
// does, at each call that passes it owned or as a view.
LogicalResult checkInPlace(ModuleOp module) {
  DenseMap<StringAttr, SmallVector<unsigned>> promised;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
    if (!fn.isExternal())
      if (SmallVector<unsigned> params = rebuilt(fn); !params.empty())
        promised[fn.getSymNameAttr()] = std::move(params);
  if (promised.empty())
    return success();

  SmallVector<Broken> broken;
  for (idr::FuncOp caller : module.getOps<idr::FuncOp>())
    caller.walk([&](idr::CallOp call) {
      auto found = promised.find(call.getCalleeAttr().getAttr());
      if (found == promised.end())
        return;
      for (unsigned index : found->second) {
        Value argument = call.getArgs()[index];
        if (!idr::isExclusive(argument.getType()))
          broken.push_back(
              {caller, call, index, idr::throughLinear(argument).getDefiningOp<idr::DupOp>()});
      }
    });
  // A call that shares the value there is the cause: each other one passes
  // on a value such a call shared (a function's call of itself on a part of
  // what it took apart), or one shared into the grade such a call set, and
  // is no error of its own. So the calls that share are reported, and the
  // others only when no call shares.
  bool shares = llvm::any_of(broken, [](const Broken &each) { return bool(each.dup); });
  for (const Broken &each : broken)
    if (bool(each.dup) == shares)
      report(each);
  return success(broken.empty());
}

struct Demand : idr::impl::IdrDemandBase<Demand> {
  using IdrDemandBase::IdrDemandBase;

  void runOnOperation() override {
    markAllAnalysesPreserved();
    if (inPlace && failed(checkInPlace(getOperation())))
      signalPassFailure();
  }
};

} // namespace
