// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a data type's body says beyond the type's own accessors, read from
// the type of a value, never from the module; a constructor written by its
// name; how a pass that would change a body makes new data types instead;
// the names generated from content, which no creation order and no
// printing flag reaches; and the names the lowering reserves for itself.
#ifndef IDR_IR_SYMBOLS_H
#define IDR_IR_SYMBOLS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace idr {

// The data type a value of `type` is of: `type` itself or the data of its
// box, through a grade; null for any other type.
DataType dataTypeOf(mlir::Type type);

// Whether a value of `type` is a box, a reference to a cell, through a grade.
bool isBoxed(mlir::Type type);

// Whether how `value` was built (its idr.con, its constant) still says its
// constructor where `reader` reads it. Always, but for a memo cell, whose
// state every force writes: never for a constant, one static cell every
// run of the program shares and forces, and for a cell an idr.con built
// only while nothing but `reader` enters or settles it.
bool builtStateHolds(mlir::Value value, mlir::Operation *reader);

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
  // again before it is read, when there is one.
  std::optional<std::pair<LinEnterOp, LinUseOp>> passed;
  // The field dispatched on, when it is not the value itself.
  std::optional<FieldOp> field;
  // The one use of what is dispatched on, when it is linear.
  std::optional<LinUseOp> use;
  MatchOp dispatch;

  // The ops from the use to the dispatch, each the one use of the one
  // before, in the order they run.
  llvm::SmallVector<mlir::Operation *> steps() const;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);

// The data types of a module remade where a body would change. A body is
// set once, so a pass that changes what a body holds (the type of a field,
// a type it holds in place that becomes a box, a label's function renamed)
// makes a new type in place of the one whose body holds it, and of every
// type whose body holds one of those, transitively; every other type stays
// itself. What each field becomes is decided once, as its shape: the field
// with each box and leaf applied at any depth, every data type in it by its
// old name. A type changes where a shape is not its field or a label's
// function is renamed; its key is its shapes and its labels' functions'
// new names; its new body is each shape with its data types remade. A
// remade type keeps the old one's kind, constructor names, roles (a label
// with its function's new name) and instance, and is named contentName(old
// name, `kind`, key and the keys of every remade type it reaches), so that
// two remaps of one kind that remake a type differently anywhere below it
// or anywhere in a field name it differently. No name needs a new name
// first. Every new body is made when the remap is.
class DataRemap {
public:
  // Where a type is held in a body: field `field` of the constructor `tag`
  // of `owner`.
  struct FieldPlace {
    DataType owner;
    Tag tag;
    unsigned field;
  };
  // The replacement of `type`, a type that is neither a data type nor a box
  // (a closure, a suspension, a tensor), or nothing to look inside it.
  // `place` is the field of a body that holds `type` (a field's replacement
  // may be keyed by where it is held, not by its type), or nothing where
  // `type` is met anywhere but in a body. It may give a data type a remap
  // made, and what it gives is looked inside in turn.
  using Leaf =
      std::function<std::optional<mlir::Type>(mlir::Type type, std::optional<FieldPlace> place)>;
  // Functions renamed, each old symbol to its new one.
  using Renames = llvm::DenseMap<mlir::StringAttr, mlir::StringAttr>;

  // The remap of what `root` (a module or a program) holds, with every new
  // body made; failure, after an internal error at the root, when a name is
  // made from two keys or a body is no well-formed sum. It keeps `leaf`,
  // and asks it once per type and place. Every occurrence of a type of
  // `boxed` outside a box becomes a box of it. A label whose function
  // `renames` renames names the new function, and retype renames every
  // reference to one, so a renamed function needs no other rename. The
  // remap's replacements refer to it, so it stays where it is made.
  static mlir::FailureOr<std::unique_ptr<DataRemap>>
  create(mlir::Operation *root, llvm::StringRef kind, Leaf leaf,
         llvm::ArrayRef<DataType> boxed = {}, Renames renames = {});

  DataRemap(const DataRemap &) = delete;
  DataRemap &operator=(const DataRemap &) = delete;

