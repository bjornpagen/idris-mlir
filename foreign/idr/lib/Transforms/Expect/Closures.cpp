// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-closures and labels: after defunctionalization, or where a test says
// every closure is gone, none is built, applied or kept as a constant; and
// what each closure or suspension became, the sum of the labels that reach
// it, stated as the functions its labels run, not as the printed type.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

#include <variant>

using namespace mlir;

namespace idr::expect {

// No closure is built, applied or kept as a constant, anywhere or in the
// function the argument names.
LogicalResult noClosures(const Request<Roots> &request) {
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](Operation *op) {
      StringRef found;
      if (isa<ClosureOp>(op))
        found = "a closure is built";
      else if (isa<ApplyOp>(op))
        found = "a closure is applied";
      else if (auto constant = dyn_cast<ConstantOp>(op);
               constant && isa<ClosureAttr>(constant.getValue()) && !isa<LazyType>(constant.getType()))
        found = "a closure is a constant";
      else
        return;
      fail(op->getLoc(), request.property) << found << " in " << where(op);
      held = false;
    });
  return success(held);
}

namespace {

// The position, for an error: `result <n>` or `parameter <n>`.
std::string spelled(Position position) {
  return ((position.kind == Position::Kind::Result ? "result " : "parameter ") +
          Twine(position.index))
      .str();
}

} // namespace

// At the position of every copy of @f, the type is a sum of labels,
// closures or a memo cell's, through a box or a grade, whose labels run
// exactly the functions the list names, each by `names`.
LogicalResult labels(const Request<Labels> &request) {
  const Labels &stated = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface fn : stated.function.functions) {
    Position at = stated.position;
    ArrayRef<Type> types =
        at.kind == Position::Kind::Result ? fn.getResultTypes() : fn.getArgumentTypes();
    DataType sum = at.index < types.size() ? dataTypeOf(types[at.index]) : DataType();
    if (!sum || !llvm::is_contained({SumKind::Closures, SumKind::Memo}, sum.getKind())) {
      fail(fn->getLoc(), request.property)
          << where(fn) << " has no sum of labels at " << spelled(at);
      held = false;
      continue;
    }
    // Each label's function, found by the symbol the label names.
    SmallVector<FunctionOpInterface> run;
    for (const Ctor &ctor : sum.getCtors())
      if (const auto *label = std::get_if<role::Label>(&ctor.role))
        if (auto callee = symbols.lookup<FunctionOpInterface>(label->fn.getAttr()))
          run.push_back(callee);
    auto ranBy = [&](const Symbol &g) {
      return llvm::any_of(run, [&](FunctionOpInterface label) { return names(label, g.name); });
    };
    bool same = run.size() == stated.names.size() && llvm::all_of(stated.names, ranBy);
    if (same)
      continue;
    InFlightDiagnostic error = fail(fn->getLoc(), request.property)
                               << "the sum at " << spelled(at) << " of " << where(fn) << " runs";
    for (FunctionOpInterface label : run)
      error << " " << where(label);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
