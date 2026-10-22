// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/89-dataflow-iterative-initialization, checked on the pinned
// MLIR: a sparse forward analysis (constant propagation, with dead-code
// analysis) and a sparse backward one (liveness), initialized and run over
// operations nested DEPTH deep on a thread whose stack a native frame per
// level would overflow, each reach the innermost value: constant
// propagation gives it a state, and liveness finds it live, since an
// operation of unknown effects uses it. The operations are unregistered, so
// dead-code analysis takes each of their regions to be entered. The nesting
// is built in memory, since mlir-opt's parser recurses on the same depth
// through each operation's parse hook. Prints `ok` when both hold, and what
// they found otherwise.
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/LivenessAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack the analyses run on: far below what a frame per level takes at
// the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// A chain of `depth` operations in the module's body, each but the last
// two holding one region of one block, which holds the next; innermost, a
// value, and an operation of unknown effects that uses it. Outermost
// first.
std::vector<Operation *> chain(ModuleOp module, unsigned depth) {
  Location loc = UnknownLoc::get(module.getContext());
  OpBuilder builder = OpBuilder::atBlockEnd(module.getBody());
  std::vector<Operation *> ops;
  for (unsigned level = 2; level < depth; ++level) {
    OperationState state(loc, "test.nest");
    state.addRegion();
    ops.push_back(builder.create(state));
    builder.createBlock(&ops.back()->getRegion(0));
  }
  OperationState leaf(loc, "test.leaf");
  leaf.addTypes(builder.getI32Type());
  ops.push_back(builder.create(leaf));
  OperationState sink(loc, "test.sink");
  sink.addOperands(ops.back()->getResult(0));
  ops.push_back(builder.create(sink));
  return ops;
}

// What an analysis found of the innermost value.
enum class Found { NotRun, Missed, Reached };

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  if (depth < 3)
    return 2;
  MLIRContext context;
  context.allowUnregisteredDialects();
  OwningOpRef<ModuleOp> module = ModuleOp::create(UnknownLoc::get(&context));
  std::vector<Operation *> ops = chain(*module, depth);
  Value innermost = ops[ops.size() - 2]->getResult(0);

  Found constants = Found::NotRun;
  Found liveness = Found::NotRun;
  llvm::thread analyses(smallStack, [&] {
    SymbolTableCollection symbols;
    DataFlowSolver solver;
    solver.load<dataflow::DeadCodeAnalysis>();
    solver.load<dataflow::SparseConstantPropagation>();
    solver.load<dataflow::LivenessAnalysis>(symbols);
    if (failed(solver.initializeAndRun(module->getOperation())))
      return;
    const auto *constant =
        solver.lookupState<dataflow::Lattice<dataflow::ConstantValue>>(innermost);
    constants = constant != nullptr && !constant->getValue().isUninitialized() ? Found::Reached
                                                                               : Found::Missed;
    const auto *live = solver.lookupState<dataflow::Liveness>(innermost);
    liveness = live != nullptr && live->isLive ? Found::Reached : Found::Missed;
  });
  analyses.join();

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  if (constants == Found::Reached && liveness == Found::Reached) {
    llvm::outs() << "ok\n";
    return 0;
  }
  if (constants == Found::NotRun)
    llvm::outs() << "the analyses failed\n";
  if (constants == Found::Missed)
    llvm::outs() << "constant propagation gave the innermost value no state\n";
  if (liveness == Found::Missed)
    llvm::outs() << "liveness did not find the innermost value live\n";
  return 1;
}
