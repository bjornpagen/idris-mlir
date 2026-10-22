// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/84-region-dce-iterative, checked on the pinned MLIR: region dead
// code elimination over operations nested DEPTH deep, each level holding a
// dead cast of its block's argument, on a thread whose stack frames per
// level would overflow, erases every dead cast and keeps every live
// operation. The nesting is built in memory, since mlir-opt's parser
// recurses on the same depth through each operation's parse hook. Prints
// `ok` when every check holds, and a line for each that does not.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstddef>
#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack region DCE runs on: far below what frames per level take at
// the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// A chain of `depth` operations (two at least) in the module's body, each
// but the last holding one region of one block of one argument, which
// holds a cast of that argument nothing uses, then the next; each but the
// first takes the argument of the block it is in. The chain's operations
// are unregistered, so their effects are unknown and each is live; the
// casts are pure and dead. Outermost first.
std::vector<Operation *> chain(ModuleOp module, unsigned depth) {
  MLIRContext *context = module.getContext();
  Location loc = UnknownLoc::get(context);
  Type word = IntegerType::get(context, 32);
  Type wide = IntegerType::get(context, 64);
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
    UnrealizedConversionCastOp::create(builder, loc, wide, argument);
  }
  OperationState leaf(loc, "test.leaf");
  leaf.addOperands(argument);
  ops.push_back(builder.create(leaf));
  return ops;
}

// The casts left in the blocks of the chain.
std::size_t castsIn(const std::vector<Operation *> &ops) {
  std::size_t casts = 0;
  for (Operation *op : ops)
    for (Region &region : op->getRegions())
      for (Operation &inner : region.front())
        if (isa<UnrealizedConversionCastOp>(inner))
          ++casts;
  return casts;
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

  Tally tally;
  tally.expect("dead casts before", castsIn(ops), depth - std::size_t{1});
  llvm::thread dce(smallStack, [&] {
    IRRewriter rewriter(&context);
    (void)runRegionDCE(rewriter, module->getOperation()->getRegions());
  });
  dce.join();
  tally.expect("dead casts after", castsIn(ops), std::size_t{0});
  std::size_t kept = 0;
  for (std::size_t level = 1; level < ops.size(); ++level)
    if (ops[level]->getParentOp() == ops[level - 1])
      ++kept;
  tally.expect("live operations kept in place", kept, depth - std::size_t{1});

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  if (tally.wrong != 0)
    return 1;
  llvm::outs() << "ok\n";
  return 0;
}
