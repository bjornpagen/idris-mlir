// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What specialization decides by: the binding time of every parameter.
// idr-optimize's ready set computes them once per function, on the
// function's summary: for a function the program held, when its component
// is taken up, from the component's bodies; for a node, its owner's by its
// key, from its build. Read by name, the symbol a call's callee gives,
// from any worker, once the function is final.
#ifndef IDR_ANALYSIS_SPECIALIZE_H
#define IDR_ANALYSIS_SPECIALIZE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>

namespace idr {

// The binding time of one parameter: which static arguments a call may
// specialize on there.
enum class BindingTime : uint8_t {
  // The function is on no cycle: a call specializes on anything static.
  Free,
  Fixed,
  Decreasing,
  Bounded,
  Other,
};

// The name idr-binding-times reports a binding time by.
llvm::StringRef nameOf(BindingTime time);

// Which parameters of a function a call may specialize on.
//
// A function is on a cycle when its component of the direct calls has two
// or more functions, or when it calls itself. A parameter of such a
// function is
//   - fixed when every call to the function from its component passes it
//     unchanged in the same position: one specialization serves the whole
//     recursion, whose calls then have its key;
//   - decreasing when every such call passes a proper part of it: a field
//     of it, an argument of a case of a match on it (the default region's
//     argument is the scrutinee itself, no part of it), or its predecessor
//     as a Nat (`idr.big.pred`, defined on non-zero values only); the keys
//     shrink along the chain of specializations;
//   - bounded when every such call passes it or a proper part of it: the
//     keys are parts of the first one;
//   - other otherwise: an accumulator, a counter, a closure rebuilt on
//     every iteration. A call never specializes on it.
//
// The result holds one list per function of `component`, in its order, one
// binding time per parameter. Each body is read as it is now; nothing
// outside `component` is read.
llvm::SmallVector<llvm::SmallVector<BindingTime>>
bindingTimesOf(llvm::ArrayRef<idr::FuncOp> component);

// The binding times a specialization reads: those of the functions whose
// component of idr-optimize's ready set is final, where they no longer
// change. The ready set answers; safe from any worker.
class BindingTimes {
public:
  virtual ~BindingTimes() = default;
  // One per parameter of the final function named `fn`; empty while its
  // component is not final.
  virtual llvm::SmallVector<BindingTime> of(mlir::StringAttr fn) const = 0;
};

} // namespace idr

#endif // IDR_ANALYSIS_SPECIALIZE_H
