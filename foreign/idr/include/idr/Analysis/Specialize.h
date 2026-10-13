// What specialization decides by: the clones the module holds, by key, and
// the binding time of every parameter. Both are read by name, the symbol a
// call's callee gives without resolving anything, so a function pass asks
// them about a callee it never looks up and the module pass that makes the
// clones asks the same tables.
#ifndef IDR_ANALYSIS_SPECIALIZE_H
#define IDR_ANALYSIS_SPECIALIZE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <array>
#include <cstdint>
#include <optional>

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

// A clone as the table holds it. name, type and effects are copies of the
// clone's own, so a function pass reads them without touching the clone;
// fn is for the module pass that made or found it.
struct Clone {
  idr::FuncOp fn;
  mlir::Attribute key;
  mlir::FlatSymbolRefAttr name;
  mlir::FunctionType type;
  std::optional<idr::Effect> effects; // none: may do anything
};

// The clones of a module by key, from the clone fact of each function. A
// clone's parameter p holds hole p of its key, so the fact alone says
// which argument fills which hole.
class CloneTable {
public:
  // The clones of one owner, over the whole compilation, past which the
  // construction is broken: every key is drawn from a finite set, and a
  // run that makes this many has found a set that is not.
  static constexpr unsigned kClonesPerOwner = 1024;

  enum class Kind : uint8_t { Spec, Raise };
  // A SpecKey is a specialization's; KeyApply and KeyApplyField a raised
  // clone's.
  static Kind kindOf(mlir::Attribute key);

  CloneTable(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  const Clone *lookup(mlir::Attribute key) const;
  // The clone `fn` is, or null for a function that is none (or that shares
  // its key with a clone met first in module order).
  const Clone *find(mlir::StringAttr fn) const;
  // The clone `fn` is, if it specializes: calls of it are keyed by its
  // owner's parameters.
  const Clone *specialization(mlir::StringAttr fn) const;
  // The function whose parameters the keys of calls of `fn` describe: a
  // specialization describes its origin's, any other function its own.
  mlir::StringAttr ownerOf(mlir::StringAttr fn) const;
  // The owner's clones, both kinds, which the budget counts.
  unsigned count(mlir::StringAttr owner) const;
  // The owner's clones of one kind, which the next clone's name counts.
  unsigned count(mlir::StringAttr owner, Kind kind) const;
  // `fn`, after its insertion and its clone fact: recorded under the fact's
  // key with copies of its name, type and effects, and counted for its
  // owner. It changes the table, not the IR, so that the pass inserting
  // clones keeps the table current.
  const Clone &add(idr::FuncOp fn);

private:
  // The owner `key` counts for, from what the table holds.
  mlir::StringAttr ownerOfKey(mlir::Attribute key) const;
  void countFor(mlir::Attribute key);

  llvm::DenseMap<mlir::Attribute, Clone> byKey;
  // The key of each function with a clone fact, by its name.
  llvm::DenseMap<mlir::StringAttr, mlir::Attribute> keys;
  // Each owner's clones, by kind.
  llvm::DenseMap<mlir::StringAttr, std::array<unsigned, 2>> counts;
};

// Which parameters of a function a call may specialize on.
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
// They are computed from the module as it is when the analysis is built: a
// clone made since has none until the analysis is built again.
class BindingTimes {
public:
  BindingTimes(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // None, or empty, for a function it did not see: one made since.
  std::optional<BindingTime> of(mlir::StringAttr fn, unsigned index) const;
  llvm::ArrayRef<BindingTime> of(mlir::StringAttr fn) const;

private:
  // Every parameter of every function the analysis saw, by its name; Free
  // throughout for one on no cycle.
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<BindingTime>> times;
};

} // namespace idr

#endif // IDR_ANALYSIS_SPECIALIZE_H
