// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a data type's body says beyond the type's own accessors, read from
// the type of a value, never from the module; how a pass that would change
// a body makes new data types instead; and the names generated from
// content, which no creation order reaches.
#ifndef IDR_IR_SYMBOLS_H
#define IDR_IR_SYMBOLS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringMap.h"

#include <functional>
#include <optional>
#include <string>
#include <tuple>
#include <utility>

namespace idr {

// The data type a value of `type` is of: `type` itself or the data of its
// box, through a grade; null for any other type.
DataType dataTypeOf(mlir::Type type);

// Whether a value of `type` is a box, a reference to a cell, through a grade.
bool isBoxed(mlir::Type type);

// Whether a value of `type` holds a reference a count accounts for. An
// unboxed sum has no cell: it holds what its constructors' fields hold,
// which its body says.
bool holdsReferences(mlir::Type type);

// The elimination of a value that begins at one of its uses: the dispatch
// on the value, or on one field of it (an action in `MkIO f`), each read
// through the one use of a linear value, where the value may first pass a
// linear position entered and used at once. Each step is the one use of
// the step before, so the dispatch is all the use does with the value. The
// dispatch is an idr.match whose scrutinee is of a closure sum: what an
// application became. It is what raising moves into a clone of a callee
// whose result it eliminates, where it meets the closure each tail builds;
// so a call's result that has one is worth moving to where the elimination
// is.
struct Elimination {
  // The pair that only moves the value into a linear position and out
  // again before it is read, or null.
  LinEnterOp enter;
  LinUseOp exit;
  FieldOp field; // null: the value itself is dispatched on
  LinUseOp use;  // null: what is dispatched on is not linear
  MatchOp dispatch;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);

// The data types of a module remade where a body would change. A body is
// set once, so a pass that changes the type of what a body holds makes a
// new type in place of the one whose body holds it, and of every type whose
// body holds one of those, transitively; every other type stays itself. A
// remade type keeps the old one's kind, constructor names, `byName` and
// instance, and is named contentName(old name, `kind`, key), the key being
// its new body with every data type in it written by its old name, so no
// name needs a new name first. Every new body is set when the remap is made.
class DataRemap {
public:
  // The replacement of `type`, a type that is neither a data type nor a box
  // (a closure, a suspension, a tensor), or nothing to look inside it.
  // `owner` is the data type whose field `field` of constructor `tag` holds
  // `type` (a field's replacement may be keyed by where it is held, not by
  // its type), or null where `type` is met anywhere but in a body. It may
  // give a data type whose body its caller sets later, and what it gives is
  // looked inside in turn.
  using Leaf = std::function<std::optional<mlir::Type>(mlir::Type type, DataType owner,
                                                       unsigned tag, unsigned field)>;

  // The remap keeps `leaf`, and asks it once per type and place. Every
  // occurrence of a type of `boxed` outside a box becomes a box of it.
  DataRemap(mlir::ModuleOp module, llvm::StringRef kind, Leaf leaf,
            llvm::ArrayRef<DataType> boxed = {});

  // The type `type`, met anywhere but in a body, becomes.
  mlir::Type map(mlir::Type type);
  // Every attribute, result type and block argument type under `root`,
  // mapped.
  void retype(mlir::Operation *root);
  // The data types remade, old to new, in the order of the old names.
  llvm::ArrayRef<std::pair<DataType, DataType>> remade() const { return pairs; }
  // Whether every body was set: a name made from two keys, or a body that
  // is no well-formed sum, is an internal error at the module.
  mlir::LogicalResult status() const { return mlir::success(!broken); }

private:
  // Where a type is held: a field of a body, or anywhere else (no owner).
  struct Place {
    DataType owner;
    unsigned tag = 0;
    unsigned field = 0;
  };

  DataType mapData(DataType type);
  std::optional<mlir::Type> leafAt(mlir::Type type, Place place);
  void addReplacements(mlir::AttrTypeReplacer &into, Place place);

  Leaf leaf;
  llvm::DenseMap<std::tuple<mlir::Type, DataType, unsigned, unsigned>, std::optional<mlir::Type>>
      leaves;
  llvm::DenseSet<DataType> boxed;
  llvm::DenseMap<DataType, DataType> next;
  llvm::SmallVector<std::pair<DataType, DataType>> pairs;
  mlir::AttrTypeReplacer replacer;
  bool broken = false;
};

// The low 64 bits of XXH3-128 of `key`'s bytes, as 16 lower-case hex digits.
std::string contentHash(llvm::StringRef key);

// A generated name: `<owner>.<kind>.<contentHash(key)>`, a function of
// what it names alone.
std::string contentName(llvm::StringRef owner, llvm::StringRef kind, llvm::StringRef key);

// The names one pass makes, each with the key it was made from, so that a
// second key of the same name is caught where the name is interned: an
// internal error, never a merge and never a longer name. A name made again
// from its own key is the same thing, which the caller reuses.
class ContentNames {
public:
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, llvm::StringRef key);

private:
  llvm::StringMap<std::string> keys;
};

} // namespace idr

#endif // IDR_IR_SYMBOLS_H
