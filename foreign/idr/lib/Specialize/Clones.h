// The clones of a module by key.
//
// A clone keeps its key as `idr.spec_key`, a typed attribute, and each of
// its parameters the hole of the key it holds as `idr.hole`, so that the
// next run shares the clone after remove-dead-values has erased parameters
// it never reads. A clone is parsed once, when the table meets it; one whose
// marks do not parse is no clone to the table, only a function.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

#include <optional>

namespace idr::specialize {

// The clones of one owner, over the whole compilation, past which the
// construction is broken: every key is drawn from a finite set, and a run
// that makes this many has found a set that is not.
constexpr unsigned kClonesPerOwner = 1024;

inline constexpr llvm::StringLiteral kKeyAttr = "idr.spec_key";
inline constexpr llvm::StringLiteral kHoleAttr = "idr.hole";

// A clone as the table knows it: its key, and the hole each parameter
// holds, in increasing order.
struct Clone {
  mlir::func::FuncOp fn;
  mlir::Attribute key;
  llvm::SmallVector<unsigned> holes;
};

class CloneTable {
public:
  explicit CloneTable(mlir::ModuleOp module);

  const Clone *lookup(mlir::Attribute key) const;

  // The clone `fn` is, if it specializes: calls of it are keyed by its
  // owner's parameters.
  const Clone *specialization(mlir::func::FuncOp fn) const;

  // The function whose parameters the keys of calls of `fn` describe: a
  // clone that specializes describes its owner's, any other function its
  // own.
  mlir::StringAttr ownerOf(mlir::func::FuncOp fn) const;

  // A copy of `from` for `owner`, named `<owner>$<kind>$<n>`, in the module
  // but not yet in the table; the error `unsupported (compile-time budget)`
  // at `at` once `owner` has had kClonesPerOwner.
  mlir::FailureOr<mlir::func::FuncOp> copy(mlir::func::FuncOp from, mlir::StringAttr owner,
                                           llvm::StringRef kind, mlir::Operation *at);

  // `fn`, whose parameters hold the holes their `idr.hole` says, as the
  // clone for `key`.
  const Clone &add(mlir::Attribute key, mlir::func::FuncOp fn);

  mlir::SymbolTable &symbols() { return table; }

private:
  static std::optional<Clone> parse(mlir::func::FuncOp fn);

  mlir::ModuleOp module;
  mlir::SymbolTable table;
  llvm::DenseMap<mlir::Attribute, Clone> byKey;
  llvm::DenseMap<mlir::Operation *, mlir::Attribute> keyOf;
  // The clones of each owner, counted from their names.
  llvm::StringMap<unsigned> counts;
};

// The operands of a call of `clone` given the value of each hole of its
// key, or none when the call has no value for a hole the clone still takes.
std::optional<llvm::SmallVector<mlir::Value>>
operandsFor(const Clone &clone, llvm::ArrayRef<std::optional<mlir::Value>> holes);

// `from`, the attributes of a parameter of a clone, now holding `hole`.
mlir::DictionaryAttr parameterAttrs(mlir::MLIRContext *ctx, unsigned hole,
                                    mlir::DictionaryAttr from = {});

} // namespace idr::specialize
