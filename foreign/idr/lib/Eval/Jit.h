// Compiling a round of compile-time evaluation (ELIM-EVAL-1): ORC's
// LLJIT, not mlir::ExecutionEngine, which aborts in a static musl process
// (PINS.md: orc-lljit). Nothing is linked from the process by name: the
// runtime's entry points, which idris-mlir-cc links natively, and the libc
// functions LLVM may call are bound through an absolute-symbol table, so the
// JITed code runs the same runtime and libm as executables.
#pragma once

#include "mlir/IR/BuiltinOps.h"

#include "llvm/ExecutionEngine/Orc/LLJIT.h"

#include <memory>
#include <string>

namespace idr::eval {

class Jit {
public:
  using Entry = void (*)(void *);

  // Translates `module` (LLVM dialect) to LLVM IR, optimizes it as
  // idris-mlir-cc optimizes executables for the host CPU (LOW-TARGET-1),
  // compiles it once, and finds `entries`. On failure, says why in `error`.
  static std::unique_ptr<Jit> compile(mlir::ModuleOp module, llvm::ArrayRef<std::string> entries,
                                      std::string &error);

  llvm::ArrayRef<Entry> getEntries() const { return entries; }

private:
  std::unique_ptr<llvm::orc::LLJIT> jit;
  llvm::SmallVector<Entry> entries;
};

} // namespace idr::eval
