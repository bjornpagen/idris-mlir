// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a function's work happens, on the paths through its matches: a
// value is built, or a call made, only on the paths that use it, a value
// is tested once on a path, a check runs on every path, and nothing is
// written before a crash that may end the program. Each is a property of
// the paths, stated of every copy of the function (`names`), however the
// ops that show it are arranged.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/Twine.h"

#include <variant>

using namespace mlir;

namespace idr::expect {

namespace {

// A case of a match: a literal's value, or a constructor's tag. Two matches
// on one value are of one kind, so a key is only ever compared with one of
// its own alternative.
using Case = std::variant<Attribute, Tag>;

// The cases of a match, in their order: a literal match's values, or a
// constructor match's tags, which are what the two kinds differ in.
SmallVector<Case> casesOf(MatchOpInterface match) {
  SmallVector<Case> out;
  if (auto lit = dyn_cast<MatchLitOp>(match.getOperation())) {
    for (Attribute value : lit.getCases().getValue())
      out.push_back(value);
    return out;
  }
  auto data = cast<MatchOp>(match.getOperation());
  for (unsigned index : llvm::seq<unsigned>(0, data.getNumCases()))
    out.push_back(data.getCaseTag(index));
  return out;
}

// The match around `inner`, on the same value, that already decides which
// region `inner` takes: `inner` sits in one of its cases, or in its default
// region and has no case it does not have. Null when there is none.
Operation *decidedBy(MatchOpInterface inner) {
  Value value = inner.getScrutinee();
  SmallVector<Case> own = casesOf(inner);
  for (Operation *at = inner; Operation *parent = at->getParentOp(); at = parent) {
    auto outer = dyn_cast<MatchOpInterface>(parent);
    if (!outer || outer.getScrutinee() != value)
      continue;
    if (at->getParentRegion() != &outer.getDefaultRegion())
      return outer;
    SmallVector<Case> theirs = casesOf(outer);
    if (llvm::all_of(own, [&](const Case &key) { return llvm::is_contained(theirs, key); }))
      return outer;
  }
  return nullptr;
}

// A region of `match`, for an error: `case <n>`, or `the default`.
std::string regionName(MatchOpInterface match, Region &region) {
  if (&region == &match.getDefaultRegion())
    return "the default";
  return ("case " + Twine(match.caseOf(region))).str();
}

// What `op` may do of the two that order a program's output: perform IO,
// and end the program by a crash. An op says so by its own effects on the
// IO and the crash resources, a call by those it holds, its callee's. What
// MLIR knows nothing of states nothing here.
struct Order {
  bool io = false;
  bool crash = false;
};

Order orderOf(Operation *op) {
  Order out;
  std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = getEffectsRecursively(op);
  if (!effects)
    return out;
  for (const MemoryEffects::EffectInstance &effect : *effects) {
    out.io |= isa<IOResource>(effect.getResource());
    out.crash |= isa<CrashResource>(effect.getResource());
  }
  return out;
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
// none is built on a path that only one region of a later match takes. A
// constructor's value is built by idr.con, or, once cells are explicit, by
// the idr.cell.init that writes it into its cell.
LogicalResult buildsWhereUsed(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](Operation *op) {
      if (!op->hasTrait<BuildsValue>() || op->use_empty())
        return;
      if (llvm::any_of(op->getUsers(),
                       [&](Operation *user) { return user->getBlock() == op->getBlock(); }))
        return;
      fail(op->getLoc(), request.property) << op->getName() << " in " << where(op)
                                           << " builds a value only the regions of a later op use";
      held = false;
    });
  return success(held);
}

// Every call of @g or of a copy of it in every copy of @f whose results
// something uses is used in the block that holds it: none runs on a path
// that only a region of a later op takes.
LogicalResult callsWhereUsed(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface fn : pair.caller.functions)
    fn->walk([&](CallOpInterface call) {
      Operation *op = call.getOperation();
      if (op->use_empty() || !callsNamed(call, pair.callee, symbols))
        return;
      if (llvm::any_of(op->getUsers(),
                       [&](Operation *user) { return user->getBlock() == op->getBlock(); }))
        return;
      fail(op->getLoc(), request.property) << "a call of @" << pair.callee.name << " in "
                                           << where(op)
                                           << " runs where only the regions of a later op use it";
      held = false;
    });
  return success(held);
}

