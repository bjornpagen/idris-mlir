// Runtime helpers and static data for idr-lower (LOW-IO-*, LOW-STR-1,
// LOW-CRASH-1).
#pragma once

#include "idr/Idr.h"

#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/StringMap.h"

#include <string>
#include <utility>

namespace idr::lower {

class Runtime {
public:
  explicit Runtime(mlir::ModuleOp m) : module(m) {}

  // Declares the static data for `bytes` (LOW-STR-1). Called before the
  // conversion starts, so patterns only reference existing globals.
  void declareString(llvm::StringRef bytes);

  // The address and byte length of a declared static string.
  std::pair<mlir::Value, mlir::Value> string(mlir::OpBuilder &b, mlir::Location loc,
                                             llvm::StringRef bytes) const;

private:
  mlir::ModuleOp module;
  llvm::StringMap<std::string> strings;
};

// The message of a crash: its cause and the Idris location.
std::string crashMessage(mlir::Location loc, llvm::StringRef cause);

// Calls @__idr_crash with a message naming the cause and the Idris location.
void emitCrash(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime,
               llvm::StringRef cause);

} // namespace idr::lower
