// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// effects: what idr-effects found a function may do, stated as the set the
// function holds, the one copy every call reads, not as the ops of a pass
// that happens to act on it. A function that holds none may do anything,
// as the dialect reads it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/StringExtras.h"

using namespace mlir;

namespace idr::expect {

// `@f:<e>+<e>...` or `@f:none`: every copy of @f is an idr.func whose
// effects are exactly the ones written, of io, crash and diverge.
LogicalResult solvedEffects(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "effects";
  auto [function, written] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  // The set as the enum spells it: its cases joined by its separator.
  std::string spelled = written.str();
  for (char &c : spelled)
    if (c == '+')
      c = ',';
  SmallVector<StringRef> cases;
  StringRef(spelled).split(cases, ',');
  std::string joined = llvm::join(cases, ", ");
  std::optional<Effect> wanted = symbolizeEffect(joined);
  if (!wanted)
    return fail(module.getLoc(), property)
           << "name the effects, as effects=@f:io+crash+diverge or effects=@f:none";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface each : functions) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (!fn) {
      fail(each->getLoc(), property) << where(each) << " is no idr.func, which holds its effects";
      held = false;
      continue;
    }
    Effect found = fn.getEffects().value_or(anyEffect);
    if (found == *wanted)
      continue;
    fail(fn.getLoc(), property) << where(fn) << " may do " << stringifyEffect(found) << ", not "
                                << stringifyEffect(*wanted);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
