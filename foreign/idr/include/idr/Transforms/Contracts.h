// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The contracts of the passes, checked where each pass runs. Between two
// passes the structural verifier is all MLIR checks, so a pass that drops
// a quantity Idris proved, or widens what a function may do, would pass
// unnoticed until something downstream miscompiles. MLIR's pass
// instrumentation sees every pass at its boundary: before a pass on the
// module or on its idr.program it keeps a snapshot of the module, and
// after the pass it checks the relations no correct pass breaks between
// the snapshot and the module, failing the pass and naming it when one is
// broken. A relation idr-expect states is idr-expect's definition, called;
// the others compare what the functions the pass kept declare. A pass on
// each function is checked as the group its nest runs on the program.
// idris-mlir-opt installs it under --idr-contracts; idris-mlir never does.
#ifndef IDR_TRANSFORMS_CONTRACTS_H
#define IDR_TRANSFORMS_CONTRACTS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/FileUtilities.h"

#include <memory>
#include <mutex>
#include <string>

namespace idr {

// What a function declares that every pass keeping it keeps: what a run
// of it may do, and the quantity of each parameter and each result.
struct FunctionFacts {
  idr::Effect effects;
  llvm::SmallVector<idr::Quantity> parameters, results;
};

// The module before one run of a pass: the pass, the module printed with
// its locations to a file that goes when the snapshot goes (the form
// idr-expect's quantities-kept reads), and the facts of each function of
// its program, by symbol.
struct Snapshot {
  mlir::Pass *pass = nullptr;
  std::unique_ptr<llvm::FileRemover> printed;
  std::string path;
  llvm::DenseMap<mlir::StringAttr, FunctionFacts> functions;
};

class ContractInstrumentation final : public mlir::PassInstrumentation {
public:
  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override;
  void runAfterPass(mlir::Pass *pass, mlir::Operation *op) override;
  void runAfterPassFailed(mlir::Pass *pass, mlir::Operation *op) override;

private:
  // The runs under way, one per op: the snapshot of the outermost run on
  // each. A pass that runs passes through its own pipeline runs them on its
  // own op, inside its run, which is checked whole.
  std::mutex mutex;
  llvm::DenseMap<mlir::Operation *, Snapshot> before;
};

// Registers test-idr-break-contract, the pass that breaks a contract on
// purpose for the contracts' own test.
void registerContractTestPass();

} // namespace idr

#endif // IDR_TRANSFORMS_CONTRACTS_H