// No match in @f tests what an enclosing match on the same value already
// decided.
LogicalResult matchesOnce(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](MatchOpInterface match) {
      if (!decidedBy(match))
        return;
      fail(match->getLoc(), request.property) << match->getName() << " in " << where(match)
                                              << " tests a value a match around it already decided";
      held = false;
    });
  return success(held);
}

// Nothing @f writes may be written before something that may crash: the
// output a crash cuts short is the output that came before it.
LogicalResult crashesBeforeOutput(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions) {
    // A crash acts on the IO resource too, as the end of the program's
    // output, so what may crash is no write of output.
    SmallVector<Operation *> crashes, writes;
    fn->walk([&](Operation *op) {
      if (op->getNumRegions() != 0)
        return;
      Order order = orderOf(op);
      if (order.crash)
        crashes.push_back(op);
      else if (order.io)
        writes.push_back(op);
    });
    for (Operation *write : writes)
      for (Operation *crash : crashes)
        if (mayRunBefore(write, crash)) {
          fail(write->getLoc(), request.property) << write->getName() << " in " << where(write)
                                                  << " may write before " << crash->getName()
                                                  << ", which may crash";
          held = false;
        }
  }
  return success(held);
}

// Every parameter of @f is read in its body: one nothing reads is no
// parameter, and every call stops passing it.
LogicalResult parametersUsed(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions) {
    if (fn.isExternal())
      continue;
    for (BlockArgument parameter : fn.getArguments())
      if (parameter.use_empty()) {
        fail(fn->getLoc(), request.property) << "parameter " << parameter.getArgNumber() << " of "
                                             << where(fn) << " is not read";
        held = false;
      }
  }
  return success(held);
}

// Every result of every match in @f is used: a result no one reads is no
// result, and every region stops yielding it.
LogicalResult resultsUsed(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](MatchOpInterface match) {
      for (OpResult result : match->getResults())
        if (result.use_empty()) {
          fail(match->getLoc(), request.property)
              << "result " << result.getResultNumber() << " of " << match->getName() << " in "
              << where(match) << " is not used";
          held = false;
        }
    });
  return success(held);
}

// No match in @f has two regions that do the same: the same ops, from the
// same values, binding what they bind alike. An empty default, which an
// exhaustive match has, holds no block, and upstream's comparison finds
// no region with one alike.
LogicalResult regionsDistinct(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](MatchOpInterface match) {
      MutableArrayRef<Region> regions = match->getRegions();
      for (size_t i = 0; i < regions.size(); ++i)
        for (size_t j = i + 1; j < regions.size(); ++j)
          if (OperationEquivalence::isRegionEquivalentTo(&regions[i], &regions[j],
                                                         OperationEquivalence::IgnoreLocations)) {
            fail(match->getLoc(), request.property)
                << match->getName() << " in " << where(match) << " has "
                << regionName(match, regions[i]) << " and " << regionName(match, regions[j])
                << " that do the same";
            held = false;
          }
    });
  return success(held);
}

// Every check in @f runs on every path through it: each guard is in a
// block of the body, not in a region of an op.
LogicalResult checksEveryPath(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, checked = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](GuardOpInterface guard) {
      checked = true;
      if (guard->getParentOp() == fn.getOperation())
        return;
      fail(guard->getLoc(), request.property) << guard->getName() << " in " << where(guard)
                                              << " runs on some paths only";
      held = false;
    });
  if (!checked) {
    fail(functions.front()->getLoc(), request.property)
        << "no check in @" << request.argument.name;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
