// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/82-clone-iterative, checked on the pinned MLIR: cloning
// operations nested DEPTH deep, each but the first taking the argument of
// the block it is in, on a thread whose stack a native frame per level
// would overflow, copies every level and maps every operand to the copy's
// own argument. The nesting is built in memory, since mlir-opt's parser
// recurses on the same depth through each operation's parse hook. Prints
// `ok` when every check holds, and a line for each that does not.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstddef>
#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack the clone runs on: far below what a frame per level takes at
// the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// A chain of `depth` operations (two at least) in the module's body, each
// but the last holding one region of one block of one argument, which
// holds the next; each but the first takes the argument of the block it is
// in. Outermost first.
std::vector<Operation *> chain(ModuleOp module, unsigned depth) {
  MLIRContext *context = module.getContext();
  Location loc = UnknownLoc::get(context);
  Type word = IntegerType::get(context, 32);
  OpBuilder builder = OpBuilder::atBlockEnd(module.getBody());
  std::vector<Operation *> ops;
  // The first operation is outside the chain's blocks: it takes nothing.
  Value argument;
  for (unsigned level = 1; level < depth; ++level) {
    OperationState state(loc, "test.nest");
    if (argument)
      state.addOperands(argument);
    state.addRegion();
    ops.push_back(builder.create(state));
    argument = builder.createBlock(&ops.back()->getRegion(0))->addArgument(word, loc);
  }
  OperationState leaf(loc, "test.leaf");
  leaf.addOperands(argument);
  ops.push_back(builder.create(leaf));
  return ops;
}

// The chain from `outermost` in, through each operation's one block.
std::vector<Operation *> levels(Operation *outermost) {
  std::vector<Operation *> ops;
  for (Operation *op = outermost;; op = &op->getRegion(0).front().front()) {
    ops.push_back(op);
    if (op->getNumRegions() == 0)
      return ops;
  }
}

// Destroyed innermost first, each operation then holding an empty region,
// so no destruction recurses and the check needs no other patch.
void destroy(const std::vector<Operation *> &ops) {
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
}

// What each check gave against what it should, a line for each that
// differs.
struct Tally {
  unsigned wrong = 0;
  void expect(const char *check, std::size_t got, std::size_t want) {
    if (got == want)
      return;
    llvm::outs() << check << ": " << got << ", not " << want << "\n";
    ++wrong;
  }
};

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

  Operation *copy = nullptr;
  llvm::thread cloning(smallStack, [&] { copy = ops.front()->clone(); });
  cloning.join();

  Tally tally;
  std::vector<Operation *> copies = levels(copy);
  tally.expect("levels copied", copies.size(), depth);
  std::size_t mapped = 0;
  for (std::size_t level = 1; level < copies.size(); ++level)
    if (copies[level]->getOperand(0) == copies[level - 1]->getRegion(0).front().getArgument(0))
      ++mapped;
  tally.expect("operands mapped to the copy's own arguments", mapped, depth - std::size_t{1});

  destroy(copies);
  destroy(ops);
  if (tally.wrong != 0)
    return 1;
  llvm::outs() << "ok\n";
  return 0;
}
