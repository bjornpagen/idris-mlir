// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/80-walk-iterative, checked on the pinned MLIR: every kind of walk
// over operations nested DEPTH deep, on a thread whose stack a native frame
// per level would overflow, visits what the recursion visited. The nesting
// is built in memory, since mlir-opt's parser recurses on the same depth
// through each operation's parse hook. Prints `ok` when every walk holds,
// and a line for each that does not.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Iterators.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstddef>
#include <cstdlib>
#include <vector>

using namespace mlir;

namespace {

// The stack the walks run on: far below what a frame per level takes at
// the depths the check uses.
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

// What each walk gave against what it should, a line for each that
// differs.
struct Tally {
  unsigned wrong = 0;
  template <class T>
  void expect(const char *walk, T got, T want) {
    if (got == want)
      return;
    llvm::outs() << walk << ": " << got << ", not " << want << "\n";
    ++wrong;
  }
};

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  MLIRContext context;
  context.allowUnregisteredDialects();
  OwningOpRef<ModuleOp> module = ModuleOp::create(UnknownLoc::get(&context));
  std::vector<Operation *> ops = chain(*module, depth);
  Operation *root = module->getOperation();
  Operation *outermost = ops.front();
  Operation *leaf = ops.back();
  // The module and the chain; a region, and its one block, for the module
  // and for every operation of the chain but the leaf.
  std::size_t operations = depth + std::size_t{1};
  std::size_t regions = depth;

  Tally tally;
  llvm::thread walks(smallStack, [&] {
    std::size_t n = 0;
    root->walk([&](Operation *) { ++n; });
    tally.expect("post-order", n, operations);
    n = 0;
    root->walk<WalkOrder::PreOrder>([&](Operation *) { ++n; });
    tally.expect("pre-order", n, operations);
    n = 0;
    root->walk<WalkOrder::PostOrder, ReverseIterator>([&](Operation *) { ++n; });
    tally.expect("post-order, reversed", n, operations);
    n = 0;
    root->walk<WalkOrder::PreOrder, ForwardDominanceIterator<>>([&](Operation *) { ++n; });
    tally.expect("pre-order, in dominance order", n, operations);
    n = 0;
    root->walk<WalkOrder::PostOrder, ReverseDominanceIterator<>>([&](Operation *) { ++n; });
    tally.expect("post-order, in reverse dominance order", n, operations);
    n = 0;
    root->walk([&](Region *) { ++n; });
    tally.expect("regions", n, regions);
    n = 0;
    root->walk([&](Block *) { ++n; });
    tally.expect("blocks", n, regions);
    n = 0;
    root->walk([&](Operation *, const WalkStage &stage) {
      if (stage.isAfterAllRegions())
        ++n;
    });
    tally.expect("by stage, after all regions", n, operations);

    // An interrupt ends the walk at once: in pre-order at the leaf, after
    // every operation above it; in post-order at the leaf, the first.
    n = 0;
    WalkResult pre = root->walk<WalkOrder::PreOrder>([&](Operation *op) {
      ++n;
      return op == leaf ? WalkResult::interrupt() : WalkResult::advance();
    });
    tally.expect("pre-order, interrupted at the leaf", pre.wasInterrupted(), true);
    tally.expect("pre-order, operations before the interrupt", n, operations);
    n = 0;
    WalkResult post = root->walk([&](Operation *op) {
      ++n;
      return op == leaf ? WalkResult::interrupt() : WalkResult::advance();
    });
    tally.expect("post-order, interrupted at the leaf", post.wasInterrupted(), true);
    tally.expect("post-order, operations before the interrupt", n, std::size_t{1});

    // A pre-order skip passes over what the operation holds.
    n = 0;
    root->walk<WalkOrder::PreOrder>([&](Operation *op) {
      ++n;
      return op == outermost ? WalkResult::skip() : WalkResult::advance();
    });
    tally.expect("pre-order, skipping the chain", n, std::size_t{2});
  });
  walks.join();

  // Destroyed innermost first, each operation then holding an empty
  // region, so no destruction recurses and the check needs no other patch.
  for (auto at = ops.rbegin(); at != ops.rend(); ++at)
    (*at)->erase();
  if (tally.wrong != 0)
    return 1;
  llvm::outs() << "ok\n";
  return 0;
}
