// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The contracts of the passes, checked where each pass runs. Between two
// passes the structural verifier is all MLIR checks, so a pass that drops
// a quantity Idris proved, or widens what a function may do, would pass
// unnoticed until something downstream miscompiles. MLIR's pass
// instrumentation sees every pass at its boundary: before a pass on the
// module or on its idr.program it keeps a copy of the module, and after
// the pass it checks the relations no correct pass breaks between the copy
// and the module, failing the pass and naming it when one is broken. A
// relation idr-expect states is idr-expect's typed check, called with the
// copy; the others compare each function the pass kept with its copy. A
// pass on each function is checked as the group its nest runs on the
// program. idris-mlir-opt and idris-mlir install it under --idr-contracts,
// which the tests give; no compilation otherwise pays for it.
#ifndef IDR_TRANSFORMS_CONTRACTS_H
#define IDR_TRANSFORMS_CONTRACTS_H

#include "idr/Transforms/Expect.h"

#include "mlir/Pass/PassInstrumentation.h"
#include "llvm/ADT/DenseMap.h"

#include <mutex>

namespace idr {

// The module before one run of a pass: the pass, and a clone of the module,
// the one copy of the state before it, which goes when the snapshot goes.
struct Snapshot {
  mlir::Pass *pass = nullptr;
  expect::Module before;
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
