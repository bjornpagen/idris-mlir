// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/92-dead-code-iterative-initialization, checked on the pinned
// MLIR: dead-code analysis, initialized and run over operations nested
// DEPTH deep on a thread whose stack a native frame per level would
// overflow, finds the innermost block executable. The operations are
// unregistered, so the analysis takes each of their regions to be entered.
// The nesting is built in memory, since mlir-opt's parser recurses on the
// same depth through each operation's parse hook. Prints `ok` when the
// analysis holds, and what it found otherwise.
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack the analysis runs on: far below what a frame per level takes
// at the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// A chain of `depth` operations in the module's body, each but the last
// holding one region of one block, which holds the next; outermost first.
std::vector<Operation *> chain(ModuleOp module, unsigned depth) {
  Location loc = UnknownLoc::get(module.getContext());
  OpBuilder builder = OpBuilder::atBlockEnd(module.getBody());
  std::vector<Operation *> ops;
  for (unsigned level = 1; level < depth; ++level) {
    OperationState state(loc, "test.nest");
    state.addRegion();
    ops.push_back(builder.create(state));
    builder.createBlock(&ops.back()->getRegion(0));
  }
  OperationState leaf(loc, "test.leaf");
  ops.push_back(builder.create(leaf));
  return ops;
}

// What the analysis found of the innermost block.
enum class Found { Failed, Dead, Live };

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  if (depth < 2)
    return 2;
  MLIRContext context;
  context.allowUnregisteredDialects();
  OwningOpRef<ModuleOp> module = ModuleOp::create(UnknownLoc::get(&context));
  std::vector<Operation *> ops = chain(*module, depth);
  Block *innermost = ops.back()->getBlock();

  Found found = Found::Failed;
  llvm::thread analysis(smallStack, [&] {
    DataFlowSolver solver;
    solver.load<dataflow::DeadCodeAnalysis>();
    if (failed(solver.initializeAndRun(module->getOperation())))
      return;
    const auto *executable =
        solver.lookupState<dataflow::Executable>(solver.getProgramPointBefore(innermost));
    found = executable != nullptr && executable->isLive() ? Found::Live : Found::Dead;
  });
  analysis.join();

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  switch (found) {
  case Found::Failed:
    llvm::outs() << "the analysis failed\n";
    return 1;
  case Found::Dead:
    llvm::outs() << "the innermost block is not executable\n";
    return 1;
  case Found::Live:
    llvm::outs() << "ok\n";
    return 0;
  }
  return 1;
}
