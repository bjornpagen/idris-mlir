// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-cells: memory made explicit, on each function. A constructor value
// is a value until counting; from here on, a constructor that has a cell of
// its own is two ops, as upstream separates memory from values: the cell's
// source (idr.cell.new, a fresh cell its count frees) and its
// initialization (idr.cell.init, which writes the fields and gives the
// value). A later step replaces only the source (a lifetime's memory, a
// recycled cell); the init that names the cell never changes. A
// constructor without a cell (an inline value, an atom) stays data.con.
//
// Two more shapes counting reads are made here, once, so no later step
// meets the old one: a select of values that hold references becomes
// upstream's scf.if, whose regions each move the value they yield, so a
// reference is never chosen by an op that forwards no region; and each
// place a reference crosses into upstream's buffer ops is an op of its
// own: a fresh buffer's reference is taken over by idr.own.adopt, and a
// value stored into a buffer hands its reference over by idr.own.give.
#include "idr/IR/Effects/Query.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCCELLS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

// A constructor of a cell becomes the cell's source and its init; the
// value is the init's, at the constructor's grade. The cell is typed by the
// value refined to its constructor, which the constructor's type is.
void splitCell(RewriterBase &rewriter, DataConOp con) {
  Type type = con.getResult().getType();
  rewriter.setInsertionPoint(con);
  auto cellType = CellType::get(rewriter.getContext(), cast<DataType>(unrestricted(type)));
  Value cell = CellNewOp::create(rewriter, con.getLoc(), cellType);
  auto init = CellInitOp::create(rewriter, con.getLoc(), type, cell, con.getFields(),
                                 ArrayRef<int32_t>());
  rewriter.replaceOp(con, init.getResult());
}

// A select of references becomes a branch whose regions each yield one of
// the values: each region then moves the value it yields, and counting
// reads the move off upstream's region-branch interface.
void branchSelect(RewriterBase &rewriter, arith::SelectOp select) {
  rewriter.setInsertionPoint(select);
  Location loc = select.getLoc();
  auto branch = scf::IfOp::create(rewriter, loc, TypeRange{select.getType()},
                                  select.getCondition(), /*withElseRegion=*/true);
  OpBuilder::InsertionGuard guard(rewriter);
  rewriter.setInsertionPointToStart(branch.thenBlock());
  scf::YieldOp::create(rewriter, loc, select.getTrueValue());
  rewriter.setInsertionPointToStart(branch.elseBlock());
  scf::YieldOp::create(rewriter, loc, select.getFalseValue());
  rewriter.replaceOp(select, branch);
}

// A buffer an op of upstream's makes is counting's from its making on: the
// one result it allocates is taken over right after it, and every other
// use reads the adopted value.
void adopt(RewriterBase &rewriter, OpResult buffer) {
  rewriter.setInsertionPointAfterValue(buffer);
  auto adopted = OwnAdoptOp::create(rewriter, buffer.getLoc(), buffer);
  rewriter.replaceAllUsesExcept(buffer, adopted.getResult(), adopted);
}

// A value an op of upstream's stores hands its reference to the memory:
// the store takes the plain carrier, so a store of a linear value is
// refused rather than its quantity lost.
void give(RewriterBase &rewriter, OpOperand &stored) {
  Operation *store = stored.getOwner();
  rewriter.setInsertionPoint(store);
  auto given = OwnGiveOp::create(rewriter, store->getLoc(), stored.get());
  rewriter.modifyOpInPlace(store, [&] { stored.set(given.getResult()); });
}

struct Cells : impl::IdrRcCellsBase<Cells> {
  void runOnProgram(ProgramOp) {
    FuncOp fn = getOperation();
    // Found first and rewritten after: each rewrite replaces the op the
    // walk would stand on. Each op is met once, and each list holds a kind
    // of op the rewrite of another never makes.
    SmallVector<DataConOp> cons;
    SmallVector<arith::SelectOp> selects;
    SmallVector<OpResult> buffers;
    SmallVector<OpOperand *> stores;
    fn.walk([&](Operation *op) {
      if (auto con = dyn_cast<DataConOp>(op)) {
        if (buildsCell(con.getResult().getType(), con.getTag()))
          cons.push_back(con);
        return;
      }
      if (auto select = dyn_cast<arith::SelectOp>(op)) {
        if (holdsReferences(select.getType()))
          selects.push_back(select);
        return;
      }
      // An op of the dialect states its references in its grades; only an
      // op of upstream's, which takes plain carriers, needs a crossing.
      if (op->getDialect() == getContext().getLoadedDialect<IdrDialect>())
        return;
      for (OpResult result : op->getResults())
        if (isa<BaseMemRefType>(result.getType()) && effects::allocates(op, result))
          buffers.push_back(result);
      for (OpOperand &operand : op->getOpOperands())
        if (holdsReferences(operand.get().getType()) && ownership::storedBy(operand))
          stores.push_back(&operand);
    });
    IRRewriter rewriter(&getContext());
    for (DataConOp con : cons)
      splitCell(rewriter, con);
    for (arith::SelectOp select : selects)
      branchSelect(rewriter, select);
    for (OpResult buffer : buffers)
      adopt(rewriter, buffer);
    for (OpOperand *stored : stores)
      give(rewriter, *stored);
    numBoxes += cons.size();
  }
};

} // namespace
} // namespace idr::counting
