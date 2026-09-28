// Reading a result of compile-time evaluation back as a constant attribute
// (IDR-CONST-1), through the layouts idr-lower built it in (ELIM-EVAL-1).
// Runs in idr-eval's child, on the memory of the JITed code.
#pragma once

#include "Lower/Layout.h"

namespace idr::eval {

class Reifier {
public:
  explicit Reifier(lower::Layouts &l) : layouts(l) {}

  // The value of type `type` whose components are the next words of
  // `words`, each an 8-byte slot holding one component; advances `words`.
  mlir::Attribute value(mlir::Type type, llvm::ArrayRef<uint64_t> &words);

private:
  // The components of `slots` in the cell at `cell`, one word each.
  llvm::SmallVector<uint64_t> read(const char *cell, llvm::ArrayRef<lower::Slot> slots);
  mlir::Attribute constructor(DataOp data, CtorOp ctor,
                              llvm::function_ref<llvm::SmallVector<uint64_t>(unsigned field)> fields);

  lower::Layouts &layouts;
};

} // namespace idr::eval
