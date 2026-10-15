// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Worlds and !idr.lin values: every value of quantity one is used at most
// once on every path. Its type says where it may go; this says how often.
// One walk numbers the body; each linear value then costs its holders.
// Which regions of an op exclude each other is the owned walk's question
// too: both ask RegionBranchOpInterface, here.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;
using namespace idr;

// Each region returns straight to the op: the regions of a match or of an
// scf.if, not those of a loop.
bool idr::verify::alternatives(RegionBranchOpInterface branch) {
  return llvm::all_of(branch->getRegions(), [&](Region &region) {
    SmallVector<RegionSuccessor> next;
    branch.getSuccessorRegions(region, next);
    return llvm::all_of(next, [](RegionSuccessor &successor) { return successor.isOperation(); });
  });
}

namespace {

// One pre-order walk of a function's body: the place of every op in it,
// and every value of quantity one in walk order. Pre-order numbers the ops
// of one region in block order, so comparing two places orders the ops of
// a region without touching a block's order cache, which other threads'
// verifiers read.
class Numbering {
public:
  explicit Numbering(FuncOp fn) {
    auto collect = [&](ValueRange values) {
      for (Value value : values)
        if (quantityOf(value.getType()) == Quantity::One)
          linear.push_back(value);
    };
    unsigned next = 0;
    fn->walk<WalkOrder::PreOrder>([&](Operation *op) {
      places.try_emplace(op, next++);
      collect(op->getResults());
      for (Region &region : op->getRegions())
        for (Block &block : region)
          collect(block.getArguments());
    });
  }

  unsigned place(Operation *op) const { return places.lookup(op); }
  ArrayRef<Value> linearValues() const { return linear; }

private:
  DenseMap<Operation *, unsigned> places;
  SmallVector<Value> linear;
};

// The uses of one linear value, counted on the worst path. The regions of
// a match, and of any op whose regions exclude each other, are alternative
// paths; a region that may run repeatedly counts twice. A region of several
// blocks, which a function body is only after the inliner takes in a callee
// that ends in ub.unreachable, counts every use in it.
class LinearUses {
public:
  LinearUses(Value value, const Numbering &numbering) : value(value) {
    Region *home = value.getParentRegion();
    for (OpOperand &use : value.getUses())
      for (Operation *op = use.getOwner(); op; op = op->getParentOp()) {
        if (!holders.insert(op).second)
          break;
        if (op->getParentRegion() == home) {
          top.push_back(op);
          break;
        }
        byBlock[op->getBlock()].push_back(op);
      }
    // The reported second use is the earliest in the region.
    llvm::sort(top, [&](Operation *a, Operation *b) {
      return numbering.place(a) < numbering.place(b);
    });
  }

  // The first op after which the value has been used twice, if any.
  Operation *secondUse() {
    unsigned total = 0;
    for (Operation *op : top) {
      total += count(op);
      if (total > 1)
        return op;
    }
    return nullptr;
  }

private:
  unsigned count(Region &region) {
    unsigned total = 0;
    for (Block &block : region)
      for (Operation *op : byBlock.lookup(&block))
        total += count(op);
    return total;
  }

  unsigned count(Operation *op) {
    // A view of the value (idr.borrow) is not a use of it: the owner keeps
    // its reference, and the view's uses come before the owner's one use.
    unsigned total =
        isa<BorrowOp>(op) ? 0u : static_cast<unsigned>(llvm::count(op->getOperands(), value));
    if (op->getNumRegions() == 0)
      return total;
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    bool exclusive = branch && verify::alternatives(branch);
    unsigned regions = 0;
    for (unsigned index = 0, e = op->getNumRegions(); index < e; ++index) {
      unsigned uses = count(op->getRegion(index));
      if (uses && !exclusive && branch && branch.isRepetitiveRegion(index))
        uses = 2;
      regions = exclusive ? std::max(regions, uses) : regions + uses;
    }
    return total + regions;
  }

  Value value;
  llvm::DenseSet<Operation *> holders;
  SmallVector<Operation *> top;
  llvm::DenseMap<Block *, SmallVector<Operation *>> byBlock;
};

} // namespace

LogicalResult idr::verify::linearity(FuncOp fn) {
  Numbering numbering(fn);
  for (Value value : numbering.linearValues()) {
    // A constant holds nothing a use could take: the folder materializes
    // one wherever it is needed, merges equal ones and hoists them out of
    // loops, so its uses repeat however the program was written. A
    // constant of quantity 1 stands for a value nothing reads: the payload
    // a loop yields on the path that does not use it, or an argument its
    // callee never reads.
    if (matchPattern(value, m_Constant()))
      continue;
    if (Operation *op = LinearUses(value, numbering).secondUse())
      return op->emitOpError(isWorld(value.getType())
                                 ? "uses a world that is already used on the same path"
                                 : "uses a linear value that is already used on the same path");
  }
  return success();
}
