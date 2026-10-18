// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place: the references of one function made explicit, once
// idr-rc-grades graded every signature: the reuse rewrite at the sites the
// program's Reuses decided, then the reshaping and the placement of the
// counts. It reads the Reuses and the symbol table its program holds, and
// writes nothing outside its function: an entry argument it grades owned is
// one the signature already made owned.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"

#include <functional>
#include <optional>

namespace idr {
#define GEN_PASS_DEF_IDRRCPLACE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Place : idr::impl::IdrRcPlaceBase<Place> {
  void runOnProgram(idr::ProgramOp program) override {
    namespace own = idr::ownership;
    idr::FuncOp fn = getOperation();
    std::optional<std::reference_wrapper<idr::Reuses>> reuses =
        getCachedParentAnalysis<idr::Reuses>(program);
    std::optional<std::reference_wrapper<SymbolTable>> symbols =
        getCachedParentAnalysis<SymbolTable>(program);
    // What idr-rc-grades decided is its program's, which this step reads
    // and cannot make: a run without it is a pipeline's bug, never a
    // program's.
    if (!reuses || !symbols) {
      fn.emitError("internal error: idr-rc-place: no ")
          << (reuses ? "symbol table" : "Reuses") << " of the program";
      return signalPassFailure();
    }
    IRRewriter rewriter(&getContext());
    ArrayRef<idr::Reuses::Site> sites = reuses->get().sites(fn);
    own::reuseAt(rewriter, sites);
    numTakes += sites.size();
    for (const idr::Reuses::Site &site : sites)
      numReuses += site.cells.size();
    own::Counted reshaped = own::reshape(rewriter, fn, *symbols);
    own::Counted placed = own::place(rewriter, fn, *symbols);
    numDups += reshaped.dups + placed.dups;
    numDrops += reshaped.drops + placed.drops;
  }
};

} // namespace
