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

using namespace mlir;

namespace idr::expect {

// No closure is built, applied or kept as a constant, anywhere or in the
// function the argument names.
LogicalResult noClosures(ModuleOp module, AnalysisManager &, StringRef function) {
  SmallVector<Operation *> roots = rootsOf(module, function, "no-closures");
  if (roots.empty())
    return failure();
  bool held = true;
  for (Operation *root : roots)
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
      fail(op->getLoc(), "no-closures") << found << " in " << where(op);
      held = false;
    });
  return success(held);
}

// `@f:<position>:[@g, ...]`: at that position of every copy of @f, a
// result (`result`, `result<n>`) or a parameter (`arg<n>`), the type is a
// sum of labels, closures or a memo cell's, through a box or a grade, whose
// labels run exactly the functions the list names, each by `names`.
LogicalResult labels(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "labels";
  auto [function, rest] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  auto [position, list] = rest.split(':');
  bool result = position.consume_front("result");
  bool parameter = !result && position.consume_front("arg");
  unsigned index = 0;
  if ((!result && !parameter) || (!position.empty() && position.getAsInteger(10, index)) ||
      (parameter && position.empty()) || !list.starts_with("["))
    return fail(module.getLoc(), property)
           << "name the function, the position and the labels, as labels=@f:result:[@g, @h] "
              "or labels=@f:arg0:[@g]";
  SmallVector<StringRef> wanted = symbolList(list);
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    ArrayRef<Type> types = result ? fn.getResultTypes() : fn.getArgumentTypes();
    DataType sum = index < types.size() ? dataTypeOf(types[index]) : DataType();
    if (!sum || !llvm::is_contained({SumKind::Closures, SumKind::Memo}, sum.getKind())) {
      fail(fn->getLoc(), property) << where(fn) << " has no sum of labels at "
                                   << rest.split(':').first;
      held = false;
      continue;
    }
    // Each label's function, found by the symbol the label names.
    SmallVector<FunctionOpInterface> run;
    for (const Ctor &ctor : sum.getCtors())
      if (ctor.role == CtorRole::Label)
        if (auto callee = symbols.lookup<FunctionOpInterface>(ctor.fn.getAttr()))
          run.push_back(callee);
    auto ranBy = [&](StringRef g) {
      return llvm::any_of(run, [&](FunctionOpInterface label) { return names(label, g); });
    };
    bool same = run.size() == wanted.size() && llvm::all_of(wanted, ranBy);
    if (same)
      continue;
    InFlightDiagnostic error = fail(fn->getLoc(), property)
                               << "the sum at " << rest.split(':').first << " of " << where(fn)
                               << " runs";
    for (FunctionOpInterface label : run)
      error << " " << where(label);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
