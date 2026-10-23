// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The contracts of the passes, and the promises every compiled program
// keeps, checked where each pass runs. Between two passes the verifier is
// all MLIR checks, so a pass that drops a quantity Idris proved would pass
// unnoticed until something downstream miscompiles. MLIR's pass
// instrumentation sees every pass at its boundary: before a pass on the
// module or on its idr.program it records, per function, the facts the
// relations read (each parameter's and result's uses, whether its row may
// crash), never a copy of the module; after the pass it checks the
// relations no correct pass breaks between that record and the module, and
// what the module after it holds alone (every cycle of calls Idris did not
// prove holds its divergence in each member's row, which no function's
// check can see), failing the pass and naming it when one is broken. A
// pass on each function is checked as the group its nest runs on the
// program. When the pipeline ends, the promises: no recursion of the
// program grows the native stack. idris-mlir-opt and idris-mlir install it
// under --idr-contracts, which the tests give; no compilation otherwise
// pays for it.
#ifndef IDR_TRANSFORMS_CONTRACTS_H
#define IDR_TRANSFORMS_CONTRACTS_H

#include "idr/IR/Grades.h"
#include "idr/Transforms/Expect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace idr {

// What a function may do that a relation compares: whether its row may
// crash.
enum class MayCrash : std::uint8_t { No, Yes };

// One function's facts before a pass: what the relations compare with the
// function of its symbol after it.
struct FunctionRecord {
  mlir::StringAttr symbol;
  llvm::SmallVector<Uses> parameters;
  llvm::SmallVector<Uses> results;
  MayCrash crash;
};

// The record of every function before one run of a pass, and the pass the
// run is of. Across a pass a function's identity is its symbol, MLIR's own,
// which follows a function the pass rebuilt as a new op: after the pass
// each record finds its function through the program's symbol table, the
// one index of its symbols, so the snapshot keeps none of its own.
struct Snapshot {
  mlir::Pass *pass = nullptr;
  llvm::SmallVector<FunctionRecord> functions;
};

class ContractInstrumentation final : public mlir::PassInstrumentation {
public:
  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override;
  void runAfterPass(mlir::Pass *pass, mlir::Operation *op) override;
  void runAfterPassFailed(mlir::Pass *pass, mlir::Operation *op) override;

  // After the pipeline, the promises of the module it left: idr-expect's
  // universal properties, each of the whole program (no recursion grows
  // the native stack among them). The pass manager instruments no end of
  // its own pipeline, so the tool that ran it calls this once, with the
  // module.
  mlir::LogicalResult finish(mlir::ModuleOp module);

private:
  // The run under way, of the module or its program: both run on the pass
  // manager's own thread, and a pass that runs passes through its own
  // pipeline runs them inside its run, which is checked whole.
  std::optional<Snapshot> before;
  // The uses Idris proved of each binder, by its identity: read once, from
  // the module the frontend emitted, before the first pass.
  std::optional<expect::ProvedUses> proved;
};

// Registers test-idr-break-contract, the pass that breaks a contract on
// purpose for the contracts' own test.
void registerContractTestPass();

} // namespace idr

#endif // IDR_TRANSFORMS_CONTRACTS_H
