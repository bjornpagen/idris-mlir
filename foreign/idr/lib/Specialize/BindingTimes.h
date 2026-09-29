// Binding times: which parameters of a function a call may specialize on.
//
// A function is recursive when it is on a cycle of references (the
// functions it calls, and those its closures and closure constants name):
// recursion through a closure counts. A parameter of a recursive function
// is
//   - fixed when every reference to the function from its cycles passes it
//     unchanged in the same position: one clone serves the whole recursion,
//     whose calls then have its key;
//   - decreasing when every such reference passes a proper part of it: a
//     field of it, an argument of a region of a match on it, or its
//     predecessor as a Nat (`idr.big.pred`, defined on non-zero values
//     only); the keys shrink along the chain of clones;
//   - bounded when every such reference passes it or a proper part of it:
//     the keys are parts of the first one;
//   - other otherwise: an accumulator, a counter, a closure rebuilt on every
//     iteration. A call never specializes on it.
//
// The classes are found as Lean's fixed parameters are: each function is
// interpreted over abstract values (a parameter, a proper part of one, or
// anything), and so is every function of its cycles that it reaches, once
// for each assignment of abstract values to its parameters, so the analysis
// ends. They are computed from the module as the pass finds it, before it
// changes anything: a clone the pass makes has none until its next run.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::specialize {

enum class BindingTime : uint8_t {
  // The function is on no cycle: a call specializes on anything static.
  Free,
  Fixed,
  Decreasing,
  Bounded,
  Other,
};

llvm::StringRef nameOf(BindingTime time);

class BindingTimes {
public:
  BindingTimes(mlir::ModuleOp module, mlir::SymbolTable &symbols);

  // The binding time of parameter `index` of `fn`, or none for a function
  // the analysis did not see: one made after it ran.
  std::optional<BindingTime> of(mlir::func::FuncOp fn, unsigned index) const;

private:
  // Every parameter of every function the analysis saw; Free throughout for
  // one on no cycle.
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<BindingTime>> times;
};

} // namespace idr::specialize
