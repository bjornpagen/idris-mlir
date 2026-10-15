// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower tells LLVM about the values functions take and return,
// which the types say and the LLVM types no longer do.

#ifndef IDR_CONVERSION_FACTS_H
#define IDR_CONVERSION_FACTS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

#include <utility>

namespace idr::conversion {

class Facts {
public:
  // Reads each function of the program, its idr signature and the
  // parameters some call passes poison, before phase 0 renames the
  // functions and the conversion takes the types apart; each is kept under
  // the function's mangled name, the name it has from phase 0 on. A memo
  // label's function is called by its sum's dispatch function with the
  // fields a force reads from the cell, its captures in order as its
  // parameters: so the label's constructor, built new or in a reused cell,
  // passes its fields to the function as a call passes its arguments. The
  // memo sum's other two states, running and forced, have no function.
  explicit Facts(ProgramOp program);

  // After the conversion, marks each function's parameters and result:
  //   - a box, a closure or a string is a pointer to a cell, never null,
  //     8-aligned, with at least its 8-byte header to read (`nonnull`,
  //     `align 8`, `dereferenceable(8)`);
  //   - an unboxed sum's tag is in [0, n) for n constructors (`range`).
  // A parameter some call passes poison gets no pointer facts: its poison
  // is lowered to null, which the callee may drop, and a null that is
  // `dereferenceable` is undefined behaviour even if nothing reads it.
  void apply(const Layouts &layouts);

private:
  ProgramOp program;
  llvm::DenseMap<mlir::StringAttr, mlir::FunctionType> signatures;
  llvm::DenseSet<std::pair<mlir::StringAttr, unsigned>> poisoned;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_FACTS_H
