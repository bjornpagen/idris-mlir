// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// constant-stack: what idr-tail-loops and idr-tail-calls guarantee of a
// function, stated as a property of the graph of references, not as the
// ops that happen to show it. It is stated of a lowered module as well as
// of an idr one, so it follows symbol uses, whatever ops make them.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

// A function's reference to another: by a call, guaranteed a tail call or
// not, or by a closure or an address that names it.
struct Reference {
  Operation *target;
  bool tailCall;
};

// The functions the body of each function refers to, read once per
// function. What the function's own attributes name (the clone it is) is
// provenance, not a call.
class Graph {
public:
  explicit Graph(SymbolTable &symbols) : symbols(symbols) {}

  // The answer lives in the map, so it holds until the next question.
  ArrayRef<Reference> of(Operation *fn) {
    auto [at, fresh] = read.try_emplace(fn);
    SmallVector<Reference> &out = at->second;
    if (!fresh)
      return out;
    Region &body = cast<FunctionOpInterface>(fn).getFunctionBody();
    if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
      for (const SymbolTable::SymbolUse &use : *uses) {
        Operation *target = symbols.lookup(use.getSymbolRef().getRootReference());
        if (!isa_and_nonnull<FunctionOpInterface>(target))
          continue;
        auto call = dyn_cast<LLVM::CallOp>(use.getUser());
        out.push_back(
            {target, call && call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::MustTail});
      }
    return out;
  }

  SmallVector<Operation *> targets(Operation *fn) {
    return llvm::map_to_vector(of(fn), [](Reference ref) { return ref.target; });
  }

private:
  SymbolTable &symbols;
  llvm::DenseMap<Operation *, SmallVector<Reference>> read;
};

} // namespace

// No recursion reachable from the function the argument names grows the
// stack: each function it may call, itself included, that is on a cycle
// of references refers to the others of its cycle only by guaranteed tail
// calls (`musttail`, which idr-tail-calls makes), each of which replaces
// its caller's frame; so before idr-tail-calls none may be on a cycle at
// all: every recursion became a loop. Functions without a body in the
// module call nothing back.
LogicalResult constantStack(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "constant-stack";
  SymbolTable &symbols = analyses.getAnalysis<SymbolTable>();
  SmallVector<Operation *> reached = llvm::map_to_vector(
      named(module, function, property),
      [](FunctionOpInterface fn) -> Operation * { return fn; });
  if (reached.empty())
    return failure();
  Graph graph(symbols);
  llvm::DenseSet<Operation *> seen(reached.begin(), reached.end());
  for (size_t next = 0; next < reached.size(); ++next)
    for (Reference ref : graph.of(reached[next]))
      if (seen.insert(ref.target).second)
        reached.push_back(ref.target);
  auto edges = [&](Operation *fn) { return graph.targets(fn); };
  bool held = true;
  for (const SmallVector<Operation *> &cycle : cycles(reached, edges)) {
    llvm::DenseSet<Operation *> members(cycle.begin(), cycle.end());
    bool grows = false;
    for (Operation *fn : cycle)
      for (Reference ref : graph.of(fn))
        grows |= members.contains(ref.target) && !ref.tailCall;
    if (!grows)
      continue;
    InFlightDiagnostic error = fail(cycle.front()->getLoc(), property)
                               << "the stack grows with the recursion of";
    for (Operation *fn : cycle)
      error << " " << where(fn);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
