// What idr-lower tells LLVM about the values functions take and return,
// which the types say and the LLVM types no longer do.
#pragma once

#include "Lower/Layout.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

namespace idr::lower {

class Facts {
public:
  // Reads each function's idr signature, and the parameters some call
  // passes poison, before the conversion takes the types apart.
  explicit Facts(mlir::ModuleOp module);

  // After the conversion, marks each function's parameters and result:
  //   - a box, a closure or a string is a pointer to a cell, never null,
  //     8-aligned, with at least its 8-byte header to read (`nonnull`,
  //     `align 8`, `dereferenceable(8)`);
  //   - an unboxed sum's tag is in [0, n) for n constructors (`range`).
  // A parameter some call passes poison gets no pointer facts: its poison
  // is lowered to null, which the callee may drop, and a null that is
  // `dereferenceable` is undefined behaviour even if nothing reads it.
  void apply(Layouts &layouts);

private:
  mlir::ModuleOp module;
  llvm::DenseMap<mlir::Operation *, mlir::FunctionType> signatures;
  llvm::DenseSet<std::pair<mlir::Operation *, unsigned>> poisoned;
  // How many constructors each data type has, read before the conversion
  // erases the declarations.
  llvm::DenseMap<mlir::StringAttr, uint64_t> constructors;
};

} // namespace idr::lower
