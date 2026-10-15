// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a function's work happens, on the paths through its matches: a
// value is built only on the paths that use it, a value is tested once on
// a path, a check runs on every path, and nothing is written before a
// crash that may end the program. Each is a property of the paths, stated
// of every copy of the function (`named`), however the ops that show it
// are arranged.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The cases of a match, each an attribute: a literal's value, or a
// constructor's tag.
SmallVector<Attribute> casesOf(Operation *match) {
  if (auto lit = dyn_cast<MatchLitOp>(match))
    return llvm::to_vector(lit.getCases().getValue());
  auto data = cast<MatchOp>(match);
  Builder builder(data.getContext());
  SmallVector<Attribute> out;
  for (size_t index = 0, e = data.getCases().size(); index != e; ++index)
    out.push_back(builder.getI64IntegerAttr(data.getCaseTag(static_cast<unsigned>(index))));
  return out;
}

Value scrutineeOf(Operation *match) {
  if (auto lit = dyn_cast<MatchLitOp>(match))
    return lit.getScrutinee();
  return cast<MatchOp>(match).getScrutinee();
}

// The match around `inner`, on the same value, that already decides which
// region `inner` takes: `inner` sits in one of its cases, or in its default
// region and has no case it does not have. Null when there is none.
Operation *decidedBy(Operation *inner) {
  Value value = scrutineeOf(inner);
  SmallVector<Attribute> own = casesOf(inner);
  for (Operation *at = inner; Operation *outer = at->getParentOp(); at = outer) {
    if (!isa<MatchOp, MatchLitOp>(outer) || scrutineeOf(outer) != value)
      continue;
    SmallVector<Attribute> theirs = casesOf(outer);
    unsigned region = at->getParentRegion()->getRegionNumber();
    if (region < theirs.size())
      return outer;
    if (llvm::all_of(own, [&](Attribute key) { return llvm::is_contained(theirs, key); }))
      return outer;
  }
  return nullptr;
}

// Whether `op` may end the program by a crash: it writes the crash
// resource, on its own or through what it calls.
bool mayCrash(Operation *op) {
  auto effects = dyn_cast<MemoryEffectOpInterface>(op);
  if (!effects)
    return false;
  SmallVector<MemoryEffects::EffectInstance> all;
  effects.getEffects(all);
  return llvm::any_of(all, [](const MemoryEffects::EffectInstance &effect) {
    return isa<CrashResource>(effect.getResource());
  });
}

// Whether `op` writes output: it acts on the IO resource and cannot crash
// (a crash acts on it too, as the end of the program's output).
bool writesOutput(Operation *op) {
  auto effects = dyn_cast<MemoryEffectOpInterface>(op);
  if (!effects)
    return false;
  SmallVector<MemoryEffects::EffectInstance> all;
  effects.getEffects(all);
  bool io = false, crash = false;
  for (const MemoryEffects::EffectInstance &effect : all) {
    io |= isa<IOResource>(effect.getResource());
    crash |= isa<CrashResource>(effect.getResource());
  }
  return io && !crash;
}

// Whether some run of the function performs `first` before `second`: in
// the block that holds both, the op that holds `first` comes before the
// op that holds `second`. Two regions of one match are two paths, never
// one after the other.
bool mayRunBefore(Operation *first, Operation *second) {
  for (Operation *a = first; a; a = a->getParentOp())
    for (Operation *b = second; b; b = b->getParentOp())
      if (a->getBlock() && a->getBlock() == b->getBlock())
        return a != b && a->isBeforeInBlock(b);
  return false;
}

} // namespace

// Every value @f builds at run time is used in the block that builds it:
// none is built on a path that only one region of a later match takes.
LogicalResult buildsWhereUsed(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "builds-where-used";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<ConOp, ClosureOp, SuspendOp, DelayOp>(op) || op->use_empty())
        return;
      if (llvm::any_of(op->getUsers(),
                       [&](Operation *user) { return user->getBlock() == op->getBlock(); }))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op)
                                   << " builds a value only the regions of a later op use";
      held = false;
    });
  return success(held);
}

// No match in @f tests what an enclosing match on the same value already
// decided.
LogicalResult matchesOnce(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "matches-once";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<MatchOp, MatchLitOp>(op) || !decidedBy(op))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op)
                                   << " tests a value a match around it already decided";
      held = false;
    });
  return success(held);
}

// Nothing @f writes may be written before something that may crash: the
// output a crash cuts short is the output that came before it.
LogicalResult crashesBeforeOutput(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "crashes-before-output";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    SmallVector<Operation *> crashes, writes;
    fn->walk([&](Operation *op) {
      if (op->getNumRegions() != 0)
        return;
      if (mayCrash(op))
        crashes.push_back(op);
      else if (writesOutput(op))
        writes.push_back(op);
    });
    for (Operation *write : writes)
      for (Operation *crash : crashes)
        if (mayRunBefore(write, crash)) {
          fail(write->getLoc(), property) << write->getName() << " in " << where(write)
                                          << " may write before " << crash->getName()
                                          << ", which may crash";
          held = false;
        }
  }
  return success(held);
}

// Every parameter of @f is read in its body: one nothing reads is no
// parameter, and every call stops passing it.
LogicalResult parametersUsed(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "parameters-used";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    if (fn.isExternal())
      continue;
    for (BlockArgument parameter : fn.getArguments())
      if (parameter.use_empty()) {
        fail(fn->getLoc(), property) << "parameter " << parameter.getArgNumber() << " of "
                                     << where(fn) << " is not read";
        held = false;
      }
  }
  return success(held);
}

// Every result of every match in @f is used: a result no one reads is no
// result, and every region stops yielding it.
LogicalResult resultsUsed(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "results-used";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<MatchOp, MatchLitOp>(op))
        return;
      for (OpResult result : op->getResults())
        if (result.use_empty()) {
          fail(op->getLoc(), property) << "result " << result.getResultNumber() << " of "
                                       << op->getName() << " in " << where(op) << " is not used";
          held = false;
        }
    });
  return success(held);
}

// No match in @f has two regions that do the same: the same ops, from the
// same values, binding what they bind alike.
LogicalResult regionsDistinct(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "regions-distinct";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<MatchOp, MatchLitOp>(op))
        return;
      MutableArrayRef<Region> regions = op->getRegions();
      for (size_t i = 0; i < regions.size(); ++i)
        for (size_t j = i + 1; j < regions.size(); ++j)
          if (OperationEquivalence::isRegionEquivalentTo(&regions[i], &regions[j],
                                                         OperationEquivalence::IgnoreLocations)) {
            fail(op->getLoc(), property) << op->getName() << " in " << where(op) << " has regions "
                                         << i << " and " << j << " that do the same";
            held = false;
          }
    });
  return success(held);
}

// Every check in @f runs on every path through it: each guard is in a
// block of the body, not in a region of an op.
LogicalResult checksEveryPath(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "checks-every-path";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true, checked = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](GuardOpInterface guard) {
      checked = true;
      if (guard->getParentOp() == fn.getOperation())
        return;
      fail(guard->getLoc(), property) << guard->getName() << " in " << where(guard)
                                      << " runs on some paths only";
      held = false;
    });
  if (!checked) {
    fail(functions.front()->getLoc(), property) << "no check in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
