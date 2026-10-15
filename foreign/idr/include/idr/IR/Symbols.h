// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a data type's body says beyond the type's own accessors, read from
// the type of a value, never from the module; a constructor written by its
// name; how a pass that would change a body makes new data types instead;
// and the names generated from content, which no creation order and no
// printing flag reaches.
#ifndef IDR_IR_SYMBOLS_H
#define IDR_IR_SYMBOLS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
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

// A constructor written by its name, `@Name`, in the data type of `type` (a
// data type or its box, at any grade), and read back into its tag, an i32
// attribute: the one place a constructor's name becomes its tag. An op's
// assembly format reads one as `custom<CtorRef>(ref(type($x)), $tag)`,
// after the type that names it; `#idr.con` reads its own with the parser.
mlir::ParseResult parseCtorRef(mlir::AsmParser &parser, mlir::Type type, mlir::IntegerAttr &tag);
void printCtorRef(mlir::OpAsmPrinter &printer, mlir::Operation *op, mlir::Type type,
                  mlir::IntegerAttr tag);

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
// set once, so a pass that changes what a body holds (the type of a field,
// a type it holds in place that becomes a box, a label's function renamed)
// makes a new type in place of the one whose body holds it, and of every
// type whose body holds one of those, transitively; every other type stays
// itself. A remade type keeps the old one's kind, constructor names and
// roles, `byName` and instance, and is named contentName(old name, `kind`,
// key): the key is its new body with every data type in it written by its
// old name, and the keys of every remade type it reaches, so that two
// remaps of one kind that remake a type differently anywhere below it name
// it differently. No name needs a new name first. Every new body is made
// when the remap is.
class DataRemap {
public:
  // The replacement of `type`, a type that is neither a data type nor a box
  // (a closure, a suspension, a tensor), or nothing to look inside it.
  // `owner` is the data type whose field `field` of constructor `tag` holds
  // `type` (a field's replacement may be keyed by where it is held, not by
  // its type), or null where `type` is met anywhere but in a body. It may
  // give a data type a remap made, and what it gives is looked inside in
  // turn.
  using Leaf = std::function<std::optional<mlir::Type>(mlir::Type type, DataType owner,
                                                       unsigned tag, unsigned field)>;
  // Functions renamed, each old symbol to its new one.
  using Renames = llvm::DenseMap<mlir::StringAttr, mlir::StringAttr>;

  // The remap of what `root` (a module or a program) holds. It keeps `leaf`,
  // and asks it once per type and place. Every occurrence of a type of
  // `boxed` outside a box becomes a box of it. A label whose function
  // `renames` renames names the new function, and retype renames every
  // reference to one, so a renamed function needs no other rename.
  DataRemap(mlir::Operation *root, llvm::StringRef kind, Leaf leaf,
            llvm::ArrayRef<DataType> boxed = {}, Renames renames = {});

  // The type `type`, met anywhere but in a body, becomes.
  mlir::Type map(mlir::Type type);
  // Every attribute, result type and block argument type under `root`,
  // mapped.
  void retype(mlir::Operation *root);
  // The data types remade, old to new, in the order of the old names.
  llvm::ArrayRef<std::pair<DataType, DataType>> remade() const { return pairs; }
  // Whether every body was made: a name made from two keys, or a body that
  // is no well-formed sum, is an internal error at the root.
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
  // The new type of `old`, made the first time it is asked for.
  DataType make(DataType old);

  mlir::MLIRContext *context;
  Leaf leaf;
  Renames renames;
  llvm::DenseMap<std::tuple<mlir::Type, DataType, unsigned, unsigned>, std::optional<mlir::Type>>
      leaves;
  llvm::DenseSet<DataType> boxed;
  // The name of each type to remake, and the type once it is made.
  llvm::DenseMap<DataType, std::string> names;
  llvm::DenseMap<DataType, DataType> next;
  llvm::SmallVector<std::pair<DataType, DataType>> pairs;
  mlir::AttrTypeReplacer replacer;
  mlir::Location at;
  bool broken = false;
};

//===----------------------------------------------------------------------===//
// Content
//===----------------------------------------------------------------------===//

// XXH3-128 of a key's bytes: the hash every name from content is made of,
// pinned to the published vectors as the Idris side's is.
struct Digest {
  uint64_t low = 0;
  uint64_t high = 0;
  bool operator==(const Digest &) const = default;
};

// Written as 32 lower-case hex digits, the high half first.
llvm::raw_ostream &operator<<(llvm::raw_ostream &os, Digest digest);

Digest digestOf(llvm::StringRef key);

// The low 64 bits of XXH3-128 of `key`'s bytes, as 16 lower-case hex digits.
std::string contentHash(llvm::StringRef key);

// The text a content key is made of: printed with every printing option
// chosen here, so no command-line flag reaches it. Generic op form, no
// locations, nothing elided, large elements in hex, no name from a
// location, and the aliases of the text written before it, so that a data
// type's body is written once whatever holds it. An attribute or a type is
// printed held by a detached op of its own; an op is printed numbered from
// itself, so a value it uses from outside is no part of its text.
std::string canonicalText(mlir::Attribute attr);
std::string canonicalText(mlir::Type type);
std::string canonicalText(mlir::Operation *op);

// The digest of canonicalText, printed afresh at each call: no state
// outlives it. A pass that asks for the key of one attribute or type many
// times keeps its digests with its names (ContentNames::digest).
Digest canonicalHash(mlir::Attribute attr);
Digest canonicalHash(mlir::Type type);
Digest canonicalHash(mlir::Operation *op);

// A generated name: `<owner>.<kind>.<16 hex digits>`, the low half of the
// key's digest, a function of what it names alone. A text key is its
// digestOf; an attribute, a type or an op its canonicalHash.
std::string contentName(llvm::StringRef owner, llvm::StringRef kind, Digest key);
std::string contentName(llvm::StringRef owner, llvm::StringRef kind, llvm::StringRef key);

// The names one pass makes, each with the digest of the key it was made
// from, so that a second key of the same name is caught where the name is
// interned: an internal error, never a merge and never a longer name. A
// name made again from its own key is the same thing, which the caller
// reuses. They are the pass's, kept as long as it keeps them and asked from
// one thread at a time.
class ContentNames {
public:
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, Digest key);
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, llvm::StringRef key) {
    return intern(at, owner, kind, digestOf(key));
  }

  // The canonicalHash of a uniqued attribute or type, kept with these
  // names, so each is printed once however many keys hold it.
  Digest digest(mlir::Attribute attr);
  Digest digest(mlir::Type type);

private:
  llvm::StringMap<Digest> keys;
  llvm::DenseMap<const void *, Digest> digests;
};

} // namespace idr

#endif // IDR_IR_SYMBOLS_H
