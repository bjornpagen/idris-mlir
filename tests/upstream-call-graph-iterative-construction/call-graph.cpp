// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/93-call-graph-iterative-construction, checked on the pinned
// MLIR: the call graph of a module whose one function sits under
// operations nested DEPTH deep, built on a thread whose stack a native
// frame per level would overflow, has that function's node. The nesting
// is built in memory, since mlir-opt's parser recurses on the same depth
// through each operation's parse hook. Prints `ok` when the node is found,
// and says so otherwise.
#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
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

// The stack the call graph is built on: far below what a frame per level
// takes at the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// What the call graph holds of the function.
enum class Found { Missing, Node };

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  MLIRContext context;
  context.allowUnregisteredDialects();
  context.loadDialect<func::FuncDialect>();
  Location loc = UnknownLoc::get(&context);
  OwningOpRef<ModuleOp> module = ModuleOp::create(loc);

  // `depth` operations, each holding one region of one block, which holds
  // the next, and in the innermost a function with a body.
  OpBuilder builder = OpBuilder::atBlockEnd(module->getBody());
  std::vector<Operation *> ops;
  for (unsigned level = 0; level < depth; ++level) {
    OperationState state(loc, "test.nest");
    state.addRegion();
    ops.push_back(builder.create(state));
    builder.createBlock(&ops.back()->getRegion(0));
  }
  auto function = func::FuncOp::create(builder, loc, "leaf", builder.getFunctionType({}, {}));
  function.addEntryBlock();
  ops.push_back(function.getOperation());

  Found found = Found::Missing;
  llvm::thread construction(smallStack, [&] {
    CallGraph graph(module->getOperation());
    if (graph.lookupNode(&function.getBody()) != nullptr)
      found = Found::Node;
  });
  construction.join();

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  if (found == Found::Missing) {
    llvm::outs() << "the call graph has no node for the function\n";
    return 1;
  }
  llvm::outs() << "ok\n";
  return 0;
}
