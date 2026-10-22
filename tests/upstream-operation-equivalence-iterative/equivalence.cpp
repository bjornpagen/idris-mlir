// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/90-operation-equivalence-iterative, checked on the pinned MLIR:
// OperationEquivalence compares operations nested DEPTH deep on a thread
// whose stack a native frame per level would overflow, and answers as the
// recursion did. Each chain is DEPTH operations, each with a result and one
// region of one block with an argument, which holds the next operation and
// then a use of the argument; innermost, a region of two blocks, the first
// branching to the second and the second to a block of the same region. Two
// chains whose innermost branches go to the same block are equivalent by
// both entry points, and the comparison marks each pair of values once, in
// the order the recursion marked them: each operation's result, then its
// block's argument, down the chain, then the uses back up. A chain whose
// innermost branch goes to the other block is not equivalent to them,
// though everything above it is alike. The chains are built in memory,
// since mlir-opt's parser recurses on the same depth through each
// operation's parse hook. Prints `ok` when every comparison holds, and what
// it found otherwise.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/thread.h"

#include <cstddef>
#include <cstdlib>
#include <utility>
#include <vector>

using namespace mlir;

namespace {

// The stack the comparisons run on: far below what a frame per level takes
// at the depths the check uses.
constexpr unsigned smallStack = 256 * 1024;

// Where the second block of the innermost region branches: to itself, or
// back to the first.
enum class Innermost { ToItself, ToTheFirst };

// A chain, outermost first, and its values in the order a comparison of
// two such chains marks them.
struct Chain {
  std::vector<Operation *> levels;
  std::vector<Value> marked;
};

Chain chain(MLIRContext &context, unsigned depth, Innermost innermost) {
  OpBuilder b(&context);
  Location loc = b.getUnknownLoc();
  Type i32 = b.getI32Type();
  Chain made;
  std::vector<Block *> bodies;
  for (unsigned level = 0; level < depth; ++level) {
    OperationState nest(loc, "check.nest");
    nest.addTypes(i32);
    nest.addRegion();
    made.levels.push_back(b.create(nest));
    made.marked.push_back(made.levels.back()->getResult(0));
    bodies.push_back(b.createBlock(&made.levels.back()->getRegion(0), {}, {i32}, {loc}));
    made.marked.push_back(bodies.back()->getArgument(0));
  }
  OperationState leaf(loc, "check.leaf");
  leaf.addRegion();
  Region &graph = b.create(leaf)->getRegion(0);
  Block *first = b.createBlock(&graph);
  Block *second = b.createBlock(&graph);
  b.setInsertionPointToEnd(first);
  OperationState toSecond(loc, "check.br");
  toSecond.addSuccessors(second);
  b.create(toSecond);
  b.setInsertionPointToEnd(second);
  OperationState onward(loc, "check.br");
  onward.addSuccessors(innermost == Innermost::ToItself ? second : first);
  b.create(onward);
  for (auto at = bodies.rbegin(); at != bodies.rend(); ++at) {
    b.setInsertionPointToEnd(*at);
    OperationState use(loc, "check.use");
    use.addOperands((*at)->getArgument(0));
    use.addTypes(i32);
    made.marked.push_back(b.create(use)->getResult(0));
  }
  return made;
}

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  unsigned depth = static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10));
  if (depth == 0)
    return 2;
  MLIRContext context;
  context.allowUnregisteredDialects();
  Chain lhs = chain(context, depth, Innermost::ToItself);
  Chain rhs = chain(context, depth, Innermost::ToItself);
  Chain other = chain(context, depth, Innermost::ToTheFirst);

  llvm::DenseMap<Value, Value> equivalent;
  std::vector<std::pair<Value, Value>> marks;
  bool chainsAlike = false, regionsAlike = false, otherAlike = true;
  llvm::thread compare(smallStack, [&] {
    chainsAlike = OperationEquivalence::isEquivalentTo(
        lhs.levels.front(), rhs.levels.front(),
        [&](Value l, Value r) { return success(l == r || equivalent.lookup(l) == r); },
        [&](Value l, Value r) {
          equivalent[l] = r;
          marks.emplace_back(l, r);
        },
        OperationEquivalence::IgnoreLocations);
    regionsAlike = OperationEquivalence::isRegionEquivalentTo(
        &lhs.levels.front()->getRegion(0), &rhs.levels.front()->getRegion(0),
        OperationEquivalence::IgnoreLocations);
    otherAlike = OperationEquivalence::isEquivalentTo(lhs.levels.front(), other.levels.front(),
                                                     OperationEquivalence::IgnoreLocations);
  });
  compare.join();

  std::size_t inOrder = 0;
  while (inOrder < marks.size() && inOrder < lhs.marked.size() &&
         marks[inOrder].first == lhs.marked[inOrder] &&
         marks[inOrder].second == rhs.marked[inOrder])
    ++inOrder;
  bool marksHold = inOrder == marks.size() && marks.size() == lhs.marked.size();

  // Destroyed innermost first, each operation then holding a region with no
  // chain left in it, so no destruction recurses and the check needs no
  // other patch.
  for (Chain *each : {&lhs, &rhs, &other})
    for (auto at = each->levels.rbegin(); at != each->levels.rend(); ++at)
      (*at)->erase();
  if (chainsAlike && regionsAlike && !otherAlike && marksHold) {
    llvm::outs() << "ok\n";
    return 0;
  }
  if (!chainsAlike)
    llvm::outs() << "the two chains alike are not equivalent as operations\n";
  if (!regionsAlike)
    llvm::outs() << "the two chains alike are not equivalent as regions\n";
  if (otherAlike)
    llvm::outs() << "the chain whose innermost branch differs is equivalent to them\n";
  if (!marksHold)
    llvm::outs() << marks.size() << " pairs marked, of " << lhs.marked.size()
                 << " values of a chain; the first " << inOrder
                 << " in the recursion's order\n";
  return 1;
}
