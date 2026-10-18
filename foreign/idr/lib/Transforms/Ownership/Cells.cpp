// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-cells: memory made explicit. A constructor value is a value until
// counting; from here on, a constructor that has a cell of its own is two
// ops, as upstream separates memory from values: the cell's allocation
// (idr.cell.new, a fresh cell of the heap) and its initialization
// (idr.cell.init, which writes the fields and gives the box). The later
// steps each replace the allocation by another source of the cell (the
// frame, a recycled cell), and the initialization that names the cell
// never changes. A constructor without a cell (an unboxed sum's, an atom)
// stays idr.con.
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCCELLS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Cells : idr::impl::IdrRcCellsBase<Cells> {
  void runOnProgram(idr::ProgramOp) override {
    // Found first and split after: each split replaces the con the walk
    // would stand on.
    SmallVector<idr::ConOp> cons;
    getOperation().walk([&](idr::ConOp con) {
      if (idr::buildsCell(con.getResult().getType(), con.getTag()))
        cons.push_back(con);
    });
    IRRewriter rewriter(&getContext());
    for (idr::ConOp con : cons) {
      Type type = con.getResult().getType();
      auto cellType = idr::CellType::get(&getContext(), cast<idr::BoxType>(idr::unrestricted(type)),
                                         con.getTag());
      rewriter.setInsertionPoint(con);
      Value cell = idr::CellNewOp::create(rewriter, con.getLoc(), cellType);
      // The box is the constructor's value at the constructor's grade (a
      // linear box stays linear), which counting grades later as every
      // value.
      auto init = idr::CellInitOp::create(rewriter, con.getLoc(), type, cell, con.getFields());
      rewriter.replaceOp(con, init.getResult());
    }
    numBoxes += cons.size();
  }
};

} // namespace
