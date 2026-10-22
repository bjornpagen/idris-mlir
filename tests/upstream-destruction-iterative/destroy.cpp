// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/83-destruction-iterative, checked on the pinned MLIR: operations
// nested DEPTH deep, each but the first using the argument of the block it
// is in, have their references dropped, are destroyed, and are deleted with
// a block that holds them, each on a thread whose stack a native frame per
// level would overflow. The nesting is built in memory, since mlir-opt's
// parser recurses on the same depth through each operation's parse hook.
// Prints `ok` when the module is empty after it, and says so otherwise; a
// destruction that overflows the stack ends the program by a signal.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstdlib>

using namespace mlir;

namespace {

// The stack the destruction runs on: far below what frames per level take
// at the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// A chain of `depth` operations (two at least) where `builder` inserts,
// each but the last holding one region of one block of one argument, which
// holds the next; each but the first takes the argument of the block it is
// in, so a use stays inside the chain until its references are dropped.
// Its outermost operation.
Operation *chain(OpBuilder &builder, unsigned depth) {
  MLIRContext *context = builder.getContext();
  Location loc = UnknownLoc::get(context);
  Type word = IntegerType::get(context, 32);
  Operation *outermost = nullptr;
  // The first operation is outside the chain's blocks: it takes nothing.
  Value argument;
  for (unsigned level = 1; level < depth; ++level) {
    OperationState state(loc, "test.nest");
    if (argument)
      state.addOperands(argument);
    state.addRegion();
    Operation *nest = builder.create(state);
    if (!outermost)
      outermost = nest;
    argument = builder.createBlock(&nest->getRegion(0))->addArgument(word, loc);
  }
  OperationState leaf(loc, "test.leaf");
  leaf.addOperands(argument);
  builder.create(leaf);
  return outermost;
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
  OpBuilder builder = OpBuilder::atBlockEnd(module->getBody());
  Operation *inModule = chain(builder, depth);
  auto *holder = new Block();
  builder.setInsertionPointToEnd(holder);
  chain(builder, depth);

  llvm::thread destruction(smallStack, [&] {
    inModule->dropAllReferences();
    inModule->erase();
    delete holder;
  });
  destruction.join();

  if (!module->getBody()->empty()) {
    llvm::outs() << "the module still holds operations\n";
    return 1;
  }
  llvm::outs() << "ok\n";
  return 0;
}
