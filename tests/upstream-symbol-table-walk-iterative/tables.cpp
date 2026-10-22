// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/88-symbol-table-walk-iterative, checked on the pinned MLIR:
// SymbolTable::walkSymbolTables, over a module holding operations nested
// DEPTH deep with a module innermost, on a thread whose stack a native
// frame per level would overflow, gives its callback the two symbol tables
// as the recursion did: the inner one first, after everything nested in
// it, with every use of its symbols visible, since the operations around
// it are no symbol table; then the outer one, public, so not every use of
// its symbols is visible. The nesting is built in memory, since mlir-opt's
// parser recurses on the same depth through each operation's parse hook.
// Prints `ok` when the walk holds, and what it found otherwise.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack the walk runs on: far below what a frame per level takes at
// the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// Whether every use of a symbol table's symbols is visible, as the walk
// says of it.
enum class Uses { SomeHidden, AllVisible };

// A symbol table the walk gave its callback, and what it said of its uses.
struct Visited {
  Operation *table;
  Uses uses;
};

// A chain of `depth` operations in the module's body, each holding one
// region of one block, which holds the next, and a module innermost;
// outermost first.
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
  ops.push_back(ModuleOp::create(builder, loc).getOperation());
  return ops;
}

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
  Operation *inner = ops.back();
  Operation *outer = module->getOperation();

  std::vector<Visited> visited;
  llvm::thread walk(smallStack, [&] {
    SymbolTable::walkSymbolTables(outer, /*allSymUsesVisible=*/false,
                                  [&](Operation *table, bool allUsesVisible) {
                                    visited.push_back(
                                        {table, allUsesVisible ? Uses::AllVisible
                                                               : Uses::SomeHidden});
                                  });
  });
  walk.join();

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  bool held = visited.size() == 2 && visited[0].table == inner &&
              visited[0].uses == Uses::AllVisible && visited[1].table == outer &&
              visited[1].uses == Uses::SomeHidden;
  if (held) {
    llvm::outs() << "ok\n";
    return 0;
  }
  llvm::outs() << "the walk gave " << visited.size() << " symbol tables:";
  for (const Visited &each : visited) {
    llvm::StringRef which = each.table == inner   ? "the inner module"
                            : each.table == outer ? "the outer module"
                                                  : "another operation";
    llvm::StringRef uses =
        each.uses == Uses::AllVisible ? "all uses visible" : "some uses hidden";
    llvm::outs() << " " << which << " (" << uses << ")";
  }
  llvm::outs() << "\n";
  return 1;
}
