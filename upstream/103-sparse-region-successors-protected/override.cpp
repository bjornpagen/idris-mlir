// An integer range analysis that overrides visitRegionSuccessors and hands
// every successor back to the base: it prints "ok" with the patch, once the
// override ran and the scf.if's result has its range [1, 2]. At the pin it
// does not build: the base is private.
// Built against the toolchain's MLIR:
//   clang++ -std=c++17 override.cpp $(llvm-config --cxxflags --ldflags) libMLIR*.a $(llvm-config --libs --system-libs)
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Parser/Parser.h"
#include <cstdio>

namespace {
class CountingRanges : public mlir::dataflow::IntegerRangeAnalysis {
public:
  using IntegerRangeAnalysis::IntegerRangeAnalysis;
  int visits = 0;

  void visitRegionSuccessors(
      mlir::ProgramPoint *point, mlir::RegionBranchOpInterface branch,
      mlir::RegionSuccessor successor,
      llvm::ArrayRef<mlir::dataflow::AbstractSparseLattice *> lattices) override {
    ++visits;
    AbstractSparseForwardDataFlowAnalysis::visitRegionSuccessors(point, branch, successor,
                                                                 lattices);
  }
};
} // namespace

static const char *source = R"mlir(
func.func @f(%c: i1) -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %r = scf.if %c -> i32 {
    scf.yield %a : i32
  } else {
    scf.yield %b : i32
  }
  return %r : i32
}
)mlir";

int main() {
  mlir::MLIRContext context;
  context.loadDialect<mlir::arith::ArithDialect, mlir::func::FuncDialect,
                      mlir::scf::SCFDialect>();
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceString<mlir::ModuleOp>(source, &context);
  if (!module)
    return 2;
  mlir::DataFlowSolver solver;
  solver.load<mlir::dataflow::DeadCodeAnalysis>();
  solver.load<mlir::dataflow::SparseConstantPropagation>();
  CountingRanges *ranges = solver.load<CountingRanges>();
  if (mlir::failed(solver.initializeAndRun(*module)))
    return 2;
  bool ok = false;
  module->walk([&](mlir::scf::IfOp branch) {
    auto *lattice =
        solver.lookupState<mlir::dataflow::IntegerValueRangeLattice>(branch.getResult(0));
    if (lattice && !lattice->getValue().isUninitialized()) {
      const mlir::ConstantIntRanges &range = lattice->getValue().getValue();
      ok = range.smin() == 1 && range.smax() == 2;
    }
  });
  ok = ok && ranges->visits > 0;
  std::puts(ok ? "ok" : "wrong");
  return ok ? 0 : 1;
}
