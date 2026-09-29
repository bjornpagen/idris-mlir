// idr-specialize's state for one run: the clone table, and the binding
// times found when the run starts.
#pragma once

#include "Specialize/BindingTimes.h"
#include "Specialize/Clones.h"
#include "Specialize/Pattern.h"

#include "mlir/Rewrite/FrozenRewritePatternSet.h"

#include <optional>
#include <variant>

namespace idr::specialize {

// The largest static value (unrollSize) a decreasing or bounded parameter
// is unrolled on. Unrolling exists to take small, partially static data off
// the heap (`Vect 3 Double`); a larger value stays data.
constexpr uint64_t kUnrollLimit = 32;

struct Statistics {
  uint64_t clones = 0;
  uint64_t raised = 0;
  uint64_t shared = 0;
  // The static arguments specialized on, by the binding time of their
  // parameter.
  uint64_t free = 0;
  uint64_t fixed = 0;
  uint64_t decreasing = 0;
  uint64_t bounded = 0;
};

// The single consumer of a call's result that raising moves into a clone of
// the callee: an apply of the result, of one field of it, or of the one use
// of either when it is linear (an action in `MkIO` is); or output of it.
struct Apply {
  FieldOp field; // null: the result itself is applied
  LinUseOp use;  // null: what is applied is not linear
  ApplyOp apply;
};
struct Write {
  PutStrOp write;
};
using Consumer = std::variant<Apply, Write>;

class Specializer {
public:
  explicit Specializer(mlir::ModuleOp module);

  // Raises and specializes the calls of every function, and of every clone
  // it makes; fails once a budget is spent.
  mlir::LogicalResult run();

  Statistics stats;

private:
  // Raising (Raise.cc): the call of a clone that replaces `call` and the
  // consumer of its result, or null.
  mlir::FailureOr<mlir::func::CallOp> raise(mlir::func::CallOp call);
  std::optional<Consumer> consumerOf(mlir::func::CallOp call, mlir::func::FuncOp callee);
  mlir::FailureOr<mlir::func::FuncOp> makeRaised(mlir::func::FuncOp callee,
                                                 mlir::func::CallOp call, const Consumer &c,
                                                 mlir::Attribute key);

  // Specialization (Specialize.cc).
  mlir::LogicalResult specialize(mlir::func::CallOp call);

  void canonicalize(mlir::func::FuncOp fn);

  mlir::ModuleOp module;
  CloneTable clones;
  BindingTimes times;
  std::optional<mlir::FrozenRewritePatternSet> patterns;
  llvm::SmallVector<mlir::func::FuncOp> work;
};

} // namespace idr::specialize
