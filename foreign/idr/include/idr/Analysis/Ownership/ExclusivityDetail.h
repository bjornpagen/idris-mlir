// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the two units of exclusivity's solve share, and no other unit reads:
// lib/Analysis/Ownership/Exclusivity.cpp, which runs the solve and keeps
// its answers, and ExclusivityAnalyses.cpp beside it, the analyses it runs.
// The lattice a value holds, whether a function runs, and how each call
// goes, which are what the analyses write and the answers are read off.
#ifndef IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
#define IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H

#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <variant>

namespace idr::detail::exclusivity {

using Sharing = Exclusivity::Sharing;

// What is known of a value's cell graph, as the lattice holds it.
struct Cells {
  Sharing sharing = Sharing::Unknown;

  static Cells of(Sharing sharing) { return {sharing}; }
  static Cells join(const Cells &a, const Cells &b) { return of(std::max(a.sharing, b.sharing)); }
  bool operator==(const Cells &) const = default;
  void print(llvm::raw_ostream &os) const;
};

struct CellsLattice : mlir::dataflow::Lattice<Cells> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(CellsLattice)
  using Lattice::Lattice;
};

// What a value holds, optimistically: unknown counts as exclusive until a
// path shares it.
inline bool exclusive(const CellsLattice &lattice) {
  return lattice.getValue().sharing != Sharing::Shared;
}

// Whether a function runs, held at the start of its body. It only ever
// becomes true.
class Runs : public mlir::AnalysisState {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Runs)
  using AnalysisState::AnalysisState;

  bool running() const { return runs; }
  mlir::ChangeResult setRunning() {
    if (runs)
      return mlir::ChangeResult::NoChange;
    runs = true;
    return mlir::ChangeResult::Change;
  }
  void print(llvm::raw_ostream &os) const override { os << (runs ? "runs" : "runs nowhere"); }

private:
  bool runs = false;
};

// The entry block of `fn`'s body, before which its Runs is held.
inline mlir::Block *entryOf(FuncOp fn) { return &fn.getBody().front(); }

// How calls go, fixed before the solve. Each function of the program is
// called by its name alone, or, a key of grade specialization and its copy,
// by either name: such a call runs the copy when every value it passes at a
// followed parameter is exclusive, and the original otherwise. A verified
// call names a function of the program, so every name a call holds is
// here. What each function returns from is the idr.return ending a block
// of its body.
class Calls {
public:
  struct Pair {
    FuncOp original;
    FuncOp copy;
  };
  using Callee = std::variant<FuncOp, Pair>;

  Calls(ProgramOp program, const ownership::Copies &copies);

  // What a call of `call`'s callee runs.
  const Callee &calleeOf(CallOp call) const;
  // The functions whose calls may run `fn`.
  llvm::SmallVector<FuncOp, 2> namesOf(FuncOp fn) const;
  // The function `call` runs, `isExclusive` saying which of the values it
  // passes are.
  FuncOp target(CallOp call, llvm::function_ref<bool(mlir::Value)> isExclusive) const;
  // The returns of `fn`, a function of the program.
  llvm::ArrayRef<ReturnOp> returns(FuncOp fn) const { return returnsOf.at(fn); }

private:
  llvm::DenseMap<mlir::StringAttr, Callee> callees;
  llvm::DenseMap<FuncOp, llvm::SmallVector<ReturnOp>> returnsOf;
};

// Loads into `solver` the analyses of one solve of `program`, whose calls
// go as `calls` says, which must outlive the solver's run: the run fills a
// CellsLattice for each value and a Runs for each function, beside
// upstream's Executable for each block and PredecessorState for each
// function.
void loadAnalyses(mlir::DataFlowSolver &solver, ProgramOp program, const Calls &calls);

} // namespace idr::detail::exclusivity

#endif // IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