  // Every attribute, result type and block argument type under `root`,
  // mapped.
  void retype(mlir::Operation *root);

private:
  DataRemap(mlir::Operation *root, Leaf leaf, llvm::ArrayRef<DataType> boxed, Renames renames);

  // Decides the types to remake and their names, and makes each.
  void remakeAll(mlir::Operation *root, llvm::StringRef kind);
  DataType mapData(DataType type);
  std::optional<mlir::Type> leafAt(mlir::Type type, std::optional<FieldPlace> place);
  // The shape of `type` held at `place` (a field of a body, or nothing for
  // anywhere else): each box and leaf applied, every data type by its old
  // name.
  mlir::Type shapeAt(mlir::Type type, std::optional<FieldPlace> place);
  // `shape` with each data type in it remade.
  mlir::Type remadeOf(mlir::Type shape);
  // The new type of `old`, made the first time it is asked for, from inside
  // the remaking of another's body too.
  DataType remake(DataType old);

  mlir::MLIRContext *context;
  Leaf leaf;
  Renames renames;
  // What `leaf` gave for each type at each field of a body, and anywhere
  // else.
  llvm::DenseMap<std::tuple<mlir::Type, DataType, uint32_t, unsigned>, std::optional<mlir::Type>>
      leavesInBodies;
  llvm::DenseMap<mlir::Type, std::optional<mlir::Type>> leavesElsewhere;
  llvm::DenseSet<DataType> boxed;
  // The shape of each field of each body the root reaches, by tag and then
  // field, which the change, the key and the new body read.
  llvm::DenseMap<DataType, std::vector<llvm::SmallVector<mlir::Type>>> shapes;
  // The name of each type to remake, and the type once it is made.
  llvm::DenseMap<DataType, std::string> names;
  llvm::DenseMap<DataType, DataType> next;
  // The replacement of everything met anywhere but in a body.
  mlir::AttrTypeReplacer replacer;
  mlir::Location at;
  // Whether every body was made, which create reads: a body is made inside
  // the replacements of another, which return a type whatever happens.
  mlir::LogicalResult made = mlir::success();
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

// A generated name: `<owner>.<kind>.<16 hex digits>`, the low half of the
// key's digest, a function of what it names alone. A text key is its
// digestOf; an attribute or a type its canonicalHash.
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
  // contentName(owner, kind, key), interned.
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, Digest key);
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, llvm::StringRef key) {
    return intern(at, owner, kind, digestOf(key));
  }
  // `name`, made from `key` (a content name, or a reserved name of a
  // digest), interned: the one check that no two keys make one name.
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef name, Digest key);

  // The canonicalHash of a uniqued type, kept with these names, so each is
  // printed once however many keys hold it.
  Digest digest(mlir::Type type);

private:
  llvm::StringMap<Digest> keys;
  llvm::DenseMap<const void *, Digest> digests;
};

//===----------------------------------------------------------------------===//
// Reserved names
//===----------------------------------------------------------------------===//

// A symbol the lowering makes for itself, outside the program's names:
// `__idr$<kind>$<discriminator>`, `kind` a word that starts with a letter.
// It is never a program symbol's mangling (conversion::mangle): a mangled
// name's first `$` opens an escape, so a digit follows it, where a letter
// follows a reserved name's first `$`. It is never a runtime function's
// name either, a C identifier, which holds no `$`. So a reserved name is
// distinct by its spelling, and no check of a collision guards it.
std::string reservedName(llvm::StringRef kind, llvm::StringRef discriminator);

// The reserved name of a thing named by its content: the discriminator is
// what a name from content writes of `key`, the 16 low hex digits of its
// digest (lib/IR/ContentNames.cpp). ContentNames::intern(at, name, key)
// interns one, so a second key of one name is caught as a content name's is.
std::string reservedName(llvm::StringRef kind, Digest key);

// The function that releases the program's constant applicative forms once
// its root returns: reservedName("release", "cafs"), the one spelling of
// it, read wherever it is made or called.
std::string releaseCafsName();

} // namespace idr

#endif // IDR_IR_SYMBOLS_H
